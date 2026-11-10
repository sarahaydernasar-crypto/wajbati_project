"""واجهات الطالب: الحساب، الكافيتريات، القائمة، الطلبات، التقييم، المفضلة، الإشعارات."""

import random
import hashlib
import re
from datetime import datetime

from fastapi import APIRouter, HTTPException, Response, status
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import select, update

from . import logic, push
from .models import (
    CLOSED,
    CANCELLED,
    ACTIVE_STATUSES,
    DELIVERED,
    RECEIVED,
    Cafeteria,
    DeviceToken,
    Favorite,
    MenuItem,
    Notification,
    Order,
    OrderLine,
    OrderRequest,
    Student,
)
from .security import DbDep, StudentDep, create_token, hash_secret, verify_secret
from .rate_limit import check_login

router = APIRouter()

PHONE_RE = re.compile(r"^07\d{9}$")


def normalize_phone(p: str) -> str:
    return re.sub(r"[\s-]", "", p)


def student_json(s: Student) -> dict:
    return {"id": s.id, "name": s.name, "university_id": s.university_id, "phone": s.phone}


# ---------------- الحساب ----------------
class RegisterIn(BaseModel):
    name: str = Field(min_length=3, max_length=100)
    university_id: str
    phone: str
    password: str = Field(min_length=6, max_length=100)

    @field_validator("name")
    @classmethod
    def _name(cls, v: str) -> str:
        v = v.strip()
        if len(v) < 3:
            raise ValueError("أدخل اسماً من ثلاثة أحرف على الأقل")
        return v

    @field_validator("password")
    @classmethod
    def _password(cls, v: str) -> str:
        if len(v.encode()) > 72:
            raise ValueError("كلمة المرور طويلة جداً، استخدم حتى 72 بايت")
        return v

    @field_validator("university_id")
    @classmethod
    def _uni(cls, v: str) -> str:
        v = v.strip()
        if not re.fullmatch(r"\d{4,12}", v):
            raise ValueError("رقم جامعي غير صالح (أرقام فقط)")
        return v

    @field_validator("phone")
    @classmethod
    def _phone(cls, v: str) -> str:
        v = normalize_phone(v)
        if not PHONE_RE.fullmatch(v):
            raise ValueError("رقم هاتف غير صالح (مثال: 07701234567)")
        return v


class LoginIn(BaseModel):
    phone: str
    password: str


@router.post("/auth/register", status_code=201, tags=["auth"])
def register(body: RegisterIn, db: DbDep):
    if db.scalar(select(Student).where(Student.phone == body.phone)):
        raise HTTPException(status.HTTP_409_CONFLICT, "رقم الهاتف مسجّل مسبقاً، جرّب تسجيل الدخول.")
    if db.scalar(select(Student).where(Student.university_id == body.university_id)):
        raise HTTPException(status.HTTP_409_CONFLICT, "الرقم الجامعي مستخدم في حساب آخر.")
    student = Student(
        name=body.name, university_id=body.university_id, phone=body.phone, password_hash=hash_secret(body.password)
    )
    db.add(student)
    db.commit()
    return {"token": create_token(student.id, "student", student.auth_version), "student": student_json(student)}


@router.post("/auth/login", tags=["auth"])
def login(body: LoginIn, db: DbDep):
    check_login(db, "student:" + normalize_phone(body.phone))
    student = db.scalar(select(Student).where(Student.phone == normalize_phone(body.phone)))
    if student is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "لا يوجد حساب بهذا الرقم. أنشئ حساباً جديداً.")
    if not verify_secret(body.password, student.password_hash):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "كلمة المرور غير صحيحة.")
    return {"token": create_token(student.id, "student", student.auth_version), "student": student_json(student)}


class PasswordChangeIn(BaseModel):
    current_password: str = Field(max_length=100)
    new_password: str = Field(min_length=8, max_length=72)

    @field_validator("new_password")
    @classmethod
    def password_bytes(cls, value: str) -> str:
        if len(value.encode()) > 72:
            raise ValueError("كلمة المرور طويلة جداً، استخدم حتى 72 بايت")
        return value


