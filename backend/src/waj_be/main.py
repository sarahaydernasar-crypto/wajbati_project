from contextlib import asynccontextmanager

from fastapi import FastAPI
from waj_be.routes.admin import router as admin_router
from waj_be.routes.auth import router as auth_router
from waj_be.routes.cafeterias import router as cafeterias_router
from waj_be.routes.orders import router as orders_router
from waj_be.routes.ratings import router as ratings_router
from waj_be.routes.realtime import router as realtime_router
from waj_be.database import create_db


@asynccontextmanager
async def lifespan(app: FastAPI):
    create_db()
    yield


app = FastAPI(lifespan=lifespan)
app.include_router(auth_router)
app.include_router(admin_router)
app.include_router(cafeterias_router)
app.include_router(orders_router)
app.include_router(ratings_router)
app.include_router(realtime_router)

