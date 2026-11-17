from datetime import datetime

from sqlalchemy import JSON, Boolean, DateTime, ForeignKey, Integer, LargeBinary, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .database import Base

# حالات الطلب الأربع بالترتيب
RECEIVED = "received"  # تم استلام الطلب
PREPARING = "preparing"  # قيد التحضير
READY = "ready"  # جاهز للاستلام
DELIVERED = "delivered"  # تم التسليم
CANCELLED = "cancelled"
REJECTED = "rejected"
STATUSES = [RECEIVED, PREPARING, READY, DELIVERED]
ACTIVE_STATUSES = [RECEIVED, PREPARING, READY]
TERMINAL_STATUSES = [DELIVERED, CANCELLED, REJECTED]

# حالات الكافيتريا
OPEN, BUSY, CLOSED = "open", "busy", "closed"
CAFETERIA_STATUSES = [OPEN, BUSY, CLOSED]


class Student(Base):
    __tablename__ = "students"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(100))
    university_id: Mapped[str] = mapped_column(String(20), unique=True, index=True)
    phone: Mapped[str] = mapped_column(String(20), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(100))
    auth_version: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.now)

    @property
    def public_university_id(self) -> str:
        # New accounts keep an internal key for the legacy non-null unique column.
        return "" if self.university_id.startswith("sys_") else self.university_id


class PlatformAdmin(Base):
    __tablename__ = "platform_admins"

    id: Mapped[int] = mapped_column(primary_key=True)
    username: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(100))
    auth_version: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.now)


class Cafeteria(Base):
    __tablename__ = "cafeterias"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(100), unique=True)
    location: Mapped[str] = mapped_column(String(200), default="")
    open_hour: Mapped[int] = mapped_column(Integer, default=8)
    close_hour: Mapped[int] = mapped_column(Integer, default=16)
    code_hash: Mapped[str] = mapped_column(String(100))  # الرمز السري لمسؤول الكافيتريا
    auth_version: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    manual_status: Mapped[str | None] = mapped_column(String(10), nullable=True)  # None = تلقائي

    menu_items: Mapped[list["MenuItem"]] = relationship(back_populates="cafeteria")


class MenuItem(Base):
    __tablename__ = "menu_items"

    id: Mapped[int] = mapped_column(primary_key=True)
    cafeteria_id: Mapped[int] = mapped_column(ForeignKey("cafeterias.id"), index=True)
    name: Mapped[str] = mapped_column(String(100))
    price: Mapped[int] = mapped_column(Integer)  # بالدينار العراقي
    prep_minutes: Mapped[int] = mapped_column(Integer, default=5)
    available: Mapped[bool] = mapped_column(Boolean, default=True)
    emoji: Mapped[str] = mapped_column(String(10), default="🍽️")
    image_url: Mapped[str | None] = mapped_column(String(500), nullable=True)  # رابط خارجي (اختياري)
    # الصورة المرفوعة من لوحة التحكم تُحفظ في قاعدة البيانات نفسها حتى لا تضيع عند إعادة النشر
    image_data: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True, deferred=True)
    image_mime: Mapped[str | None] = mapped_column(String(30), nullable=True)
    image_version: Mapped[int] = mapped_column(Integer, default=0)  # لتجاوز ذاكرة المتصفح عند تغيير الصورة
    deleted: Mapped[bool] = mapped_column(Boolean, default=False)  # حذف ناعم حتى يبقى سجل الطلبات سليماً
    ingredients: Mapped[list[str]] = mapped_column(JSON, default=list, server_default="[]")
    removable_ingredients: Mapped[list[str]] = mapped_column(JSON, default=list, server_default="[]")

    cafeteria: Mapped[Cafeteria] = relationship(back_populates="menu_items")


