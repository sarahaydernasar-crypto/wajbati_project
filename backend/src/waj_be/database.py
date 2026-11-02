import os
from pathlib import Path

from dotenv import load_dotenv
from sqlmodel import Session, SQLModel, create_engine, select

from waj_be import models as _models  # Register all table models in SQLModel metadata.
from waj_be.models import OwnerApplication, OwnerApplicationStatus, User, UserRole

load_dotenv(Path(__file__).resolve().parents[2] / ".env")

database_url = os.getenv("DATABASE_URL")
if not database_url:
    raise RuntimeError("DATABASE_URL is missing. Add it to Waj-BE/.env")

# Aiven supplies PostgreSQL URLs; select psycopg explicitly for SQLAlchemy.
if database_url.startswith("postgres://"):
    database_url = database_url.replace("postgres://", "postgresql+psycopg://", 1)
elif database_url.startswith("postgresql://"):
    database_url = database_url.replace("postgresql://", "postgresql+psycopg://", 1)

engine = create_engine(database_url, echo=False, pool_pre_ping=True)


def create_db() -> None:
    SQLModel.metadata.create_all(engine)
    # Existing owner accounts predate approval flow; queue them for admin review.
    with Session(engine) as session:
        owner_ids = session.exec(
            select(User.id).where(User.role == UserRole.CAFETERIA_OWNER)
        ).all()
        application_user_ids = set(session.exec(select(OwnerApplication.user_id)).all())
        for user_id in owner_ids:
            if user_id not in application_user_ids:
                session.add(OwnerApplication(user_id=user_id))
        session.commit()


def get_session():
    with Session(engine) as session:
        yield session
