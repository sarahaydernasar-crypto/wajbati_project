"""منطق العمل: حالة الكافيتريا، أوقات الاستلام، الإشعارات، وتحويل البيانات إلى JSON."""

import math
import os
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from . import push
from .models import (
    BUSY,
    ACTIVE_STATUSES,
    CANCELLED,
    CLOSED,
    DELIVERED,
    OPEN,
    PREPARING,
    READY,
    REJECTED,
    Cafeteria,
    MenuItem,
    Notification,
    Order,
    OrderLine,
    OrderEvent,
)

BUSY_THRESHOLD = 5  # عدد الطلبات النشطة الذي تصبح بعده الكافيتريا "مزدحمة"
SLOT_MINUTES = 15
SLOT_CAPACITY = 4  # أقصى عدد طلبات لكل فترة استلام
PREP_BUFFER_MINUTES = 5


# توقيت الجامعة؛ مهم عند النشر لأن سيرفرات الاستضافة تعمل بتوقيت UTC
TIMEZONE = ZoneInfo(os.getenv("WAJBATI_TZ", "Asia/Baghdad"))


def now() -> datetime:
    """الوقت الحالي بتوقيت الجامعة بدون معلومات المنطقة (يُستبدل في الاختبارات)."""
    return datetime.now(TIMEZONE).replace(tzinfo=None)


def active_orders_count(db: Session, cafeteria_id: int) -> int:
    return db.scalar(
        select(func.count()).select_from(Order).where(Order.cafeteria_id == cafeteria_id, Order.status.in_(ACTIVE_STATUSES))
    ) or 0


def lock_cafeteria(db: Session, cafeteria_id: int) -> None:
    # A DB row write serializes capacity checks and order changes across workers.
    # Unlike an in-process mutex, this also works with multiple API processes.
    db.execute(update(Cafeteria).where(Cafeteria.id == cafeteria_id).values(id=cafeteria_id))


def is_open_hours(cafe: Cafeteria, t: datetime) -> bool:
    return cafe.open_hour <= t.hour < cafe.close_hour


def cafeteria_status(db: Session, cafe: Cafeteria) -> str:
    if cafe.manual_status:
        return cafe.manual_status
    if not is_open_hours(cafe, now()):
        return CLOSED
    if active_orders_count(db, cafe.id) >= BUSY_THRESHOLD:
        return BUSY
    return OPEN


def pickup_slots(db: Session, cafe: Cafeteria, prep_minutes: int) -> list[dict]:
    """كل فترات الاستلام من أقرب وقت ممكن حتى الإغلاق مع عدد المحجوز في كل فترة."""
    t = now()
    day = t.replace(hour=0, minute=0, second=0, microsecond=0)
    earliest = t + timedelta(minutes=prep_minutes + PREP_BUFFER_MINUTES)
    minutes = (earliest - day).total_seconds() / 60
    slot = day + timedelta(minutes=math.ceil(minutes / SLOT_MINUTES) * SLOT_MINUTES)
    opening = day.replace(hour=cafe.open_hour)
    closing = day.replace(hour=cafe.close_hour) if cafe.close_hour < 24 else day + timedelta(days=1)
    if slot < opening:
        slot = opening

    booked_rows = db.execute(
        select(Order.pickup_time, func.count())
        .where(Order.cafeteria_id == cafe.id, Order.status.in_(ACTIVE_STATUSES), Order.pickup_time >= slot)
        .group_by(Order.pickup_time)
    ).all()
    booked = {row[0]: row[1] for row in booked_rows}

    result = []
    while slot < closing:
        count = booked.get(slot, 0)
        result.append({"time": slot.isoformat(timespec="minutes"), "booked": count, "available": count < SLOT_CAPACITY})
        slot += timedelta(minutes=SLOT_MINUTES)
    return result


def notify(db: Session, student_id: int, title: str, body: str, order_id: str | None = None) -> None:
    """إشعار داخل التطبيق + Push للهاتف (إن كان Firebase مفعّلاً)."""
    db.add(Notification(student_id=student_id, order_id=order_id, title=title, body=body, created_at=now()))
    push.queue(db, student_id, title, body, order_id)


STATUS_MESSAGES = {
    PREPARING: "بدأت {cafe} بتحضير طلبك 👨‍🍳",
    READY: 'طلبك جاهز! توجّه للاستلام واضغط "وصلت" لعرض رمز QR',
    DELIVERED: "تم تسليم طلبك، بالعافية! 😋 لا تنسَ تقييم الوجبة",
    CANCELLED: "تم إلغاء طلبك قبل بدء التحضير.",
    REJECTED: "اعتذرت الكافيتريا عن طلبك. راجع تفاصيل الطلب لمعرفة السبب.",
}


