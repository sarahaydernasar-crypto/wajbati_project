"""Operator tools: backups and verified, manual account recovery.

Run from backend with: uv run python -m project.manage --help
"""

import argparse
import getpass
import os
from pathlib import Path
import sqlite3
import subprocess

from sqlalchemy import select, update
from sqlalchemy.engine import make_url

from .database import DATABASE_URL, IS_SQLITE, SessionLocal, engine
from .models import Cafeteria, Student
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
                with sqlite3.connect(temporary) as target:
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
    model = Student if kind == "student" else Cafeteria
    minimum = 8 if kind == "student" else 12
    password = getpass.getpass("القيمة الجديدة: ")
    if len(password) < minimum or len(password.encode()) > 72 or password != getpass.getpass("تأكيد القيمة الجديدة: "):
        raise ValueError(f"استخدم {minimum} أحرف على الأقل، وحتى 72 بايت، وطابق التأكيد")
    if kind == "cafeteria" and (not password.isascii() or any(c.isspace() for c in password)):
        raise ValueError("رمز الكافيتريا يجب أن يكون أحرفاً وأرقاماً ورموزاً إنجليزية دون مسافات")
    with SessionLocal() as db:
        condition = Student.phone == identifier if kind == "student" else Cafeteria.id == int(identifier)
        account = db.scalar(select(model).where(condition))
        if account is None:
            raise ValueError("الحساب غير موجود")
        db.execute(update(model).where(model.id == account.id).values(id=account.id))
        db.refresh(account)
        setattr(account, "password_hash" if kind == "student" else "code_hash", hash_secret(password))
        account.auth_version += 1
        db.commit()
    print("تم تغيير القيمة وإنهاء الجلسات القديمة")


def main() -> None:
    parser = argparse.ArgumentParser(description="Wajbati operator tools")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("backup").add_argument("destination", type=Path)
    reset = commands.add_parser("reset-password")
    reset.add_argument("kind", choices=["student", "cafeteria"])
    reset.add_argument("identifier", help="Student phone or cafeteria ID. Verify identity before use.")
    args = parser.parse_args()
    if args.command == "backup":
        backup(args.destination)
    else:
        reset_password(args.kind, args.identifier)


if __name__ == "__main__":
    main()
