from datetime import datetime, timezone
from decimal import Decimal
from enum import Enum

from sqlalchemy import Numeric, UniqueConstraint
from sqlmodel import Field, SQLModel

from waj_be.services.qr import create_order_qr_token


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


class UserRole(str, Enum):
    STUDENT = "student"
    CAFETERIA_OWNER = "cafeteria_owner"
    ADMIN = "admin"


class OwnerApplicationStatus(str, Enum):
    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"


class OrderStatus(str, Enum):
    NEW = "new"
    PREPARING = "preparing"
    READY = "ready"
    RECEIVED = "received"


class User(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    full_name: str = Field(min_length=2, max_length=120)
    phone_number: str = Field(max_length=16, unique=True, index=True)
    password_hash: str = Field(max_length=255)
    role: UserRole = Field(default=UserRole.STUDENT, index=True)
    phone_verified: bool = Field(default=False)
    is_active: bool = Field(default=True)
    created_at: datetime = Field(default_factory=utc_now)


class OwnerApplication(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="user.id", unique=True, index=True)
    status: OwnerApplicationStatus = Field(default=OwnerApplicationStatus.PENDING, index=True)
    submitted_at: datetime = Field(default_factory=utc_now)
    reviewed_at: datetime | None = None
    reviewed_by_id: int | None = Field(default=None, foreign_key="user.id")


class Cafeteria(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    owner_id: int = Field(foreign_key="user.id", index=True)
    name: str = Field(min_length=2, max_length=120, index=True)
    description: str | None = Field(default=None, max_length=1000)
    location: str | None = Field(default=None, max_length=255)
    is_open: bool = Field(default=True)
    created_at: datetime = Field(default_factory=utc_now)


class Item(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    cafeteria_id: int = Field(foreign_key="cafeteria.id", index=True)
    name: str = Field(min_length=1, max_length=120, index=True)
    description: str | None = Field(default=None, max_length=1000)
    price: Decimal = Field(sa_type=Numeric(10, 2), gt=0)
    is_available: bool = Field(default=True)
    created_at: datetime = Field(default_factory=utc_now)


class Order(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="user.id", index=True)
    cafeteria_id: int = Field(foreign_key="cafeteria.id", index=True)
    status: OrderStatus = Field(default=OrderStatus.NEW, index=True)
    total_amount: Decimal = Field(default=Decimal("0.00"), sa_type=Numeric(10, 2), ge=0)
    qr_token: str = Field(default_factory=create_order_qr_token, unique=True, index=True)
    created_at: datetime = Field(default_factory=utc_now, index=True)
    received_at: datetime | None = None


class OrderItem(SQLModel, table=True):
    __table_args__ = (UniqueConstraint("order_id", "item_id", name="uq_order_item"),)

    id: int | None = Field(default=None, primary_key=True)
    order_id: int = Field(foreign_key="order.id", index=True)
    item_id: int = Field(foreign_key="item.id", index=True)
    quantity: int = Field(gt=0)
    # Snapshot the price so later menu price changes do not alter old orders.
    unit_price: Decimal = Field(sa_type=Numeric(10, 2), gt=0)


class Rating(SQLModel, table=True):
    __table_args__ = (UniqueConstraint("order_id", name="uq_rating_order"),)

    id: int | None = Field(default=None, primary_key=True)
    order_id: int = Field(foreign_key="order.id", index=True)
    user_id: int = Field(foreign_key="user.id", index=True)
    cafeteria_id: int = Field(foreign_key="cafeteria.id", index=True)
    stars: int = Field(ge=1, le=5)
    comment: str | None = Field(default=None, max_length=1000)
    created_at: datetime = Field(default_factory=utc_now)
