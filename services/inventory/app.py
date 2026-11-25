"""Inventory service: medicines, stock levels, low-stock check.

Set BUGGY=true to simulate a bad release (random 500s + slow responses).
OpsPilot's AI agent will later detect and roll this back.
"""
import os
import random
import time

from fastapi import FastAPI, HTTPException
from prometheus_fastapi_instrumentator import Instrumentator
from pydantic import BaseModel

app = FastAPI(title="inventory-service", version=os.getenv("APP_VERSION", "1.0.0"))
Instrumentator().instrument(app).expose(app)  # exposes /metrics for Prometheus

BUGGY = os.getenv("BUGGY", "false").lower() == "true"

STOCK: dict[str, dict] = {
    "paracetamol-500": {"name": "Paracetamol 500mg", "qty": 120, "min_qty": 30},
    "cetirizine-10": {"name": "Cetirizine 10mg", "qty": 25, "min_qty": 20},
    "ors-sachet": {"name": "ORS Sachet", "qty": 8, "min_qty": 15},
    "amoxicillin-500": {"name": "Amoxicillin 500mg", "qty": 40, "min_qty": 25},
}


class Reserve(BaseModel):
    sku: str
    qty: int


def maybe_break():
    if BUGGY:
        time.sleep(random.uniform(0.5, 2.0))
        if random.random() < 0.4:
            raise HTTPException(status_code=500, detail="simulated failure")


@app.get("/healthz")
def healthz():
    return {"status": "ok", "version": app.version}


@app.get("/items")
def list_items():
    maybe_break()
    return STOCK


@app.get("/items/{sku}")
def get_item(sku: str):
    maybe_break()
    if sku not in STOCK:
        raise HTTPException(status_code=404, detail="not found")
    return STOCK[sku]


@app.get("/low-stock")
def low_stock():
    return {k: v for k, v in STOCK.items() if v["qty"] < v["min_qty"]}


@app.post("/reserve")
def reserve(req: Reserve):
    maybe_break()
    item = STOCK.get(req.sku)
    if not item:
        raise HTTPException(status_code=404, detail="not found")
    if req.qty <= 0 or item["qty"] < req.qty:
        raise HTTPException(status_code=409, detail="insufficient stock")
    item["qty"] -= req.qty
    return {"sku": req.sku, "remaining": item["qty"]}
