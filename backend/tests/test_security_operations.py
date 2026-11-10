from datetime import timedelta
from contextlib import closing

from conftest import auth, FIXED_NOW
from test_flow import place
from project import logic
from project.database import Base, SessionLocal, engine
from project.models import Student


def test_password_change_invalidates_old_sessions(client, student_token, admin_token):
    changed = client.post("/auth/password", headers=auth(student_token),
                          json={"current_password": "123456", "new_password": "new-password-123"})
    assert changed.status_code == 200
    assert client.get("/me", headers=auth(student_token)).status_code == 401
    assert client.get("/me", headers=auth(changed.json()["token"])).status_code == 200
    assert client.post("/auth/login", json={"phone": "07700000000", "password": "new-password-123"}).status_code == 200
    changed = client.post("/admin/password", headers=auth(admin_token),
                          json={"current_code": "CS771SOL", "new_code": "cafeteria-new-secret-123"})
    assert changed.status_code == 200
    assert client.get("/admin/me", headers=auth(admin_token)).status_code == 401
    assert client.get("/admin/me", headers=auth(changed.json()["token"])).status_code == 200


def test_login_limit_expires(client, monkeypatch):
    for _ in range(10):
        assert client.post("/auth/login", json={"phone": "07711111111", "password": "wrong"}).status_code == 401
    blocked = client.post("/auth/login", json={"phone": "07711111111", "password": "wrong"})
    assert blocked.status_code == 429 and blocked.headers["retry-after"] == "300"
    monkeypatch.setattr(logic, "now", lambda: FIXED_NOW + timedelta(minutes=6))
    assert client.post("/auth/login", json={"phone": "07711111111", "password": "wrong"}).status_code == 401


def test_order_audit_and_daily_summary(client, student_token, admin_token):
    oid = place(client, student_token).json()["id"]
    for state in ("preparing", "ready", "delivered"):
        assert client.patch(f"/admin/orders/{oid}/status", headers=auth(admin_token), json={"status": state}).status_code == 200
    events = client.get(f"/admin/orders/{oid}/events", headers=auth(admin_token)).json()
    assert [e["status"] for e in events] == ["received", "preparing", "ready", "delivered"]
    assert events[0]["actor"] == "student"
    summary = client.get("/admin/summary", headers=auth(admin_token)).json()
    assert summary["orders"] == 1 and summary["delivered_orders"] == 1
    assert summary["sales"] == 6000 and summary["top_items"][0]["quantity"] == 2


def test_backup_preserves_database(client, student_token, tmp_path):
    import sqlite3
    from project.manage import backup

    path = tmp_path / "backup.db"
    backup(path)
    with closing(sqlite3.connect(path)) as db:
        assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        assert db.execute("SELECT phone FROM students").fetchone()[0] == "07700000000"


def test_production_seed_has_no_demo_student(monkeypatch):
    import json
    from sqlalchemy import select
    from project import main

    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    monkeypatch.setenv("WAJBATI_ENV", "production")
    monkeypatch.setenv("WAJBATI_CAFETERIA_CODES", json.dumps({name: f"private-cafe-{i}-secret" for i, (name, *_) in enumerate(main.SEED_CAFETERIAS)}))
    main.seed()
    with SessionLocal() as db:
        assert db.scalar(select(Student)) is None
