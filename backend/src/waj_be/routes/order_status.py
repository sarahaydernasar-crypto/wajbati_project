from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session

from waj_be.database import get_session
from waj_be.models import OrderStatus, User, UserRole, utc_now
from waj_be.routes.auth import get_current_user
from waj_be.schemas.orders import OrderRead, OrderStatusUpdate, QRVerificationRequest
from waj_be.services.orders import get_owned_cafeteria_order, serialize_order
from waj_be.services.qr import verify_order_qr_token
from waj_be.services.realtime import broadcast_order_event

router = APIRouter(tags=["orders"])


@router.patch("/orders/{order_id}/status", response_model=OrderRead)
async def update_order_status(
    order_id: int,
    payload: OrderStatusUpdate,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> OrderRead:
    if user.role != UserRole.CAFETERIA_OWNER:
        raise HTTPException(status_code=403, detail="Cafeteria owner role required")
    order = get_owned_cafeteria_order(order_id, user, session)
    allowed_next = {
        OrderStatus.NEW: OrderStatus.PREPARING,
        OrderStatus.PREPARING: OrderStatus.READY,
    }
    if allowed_next.get(order.status) != payload.status:
        raise HTTPException(status_code=409, detail="Invalid order status transition")

    order.status = payload.status
    session.add(order)
    session.commit()
    session.refresh(order)
    await broadcast_order_event(
        order.cafeteria_id,
        {"event": "order.status_changed", "order_id": order.id, "status": order.status.value},
    )
    return serialize_order(session, order, include_qr=False)


@router.post("/orders/{order_id}/receive", response_model=OrderRead)
async def receive_order(
    order_id: int,
    payload: QRVerificationRequest,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> OrderRead:
    if user.role != UserRole.CAFETERIA_OWNER:
        raise HTTPException(status_code=403, detail="Cafeteria owner role required")
    order = get_owned_cafeteria_order(order_id, user, session)
    if order.status != OrderStatus.READY:
        raise HTTPException(status_code=409, detail="Only ready orders can be received")
    if not verify_order_qr_token(order.qr_token, payload.qr_token):
        raise HTTPException(status_code=400, detail="Invalid QR token")

    order.status = OrderStatus.RECEIVED
    order.received_at = utc_now()
    session.add(order)
    session.commit()
    session.refresh(order)
    await broadcast_order_event(
        order.cafeteria_id,
        {"event": "order.status_changed", "order_id": order.id, "status": order.status.value},
    )
    return serialize_order(session, order, include_qr=False)