class Order(Base):
    __tablename__ = "orders"

    id: Mapped[str] = mapped_column(String(10), primary_key=True)  # رقم قصير يُعرض ويُشفَّر في QR
    student_id: Mapped[int] = mapped_column(ForeignKey("students.id"), index=True)
    cafeteria_id: Mapped[int] = mapped_column(ForeignKey("cafeterias.id"), index=True)
    status: Mapped[str] = mapped_column(String(15), default=RECEIVED)
    pickup_time: Mapped[datetime] = mapped_column(DateTime)
    payment_method: Mapped[str] = mapped_column(String(30))
    total: Mapped[int] = mapped_column(Integer)
    prep_minutes: Mapped[int] = mapped_column(Integer)
    arrived: Mapped[bool] = mapped_column(Boolean, default=False)
    rating: Mapped[int | None] = mapped_column(Integer, nullable=True)
    rating_comment: Mapped[str | None] = mapped_column(String(300), nullable=True)
    closure_reason: Mapped[str | None] = mapped_column(String(300), nullable=True)
    delivered_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.now)

    student: Mapped[Student] = relationship()
    cafeteria: Mapped[Cafeteria] = relationship()
    lines: Mapped[list["OrderLine"]] = relationship(back_populates="order", cascade="all, delete-orphan")


class OrderLine(Base):
    __tablename__ = "order_lines"

    id: Mapped[int] = mapped_column(primary_key=True)
    order_id: Mapped[str] = mapped_column(ForeignKey("orders.id"), index=True)
    menu_item_id: Mapped[int] = mapped_column(ForeignKey("menu_items.id"))
    item_name: Mapped[str] = mapped_column(String(100))  # نسخة من الاسم والسعر وقت الطلب
    unit_price: Mapped[int] = mapped_column(Integer)
    quantity: Mapped[int] = mapped_column(Integer)
    note: Mapped[str] = mapped_column(String(100), default="")

    order: Mapped[Order] = relationship(back_populates="lines")


class OrderRequest(Base):
    """One durable result per checkout attempt, including retries after a lost response."""

    __tablename__ = "order_requests"
    __table_args__ = (UniqueConstraint("student_id", "request_key"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    student_id: Mapped[int] = mapped_column(ForeignKey("students.id"))
    request_key: Mapped[str] = mapped_column(String(100))
    fingerprint: Mapped[str] = mapped_column(String(64))
    order_id: Mapped[str] = mapped_column(ForeignKey("orders.id"))


class Favorite(Base):
    __tablename__ = "favorites"
    __table_args__ = (UniqueConstraint("student_id", "menu_item_id"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    student_id: Mapped[int] = mapped_column(ForeignKey("students.id"), index=True)
    menu_item_id: Mapped[int] = mapped_column(ForeignKey("menu_items.id"))


class DeviceToken(Base):
    """أجهزة الطالب المسجلة لإشعارات Push (Firebase Cloud Messaging)."""

    __tablename__ = "device_tokens"

    id: Mapped[int] = mapped_column(primary_key=True)
    student_id: Mapped[int] = mapped_column(ForeignKey("students.id"), index=True)
    token: Mapped[str] = mapped_column(String(500), unique=True)
    platform: Mapped[str] = mapped_column(String(20), default="android")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.now)


class Notification(Base):
    __tablename__ = "notifications"

    id: Mapped[int] = mapped_column(primary_key=True)
    student_id: Mapped[int] = mapped_column(ForeignKey("students.id"), index=True)
    order_id: Mapped[str | None] = mapped_column(String(10), nullable=True)
    title: Mapped[str] = mapped_column(String(200))
    body: Mapped[str] = mapped_column(String(500))
    read: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.now)


class LoginAttempt(Base):
    __tablename__ = "login_attempts"

    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    window_start: Mapped[datetime] = mapped_column(DateTime)


class OrderEvent(Base):
    __tablename__ = "order_events"

    id: Mapped[int] = mapped_column(primary_key=True)
    order_id: Mapped[str] = mapped_column(ForeignKey("orders.id"), index=True)
    status: Mapped[str] = mapped_column(String(15))
    actor: Mapped[str] = mapped_column(String(20))
    reason: Mapped[str | None] = mapped_column(String(300), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime)


class SchemaMigration(Base):
    __tablename__ = "schema_migrations"

    version: Mapped[int] = mapped_column(Integer, primary_key=True)
    applied_at: Mapped[datetime] = mapped_column(DateTime)
