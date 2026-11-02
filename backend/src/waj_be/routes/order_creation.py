from fastapi import APIRouter, Depends, HTTPException, status
from sqlmodel import Session

from waj_be.database import get_session
from waj_be.models import User, UserRole
from waj_be.routes.auth import get_current_user
from waj_be.schemas.orders import OrderCreate, OrderRead
from waj_be.services.orders import place_order, serialize_order
from waj_be.services.realtime import broadcast_order_event

router = APIRouter(tags=["orders"])


@router.post("/orders", response_model=OrderRead, status_code=status.HTTP_201_CREATED)
async def create_order(
    payload: OrderCreate,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> OrderRead:
    if user.role != UserRole.STUDENT:
        raise HTTPException(status_code=403, detail="Only students can place orders")

    order, cafeteria = place_order(session, user, payload)
    await broadcast_order_event(
        cafeteria.id,
        {"event": "order.created", "order_id": order.id, "status": order.status.value},
    )
    return serialize_order(session, order, include_qr=True)
