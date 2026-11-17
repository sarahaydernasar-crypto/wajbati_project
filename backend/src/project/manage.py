"""Operator tools: backups and verified, manual account recovery.

Run from backend with: uv run python -m project.manage --help
"""

import argparse
from contextlib import closing
import getpass
import os
from pathlib import Path
import sqlite3
import subprocess

from sqlalchemy import select, update
from sqlalchemy.engine import make_url

from .database import DATABASE_URL, IS_SQLITE, SessionLocal, engine
from .models import Cafeteria, Student, PlatformAdmin
from .security import hash_secret


def backup(destination: Path) -> None:
    destination = destination.resolve()
    if destination.exists():
        raise ValueError("ملف النسخة الاحتياطية موجود مسبقاً؛ اختر اسماً جديداً")
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.name + ".partial")
    if temporary.exists():
        raise ValueError("يوجد ملف نسخة غير مكتمل بهذا الاسم؛ افحصه أولاً")
    try:
        if IS_SQLITE:
            source = engine.raw_connection()
            try:
                with closing(sqlite3.connect(temporary)) as target:
                    source.driver_connection.backup(target)
                    if target.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
                        raise RuntimeError("فشل فحص سلامة النسخة الاحتياطية")
            finally:
                source.close()
        else:
            url = make_url(DATABASE_URL)
            env = os.environ.copy()
            env.update(PGHOST=url.host or "localhost", PGPORT=str(url.port or 5432),
                       PGDATABASE=url.database or "", PGUSER=url.username or "", PGPASSWORD=url.password or "")
            if url.query.get("sslmode"):
                env["PGSSLMODE"] = url.query["sslmode"]
            subprocess.run(["pg_dump", "--format=custom", "--file", str(temporary)], env=env, check=True)
        temporary.replace(destination)
    except Exception:
        # Leave an incomplete file for inspection; never replace an existing backup.
        raise
    print(f"تم حفظ النسخة الاحتياطية: {destination}")


def reset_password(kind: str, identifier: str) -> None:
    model = {"student": Student, "cafeteria": Cafeteria, "platform": PlatformAdmin}[kind]
    minimum = 8 if kind == "student" else 12
    password = getpass.getpass("القيمة الجديدة: ")
    if len(password) < minimum or len(password.encode()) > 72 or password != getpass.getpass("تأكيد القيمة الجديدة: "):
        raise ValueError(f"استخدم {minimum} أحرف على الأقل، وحتى 72 بايت، وطابق التأكيد")
    if kind == "cafeteria" and (not password.isascii() or any(c.isspace() for c in password)):
        raise ValueError("رمز الكافيتريا يجب أن يكون أحرفاً وأرقاماً ورموزاً إنجليزية دون مسافات")
    with SessionLocal() as db:
        condition = (Student.phone == identifier if kind == "student" else
                     PlatformAdmin.username == identifier.strip().lower() if kind == "platform" else Cafeteria.id == int(identifier))
        account = db.scalar(select(model).where(condition))
        if account is None:
            raise ValueError("الحساب غير موجود")
        db.execute(update(model).where(model.id == account.id).values(id=account.id))
        db.refresh(account)
        setattr(account, "code_hash" if kind == "cafeteria" else "password_hash", hash_secret(password))
        account.auth_version += 1
        db.commit()
    print("تم تغيير القيمة وإنهاء الجلسات القديمة")


def create_platform_admin(username: str, password: str) -> None:
    import re
    from .database import Base
    username = username.strip().lower()
    if not re.fullmatch(r'[a-z0-9_.-]{3,64}', username):
        raise ValueError('Use a username of 3-64 English letters, digits, dots, dashes or underscores')
    if len(password) < 12 or len(password.encode()) > 72:
        raise ValueError('Use a password of at least 12 characters and at most 72 bytes')
    Base.metadata.create_all(engine)
    with SessionLocal() as db:
        if db.scalar(select(PlatformAdmin).where(PlatformAdmin.username == username)):
            raise ValueError('Platform administrator already exists; no password was changed')
        db.add(PlatformAdmin(username=username, password_hash=hash_secret(password)))
        db.commit()


def main() -> None:
    parser = argparse.ArgumentParser(description="Wajbati operator tools")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("backup").add_argument("destination", type=Path)
    create = commands.add_parser('create-admin')
    create.add_argument('username')
    reset = commands.add_parser("reset-password")
    reset.add_argument("kind", choices=["student", "cafeteria", "platform"])
    reset.add_argument("identifier", help="Student phone or cafeteria ID. Verify identity before use.")
    args = parser.parse_args()
    if args.command == "backup":
        backup(args.destination)
    elif args.command == 'create-admin':
        password = getpass.getpass('Platform administrator password: ')
        if password != getpass.getpass('Confirm password: '):
            raise ValueError('Passwords do not match')
        create_platform_admin(args.username, password)
        print('Platform administrator created')
    else:
        reset_password(args.kind, args.identifier)


if __name__ == "__main__":
    main()
