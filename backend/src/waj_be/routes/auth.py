import os
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Literal

import jwt
from dotenv import load_dotenv
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt.exceptions import InvalidTokenError
from pydantic import BaseModel, Field, field_validator
from pwdlib import PasswordHash
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from waj_be.database import get_session
from waj_be.models import OwnerApplication, OwnerApplicationStatus, User, UserRole

load_dotenv(Path(__file__).resolve().parents[3] / ".env")

router = APIRouter(prefix="/auth", tags=["authentication"])

JWT_SECRET = os.getenv("JWT_SECRET")
if not JWT_SECRET:
    raise RuntimeError("JWT_SECRET is missing. Add it to Waj-BE/.env")

JWT_ALGORITHM = "HS256"
ACCESS_TOKEN_MINUTES = 30
IRAQI_MOBILE_PATTERN = re.compile(r"^\+9647\d{9}$")
password_hasher = PasswordHash.recommended()
bearer_scheme = HTTPBearer(auto_error=False)


class RegisterRequest(BaseModel):
    full_name: str = Field(min_length=2, max_length=120)
    phone_number: str = Field(min_length=10, max_length=20)
    password: str = Field(min_length=8, max_length=128)
    role: Literal["student", "cafeteria_owner"] = "student"

    @field_validator("phone_number")
    @classmethod
    def normalize_iraqi_phone(cls, value: str) -> str:
        phone = re.sub(r"[\s()-]", "", value)
        if phone.startswith("00964"):
            phone = "+" + phone[2:]
        elif phone.startswith("07"):
            phone = "+964" + phone[1:]
        if not IRAQI_MOBILE_PATTERN.fullmatch(phone):
            raise ValueError("Use an Iraqi mobile number such as 07XXXXXXXXX or +9647XXXXXXXXX")
        return phone


class LoginRequest(BaseModel):
    phone_number: str = Field(min_length=10, max_length=20)
    password: str = Field(min_length=1, max_length=128)

    @field_validator("phone_number")
    @classmethod
    def normalize_iraqi_phone(cls, value: str) -> str:
        return RegisterRequest.normalize_iraqi_phone(value)


class UserRead(BaseModel):
    id: int
    full_name: str
    phone_number: str
    role: UserRole
    phone_verified: bool

    model_config = {"from_attributes": True}


class AuthResponse(BaseModel):
    access_token: str
    token_type: Literal["bearer"] = "bearer"
    user: UserRead


class RegistrationResponse(BaseModel):
    access_token: str | None = None
    token_type: Literal["bearer"] | None = None
    user: UserRead
    message: str


def create_access_token(user_id: int) -> str:
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_MINUTES)
    return jwt.encode(
        {"sub": str(user_id), "exp": expires_at},
        JWT_SECRET,
        algorithm=JWT_ALGORITHM,
    )


def auth_response(user: User) -> AuthResponse:
    return AuthResponse(access_token=create_access_token(user.id), user=user)


@router.post("/register", response_model=RegistrationResponse, status_code=status.HTTP_201_CREATED)
def register(
    payload: RegisterRequest,
    session: Session = Depends(get_session),
) -> RegistrationResponse:
    existing_user = session.exec(
        select(User).where(User.phone_number == payload.phone_number)
    ).first()
    if existing_user:
        raise HTTPException(status_code=409, detail="Phone number is already registered")

    user = User(
        full_name=payload.full_name,
        phone_number=payload.phone_number,
        password_hash=password_hasher.hash(payload.password),
        role=UserRole(payload.role),
        phone_verified=False,
    )
    session.add(user)
    try:
        session.flush()
        if user.role == UserRole.CAFETERIA_OWNER:
            session.add(OwnerApplication(user_id=user.id))
        session.commit()
    except IntegrityError:
        session.rollback()
        raise HTTPException(status_code=409, detail="Phone number is already registered")
    session.refresh(user)
    if user.role == UserRole.CAFETERIA_OWNER:
        return RegistrationResponse(
            user=user,
            message="Owner application submitted. An admin must approve it before login.",
        )
    return RegistrationResponse(
        access_token=create_access_token(user.id),
        token_type="bearer",
        user=user,
        message="Account created successfully.",
    )


@router.post("/login", response_model=AuthResponse)
def login(payload: LoginRequest, session: Session = Depends(get_session)) -> AuthResponse:
    user = session.exec(
        select(User).where(User.phone_number == payload.phone_number)
    ).first()
    if not user or not password_hasher.verify(payload.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid phone number or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Account is inactive")
    if user.role == UserRole.CAFETERIA_OWNER:
        application = session.exec(
            select(OwnerApplication).where(OwnerApplication.user_id == user.id)
        ).first()
        if application is None or application.status != OwnerApplicationStatus.APPROVED:
            raise HTTPException(status_code=403, detail="Cafeteria owner application is not approved")
    return auth_response(user)


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    session: Session = Depends(get_session),
) -> User:
    unauthorized = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid or expired access token",
        headers={"WWW-Authenticate": "Bearer"},
    )
    if credentials is None:
        raise unauthorized

    try:
        payload = jwt.decode(
            credentials.credentials,
            JWT_SECRET,
            algorithms=[JWT_ALGORITHM],
        )
        user_id = int(payload["sub"])
    except (InvalidTokenError, KeyError, TypeError, ValueError):
        raise unauthorized

    user = session.get(User, user_id)
    if user is None or not user.is_active:
        raise unauthorized
    if user.role == UserRole.CAFETERIA_OWNER:
        application = session.exec(
            select(OwnerApplication).where(OwnerApplication.user_id == user.id)
        ).first()
        if application is None or application.status != OwnerApplicationStatus.APPROVED:
            raise HTTPException(status_code=403, detail="Cafeteria owner application is not approved")
    return user


@router.get("/me", response_model=UserRead)
def read_current_user(user: User = Depends(get_current_user)) -> User:
    return user
