from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, Field, model_validator

from waj_be.models import OrderStatus


class OrderLineInput(BaseModel):
    item_id: int = Field(gt=0)
    quantity: int = Field(ge=1, le=25)


class OrderCreate(BaseModel):
    cafeteria_id: int = Field(gt=0)
    items: list[OrderLineInput] = Field(min_length=1, max_length=25)

    @model_validator(mode="after")
    def reject_duplicate_items(self):
        item_ids = [line.item_id for line in self.items]
        if len(item_ids) != len(set(item_ids)):
            raise ValueError("Each item must appear only once; increase its quantity instead")
        return self


class OrderLineRead(BaseModel):
    item_id: int
    item_name: str
    quantity: int
    unit_price: Decimal


class OrderRead(BaseModel):
    id: int
    user_id: int
    cafeteria_id: int
    status: OrderStatus
    total_amount: Decimal
    created_at: datetime
    received_at: datetime | None
    qr_token: str | None = None
    qr_image_data_url: str | None = None
    items: list[OrderLineRead]


class OrderStatusUpdate(BaseModel):
    status: OrderStatus


class QRVerificationRequest(BaseModel):
    qr_token: str = Field(min_length=20, max_length=100)
