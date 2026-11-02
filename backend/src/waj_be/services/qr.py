import base64
import secrets
from io import BytesIO

import qrcode


def create_order_qr_token() -> str:
    """Create an unguessable token to encode in an order's QR code."""
    return secrets.token_urlsafe(32)


def generate_order_qr_data_url(token: str) -> str:
    """Render a token as a PNG QR code and return a data URL for the client."""
    image = qrcode.make(token)
    buffer = BytesIO()
    image.save(buffer, format="PNG")
    encoded_image = base64.b64encode(buffer.getvalue()).decode("ascii")
    return f"data:image/png;base64,{encoded_image}"


def verify_order_qr_token(expected_token: str, submitted_token: str) -> bool:
    """Compare scanned QR contents without leaking timing information."""
    return secrets.compare_digest(expected_token, submitted_token)
