import struct
import zlib

from conftest import auth
from sqlalchemy import inspect, text

from project import push
from project.database import Base, _database_url, add_missing_columns, engine


def tiny_png() -> bytes:
    """صورة PNG صالحة بحجم 1×1."""
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)
    idat = zlib.compress(b"\x00\xff\x80\x00")
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")


# ---------------- صور الأصناف ----------------
def test_create_menu_item_with_image_atomically(client, admin_token):
    before = client.get("/cafeterias/1/menu").json()
    response = client.post("/admin/menu/with-image", headers=auth(admin_token),
                           data={"name": "طبق جديد", "price": "4500", "prep_minutes": "12"},
                           files={"file": ("meal.png", tiny_png(), "image/png")})
    assert response.status_code == 201, response.text
    item = response.json()
    assert item["name"] == "طبق جديد" and item["price"] == 4500
    assert item["prep_minutes"] == 12
    assert item["image_url"] == f"/menu/{item['id']}/image?v=1"
    assert client.get(item["image_url"]).content == tiny_png()
    assert len(client.get("/cafeterias/1/menu").json()) == len(before) + 1


def test_invalid_image_or_fields_never_create_menu_item(client, admin_token, student_token):
    before = client.get("/cafeterias/1/menu").json()
    fields = {"name": "طبق", "price": "4500", "prep_minutes": "12"}
    path = "/admin/menu/with-image"
    invalid = client.post(path, headers=auth(admin_token), data=fields,
                          files={"file": ("not.png", b"not an image", "image/png")})
    assert invalid.status_code == 400
    oversized = client.post(path, headers=auth(admin_token), data=fields,
                            files={"file": ("large.png", tiny_png() + b"0" * (2 * 1024 * 1024), "image/png")})
    assert oversized.status_code == 413
    for changes in ({"price": "-1"}, {"prep_minutes": "121"}, {"name": "  "}):
        response = client.post(path, headers=auth(admin_token), data={**fields, **changes},
                               files={"file": ("meal.png", tiny_png(), "image/png")})
        assert response.status_code == 422, response.text
    unauthorized = client.post(path, headers=auth(student_token), data=fields,
                               files={"file": ("meal.png", tiny_png(), "image/png")})
    assert unauthorized.status_code == 403
    assert client.get("/cafeterias/1/menu").json() == before


def test_menu_image_upload_and_serve(client, admin_token):
    item = client.get("/cafeterias/1/menu").json()[0]
    assert item["image_url"] is None

    r = client.post(
        f"/admin/menu/{item['id']}/image",
        headers=auth(admin_token),
        files={"file": ("kebab.png", tiny_png(), "image/png")},
    )
    assert r.status_code == 200, r.text
    url = r.json()["image_url"]
    assert url == f"/menu/{item['id']}/image?v=1"

    # الطلاب يرون الرابط في القائمة، والصورة تُخدم من السيرفر
    assert client.get("/cafeterias/1/menu").json()[0]["image_url"] == url
    img = client.get(url)
    assert img.status_code == 200
    assert img.headers["content-type"] == "image/png"
    assert img.content == tiny_png()

    # تغيير الصورة يغيّر رقم الإصدار
    r2 = client.post(f"/admin/menu/{item['id']}/image", headers=auth(admin_token), files={"file": ("a.png", tiny_png())})
    assert r2.json()["image_url"].endswith("v=2")

    # حذف الصورة
    assert client.delete(f"/admin/menu/{item['id']}/image", headers=auth(admin_token)).json()["image_url"] is None
    assert client.get(f"/menu/{item['id']}/image").status_code == 404


def test_menu_image_rejects_bad_files(client, admin_token, student_token):
    item = client.get("/cafeterias/1/menu").json()[0]
    path = f"/admin/menu/{item['id']}/image"

    fake = client.post(path, headers=auth(admin_token), files={"file": ("x.png", b"not an image at all", "image/png")})
    assert fake.status_code == 400 and "ليس صورة" in fake.json()["detail"]

    big = client.post(path, headers=auth(admin_token), files={"file": ("big.png", tiny_png() + b"0" * (2 * 1024 * 1024))})
    assert big.status_code == 413

    # الطالب لا يرفع صوراً، ومسؤول كافيتريا أخرى لا يعدّل أصنافنا
    assert client.post(path, headers=auth(student_token), files={"file": ("a.png", tiny_png())}).status_code == 403
    other = client.post("/admin/login", json={"cafeteria_id": 2, "code": "AP882APP"}).json()["token"]
    assert client.post(path, headers=auth(other), files={"file": ("a.png", tiny_png())}).status_code == 404


