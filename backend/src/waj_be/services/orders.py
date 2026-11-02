import os
from datetime import timedelta
from decimal import Decimal

from fastapi import HTTPException
from sqlalchemy import func, text
from sqlmodel import Session, select

from waj_be.models import Cafeteria, Item, Order, OrderItem, User, utc_now
from waj_be.schemas.orders import OrderCreate, OrderLineRead, OrderRead
from waj_be.services.qr import generate_order_qr_data_url

MAX_ORDERS_PER_STUDENT_PER_15_MINUTES = int(
    os.getenv("MAX_ORDERS_PER_STUDENT_PER_15_MINUTES", "10")
)
if MAX_ORDERS_PER_STUDENT_PER_15_MINUTES < 1:
    raise RuntimeError("MAX_ORDERS_PER_STUDENT_PER_15_MINUTES must be at least 1")

ORDER_WINDOW = timedelta(minutes=15)


def place_order(session: Session, user: User, payload: OrderCreate) -> tuple[Order, Cafeteria]:
    cafeteria = session.get(Cafeteria, payload.cafeteria_id)
    if cafeteria is None:
        raise HTTPException(status_code=404, detail="Cafeteria not found")
    if not cafeteria.is_open:
        raise HTTPException(status_code=409, detail="Cafeteria is closed")

    item_ids = [line.item_id for line in payload.items]
    items = session.exec(select(Item).where(Item.id.in_(item_ids))).all()
    items_by_id = {item.id: item for item in items}
    if len(items_by_id) != len(item_ids):
        raise HTTPException(status_code=404, detail="One or more menu items were not found")
    if any(item.cafeteria_id != cafeteria.id or not item.is_available for item in items):
        raise HTTPException(status_code=409, detail="An item is unavailable at this cafeteria")

    # Serialize this student's attempts so concurrent requests cannot exceed the limit.
    session.connection().execute(
        text("SELECT pg_advisory_xact_lock(:namespace, :student_id)"),
        {"namespace": 73104, "student_id": user.id},
    )
    now = utc_now()
    window_start = now - ORDER_WINDOW
    recent_orders = session.exec(
        select(func.count(Order.id)).where(
            Order.user_id == user.id,
            Order.created_at >= window_start,
        )
    ).one()
    if recent_orders >= MAX_ORDERS_PER_STUDENT_PER_15_MINUTES:
        oldest_recent = session.exec(
            select(Order.created_at)
            .where(Order.user_id == user.id, Order.created_at >= window_start)
            .order_by(Order.created_at)
        ).first()
        retry_after = max(
            1,
            int((oldest_recent + ORDER_WINDOW - now).total_seconds()) if oldest_recent else 1,
        )
        raise HTTPException(
            status_code=429,
            detail="You have reached your order limit for this 15-minute window",
            headers={"Retry-After": str(retry_after)},
        )

    total = sum(
        (items_by_id[line.item_id].price * line.quantity for line in payload.items),
        start=Decimal("0.00"),
    )
    order = Order(
        user_id=user.id,
        cafeteria_id=cafeteria.id,
        total_amount=total,
        created_at=now,
    )
    session.add(order)
    session.flush()
    for line in payload.items:
        item = items_by_id[line.item_id]
        session.add(
            OrderItem(
                order_id=order.id,
                item_id=item.id,
                quantity=line.quantity,
                unit_price=item.price,
            )
        )
    session.commit()
    session.refresh(order)
    return order, cafeteria


def serialize_order(session: Session, order: Order, *, include_qr: bool) -> OrderRead:
    rows = session.exec(
        select(OrderItem, Item)
        .join(Item, Item.id == OrderItem.item_id)
        .where(OrderItem.order_id == order.id)
        .order_by(OrderItem.id)
    ).all()
    lines = [
        OrderLineRead(
            item_id=order_item.item_id,
            item_name=item.name,
            quantity=order_item.quantity,
            unit_price=order_item.unit_price,
        )
        for order_item, item in rows
    ]
    return OrderRead(
        id=order.id,
        user_id=order.user_id,
        cafeteria_id=order.cafeteria_id,
        status=order.status,
        total_amount=order.total_amount,
        created_at=order.created_at,
        received_at=order.received_at,
        qr_token=order.qr_token if include_qr else None,
        qr_image_data_url=generate_order_qr_data_url(order.qr_token) if include_qr else None,
        items=lines,
    )


def get_owned_cafeteria_order(order_id: int, user: User, session: Session) -> Order:
    order = session.get(Order, order_id)
    if order is None:
        raise HTTPException(status_code=404, detail="Order not found")
    cafeteria = session.get(Cafeteria, order.cafeteria_id)
    if cafeteria is None or cafeteria.owner_id != user.id:
        raise HTTPException(status_code=403, detail="You do not manage this order")
    return order
