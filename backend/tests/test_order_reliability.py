from concurrent.futures import ThreadPoolExecutor
from threading import Barrier

from conftest import auth
from test_flow import first_slot, place


def payload(client, key="checkout-attempt-0001"):
    return {"cafeteria_id": 1, "pickup_time": first_slot(client), "payment_method": "نقداً",
            "lines": [{"menu_item_id": 1, "quantity": 1}], "request_key": key}


def test_checkout_retry_survives_status_and_availability_changes(client, student_token, admin_token):
    body = payload(client)
    first = client.post("/orders", headers=auth(student_token), json=body)
    assert first.status_code == 201
    oid = first.json()["id"]
    client.put("/admin/status", headers=auth(admin_token), json={"status": "closed"})
    retry = client.post("/orders", headers=auth(student_token), json=body)
    assert retry.status_code == 201 and retry.json()["id"] == oid
    assert len(client.get("/orders/mine", headers=auth(student_token)).json()) == 1
    assert len(client.get("/notifications", headers=auth(student_token)).json()) == 1
    body["lines"][0]["quantity"] = 2
    assert client.post("/orders", headers=auth(student_token), json=body).status_code == 409


def test_parallel_retries_create_one_order(client, student_token):
    body = payload(client)
    barrier = Barrier(6)

    def send(_):
        barrier.wait(timeout=15)
        return client.post("/orders", headers=auth(student_token), json=body)

    with ThreadPoolExecutor(max_workers=6) as executor:
        responses = list(executor.map(send, range(6)))
    assert all(r.status_code == 201 for r in responses), [r.text for r in responses]
    assert len({r.json()["id"] for r in responses}) == 1


def test_parallel_students_cannot_overbook_slot(client, student_token):
    # Different students ensure capacity is protected by the cafe lock, not just the student lock.
    from project.database import SessionLocal
    from project.models import Student
    from project.security import create_token

    with SessionLocal() as db:
        students = [Student(name=f"Test {i}", university_id=f"999{i:04}", phone=f"0779000{i:04}",
                            password_hash="unused") for i in range(8)]
        db.add_all(students)
        db.commit()
        tokens = [create_token(s.id, "student") for s in students]
    body = payload(client)
    barrier = Barrier(8)

    def send(i):
        barrier.wait(timeout=15)
        return client.post("/orders", headers=auth(tokens[i]),
                           json={**body, "request_key": f"parallel-checkout-{i:04}"})

    with ThreadPoolExecutor(max_workers=8) as executor:
        responses = list(executor.map(send, range(8)))
    assert sorted(r.status_code for r in responses) == [201] * 4 + [409] * 4
    slot = next(s for s in client.get("/cafeterias/1/slots", params={"prep_minutes": 10}).json()
                if s["time"] == body["pickup_time"])
    assert slot["booked"] == 4


def test_cancel_reject_and_scan_rules(client, student_token, admin_token):
    oid = place(client, student_token).json()["id"]
    assert client.post("/admin/scan", headers=auth(admin_token), json={"code": oid}).status_code == 409
    assert client.patch(f"/admin/orders/{oid}/status", headers=auth(admin_token), json={"status": "ready"}).status_code == 409
    cancelled = client.post(f"/orders/{oid}/cancel", headers=auth(student_token))
    assert cancelled.status_code == 200 and cancelled.json()["status"] == "cancelled"
    assert client.get("/cafeterias").json()[0]["active_orders"] == 0
    assert client.post(f"/orders/{oid}/arrived", headers=auth(student_token)).status_code == 409
    assert client.patch(f"/admin/orders/{oid}/status", headers=auth(admin_token), json={"status": "preparing"}).status_code == 409
    oid = place(client, student_token).json()["id"]
    rejected = client.post(f"/admin/orders/{oid}/reject", headers=auth(admin_token), json={"reason": "نفدت الوجبة"})
    assert rejected.status_code == 200 and rejected.json()["closure_reason"] == "نفدت الوجبة"
    assert rejected.json()["status"] == "rejected"
    assert client.get("/cafeterias").json()[0]["active_orders"] == 0
    oid = place(client, student_token).json()["id"]
    client.patch(f"/admin/orders/{oid}/status", headers=auth(admin_token), json={"status": "preparing"})
    assert client.post(f"/orders/{oid}/cancel", headers=auth(student_token)).status_code == 409
    assert client.post(f"/admin/orders/{oid}/reject", headers=auth(admin_token), json={"reason": "نفدت الوجبة"}).status_code == 409
