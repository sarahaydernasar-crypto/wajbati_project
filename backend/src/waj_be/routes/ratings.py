from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import func
from sqlmodel import Session, select

from waj_be.database import get_session
from waj_be.models import Cafeteria, Order, OrderItem, OrderStatus, Rating, User
from waj_be.routes.auth import get_current_user

router = APIRouter(tags=["ratings"])


class RatingCreate(BaseModel):
    stars: int = Field(ge=1, le=5)
    comment: str | None = Field(default=None, max_length=1000)


class RatingRead(BaseModel):
    id: int
    order_id: int
    user_id: int
    cafeteria_id: int
    stars: int
    comment: str | None
    created_at: datetime

    model_config = {"from_attributes": True}


class RatingSummary(BaseModel):
    cafeteria_id: int
    rating_count: int
    average_stars: float | None


@router.post(
    "/orders/{order_id}/rating",
    response_model=RatingRead,
    status_code=status.HTTP_201_CREATED,
)
def rate_order(
    order_id: int,
    payload: RatingCreate,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> RatingRead:
    order = session.get(Order, order_id)
    if order is None:
        raise HTTPException(status_code=404, detail="Order not found")
    if order.user_id != user.id:
        raise HTTPException(status_code=403, detail="You can only rate your own orders")
    if order.status != OrderStatus.RECEIVED:
        raise HTTPException(status_code=409, detail="You can rate an order after receiving it")
    if session.exec(select(OrderItem.id).where(OrderItem.order_id == order.id)).first() is None:
        raise HTTPException(status_code=409, detail="Order has no items to rate")
    if session.exec(select(Rating.id).where(Rating.order_id == order.id)).first() is not None:
        raise HTTPException(status_code=409, detail="This order has already been rated")

    rating = Rating(
        order_id=order.id,
        user_id=user.id,
        cafeteria_id=order.cafeteria_id,
        stars=payload.stars,
        comment=payload.comment,
    )
    session.add(rating)
    session.commit()
    session.refresh(rating)
    return rating


@router.get("/cafeterias/{cafeteria_id}/ratings", response_model=list[RatingRead])
def list_cafeteria_ratings(
    cafeteria_id: int,
    session: Session = Depends(get_session),
) -> list[Rating]:
    if session.get(Cafeteria, cafeteria_id) is None:
        raise HTTPException(status_code=404, detail="Cafeteria not found")
    return list(
        session.exec(
            select(Rating)
            .where(Rating.cafeteria_id == cafeteria_id)
            .order_by(Rating.created_at.desc())
        ).all()
    )


@router.get("/cafeterias/{cafeteria_id}/rating-summary", response_model=RatingSummary)
def get_rating_summary(
    cafeteria_id: int,
    session: Session = Depends(get_session),
) -> RatingSummary:
    if session.get(Cafeteria, cafeteria_id) is None:
        raise HTTPException(status_code=404, detail="Cafeteria not found")
    count, average = session.exec(
        select(func.count(Rating.id), func.avg(Rating.stars)).where(
            Rating.cafeteria_id == cafeteria_id
        )
    ).one()
    return RatingSummary(
        cafeteria_id=cafeteria_id,
        rating_count=count,
        average_stars=float(average) if average is not None else None,
    )
