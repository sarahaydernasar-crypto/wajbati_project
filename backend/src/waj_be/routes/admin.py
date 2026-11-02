from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlmodel import Session, select

from waj_be.database import get_session
from waj_be.models import (
    OwnerApplication,
    OwnerApplicationStatus,
    User,
    UserRole,
    utc_now,
)
from waj_be.routes.auth import get_current_user

router = APIRouter(prefix="/admin", tags=["admin"])


class OwnerApplicationRead(BaseModel):
    application_id: int
    user_id: int
    full_name: str
    phone_number: str
    submitted_at: datetime
    status: OwnerApplicationStatus


def require_admin(user: User) -> None:
    if user.role != UserRole.ADMIN:
        raise HTTPException(status_code=403, detail="Admin role required")


def get_pending_application(application_id: int, session: Session) -> OwnerApplication:
    application = session.get(OwnerApplication, application_id)
    if application is None:
        raise HTTPException(status_code=404, detail="Owner application not found")
    if application.status != OwnerApplicationStatus.PENDING:
        raise HTTPException(status_code=409, detail="Owner application was already reviewed")
    return application


@router.get("/owner-applications/pending", response_model=list[OwnerApplicationRead])
def list_pending_owner_applications(
    admin: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> list[OwnerApplicationRead]:
    require_admin(admin)
    applications = session.exec(
        select(OwnerApplication)
        .where(OwnerApplication.status == OwnerApplicationStatus.PENDING)
        .order_by(OwnerApplication.submitted_at)
    ).all()
    result = []
    for application in applications:
        user = session.get(User, application.user_id)
        if user is not None and user.is_active:
            result.append(
                OwnerApplicationRead(
                    application_id=application.id,
                    user_id=user.id,
                    full_name=user.full_name,
                    phone_number=user.phone_number,
                    submitted_at=application.submitted_at,
                    status=application.status,
                )
            )
    return result


@router.patch("/owner-applications/{application_id}/approve", response_model=OwnerApplicationRead)
def approve_owner_application(
    application_id: int,
    admin: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> OwnerApplicationRead:
    require_admin(admin)
    application = get_pending_application(application_id, session)
    user = session.get(User, application.user_id)
    if user is None or not user.is_active or user.role != UserRole.CAFETERIA_OWNER:
        raise HTTPException(status_code=409, detail="Owner account is not active")

    application.status = OwnerApplicationStatus.APPROVED
    application.reviewed_at = utc_now()
    application.reviewed_by_id = admin.id
    session.add(application)
    session.commit()
    session.refresh(application)
    return OwnerApplicationRead(
        application_id=application.id,
        user_id=user.id,
        full_name=user.full_name,
        phone_number=user.phone_number,
        submitted_at=application.submitted_at,
        status=application.status,
    )


@router.patch("/owner-applications/{application_id}/reject", response_model=OwnerApplicationRead)
def reject_owner_application(
    application_id: int,
    admin: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> OwnerApplicationRead:
    require_admin(admin)
    application = get_pending_application(application_id, session)
    user = session.get(User, application.user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="Owner account not found")

    application.status = OwnerApplicationStatus.REJECTED
    application.reviewed_at = utc_now()
    application.reviewed_by_id = admin.id
    user.is_active = False
    session.add(application)
    session.add(user)
    session.commit()
    session.refresh(application)
    return OwnerApplicationRead(
        application_id=application.id,
        user_id=user.id,
        full_name=user.full_name,
        phone_number=user.phone_number,
        submitted_at=application.submitted_at,
        status=application.status,
    )
