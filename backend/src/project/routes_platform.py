"""Platform provisioning is separate from cafeteria owner permissions."""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field, field_validator, model_validator
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from . import logic
from .models import Cafeteria, PlatformAdmin
from .rate_limit import check_login
from .security import DbDep, PlatformDep, create_token, hash_secret, verify_secret

router = APIRouter(prefix="/platform", tags=["platform"])


class PlatformLogin(BaseModel):
    username: str = Field(min_length=1, max_length=64)
    password: str = Field(min_length=1, max_length=100)


@router.post('/login')
def login(body: PlatformLogin, db: DbDep):
    username = body.username.strip().lower()
    check_login(db, 'platform:' + username)
    admin = db.scalar(select(PlatformAdmin).where(PlatformAdmin.username == username))
    if admin is None or not verify_secret(body.password, admin.password_hash):
        raise HTTPException(401, 'اسم المستخدم أو كلمة المرور غير صحيحة')
    return {'token': create_token(admin.id, 'platform', admin.auth_version), 'username': admin.username}


@router.get('/me')
def me(admin: PlatformDep):
    return {'username': admin.username}


@router.get('/cafeterias')
def cafeterias(admin: PlatformDep, db: DbDep):
    return [logic.cafeteria_json(db, cafe) for cafe in db.scalars(select(Cafeteria).order_by(Cafeteria.id)).all()]


class CafeteriaIn(BaseModel):
    name: str = Field(min_length=3, max_length=100)
    location: str = Field(min_length=3, max_length=200)
    open_hour: int = Field(ge=0, le=23)
    close_hour: int = Field(ge=1, le=24)
    code: str = Field(min_length=12, max_length=72, pattern=r'^[\x21-\x7e]+$')

    @field_validator('name', 'location')
    @classmethod
    def trim(cls, value):
        value = value.strip()
        if len(value) < 3:
            raise ValueError('استخدم ثلاثة أحرف على الأقل')
        return value

    @model_validator(mode='after')
    def valid_hours(self):
        if self.close_hour <= self.open_hour:
            raise ValueError('وقت الإغلاق يجب أن يكون بعد وقت الفتح')
        return self


@router.post('/cafeterias', status_code=201)
def add_cafeteria(body: CafeteriaIn, admin: PlatformDep, db: DbDep):
    cafe = Cafeteria(name=body.name, location=body.location, open_hour=body.open_hour,
                     close_hour=body.close_hour, code_hash=hash_secret(body.code))
    db.add(cafe)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, 'اسم الكافيتريا مستخدم مسبقاً')
    return logic.cafeteria_json(db, cafe)


class PasswordIn(BaseModel):
    current_password: str = Field(min_length=1, max_length=100)
    new_password: str = Field(min_length=12, max_length=72)

    @field_validator('new_password')
    @classmethod
    def password_bytes(cls, value):
        if len(value.encode()) > 72:
            raise ValueError('كلمة المرور طويلة جداً، استخدم حتى 72 بايت')
        return value


@router.post('/password')
def change_password(body: PasswordIn, admin: PlatformDep, db: DbDep):
    from sqlalchemy import update
    db.execute(update(PlatformAdmin).where(PlatformAdmin.id == admin.id).values(id=admin.id))
    db.refresh(admin)
    if not verify_secret(body.current_password, admin.password_hash):
        raise HTTPException(401, 'كلمة المرور الحالية غير صحيحة')
    admin.password_hash = hash_secret(body.new_password)
    admin.auth_version += 1
    db.commit()
    return {'token': create_token(admin.id, 'platform', admin.auth_version)}
