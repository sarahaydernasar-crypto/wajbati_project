"""واجهات مسؤول الكافيتريا: الدخول، الطلبات، ماسح QR، القائمة، الحالة، الدخل."""

from datetime import date, timedelta
import json

from fastapi import APIRouter, File, Form, HTTPException, Query, UploadFile, status
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import func, select

from . import logic
from .models import (ACTIVE_STATUSES, CAFETERIA_STATUSES, DELIVERED, RECEIVED, REJECTED,
                     STATUSES, TERMINAL_STATUSES, Cafeteria, MenuItem, Order, OrderLine, OrderEvent)
from .security import CafeteriaDep, DbDep, create_token, hash_secret, verify_secret
from .rate_limit import check_login
from .reporting import report

router = APIRouter(prefix="/admin", tags=["cafeteria admin"])


class CafeteriaLoginIn(BaseModel):
    cafeteria_id: int
    code: str


@router.post("/login")
def cafeteria_login(body: CafeteriaLoginIn, db: DbDep):
    check_login(db, f"cafeteria:{body.cafeteria_id}")
    cafe = db.get(Cafeteria, body.cafeteria_id)
    if cafe is None or not verify_secret(body.code.strip(), cafe.code_hash):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "الرمز السري غير صحيح!")
    return {"token": create_token(cafe.id, "cafeteria", cafe.auth_version), "cafeteria": logic.cafeteria_json(db, cafe)}


class CodeChangeIn(BaseModel):
    current_code: str = Field(max_length=100)
    new_code: str = Field(min_length=12, max_length=72, pattern=r"^[\x21-\x7e]+$")


@router.post("/password")
def change_code(body: CodeChangeIn, cafe: CafeteriaDep, db: DbDep):
    logic.lock_cafeteria(db, cafe.id)
    db.refresh(cafe)
    if not verify_secret(body.current_code, cafe.code_hash):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "الرمز الحالي غير صحيح")
    cafe.code_hash = hash_secret(body.new_code)
    cafe.auth_version += 1
    db.commit()
    return {"token": create_token(cafe.id, "cafeteria", cafe.auth_version)}


@router.get("/me")
def admin_me(cafe: CafeteriaDep, db: DbDep):
    return logic.cafeteria_json(db, cafe)


class StatusIn(BaseModel):
    status: str | None = None  # None = تلقائي


@router.put("/status")
def set_cafeteria_status(body: StatusIn, cafe: CafeteriaDep, db: DbDep):
    if body.status is not None and body.status not in CAFETERIA_STATUSES:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "حالة غير صالحة")
    cafe.manual_status = body.status
    db.commit()
    return logic.cafeteria_json(db, cafe)


# ---------------- الطلبات ----------------
@router.get("/orders")
def cafeteria_orders(cafe: CafeteriaDep, db: DbDep, days: int = 1):
    since = logic.now() - timedelta(days=max(1, days))
    orders = db.scalars(
        select(Order)
        .where(Order.cafeteria_id == cafe.id, Order.status.in_(ACTIVE_STATUSES) |
               (func.coalesce(Order.delivered_at, Order.created_at) >= since))
        .order_by(Order.pickup_time)
    ).all()
    return [logic.order_json(o) for o in orders]


def _own_order(db, cafe: Cafeteria, order_id: str) -> Order:
    order = db.get(Order, order_id.strip())
    if order is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, f"الرمز ({order_id}) غير مسجل أو غير صالح!")
    if order.cafeteria_id != cafe.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, f"هذا الطلب تابع لـ ({order.cafeteria.name}) وليس لهذه الكافيتريا!")
    return order