@router.post("/auth/password", tags=["auth"])
def change_password(body: PasswordChangeIn, student: StudentDep, db: DbDep):
    db.execute(update(Student).where(Student.id == student.id).values(id=student.id))
    db.refresh(student)
    if not verify_secret(body.current_password, student.password_hash):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "كلمة المرور الحالية غير صحيحة")
    student.password_hash = hash_secret(body.new_password)
    student.auth_version += 1
    db.commit()
    return {"token": create_token(student.id, "student", student.auth_version)}


@router.get("/me", tags=["auth"])
def me(student: StudentDep):
    return student_json(student)


# ---------------- الكافيتريات والقائمة (عامة) ----------------
def get_cafeteria(db, cafeteria_id: int) -> Cafeteria:
    cafe = db.get(Cafeteria, cafeteria_id)
    if cafe is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "الكافيتريا غير موجودة")
    return cafe


@router.get("/cafeterias", tags=["cafeterias"])
def list_cafeterias(db: DbDep):
    cafes = db.scalars(select(Cafeteria).order_by(Cafeteria.id)).all()
    return [logic.cafeteria_json(db, c) for c in cafes]


@router.get("/cafeterias/{cafeteria_id}/menu", tags=["cafeterias"])
def cafeteria_menu(cafeteria_id: int, db: DbDep):
    get_cafeteria(db, cafeteria_id)
    items = db.scalars(
        select(MenuItem).where(MenuItem.cafeteria_id == cafeteria_id, MenuItem.deleted.is_(False)).order_by(MenuItem.id)
    ).all()
    return logic.menu_json(db, list(items))


@router.get("/cafeterias/{cafeteria_id}/slots", tags=["cafeterias"])
def cafeteria_slots(cafeteria_id: int, db: DbDep, prep_minutes: int = 5):
    cafe = get_cafeteria(db, cafeteria_id)
    if logic.cafeteria_status(db, cafe) == CLOSED:
        return []
    return logic.pickup_slots(db, cafe, max(0, min(prep_minutes, 120)))


# ---------------- الطلبات ----------------
class OrderLineIn(BaseModel):
    menu_item_id: int
    quantity: int = Field(ge=1, le=20)
    note: str = Field(default="", max_length=80)


class OrderIn(BaseModel):
    cafeteria_id: int
    pickup_time: datetime
    payment_method: str = Field(min_length=1, max_length=30)
    lines: list[OrderLineIn] = Field(min_length=1, max_length=30)
    request_key: str | None = Field(default=None, min_length=16, max_length=100, pattern=r"^[A-Za-z0-9_-]+$")


def _new_order_id(db) -> str:
    while True:
        oid = f"{random.randint(0, 999999):06d}"
        if db.get(Order, oid) is None:
            return oid


