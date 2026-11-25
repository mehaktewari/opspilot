"""Orders service: places orders by reserving stock in inventory-service."""
import os
import uuid

import httpx
from fastapi import FastAPI, HTTPException
from prometheus_fastapi_instrumentator import Instrumentator
from pydantic import BaseModel

app = FastAPI(title="orders-service", version=os.getenv("APP_VERSION", "1.0.0"))
Instrumentator().instrument(app).expose(app)

INVENTORY_URL = os.getenv("INVENTORY_URL", "http://localhost:8001")
ORDERS: dict[str, dict] = {}


class OrderIn(BaseModel):
    sku: str
    qty: int


@app.get("/healthz")
def healthz():
    return {"status": "ok", "version": app.version}


@app.post("/orders", status_code=201)
def create_order(order: OrderIn):
    try:
        r = httpx.post(f"{INVENTORY_URL}/reserve", json=order.model_dump(), timeout=3.0)
    except httpx.HTTPError as e:
        raise HTTPException(status_code=503, detail=f"inventory unavailable: {e}")
    if r.status_code != 200:
        raise HTTPException(status_code=r.status_code, detail=r.json().get("detail"))
    order_id = str(uuid.uuid4())[:8]
    ORDERS[order_id] = {"id": order_id, **order.model_dump(), "status": "confirmed"}
    return ORDERS[order_id]


@app.get("/orders")
def list_orders():
    return list(ORDERS.values())