def _advance(db, order: Order, new_status: str) -> dict:
    logic.lock_cafeteria(db, order.cafeteria_id)
    db.refresh(order)
    if new_status not in STATUSES:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "حالة غير صالحة")
    if order.status in TERMINAL_STATUSES:
        raise HTTPException(status.HTTP_409_CONFLICT, "الطلب منتهٍ ولا يمكن تغيير حالته.")
    if STATUSES.index(new_status) != STATUSES.index(order.status) + 1:
        raise HTTPException(status.HTTP_409_CONFLICT, "يجب تغيير حالة الطلب بالترتيب: التحضير ثم الجاهزية ثم التسليم.")
    order.status = new_status
    if new_status == DELIVERED:
        order.delivered_at = logic.now()
    logic.notify_status_change(db, order)
    db.commit()
    return logic.order_json(order)


class OrderStatusIn(BaseModel):
    status: str


@router.patch("/orders/{order_id}/status")
def update_order_status(order_id: str, body: OrderStatusIn, cafe: CafeteriaDep, db: DbDep):
    return _advance(db, _own_order(db, cafe, order_id), body.status)


class RejectIn(BaseModel):
    reason: str = Field(min_length=3, max_length=300, pattern=r"\S.*\S")


@router.post("/orders/{order_id}/reject")
def reject_order(order_id: str, body: RejectIn, cafe: CafeteriaDep, db: DbDep):
    order = _own_order(db, cafe, order_id)
    logic.lock_cafeteria(db, cafe.id)
    db.refresh(order)
    if order.status != RECEIVED:
        raise HTTPException(status.HTTP_409_CONFLICT, "يمكن رفض الطلب قبل بدء التحضير فقط.")
    order.status = REJECTED
    order.closure_reason = body.reason.strip()
    logic.notify_status_change(db, order)
    db.commit()
    return logic.order_json(order)


class ScanIn(BaseModel):
    code: str = Field(min_length=1, max_length=50)


@router.post("/scan")
def scan_qr(body: ScanIn, cafe: CafeteriaDep, db: DbDep):
    """ماسح QR: محتوى الرمز هو رقم الطلب، ويؤكد التسليم."""
    return _advance(db, _own_order(db, cafe, body.code), DELIVERED)


# ---------------- القائمة ----------------
class IngredientValidation(BaseModel):
    @field_validator("ingredients", "removable_ingredients", check_fields=False)
    @classmethod
    def clean_ingredients(cls, values):
        if values is None:
            raise ValueError("استخدم قائمة مكونات، ويمكن أن تكون فارغة")
        cleaned = list(dict.fromkeys(value.strip() for value in values if value.strip()))
        if any(len(value) > 40 for value in cleaned):
            raise ValueError("اسم المكون لا يتجاوز 40 حرفاً")
        return cleaned


def check_removable(ingredients: list[str], removable: list[str]) -> None:
    if not set(removable).issubset(ingredients):
        raise HTTPException(422, "المكونات القابلة للإزالة يجب أن تكون ضمن مكونات الطبق")


class MenuItemIn(IngredientValidation):
    name: str = Field(min_length=1, max_length=100)
    price: int = Field(ge=0, le=1_000_000)
    prep_minutes: int = Field(default=5, ge=0, le=120)
    emoji: str = Field(default="🍽️", max_length=10)
    image_url: str | None = Field(default=None, max_length=500)
    ingredients: list[str] = Field(default_factory=list, max_length=20)
    removable_ingredients: list[str] = Field(default_factory=list, max_length=20)


class MenuItemPatch(IngredientValidation):
    name: str | None = Field(default=None, min_length=1, max_length=100)
    price: int | None = Field(default=None, ge=0, le=1_000_000)
    prep_minutes: int | None = Field(default=None, ge=0, le=120)
    available: bool | None = None
    emoji: str | None = Field(default=None, max_length=10)
    image_url: str | None = Field(default=None, max_length=500)
    ingredients: list[str] | None = Field(default=None, max_length=20)
    removable_ingredients: list[str] | None = Field(default=None, max_length=20)


