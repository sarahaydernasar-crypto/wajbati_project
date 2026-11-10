"""إشعارات Push عبر Firebase Cloud Messaging (FCM HTTP v1).

تعمل فقط عند ضبط أحد متغيري البيئة:
  FCM_SERVICE_ACCOUNT_JSON  محتوى ملف حساب الخدمة (JSON) من Firebase Console
  FCM_SERVICE_ACCOUNT_FILE  أو مسار ذلك الملف
بدونهما تبقى الإشعارات داخل التطبيق فقط ولا يحدث أي خطأ.
"""

import json
import logging
import os
import threading
import time
from concurrent.futures import ThreadPoolExecutor

import httpx
import jwt
from sqlalchemy import event, select

log = logging.getLogger("wajbati.push")

SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
_executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix="fcm")
_lock = threading.Lock()
_token_cache: dict = {"value": None, "exp": 0.0}

# في الاختبارات: الإرسال فوراً بدل الخلفية
SYNC = False


def _service_account() -> dict | None:
    raw = os.getenv("FCM_SERVICE_ACCOUNT_JSON")
    path = os.getenv("FCM_SERVICE_ACCOUNT_FILE")
    try:
        if raw:
            return json.loads(raw)
        if path and os.path.exists(path):
            with open(path, encoding="utf-8") as f:
                return json.load(f)
    except (ValueError, OSError) as e:
        log.error("ملف حساب خدمة Firebase غير صالح: %s", e)
    return None


def enabled() -> bool:
    return _service_account() is not None


def _access_token(sa: dict) -> str:
    """رمز OAuth2 قصير العمر من حساب الخدمة (يُخزَّن حتى قرب انتهائه)."""
    with _lock:
        if _token_cache["value"] and _token_cache["exp"] - 60 > time.time():
            return _token_cache["value"]
        now = int(time.time())
        assertion = jwt.encode(
            {"iss": sa["client_email"], "scope": SCOPE, "aud": sa["token_uri"], "iat": now, "exp": now + 3600},
            sa["private_key"],
            algorithm="RS256",
        )
        r = httpx.post(
            sa["token_uri"],
            data={"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": assertion},
            timeout=10,
        )
        r.raise_for_status()
        data = r.json()
        _token_cache["value"] = data["access_token"]
        _token_cache["exp"] = now + int(data.get("expires_in", 3600))
        return _token_cache["value"]


def send_to_token(sa: dict, device_token: str, title: str, body: str, data: dict) -> bool:
    """يرجع False إذا كان الجهاز لم يعد مسجلاً (يجب حذفه)."""
    message = {
        "message": {
            "token": device_token,
            "notification": {"title": title, "body": body},
            "data": {k: str(v) for k, v in data.items() if v is not None},
            "android": {"priority": "high", "notification": {"channel_id": "orders"}},
        }
    }
    r = httpx.post(
        f"https://fcm.googleapis.com/v1/projects/{sa['project_id']}/messages:send",
        headers={"Authorization": f"Bearer {_access_token(sa)}"},
        json=message,
        timeout=10,
    )
    if r.status_code in (404, 400) and ("UNREGISTERED" in r.text or "INVALID_ARGUMENT" in r.text):
        return False
    if r.status_code >= 300:
        log.warning("فشل إرسال إشعار FCM (%s): %s", r.status_code, r.text[:200])
    return True


def _deliver(student_id: int, title: str, body: str, order_id: str | None) -> None:
    from .database import SessionLocal
    from .models import DeviceToken

    sa = _service_account()
    if sa is None:
        return
    with SessionLocal() as db:
        tokens = db.scalars(select(DeviceToken).where(DeviceToken.student_id == student_id)).all()
        for t in tokens:
            try:
                if not send_to_token(sa, t.token, title, body, {"order_id": order_id}):
                    db.delete(t)  # جهاز ألغى التطبيق أو انتهى رمزه
            except Exception as e:  # لا يجب أن يؤثر فشل الإشعار على عمل السيرفر
                log.warning("خطأ في إرسال إشعار Push: %s", e)
        db.commit()


def queue(db, student_id: int, title: str, body: str, order_id: str | None) -> None:
    """يُحفظ الإشعار مع الجلسة ويُرسل فقط بعد نجاح حفظ البيانات (commit)."""
    if enabled():
        db.info.setdefault("pending_push", []).append((student_id, title, body, order_id))


def install(session_factory) -> None:
    @event.listens_for(session_factory, "after_commit")
    def _after_commit(session):
        pending = session.info.pop("pending_push", [])
        for args in pending:
            if SYNC:
                _deliver(*args)
            else:
                _executor.submit(_deliver, *args)

    @event.listens_for(session_factory, "after_rollback")
    def _after_rollback(session):
        session.info.pop("pending_push", None)
