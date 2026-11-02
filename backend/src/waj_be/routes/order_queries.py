from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session, select

from waj_be.database import get_session
from waj_be.models import Cafeteria, Order, User, UserRole
from waj_be.routes.auth import get_current_user
from waj_be.schemas.orders import OrderRead
from waj_be.services.orders import serialize_order

router = APIRouter(tags=["orders"])


@router.get("/orders/mine", response_model=list[OrderRead])
def list_my_orders(
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> list[OrderRead]:
    orders = session.exec(
        select(Order).where(Order.user_id == user.id).order_by(Order.created_at.desc())
    ).all()
    return [serialize_order(session, order, include_qr=True) for order in orders]


@router.get("/orders/{order_id}", response_model=OrderRead)
def get_order(
    order_id: int,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> OrderRead:
    order = session.get(Order, order_id)
    if order is None:
        raise HTTPException(status_code=404, detail="Order not found")
    cafeteria = session.get(Cafeteria, order.cafeteria_id)
    is_customer = order.user_id == user.id
    is_cafeteria_owner = cafeteria is not None and cafeteria.owner_id == user.id
    if not is_customer and not is_cafeteria_owner:
        raise HTTPException(status_code=403, detail="You cannot view this order")
    return serialize_order(session, order, include_qr=is_customer)


@router.get("/cafeterias/{cafeteria_id}/orders", response_model=list[OrderRead])
def list_cafeteria_orders(
    cafeteria_id: int,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> list[OrderRead]:
    cafeteria = session.get(Cafeteria, cafeteria_id)
    if cafeteria is None:
        raise HTTPException(status_code=404, detail="Cafeteria not found")
    if cafeteria.owner_id != user.id or user.role != UserRole.CAFETERIA_OWNER:
        raise HTTPException(status_code=403, detail="You do not manage this cafeteria")
    orders = session.exec(
        select(Order)
        .where(Order.cafeteria_id == cafeteria_id)
        .order_by(Order.created_at)
    ).all()
    return [serialize_order(session, order, include_qr=False) for order in orders]
