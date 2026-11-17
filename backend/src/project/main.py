"""سيرفر وجباتي.

التشغيل (من داخل مجلد backend):
    uv run uvicorn project.main:app --host 0.0.0.0 --port 8000

التوثيق التفاعلي: http://localhost:8000/docs
"""

from contextlib import asynccontextmanager
import json
import os
import logging

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import select

from . import push
from .database import Base, SessionLocal, add_missing_columns, engine
from .models import Cafeteria, MenuItem, Student
from .routes_cafeteria import router as cafeteria_router
from .routes_student import router as student_router
from .routes_platform import router as platform_router
from .security import hash_secret
from .menu_ingredients import initial_ingredients
from .settings import production

log = logging.getLogger("wajbati.api")

# بيانات أولية: نفس الكافيتريات والرموز الموجودة في التطبيق
SEED_CAFETERIAS = [
    ("كافيتريا علوم حاسوب", "CS771SOL", "قسم علوم الحاسوب - الطابق الأرضي", 7, 23),
    ("كافيتريا العلوم التطبيقية", "AP882APP", "بناية العلوم التطبيقية", 8, 22),
    ("كافيتريا كهرومكانيك", "EM993MEH", "قسم الهندسة الكهروميكانيكية", 8, 20),
    ("كافيتريا طب حياتي", "BM445BIO", "قسم الهندسة الطبية الحياتية", 8, 15),
    ("كافيتريا معماري", "AR556ARC", "قسم الهندسة المعمارية", 9, 14),
]
SEED_MENU = [
    ("صمون كباب لحم", 3000, 10, "🥙"),
    ("ببسي / عصير", 1000, 2, "🥤"),
    ("شاي مهيل", 500, 5, "🍵"),
]


def seed() -> None:
    with SessionLocal() as db:
        if db.scalar(select(Cafeteria).limit(1)) is not None:
            return
        codes = json.loads(os.getenv("WAJBATI_CAFETERIA_CODES", "{}"))
        if production() and any(not isinstance(codes.get(name), str) or
                                not 12 <= len(codes[name].encode()) <= 72
                                for name, *_ in SEED_CAFETERIAS):
            raise RuntimeError("اضبط WAJBATI_CAFETERIA_CODES برموز جديدة لكل الكافيتريات قبل أول تشغيل إنتاجي")
        for name, code, location, open_hour, close_hour in SEED_CAFETERIAS:
            code = codes.get(name, code)
            cafe = Cafeteria(
                name=name, code_hash=hash_secret(code), location=location, open_hour=open_hour, close_hour=close_hour
            )
            cafe.menu_items = [
                MenuItem(name=n, price=p, prep_minutes=m, emoji=e, **initial_ingredients(n)) for n, p, m, e in SEED_MENU
            ]
            db.add(cafe)
        # حساب طالب تجريبي
        if not production() and os.getenv("WAJBATI_SEED_DEMO", "true").lower() == "true":
            db.add(
                Student(
                    name="طالب تجريبي", university_id="2024001", phone="07700000000", password_hash=hash_secret("123456")
                )
            )
        db.commit()


push.install(SessionLocal)  # إرسال إشعارات Push بعد حفظ البيانات


@asynccontextmanager
async def lifespan(_: FastAPI):
    Base.metadata.create_all(engine)  # الجداول الجديدة
    add_missing_columns()  # الأعمدة الجديدة في الجداول القديمة
    seed()
    yield


app = FastAPI(title="Wajbati API", version="0.1.0", lifespan=lifespan)


@app.exception_handler(Exception)
async def unexpected_error(request: Request, exc: Exception):
    # Log the route and stack trace; never log credentials or request bodies.
    log.error("Unhandled API error: %s %s", request.method, request.url.path,
              exc_info=(type(exc), exc, exc.__traceback__))
    # ServerErrorMiddleware handles this outside CORSMiddleware. Keep the same
    # public-origin policy so browsers can read the error instead of reporting
    # a misleading network failure.
    return JSONResponse(status_code=500, content={"detail": "حدث خطأ في السيرفر، حاول بعد قليل."},
                        headers={"Access-Control-Allow-Origin": "*"})

# تطبيق Flutter (ويب/موبايل) يتصل من أصل مختلف
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

FIELD_NAMES = {
    "name": "الاسم",
    "university_id": "الرقم الجامعي",
    "phone": "رقم الهاتف",
    "password": "كلمة المرور",
    "quantity": "الكمية",
    "note": "الملاحظة",
    "lines": "أصناف الطلب",
    "pickup_time": "وقت الاستلام",
    "price": "السعر",
    "stars": "التقييم",
}


@app.exception_handler(RequestValidationError)
async def validation_error(_: Request, exc: RequestValidationError):
    """تحويل أخطاء التحقق إلى رسالة عربية واحدة واضحة."""
    first = exc.errors()[0] if exc.errors() else {}
    msg = str(first.get("msg", "بيانات غير صالحة")).removeprefix("Value error, ")
    field = next((str(p) for p in reversed(first.get("loc", ())) if isinstance(p, str)), "")
    if not any("؀" <= ch <= "ۿ" for ch in msg):  # رسالة إنجليزية افتراضية من pydantic
        msg = f"قيمة غير صالحة في: {FIELD_NAMES.get(field, field)}"
    return JSONResponse(status_code=422, content={"detail": msg})


app.include_router(student_router)
app.include_router(cafeteria_router)
app.include_router(platform_router)


@app.get("/health", tags=["health"])
def health():
    return {"status": "ok"}