@router.post("/menu", status_code=201)
def add_menu_item(body: MenuItemIn, cafe: CafeteriaDep, db: DbDep):
    check_removable(body.ingredients, body.removable_ingredients)
    item = MenuItem(cafeteria_id=cafe.id, **body.model_dump())
    db.add(item)
    db.commit()
    db.refresh(item)
    return logic.menu_item_json(item)


def _own_item(db, cafe: Cafeteria, item_id: int) -> MenuItem:
    item = db.get(MenuItem, item_id)
    if item is None or item.deleted or item.cafeteria_id != cafe.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "الصنف غير موجود")
    return item


@router.patch("/menu/{item_id}")
def update_menu_item(item_id: int, body: MenuItemPatch, cafe: CafeteriaDep, db: DbDep):
    item = _own_item(db, cafe, item_id)
    changes = body.model_dump(exclude_unset=True)
    ingredients = changes.get("ingredients", item.ingredients or [])
    if "ingredients" in changes and "removable_ingredients" not in changes:
        changes["removable_ingredients"] = [v for v in item.removable_ingredients or [] if v in ingredients]
    check_removable(ingredients, changes.get("removable_ingredients", item.removable_ingredients or []))
    for key, value in changes.items():
        setattr(item, key, value)
    db.commit()
    return logic.menu_item_json(item)


MAX_IMAGE_BYTES = 2 * 1024 * 1024  # 2MB
# التحقق من نوع الصورة من محتواها الفعلي وليس من اسم الملف فقط
IMAGE_SIGNATURES = {
    b"\xff\xd8\xff": "image/jpeg",
    b"\x89PNG\r\n\x1a\n": "image/png",
    b"GIF87a": "image/gif",
    b"GIF89a": "image/gif",
}


def _detect_image(data: bytes) -> str | None:
    for sig, mime in IMAGE_SIGNATURES.items():
        if data.startswith(sig):
            return mime
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    return None


async def _read_menu_image(file: UploadFile) -> tuple[bytes, str]:
    data = await file.read(MAX_IMAGE_BYTES + 1)
    if len(data) > MAX_IMAGE_BYTES:
        raise HTTPException(status.HTTP_413_CONTENT_TOO_LARGE, "حجم الصورة كبير، الحد الأقصى 2 ميغابايت.")
    mime = _detect_image(data)
    if mime is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "الملف ليس صورة مدعومة (JPG أو PNG أو WEBP أو GIF).")
    return data, mime


@router.post("/menu/with-image", status_code=201)
async def add_menu_item_with_image(
    cafe: CafeteriaDep,
    db: DbDep,
    name: str = Form(..., min_length=1, max_length=100),
    price: int = Form(..., ge=0, le=1_000_000),
    prep_minutes: int = Form(default=5, ge=0, le=120),
    ingredients: str = Form(default="[]"),
    removable_ingredients: str = Form(default="[]"),
    file: UploadFile = File(...),
):
    name = name.strip()
    if not name:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "أدخل اسم الوجبة")
    try:
        body = MenuItemIn(name=name, price=price, prep_minutes=prep_minutes,
                          ingredients=json.loads(ingredients), removable_ingredients=json.loads(removable_ingredients))
    except (ValueError, TypeError):
        raise HTTPException(422, "تحقق من قوائم المكونات، بحد أقصى 20 مكوناً و40 حرفاً لكل مكون")
    check_removable(body.ingredients, body.removable_ingredients)
    # Validate the image before inserting: failed uploads never create a partial item.
    data, mime = await _read_menu_image(file)
    item = MenuItem(cafeteria_id=cafe.id, **body.model_dump(),
                    image_data=data, image_mime=mime, image_version=1)
    db.add(item)
    db.commit()
    return logic.menu_item_json(item)


@router.post("/menu/{item_id}/image")
async def upload_menu_image(item_id: int, cafe: CafeteriaDep, db: DbDep, file: UploadFile = File(...)):
    item = _own_item(db, cafe, item_id)
    data, mime = await _read_menu_image(file)
    item.image_data = data
    item.image_mime = mime
    item.image_version = (item.image_version or 0) + 1
    db.commit()
    return logic.menu_item_json(item)


