import os

from dotenv import load_dotenv
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import DeclarativeBase, sessionmaker

load_dotenv()


def _database_url() -> str:
    """SQLite محلياً، أو PostgreSQL عند النشر (DATABASE_URL)."""
    url = os.getenv("DATABASE_URL", "sqlite:///./wajbati.db").strip()
    # Render/Heroku يعطيان postgres:// أو postgresql:// ← نستخدم مشغّل psycopg 3
    if url.startswith("postgres://"):
        url = "postgresql+psycopg://" + url[len("postgres://"):]
    elif url.startswith("postgresql://"):
        url = "postgresql+psycopg://" + url[len("postgresql://"):]
    return url


DATABASE_URL = _database_url()
IS_SQLITE = DATABASE_URL.startswith("sqlite")

engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False, "timeout": 30} if IS_SQLITE else {},
    pool_pre_ping=not IS_SQLITE,  # يعيد الاتصال تلقائياً إذا أغلقه السيرفر البعيد
)
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def add_missing_columns() -> None:
    """Ordered, additive migrations; existing rows are preserved."""
    from datetime import datetime, timezone
    from .models import SchemaMigration

    SchemaMigration.__table__.create(engine, checkfirst=True)
    blob = "BLOB" if IS_SQLITE else "BYTEA"
    revisions = [
        (1, {"menu_items": {
            "image_data": blob,
            "image_mime": "VARCHAR(30)",
            "image_version": "INTEGER DEFAULT 0",
        }}),
        (2, {"orders": {"closure_reason": "VARCHAR(300)"},
             "students": {"auth_version": "INTEGER NOT NULL DEFAULT 0"},
             "cafeterias": {"auth_version": "INTEGER NOT NULL DEFAULT 0"}}),
    ]
    with engine.begin() as conn:
        if IS_SQLITE:
            conn.exec_driver_sql("BEGIN IMMEDIATE")
        else:
            conn.execute(text("SELECT pg_advisory_xact_lock(771882993)"))
        inspector = inspect(conn)
        existing_tables = set(inspector.get_table_names())
        applied = set(conn.execute(text("SELECT version FROM schema_migrations")).scalars())
        for version, tables in revisions:
            if version in applied:
                continue
            for table, columns in tables.items():
                if table not in existing_tables:
                    continue
                present = {c["name"] for c in inspector.get_columns(table)}
                for name, ddl in columns.items():
                    if name not in present:
                        conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {name} {ddl}"))
            if set(tables) <= existing_tables:
                conn.execute(SchemaMigration.__table__.insert().values(
                    version=version, applied_at=datetime.now(timezone.utc).replace(tzinfo=None)))
