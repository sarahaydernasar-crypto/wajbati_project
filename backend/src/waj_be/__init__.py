def main() -> None:
    import uvicorn

    uvicorn.run("waj_be.main:app", host="127.0.0.1", port=8000)