@router.delete("/menu/{item_id}/image")
def delete_menu_image(item_id: int, cafe: CafeteriaDep, db: DbDep):
    item = _own_item(db, cafe, item_id)
    item.image_data = None
    item.image_mime = None
    item.image_version = (item.image_version or 0) + 1
    db.commit()
    return logic.menu_item_json(item)


@router.delete("/menu/{item_id}", status_code=204)
def delete_menu_item(item_id: int, cafe: CafeteriaDep, db: DbDep):
    item = _own_item(db, cafe, item_id)
    item.deleted = True
    item.available = False
    db.commit()


# ---------------- الدخل ----------------
@router.get("/reports")
def reports(cafe: CafeteriaDep, db: DbDep,
            period: str = Query(default="week", pattern="^(today|week|month|custom)$"),
            start_date: date | None = None, end_date: date | None = None):
    return report(db, cafe.id, period, start_date, end_date)


@router.get("/revenue")
def revenue(cafe: CafeteriaDep, db: DbDep, days: int = Query(default=7, ge=1, le=366)):
    end = logic.now().replace(hour=0, minute=0, second=0, microsecond=0) + timedelta(days=1)
    since = end - timedelta(days=days)
    delivered_time = func.coalesce(Order.delivered_at, Order.created_at)
    total, count = db.execute(
        select(func.coalesce(func.sum(Order.total), 0), func.count()).where(
            Order.cafeteria_id == cafe.id, Order.status == DELIVERED, delivered_time >= since, delivered_time < end
        )
    ).one()
    return {"days": days, "total": int(total), "orders": int(count)}


@router.get("/summary")
def daily_summary(cafe: CafeteriaDep, db: DbDep):
    start = logic.now().replace(hour=0, minute=0, second=0, microsecond=0)
    end = start + timedelta(days=1)
    conditions = (Order.cafeteria_id == cafe.id, Order.created_at >= start, Order.created_at < end)
    grouped = dict(db.execute(select(Order.status, func.count()).where(*conditions).group_by(Order.status)).all())
    delivery_conditions = (Order.cafeteria_id == cafe.id, Order.status == DELIVERED,
                           func.coalesce(Order.delivered_at, Order.created_at) >= start,
                           func.coalesce(Order.delivered_at, Order.created_at) < end)
    delivered_count = db.scalar(select(func.count()).select_from(Order).where(*delivery_conditions))
    sales = db.scalar(select(func.coalesce(func.sum(Order.total), 0)).where(*delivery_conditions))
    top = db.execute(select(OrderLine.item_name, func.sum(OrderLine.quantity))
                     .join(Order, Order.id == OrderLine.order_id)
                     .where(*delivery_conditions)
                     .group_by(OrderLine.item_name).order_by(func.sum(OrderLine.quantity).desc()).limit(5)).all()
    return {"date": start.date().isoformat(), "orders": sum(grouped.values()), "sales": int(sales),
            "delivered_orders": delivered_count,
            "active_orders": sum(grouped.get(s, 0) for s in ACTIVE_STATUSES),
            "closed_orders": sum(grouped.get(s, 0) for s in TERMINAL_STATUSES if s != DELIVERED),
            "top_items": [{"name": name, "quantity": int(quantity)} for name, quantity in top]}


@router.get("/orders/{order_id}/events")
def order_events(order_id: str, cafe: CafeteriaDep, db: DbDep):
    order = _own_order(db, cafe, order_id)
    events = db.scalars(select(OrderEvent).where(OrderEvent.order_id == order.id).order_by(OrderEvent.id)).all()
    return [{"status": e.status, "actor": e.actor, "reason": e.reason,
             "created_at": e.created_at.isoformat(timespec="seconds")} for e in events]
