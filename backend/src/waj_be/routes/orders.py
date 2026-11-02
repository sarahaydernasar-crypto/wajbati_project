"""Order route aggregator; implementation lives in focused route modules."""

from fastapi import APIRouter

from waj_be.routes.order_creation import router as order_creation_router
from waj_be.routes.order_queries import router as order_queries_router
from waj_be.routes.order_status import router as order_status_router

router = APIRouter()
router.include_router(order_creation_router)
router.include_router(order_queries_router)
router.include_router(order_status_router)
