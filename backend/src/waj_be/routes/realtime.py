import asyncio

import jwt
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from sqlmodel import Session, select

from waj_be.database import engine
from waj_be.models import (
    Cafeteria,
    OwnerApplication,
    OwnerApplicationStatus,
    User,
    UserRole,
)
from waj_be.routes.auth import JWT_ALGORITHM, JWT_SECRET
from waj_be.services.realtime import order_connection_manager

router = APIRouter(tags=["real-time"])


@router.websocket("/ws/cafeterias/{cafeteria_id}/orders")
async def cafeteria_order_updates(websocket: WebSocket, cafeteria_id: int) -> None:
    await websocket.accept()
    try:
        auth_message = await asyncio.wait_for(websocket.receive_json(), timeout=10)
        token = auth_message.get("token") if isinstance(auth_message, dict) else None
        claims = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        user_id = int(claims["sub"])
    except (
        asyncio.TimeoutError,
        WebSocketDisconnect,
        jwt.InvalidTokenError,
        KeyError,
        TypeError,
        ValueError,
    ):
        await websocket.close(code=1008, reason="Send a valid access token first")
        return

    with Session(engine) as session:
        user = session.get(User, user_id)
        cafeteria = session.get(Cafeteria, cafeteria_id)
        owner_application = session.exec(
            select(OwnerApplication).where(OwnerApplication.user_id == user_id)
        ).first()
        if (
            user is None
            or not user.is_active
            or user.role != UserRole.CAFETERIA_OWNER
            or owner_application is None
            or owner_application.status != OwnerApplicationStatus.APPROVED
            or cafeteria is None
            or cafeteria.owner_id != user.id
        ):
            await websocket.close(code=1008, reason="Cafeteria owner access required")
            return

    await order_connection_manager.connect(cafeteria_id, websocket)
    await websocket.send_json({"event": "connected", "cafeteria_id": cafeteria_id})
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        order_connection_manager.disconnect(cafeteria_id, websocket)
