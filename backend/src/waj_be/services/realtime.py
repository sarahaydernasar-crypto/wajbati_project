from fastapi import WebSocket


class OrderConnectionManager:
    def __init__(self) -> None:
        self.connections: dict[int, set[WebSocket]] = {}

    async def connect(self, cafeteria_id: int, websocket: WebSocket) -> None:
        self.connections.setdefault(cafeteria_id, set()).add(websocket)

    def disconnect(self, cafeteria_id: int, websocket: WebSocket) -> None:
        clients = self.connections.get(cafeteria_id)
        if clients is not None:
            clients.discard(websocket)
            if not clients:
                self.connections.pop(cafeteria_id, None)

    async def broadcast(self, cafeteria_id: int, event: dict) -> None:
        clients = self.connections.get(cafeteria_id, set()).copy()
        for websocket in clients:
            try:
                await websocket.send_json(event)
            except Exception:
                self.disconnect(cafeteria_id, websocket)


order_connection_manager = OrderConnectionManager()


async def broadcast_order_event(cafeteria_id: int, event: dict) -> None:
    await order_connection_manager.broadcast(cafeteria_id, event)