def record_order_event(db: Session, order: Order, actor: str) -> None:
    db.add(OrderEvent(order_id=order.id, status=order.status, actor=actor,
                      reason=order.closure_reason, created_at=now()))


def notify_status_change(db: Session, order: Order, actor: str = "cafeteria") -> None:
    record_order_event(db, order, actor)
    template = STATUS_MESSAGES.get(order.status)
    if template:
        notify(db, order.student_id, f"تحديث على طلبك #{order.id}", template.format(cafe=order.cafeteria.name), order.id)


# ---------------- تحويل إلى JSON ----------------
def ratings_for(db: Session, item_ids: list[int]) -> dict[int, tuple[float, int]]:
    if not item_ids:
        return {}
    rows = db.execute(
        select(OrderLine.menu_item_id, func.avg(Order.rating), func.count(func.distinct(Order.id)))
        .join(Order, Order.id == OrderLine.order_id)
        .where(OrderLine.menu_item_id.in_(item_ids), Order.rating.is_not(None))
        .group_by(OrderLine.menu_item_id)
    ).all()
    return {r[0]: (round(float(r[1]), 2), r[2]) for r in rows}


def menu_item_json(item: MenuItem, rating: tuple[float, int] | None = None) -> dict:
    return {
        "id": item.id,
        "cafeteria_id": item.cafeteria_id,
        "cafeteria_name": item.cafeteria.name,
        "name": item.name,
        "price": item.price,
        "prep_minutes": item.prep_minutes,
        "ingredients": item.ingredients or [],
        "removable_ingredients": item.removable_ingredients or [],
        "available": item.available,
        "emoji": item.emoji,
        # صورة مرفوعة ← رابط نسبي يخدمه السيرفر؛ وإلا الرابط الخارجي إن وجد
        "image_url": f"/menu/{item.id}/image?v={item.image_version}" if item.image_mime else item.image_url,
        "rating_avg": rating[0] if rating else None,
        "rating_count": rating[1] if rating else 0,
    }


def menu_json(db: Session, items: list[MenuItem]) -> list[dict]:
    ratings = ratings_for(db, [i.id for i in items])
    return [menu_item_json(i, ratings.get(i.id)) for i in items]


def cafeteria_json(db: Session, cafe: Cafeteria) -> dict:
    available = db.scalar(
        select(func.count())
        .select_from(MenuItem)
        .where(MenuItem.cafeteria_id == cafe.id, MenuItem.available.is_(True), MenuItem.deleted.is_(False))
    )
    return {
        "id": cafe.id,
        "name": cafe.name,
        "location": cafe.location,
        "open_hour": cafe.open_hour,
        "close_hour": cafe.close_hour,
        "status": cafeteria_status(db, cafe),
        "manual_status": cafe.manual_status,
        "active_orders": active_orders_count(db, cafe.id),
        "available_items": available or 0,
        "server_time": now().isoformat(timespec="seconds"),
    }


def order_json(order: Order) -> dict:
    return {
        "id": order.id,
        "status": order.status,
        "delivered_at": order.delivered_at.isoformat(timespec="seconds") if order.delivered_at else None,
        "cafeteria_id": order.cafeteria_id,
        "cafeteria_name": order.cafeteria.name,
        "student_name": order.student.name,
        "student_university_id": order.student.public_university_id,
        "lines": [
            {
                "menu_item_id": line.menu_item_id,
                "item_name": line.item_name,
                "unit_price": line.unit_price,
                "quantity": line.quantity,
                "note": line.note,
            }
            for line in order.lines
        ],
        "total": order.total,
        "prep_minutes": order.prep_minutes,
        "pickup_time": order.pickup_time.isoformat(timespec="minutes"),
        "payment_method": order.payment_method,
        "arrived": order.arrived,
        "rating": order.rating,
        "rating_comment": order.rating_comment,
        "closure_reason": order.closure_reason,
        "created_at": order.created_at.isoformat(timespec="seconds"),
    }


def notification_json(n: Notification) -> dict:
    return {
        "id": n.id,
        "order_id": n.order_id,
        "title": n.title,
        "body": n.body,
        "read": n.read,
        "created_at": n.created_at.isoformat(timespec="seconds"),
    }
