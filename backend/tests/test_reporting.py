from datetime import datetime, timedelta

from sqlalchemy import delete, select, text

from conftest import FIXED_NOW, auth
from test_flow import place
from project import logic
from project.database import Base, SessionLocal, add_missing_columns, engine
from project.models import Order, SchemaMigration


def test_sales_follow_delivery_day_not_creation_day(client, student_token, admin_token, monkeypatch):
    order = place(client, student_token).json()
    oid = order["id"]
    for status in ("preparing", "ready"):
        assert client.patch(f"/admin/orders/{oid}/status", headers=auth(admin_token), json={"status": status}).status_code == 200
    delivery = FIXED_NOW + timedelta(days=1, hours=2)
    monkeypatch.setattr(logic, "now", lambda: delivery)
    delivered = client.patch(f"/admin/orders/{oid}/status", headers=auth(admin_token), json={"status": "delivered"})
    assert delivered.json()["delivered_at"] == delivery.isoformat(timespec="seconds")
    report = client.get("/admin/reports?period=today", headers=auth(admin_token)).json()
    assert report["sales"] == 6000 and report["delivered_orders"] == 1
    assert report["created_orders"] == 0 and report["estimated_orders"] == 0
    assert report["top_items"][0]["quantity"] == 2
    assert report["series"] == [{"date": delivery.date().isoformat(), "sales": 6000, "orders": 1}]
    summary = client.get("/admin/summary", headers=auth(admin_token)).json()
    assert summary["sales"] == 6000 and summary["delivered_orders"] == 1 and summary["orders"] == 0
    assert client.get("/admin/revenue?days=1", headers=auth(admin_token)).json()["total"] == 6000
    # An older creation date does not hide today's delivery in the recent orders list.
    assert oid in [o["id"] for o in client.get("/admin/orders", headers=auth(admin_token)).json()]
    assert client.patch(f"/admin/orders/{oid}/status", headers=auth(admin_token), json={"status": "delivered"}).status_code == 409


def test_report_boundaries_status_and_cafeteria_scope(client, admin_token):
    with SessionLocal() as db:
        def row(oid, cafe, total, status, created, delivered):
            return Order(id=oid, student_id=1, cafeteria_id=cafe, total=total, status=status,
                         pickup_time=created, created_at=created, delivered_at=delivered, prep_minutes=5,
                         payment_method="نقداً")
        db.add_all([
            row("700001", 1, 2000, "delivered", datetime(2026, 11, 1), datetime(2026, 11, 5)),
            row("700002", 1, 3000, "delivered", datetime(2026, 11, 5), datetime(2026, 11, 6)),
            row("700003", 1, 9000, "cancelled", datetime(2026, 11, 5), None),
            row("700004", 2, 7777, "delivered", datetime(2026, 11, 5), datetime(2026, 11, 5)),
        ])
        db.commit()
    result = client.get("/admin/reports?period=custom&start_date=2026-11-05&end_date=2026-11-05",
                        headers=auth(admin_token)).json()
    assert result["sales"] == 2000 and result["delivered_orders"] == 1
    assert result["created_orders"] == 2
    assert result["series"] == [{"date": "2026-11-05", "sales": 2000, "orders": 1}]
    week = client.get("/admin/reports?period=week", headers=auth(admin_token)).json()
    assert week["start_date"] == "2026-11-02" and week["end_date"] == "2026-11-08"
    assert len(week["series"]) == 7 and sum(day["sales"] for day in week["series"]) == 5000
    assert week["timezone"] == "Asia/Baghdad"


def test_report_validation_and_empty_period(client, admin_token, student_token):
    assert client.get("/admin/reports", headers=auth(student_token)).status_code == 403
    for query in ("period=invalid", "period=custom", "period=custom&start_date=2026-11-08&end_date=2026-11-01",
                  "period=custom&start_date=2020-01-01&end_date=2026-11-01"):
        assert client.get(f"/admin/reports?{query}", headers=auth(admin_token)).status_code == 422
    result = client.get("/admin/reports?period=month", headers=auth(admin_token)).json()
    assert result["sales"] == result["delivered_orders"] == result["average_order_value"] == 0
    assert result["start_date"] == "2026-11-01"
    assert len(result["series"]) == 8 and result["top_items"] == []


def test_delivery_migration_uses_audit_and_preserves_unknown_history(client, student_token, admin_token):
    oid = place(client, student_token).json()["id"]
    for status in ("preparing", "ready", "delivered"):
        client.patch(f"/admin/orders/{oid}/status", headers=auth(admin_token), json={"status": status})
    with SessionLocal() as db:
        db.get(Order, oid).delivered_at = None
        db.add(Order(id="700009", student_id=1, cafeteria_id=1, total=1000, status="delivered",
                     pickup_time=FIXED_NOW, created_at=FIXED_NOW, prep_minutes=5, payment_method="نقداً"))
        db.execute(delete(SchemaMigration).where(SchemaMigration.version == 3))
        db.commit()
    add_missing_columns()
    add_missing_columns()
    with SessionLocal() as db:
        assert db.get(Order, oid).delivered_at == FIXED_NOW
        assert db.get(Order, "700009").delivered_at is None
    result = client.get("/admin/reports?period=today", headers=auth(admin_token)).json()
    assert result["sales"] == 7000 and result["estimated_orders"] == 1


def test_migration_adds_delivery_column_to_legacy_orders():
    Base.metadata.drop_all(engine)
    with engine.begin() as conn:
        conn.execute(text("CREATE TABLE orders (id VARCHAR(10) PRIMARY KEY, status VARCHAR(15), created_at TIMESTAMP)"))
        conn.execute(text("INSERT INTO orders VALUES ('legacy', 'delivered', '2026-11-01 10:00:00')"))
    add_missing_columns()
    with engine.connect() as conn:
        row = conn.execute(text("SELECT id, delivered_at FROM orders")).one()
        assert row[0] == "legacy" and row[1] is None
    Base.metadata.drop_all(engine)
