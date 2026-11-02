from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlmodel import Session, select

from waj_be.database import get_session
from waj_be.models import Cafeteria, Item, User, UserRole
from waj_be.routes.auth import get_current_user

router = APIRouter(prefix="/cafeterias", tags=["cafeterias"])


class CafeteriaCreate(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    description: str | None = Field(default=None, max_length=1000)
    location: str | None = Field(default=None, max_length=255)


class CafeteriaRead(BaseModel):
    id: int
    owner_id: int
    name: str
    description: str | None
    location: str | None
    is_open: bool

    model_config = {"from_attributes": True}


class ItemCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=1000)
    price: Decimal = Field(gt=0, max_digits=10, decimal_places=2)


class ItemUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=1000)
    price: Decimal | None = Field(default=None, gt=0, max_digits=10, decimal_places=2)
    is_available: bool | None = None


class ItemRead(BaseModel):
    id: int
    cafeteria_id: int
    name: str
    description: str | None
    price: Decimal
    is_available: bool

    model_config = {"from_attributes": True}


class CafeteriaDetail(CafeteriaRead):
    items: list[ItemRead]


def require_cafeteria_owner(user: User) -> None:
    if user.role != UserRole.CAFETERIA_OWNER:
        raise HTTPException(status_code=403, detail="Cafeteria owner role required")


def get_owned_cafeteria(
    cafeteria_id: int,
    user: User,
    session: Session,
) -> Cafeteria:
    cafeteria = session.get(Cafeteria, cafeteria_id)
    if cafeteria is None:
        raise HTTPException(status_code=404, detail="Cafeteria not found")
    if cafeteria.owner_id != user.id:
        raise HTTPException(status_code=403, detail="You do not own this cafeteria")
    return cafeteria


@router.get("", response_model=list[CafeteriaRead])
def list_cafeterias(session: Session = Depends(get_session)) -> list[Cafeteria]:
    return list(session.exec(select(Cafeteria).order_by(Cafeteria.name)).all())


@router.post("", response_model=CafeteriaRead, status_code=status.HTTP_201_CREATED)
def create_cafeteria(
    payload: CafeteriaCreate,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> Cafeteria:
    require_cafeteria_owner(user)
    cafeteria = Cafeteria(owner_id=user.id, **payload.model_dump())
    session.add(cafeteria)
    session.commit()
    session.refresh(cafeteria)
    return cafeteria


@router.get("/{cafeteria_id}", response_model=CafeteriaDetail)
def get_cafeteria(
    cafeteria_id: int,
    session: Session = Depends(get_session),
) -> CafeteriaDetail:
    cafeteria = session.get(Cafeteria, cafeteria_id)
    if cafeteria is None:
        raise HTTPException(status_code=404, detail="Cafeteria not found")
    items = session.exec(
        select(Item)
        .where(Item.cafeteria_id == cafeteria_id, Item.is_available.is_(True))
        .order_by(Item.name)
    ).all()
    cafeteria_data = CafeteriaRead.model_validate(cafeteria).model_dump()
    return CafeteriaDetail(**cafeteria_data, items=items)


@router.get("/{cafeteria_id}/items", response_model=list[ItemRead])
def list_items(
    cafeteria_id: int,
    session: Session = Depends(get_session),
) -> list[Item]:
    if session.get(Cafeteria, cafeteria_id) is None:
        raise HTTPException(status_code=404, detail="Cafeteria not found")
    return list(
        session.exec(
            select(Item)
            .where(Item.cafeteria_id == cafeteria_id, Item.is_available.is_(True))
            .order_by(Item.name)
        ).all()
    )


@router.post(
    "/{cafeteria_id}/items",
    response_model=ItemRead,
    status_code=status.HTTP_201_CREATED,
)
def create_item(
    cafeteria_id: int,
    payload: ItemCreate,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> Item:
    require_cafeteria_owner(user)
    get_owned_cafeteria(cafeteria_id, user, session)
    item = Item(cafeteria_id=cafeteria_id, **payload.model_dump())
    session.add(item)
    session.commit()
    session.refresh(item)
    return item


@router.patch("/{cafeteria_id}/items/{item_id}", response_model=ItemRead)
def update_item(
    cafeteria_id: int,
    item_id: int,
    payload: ItemUpdate,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> Item:
    require_cafeteria_owner(user)
    get_owned_cafeteria(cafeteria_id, user, session)
    item = session.get(Item, item_id)
    if item is None or item.cafeteria_id != cafeteria_id:
        raise HTTPException(status_code=404, detail="Item not found in this cafeteria")
    updates = payload.model_dump(exclude_unset=True)
    if any(value is None for field, value in updates.items() if field != "description"):
        raise HTTPException(status_code=422, detail="Name, price, and availability cannot be null")
    for field, value in updates.items():
        setattr(item, field, value)
    session.add(item)
    session.commit()
    session.refresh(item)
    return item


@router.delete("/{cafeteria_id}/items/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_item(
    cafeteria_id: int,
    item_id: int,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> None:
    require_cafeteria_owner(user)
    get_owned_cafeteria(cafeteria_id, user, session)
    item = session.get(Item, item_id)
    if item is None or item.cafeteria_id != cafeteria_id:
        raise HTTPException(status_code=404, detail="Item not found in this cafeteria")
    # Keep order history and mark the menu item unavailable instead of deleting it.
    item.is_available = False
    session.add(item)
    session.commit()
