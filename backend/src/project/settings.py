import os


def production() -> bool:
    return bool(os.getenv("RENDER")) or os.getenv("WAJBATI_ENV", "development").lower() == "production"
