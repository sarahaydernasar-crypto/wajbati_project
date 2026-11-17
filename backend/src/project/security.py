import os
import warnings
from datetime import datetime, timedelta, timezone
from typing import Annotated

import bcrypt
import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from .database import get_db
from .models import Cafeteria, Student, PlatformAdmin
from .settings import production

SECRET_KEY = os.getenv("WAJBATI_SECRET", "")
if production() and SECRET_KEY and len(SECRET_KEY) < 32:
    raise RuntimeError("WAJBATI_SECRET يجب أن يكون مفتاحاً عشوائياً من 32 حرفاً على الأقل في الإنتاج")
if not SECRET_KEY and production():
    # على الاستضافة لا نسمح بمفتاح التطوير المعروف: أي شخص يستطيع تزوير رموز الدخول به
    raise RuntimeError("WAJBATI_SECRET مطلوب عند النشر. أضفه في إعدادات Render.")
if not SECRET_KEY:
    SECRET_KEY = "dev-only-secret-change-me-before-deploying-wajbati"
    warnings.warn("WAJBATI_SECRET غير مضبوط، يتم استخدام مفتاح تطوير. اضبطه قبل النشر.", stacklevel=1)

ALGORITHM = "HS256"
TOKEN_DAYS = 30

_bearer = HTTPBearer(auto_error=False)


def hash_secret(raw: str) -> str:
    return bcrypt.hashpw(raw.encode(), bcrypt.gensalt()).decode()


def verify_secret(raw: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(raw.encode(), hashed.encode())
    except ValueError:
        return False


def create_token(subject: int, role: str, version: int = 0) -> str:
    payload = {
        "sub": str(subject),
        "role": role,
        "version": version,
        "exp": datetime.now(timezone.utc) + timedelta(days=TOKEN_DAYS),
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def _decode(creds: HTTPAuthorizationCredentials | None, role: str) -> tuple[int, int]:
    if creds is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "الرجاء تسجيل الدخول")
    try:
        payload = jwt.decode(creds.credentials, SECRET_KEY, algorithms=[ALGORITHM])
    except jwt.ExpiredSignatureError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "انتهت الجلسة، سجّل الدخول من جديد")
    except jwt.InvalidTokenError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "جلسة غير صالحة، سجّل الدخول من جديد")
    if payload.get("role") != role:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "ليست لديك صلاحية لهذه العملية")
    try:
        return int(payload["sub"]), int(payload.get("version", 0))
    except (KeyError, TypeError, ValueError):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "جلسة غير صالحة")


def current_student(
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
    db: Annotated[Session, Depends(get_db)],
) -> Student:
    subject, version = _decode(creds, "student")
    student = db.get(Student, subject)
    if student is None or student.auth_version != version:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "الحساب غير موجود، سجّل الدخول من جديد")
    return student


def current_cafeteria(
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
    db: Annotated[Session, Depends(get_db)],
) -> Cafeteria:
    subject, version = _decode(creds, "cafeteria")
    cafeteria = db.get(Cafeteria, subject)
    if cafeteria is None or cafeteria.auth_version != version:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "الكافيتريا غير موجودة")
    return cafeteria


def current_platform_admin(
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
    db: Annotated[Session, Depends(get_db)],
) -> PlatformAdmin:
    subject, version = _decode(creds, "platform")
    admin = db.get(PlatformAdmin, subject)
    if admin is None or admin.auth_version != version:
        raise HTTPException(401, "انتهت الجلسة، سجّل الدخول من جديد")
    return admin


PlatformDep = Annotated[PlatformAdmin, Depends(current_platform_admin)]
StudentDep = Annotated[Student, Depends(current_student)]
CafeteriaDep = Annotated[Cafeteria, Depends(current_cafeteria)]
DbDep = Annotated[Session, Depends(get_db)]