# ---------------- إشعارات Push ----------------
def test_push_disabled_by_default(client, student_token):
    assert client.get("/push/status").json() == {"enabled": False}
    r = client.post("/devices", headers=auth(student_token), json={"token": "device-token-123", "platform": "android"})
    assert r.status_code == 204


def test_push_sent_after_status_change(client, student_token, admin_token, monkeypatch):
    sent = []
    monkeypatch.setattr(push, "_service_account", lambda: {"project_id": "demo"})
    monkeypatch.setattr(push, "SYNC", True)

    def fake_send(sa, token, title, body, data):
        sent.append((token, title, data["order_id"]))
        return token != "dead-token-xyz"  # هذا الجهاز ألغى التطبيق

    monkeypatch.setattr(push, "send_to_token", fake_send)

    client.post("/devices", headers=auth(student_token), json={"token": "phone-token-abc"})
    client.post("/devices", headers=auth(student_token), json={"token": "dead-token-xyz"})

    menu = client.get("/cafeterias/1/menu").json()
    slot = next(s["time"] for s in client.get("/cafeterias/1/slots", params={"prep_minutes": 10}).json())
    order = client.post(
        "/orders",
        headers=auth(student_token),
        json={"cafeteria_id": 1, "pickup_time": slot, "payment_method": "نقداً", "lines": [{"menu_item_id": menu[0]["id"], "quantity": 1}]},
    ).json()

    # إشعار "تم إرسال طلبك" لجهازين
    assert {s[0] for s in sent} == {"phone-token-abc", "dead-token-xyz"}
    assert all(s[2] == order["id"] for s in sent)

    # الجهاز الملغى حُذف، فالتحديث التالي يصل للهاتف فقط
    sent.clear()
    client.patch(f"/admin/orders/{order['id']}/status", headers=auth(admin_token), json={"status": "preparing"})
    assert [s[0] for s in sent] == ["phone-token-abc"]
    assert "تحديث" in sent[0][1]

    # بعد تسجيل الخروج من الجهاز لا تصل إشعارات
    sent.clear()
    client.post("/devices/unregister", headers=auth(student_token), json={"token": "phone-token-abc"})
    client.patch(f"/admin/orders/{order['id']}/status", headers=auth(admin_token), json={"status": "ready"})
    assert sent == []


def test_no_push_when_request_fails(client, student_token, monkeypatch):
    """طلب مرفوض (rollback) لا يرسل أي إشعار."""
    sent = []
    monkeypatch.setattr(push, "_service_account", lambda: {"project_id": "demo"})
    monkeypatch.setattr(push, "SYNC", True)
    monkeypatch.setattr(push, "send_to_token", lambda *a: sent.append(a) or True)
    client.post("/devices", headers=auth(student_token), json={"token": "phone-token-abc"})
    r = client.post(
        "/orders",
        headers=auth(student_token),
        json={"cafeteria_id": 1, "pickup_time": "2026-11-08T10:00", "payment_method": "نقداً", "lines": [{"menu_item_id": 1, "quantity": 1}]},
    )
    assert r.status_code == 409
    assert sent == []


# ---------------- النشر ----------------
def test_database_url_for_postgres(monkeypatch):
    monkeypatch.setenv("DATABASE_URL", "postgres://u:p@host:5432/db")
    assert _database_url() == "postgresql+psycopg://u:p@host:5432/db"
    monkeypatch.setenv("DATABASE_URL", "postgresql://u:p@host/db")
    assert _database_url() == "postgresql+psycopg://u:p@host/db"


def test_migration_adds_image_columns_to_old_database():
    Base.metadata.drop_all(engine)
    with engine.begin() as conn:  # جدول بالشكل القديم (قبل إضافة الصور)
        conn.execute(text(
            "CREATE TABLE menu_items (id INTEGER PRIMARY KEY, cafeteria_id INTEGER, name VARCHAR(100), price INTEGER, "
            "prep_minutes INTEGER, available BOOLEAN, emoji VARCHAR(10), image_url VARCHAR(500), deleted BOOLEAN)"
        ))
        conn.execute(text("INSERT INTO menu_items VALUES (1, 1, 'شاي', 500, 5, 1, '🍵', NULL, 0)"))
    add_missing_columns()
    cols = {c["name"] for c in inspect(engine).get_columns("menu_items")}
    assert {"image_data", "image_mime", "image_version"} <= cols
    with engine.connect() as conn:
        assert conn.execute(text("SELECT name FROM menu_items")).scalar() == "شاي"  # البيانات باقية
    Base.metadata.drop_all(engine)
    with engine.begin() as conn:
        conn.execute(text("DROP TABLE IF EXISTS menu_items"))