@router.post("/orders", status_code=201, tags=["orders"])
def create_order(body: OrderIn, student: StudentDep, db: DbDep):
    # Lock the student first so a reused key cannot create orders in two cafes.
    db.execute(update(Student).where(Student.id == student.id).values(id=student.id))
    fingerprint = hashlib.sha256(body.model_dump_json(exclude={"request_key"}).encode()).hexdigest()
    if body.request_key:
        previous = db.scalar(select(OrderRequest).where(
            OrderRequest.student_id == student.id, OrderRequest.request_key == body.request_key
        ))
        if previous:
            if previous.fingerprint != fingerprint:
                raise HTTPException(status.HTTP_409_CONFLICT, "هذه المحاولة مرتبطة بطلب مختلف. حدّث السلة وحاول مجدداً.")
            return logic.order_json(db.get(Order, previous.order_id))
    logic.lock_cafeteria(db, body.cafeteria_id)
    cafe = get_cafeteria(db, body.cafeteria_id)
    db.refresh(cafe)
    if logic.cafeteria_status(db, cafe) == CLOSED:
        raise HTTPException(status.HTTP_409_CONFLICT, "الكافيتريا مغلقة حالياً، لا يمكن الطلب منها.")

    items = {
        i.id: i
        for i in db.scalars(select(MenuItem).where(MenuItem.id.in_([line.menu_item_id for line in body.lines]))).all()
    }
    unavailable = []
    for line in body.lines:
        item = items.get(line.menu_item_id)
        if item is None or item.cafeteria_id != cafe.id or item.deleted:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "أحد الأصناف غير موجود في قائمة هذه الكافيتريا.")
        if not item.available:
            unavailable.append(item.name)
    if unavailable:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            f"نفدت هذه الأصناف أثناء الطلب: {'، '.join(unavailable)}. احذفها من السلة وحاول مجدداً.",
        )

    prep = max(items[line.menu_item_id].prep_minutes for line in body.lines)
    pickup = body.pickup_time.replace(tzinfo=None, second=0, microsecond=0)
    slot = next((s for s in logic.pickup_slots(db, cafe, prep) if s["time"] == pickup.isoformat(timespec="minutes")), None)
    if slot is None or not slot["available"]:
        raise HTTPException(status.HTTP_409_CONFLICT, "وقت الاستلام المختار لم يعد متاحاً، اختر وقتاً آخر.")

    order = Order(
        id=_new_order_id(db),
        student_id=student.id,
        cafeteria_id=cafe.id,
        pickup_time=pickup,
        payment_method=body.payment_method,
        prep_minutes=prep,
        total=sum(items[line.menu_item_id].price * line.quantity for line in body.lines),
        created_at=logic.now(),
    )
    order.lines = [
        OrderLine(
            menu_item_id=line.menu_item_id,
            item_name=items[line.menu_item_id].name,
            unit_price=items[line.menu_item_id].price,
            quantity=line.quantity,
            note=line.note.strip(),
        )
        for line in body.lines
    ]
    db.add(order)
    db.flush()
    logic.record_order_event(db, order, "student")
    if body.request_key:
        db.add(OrderRequest(student_id=student.id, request_key=body.request_key,
                            fingerprint=fingerprint, order_id=order.id))
    logic.notify(
        db,
        student.id,
        f"تم إرسال طلبك #{order.id}",
        f"سيكون جاهزاً للاستلام الساعة {pickup.strftime('%H:%M')} من {cafe.name}",
        order.id,
    )
    db.commit()
    db.refresh(order)
    return logic.order_json(order)


@router.get("/orders/mine", tags=["orders"])
def my_orders(student: StudentDep, db: DbDep):
    orders = db.scalars(
        select(Order).where(Order.student_id == student.id).order_by(Order.created_at.desc()).limit(100)
    ).all()
    return [logic.order_json(o) for o in orders]


def _own_order(db, student: Student, order_id: str) -> Order:
    order = db.get(Order, order_id)
    if order is None or order.student_id != student.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "لم يتم العثور على الطلب")
    return order


@router.get("/orders/{order_id}", tags=["orders"])
def get_order(order_id: str, student: StudentDep, db: DbDep):
    return logic.order_json(_own_order(db, student, order_id))


@router.post("/orders/{order_id}/cancel", tags=["orders"])
def cancel_order(order_id: str, student: StudentDep, db: DbDep):
    order = _own_order(db, student, order_id)
    logic.lock_cafeteria(db, order.cafeteria_id)
    db.refresh(order)
    if order.status != RECEIVED:
        raise HTTPException(status.HTTP_409_CONFLICT, "يمكن إلغاء الطلب قبل بدء التحضير فقط.")
    order.status = CANCELLED
    order.closure_reason = "ألغى الطالب الطلب قبل بدء التحضير"
    logic.notify_status_change(db, order, "student")
    db.commit()
    return logic.order_json(order)


@router.post("/orders/{order_id}/arrived", tags=["orders"])
def mark_arrived(order_id: str, student: StudentDep, db: DbDep):
    order = _own_order(db, student, order_id)
    logic.lock_cafeteria(db, order.cafeteria_id)
    db.refresh(order)
    if order.status not in ACTIVE_STATUSES:
        raise HTTPException(status.HTTP_409_CONFLICT, "هذا الطلب منتهٍ.")
    order.arrived = True
    db.commit()
    return logic.order_json(order)


class RatingIn(BaseModel):
    stars: int = Field(ge=1, le=5)
    comment: str = Field(default="", max_length=300)


