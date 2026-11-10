import os
import tempfile
from datetime import datetime

import pytest

# قاعدة بيانات مؤقتة للاختبارات (قبل استيراد التطبيق)
_tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
_tmp.close()
os.environ["DATABASE_URL"] = f"sqlite:///{_tmp.name}"
os.environ.setdefault("WAJBATI_SECRET", "test-secret-key-for-pytest-only-0123456789")

from fastapi.testclient import TestClient  # noqa: E402

from project import logic  # noqa: E402
from project.database import Base, engine  # noqa: E402
from project.main import app  # noqa: E402

FIXED_NOW = datetime(2026, 11, 8, 10, 0)


@pytest.fixture()
def client(monkeypatch):
    # الساعة 10:00 صباحاً حتى تكون الكافيتريات مفتوحة دائماً
    monkeypatch.setattr(logic, "now", lambda: FIXED_NOW)
    Base.metadata.drop_all(engine)
    with TestClient(app) as c:  # lifespan ينشئ الجداول ويضيف البيانات الأولية
        yield c


def auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture()
def student_token(client):
    r = client.post("/auth/login", json={"phone": "07700000000", "password": "123456"})
    assert r.status_code == 200, r.text
    return r.json()["token"]


@pytest.fixture()
def admin_token(client):
    r = client.post("/admin/login", json={"cafeteria_id": 1, "code": "CS771SOL"})
    assert r.status_code == 200, r.text
    return r.json()["token"]
