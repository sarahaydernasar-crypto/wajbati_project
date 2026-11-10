from conftest import auth


def first_slot(client, cafeteria_id=1, prep=10):
    slots = client.get(f"/cafeterias/{cafeteria_id}/slots", params={"prep_minutes": prep}).json()
    return next(s["time"] for s in slots if s["available"])


def place(client, token, lines=None, pickup=None, cafeteria_id=1):
    menu = client.get(f"/cafeterias/{cafeteria_id}/menu").json()
    lines = lines or [{"menu_item_id": menu[0]["id"], "quantity": 2, "note": "بدون بصل"}]
    return client.post(
        "/orders",
        headers=auth(token),
        json={
            "cafeteria_id": cafeteria_id,
            "pickup_time": pickup or first_slot(client, cafeteria_id),
            "payment_method": "نقداً عند الاستلام",
            "lines": lines,
        },
    )


def test_register_login_errors(client):
    r = client.post(
        "/auth/register", json={"name": "سارة علي", "university_id": "20240099", "phone": "0771 111 2222", "password": "secret1"}
    )
    assert r.status_code == 201
    assert r.json()["student"]["phone"] == "07711112222"

    dup = client.post(
        "/auth/register", json={"name": "سارة", "university_id": "1234", "phone": "07711112222", "password": "secret1"}
    )
    assert dup.status_code == 409 and "مسجّل" in dup.json()["detail"]

    bad = client.post("/auth/register", json={"name": "سارة", "university_id": "12a", "phone": "07711113333", "password": "secret1"})
    assert bad.status_code == 422 and "رقم جامعي" in bad.json()["detail"]

    wrong = client.post("/auth/login", json={"phone": "07700000000", "password": "nope"})
    assert wrong.status_code == 401 and "كلمة المرور" in wrong.json()["detail"]

    assert client.get("/orders/mine").status_code == 401


def test_full_order_flow(client, student_token, admin_token):
    cafes = client.get("/cafeterias").json()
    assert cafes[0]["status"] == "open"
    assert any(c["status"] == "open" for c in cafes)

    r = place(client, student_token)
    assert r.status_code == 201, r.text
    order = r.json()
    assert order["status"] == "received"
    assert order["total"] == 6000
    assert order["lines"][0]["note"] == "بدون بصل"

    # يظهر في لوحة الكافيتريا
    admin_orders = client.get("/admin/orders", headers=auth(admin_token)).json()
    assert [o["id"] for o in admin_orders] == [order["id"]]

    # الطالب يضغط "وصلت"
    assert client.post(f"/orders/{order['id']}/arrived", headers=auth(student_token)).json()["arrived"] is True

    # المسؤول: قيد التحضير ← جاهز
    for s in ["preparing", "ready"]:
        r = client.patch(f"/admin/orders/{order['id']}/status", headers=auth(admin_token), json={"status": s})
        assert r.status_code == 200 and r.json()["status"] == s
    # لا رجوع لحالة سابقة
    back = client.patch(f"/admin/orders/{order['id']}/status", headers=auth(admin_token), json={"status": "preparing"})
    assert back.status_code == 409

    # التقييم ممنوع قبل التسليم
    early = client.post(f"/orders/{order['id']}/rating", headers=auth(student_token), json={"stars": 5})
    assert early.status_code == 409

    # ماسح QR يؤكد التسليم، والمسح مرة ثانية يرفض
    assert client.post("/admin/scan", headers=auth(admin_token), json={"code": order["id"]}).json()["status"] == "delivered"
    assert client.post("/admin/scan", headers=auth(admin_token), json={"code": order["id"]}).status_code == 409
    assert client.post("/admin/scan", headers=auth(admin_token), json={"code": "000000x"}).status_code == 404

    # الإشعارات: إرسال + 3 تحديثات
    notes = client.get("/notifications", headers=auth(student_token)).json()
    assert len(notes) == 4
    latest = notes[0]["id"]
    assert client.get("/notifications", headers=auth(student_token), params={"after_id": latest}).json() == []

    # التقييم يظهر على الصنف
    assert client.post(f"/orders/{order['id']}/rating", headers=auth(student_token), json={"stars": 4}).status_code == 200
    menu = client.get("/cafeterias/1/menu").json()
    assert menu[0]["rating_avg"] == 4 and menu[0]["rating_count"] == 1

    # الدخل الأسبوعي
    assert client.get("/admin/revenue", headers=auth(admin_token)).json() == {"days": 7, "total": 6000, "orders": 1}