@router.post("/orders/{order_id}/rating", tags=["orders"])
def rate_order(order_id: str, body: RatingIn, student: StudentDep, db: DbDep):
    order = _own_order(db, student, order_id)
    if order.status != DELIVERED:
        raise HTTPException(status.HTTP_409_CONFLICT, "يمكن التقييم بعد استلام الطلب فقط.")
    if order.rating is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "قيّمت هذا الطلب مسبقاً.")
    order.rating = body.stars
    order.rating_comment = body.comment.strip() or None
    db.commit()
    return logic.order_json(order)


# ---------------- المفضلة ----------------
@router.get("/favorites", tags=["favorites"])
def list_favorites(student: StudentDep, db: DbDep):
    items = db.scalars(
        select(MenuItem)
        .join(Favorite, Favorite.menu_item_id == MenuItem.id)
        .where(Favorite.student_id == student.id, MenuItem.deleted.is_(False))
    ).all()
    return logic.menu_json(db, list(items))


@router.put("/favorites/{item_id}", status_code=204, tags=["favorites"])
def add_favorite(item_id: int, student: StudentDep, db: DbDep):
    item = db.get(MenuItem, item_id)
    if item is None or item.deleted:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "الصنف غير موجود")
    exists = db.scalar(select(Favorite).where(Favorite.student_id == student.id, Favorite.menu_item_id == item_id))
    if not exists:
        db.add(Favorite(student_id=student.id, menu_item_id=item_id))
        db.commit()


@router.delete("/favorites/{item_id}", status_code=204, tags=["favorites"])
def remove_favorite(item_id: int, student: StudentDep, db: DbDep):
    fav = db.scalar(select(Favorite).where(Favorite.student_id == student.id, Favorite.menu_item_id == item_id))
    if fav:
        db.delete(fav)
        db.commit()


# ---------------- صور الأصناف (عامة) ----------------
@router.get("/menu/{item_id}/image", tags=["cafeterias"])
def menu_item_image(item_id: int, db: DbDep):
    item = db.get(MenuItem, item_id)
    if item is None or item.image_data is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "لا توجد صورة لهذا الصنف")
    # الرابط يحتوي رقم إصدار الصورة، لذلك يمكن تخزينها طويلاً في المتصفح
    return Response(
        content=item.image_data,
        media_type=item.image_mime or "image/jpeg",
        headers={"Cache-Control": "public, max-age=31536000, immutable"},
    )


# ---------------- أجهزة إشعارات Push ----------------
class DeviceIn(BaseModel):
    token: str = Field(min_length=10, max_length=500)
    platform: str = Field(default="android", max_length=20)


@router.post("/devices", status_code=204, tags=["notifications"])
def register_device(body: DeviceIn, student: StudentDep, db: DbDep):
    """يسجّل رمز FCM لهاتف الطالب (إذا كان الرمز لطالب آخر على نفس الجهاز يُنقل للحالي)."""
    existing = db.scalar(select(DeviceToken).where(DeviceToken.token == body.token))
    if existing:
        existing.student_id = student.id
        existing.platform = body.platform
    else:
        db.add(DeviceToken(student_id=student.id, token=body.token, platform=body.platform))
    db.commit()


@router.post("/devices/unregister", status_code=204, tags=["notifications"])
def unregister_device(body: DeviceIn, student: StudentDep, db: DbDep):
    """عند تسجيل الخروج: إيقاف الإشعارات على هذا الجهاز."""
    existing = db.scalar(
        select(DeviceToken).where(DeviceToken.token == body.token, DeviceToken.student_id == student.id)
    )
    if existing:
        db.delete(existing)
        db.commit()


@router.get("/push/status", tags=["notifications"])
def push_status():
    return {"enabled": push.enabled()}


# ---------------- الإشعارات ----------------
@router.get("/notifications", tags=["notifications"])
def list_notifications(student: StudentDep, db: DbDep, after_id: int = 0):
    rows = db.scalars(
        select(Notification)
        .where(Notification.student_id == student.id, Notification.id > after_id)
        .order_by(Notification.id.desc())
        .limit(100)
    ).all()
    return [logic.notification_json(n) for n in rows]


@router.post("/notifications/read-all", status_code=204, tags=["notifications"])
def read_all(student: StudentDep, db: DbDep):
    for n in db.scalars(
        select(Notification).where(Notification.student_id == student.id, Notification.read.is_(False))
    ).all():
        n.read = True
    db.commit()
