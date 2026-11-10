import hashlib
from datetime import timedelta

from fastapi import HTTPException
from sqlalchemy import delete, select, text, update

from . import logic
from .models import LoginAttempt

WINDOW_SECONDS = 300
MAX_ATTEMPTS = 10


def check_login(db, identifier: str) -> None:
    """A shared DB counter, so the limit applies across API workers."""
    key = hashlib.sha256(identifier.encode()).hexdigest()
    now = logic.now()
    db.execute(text("INSERT INTO login_attempts (key, attempts, window_start) VALUES (:key, 0, :now) "
                    "ON CONFLICT (key) DO NOTHING"), {"key": key, "now": now})
    db.execute(update(LoginAttempt).where(LoginAttempt.key == key).values(attempts=LoginAttempt.attempts))
    attempt = db.scalar(select(LoginAttempt).where(LoginAttempt.key == key).execution_options(populate_existing=True))
    if now >= attempt.window_start + timedelta(seconds=WINDOW_SECONDS):
        attempt.attempts = 0
        attempt.window_start = now
    limited = attempt.attempts >= MAX_ATTEMPTS
    if not limited:
        attempt.attempts += 1
    db.execute(delete(LoginAttempt).where(LoginAttempt.window_start < now - timedelta(days=1)))
    db.commit()  # Failed authentication must also retain its attempt.
    if limited:
        raise HTTPException(429, "محاولات دخول كثيرة. انتظر خمس دقائق وحاول مجدداً.",
                            headers={"Retry-After": str(WINDOW_SECONDS)})