def test_order_rules(client, student_token, admin_token):
    menu = client.get("/cafeterias/1/menu").json()
    tea = menu[2]

    # صنف منتهٍ
    client.patch(f"/admin/menu/{tea['id']}", headers=auth(admin_token), json={"available": False})
    r = place(client, student_token, lines=[{"menu_item_id": tea["id"], "quantity": 1}])
    assert r.status_code == 409 and tea["name"] in r.json()["detail"]

    # صنف من كافيتريا أخرى
    other = client.get("/cafeterias/2/menu").json()[0]
    assert place(client, student_token, lines=[{"menu_item_id": other["id"], "quantity": 1}]).status_code == 400

    # وقت غير موجود في القائمة (قبل وقت التحضير)
    assert place(client, student_token, pickup="2026-11-08T10:00").status_code == 409

    # امتلاء الفترة (4 طلبات)
    slot = first_slot(client)
    for _ in range(4):
        assert place(client, student_token, pickup=slot).status_code == 201
    full = place(client, student_token, pickup=slot)
    assert full.status_code == 409 and "لم يعد متاحاً" in full.json()["detail"]
    slots = client.get("/cafeterias/1/slots", params={"prep_minutes": 10}).json()
    assert next(s for s in slots if s["time"] == slot)["available"] is False

    # 5 طلبات نشطة ← مزدحمة
    assert place(client, student_token, pickup=slots[1]["time"]).status_code == 201
    assert client.get("/cafeterias").json()[0]["status"] == "busy"

    # إغلاق يدوي من المسؤول
    client.put("/admin/status", headers=auth(admin_token), json={"status": "closed"})
    assert client.get("/cafeterias").json()[0]["status"] == "closed"
    assert place(client, student_token, pickup=slots[2]["time"]).status_code == 409
    assert client.get("/cafeterias/1/slots").json() == []


def test_closed_outside_hours(client, monkeypatch):
    from datetime import datetime

    from project import logic

    monkeypatch.setattr(logic, "now", lambda: datetime(2026, 11, 8, 23, 30))
    cafes = {c["name"]: c["status"] for c in client.get("/cafeterias").json()}
    assert cafes["كافيتريا معماري"] == "closed"


def test_admin_permissions_and_menu(client, student_token, admin_token):
    # الطالب لا يستطيع استخدام واجهات المسؤول
    assert client.get("/admin/orders", headers=auth(student_token)).status_code == 403
    # رمز خاطئ
    assert client.post("/admin/login", json={"cafeteria_id": 1, "code": "WRONG"}).status_code == 401

    new = client.post("/admin/menu", headers=auth(admin_token), json={"name": "فلافل", "price": 1500, "prep_minutes": 7})
    assert new.status_code == 201
    item_id = new.json()["id"]
    assert any(i["name"] == "فلافل" for i in client.get("/cafeterias/1/menu").json())

    # مسؤول كافيتريا أخرى لا يعدّل قائمتنا
    other = client.post("/admin/login", json={"cafeteria_id": 2, "code": "AP882APP"}).json()["token"]
    assert client.patch(f"/admin/menu/{item_id}", headers=auth(other), json={"price": 1}).status_code == 404

    assert client.delete(f"/admin/menu/{item_id}", headers=auth(admin_token)).status_code == 204
    assert all(i["name"] != "فلافل" for i in client.get("/cafeterias/1/menu").json())


def test_favorites(client, student_token):
    item = client.get("/cafeterias/1/menu").json()[0]
    assert client.put(f"/favorites/{item['id']}", headers=auth(student_token)).status_code == 204
    client.put(f"/favorites/{item['id']}", headers=auth(student_token))  # تكرار بدون خطأ
    favs = client.get("/favorites", headers=auth(student_token)).json()
    assert [f["id"] for f in favs] == [item["id"]]
    assert favs[0]["cafeteria_name"] == "كافيتريا علوم حاسوب"
    client.delete(f"/favorites/{item['id']}", headers=auth(student_token))
    assert client.get("/favorites", headers=auth(student_token)).json() == []
