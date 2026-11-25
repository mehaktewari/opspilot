from fastapi.testclient import TestClient

from app import app

client = TestClient(app)


def test_health():
    assert client.get("/healthz").json()["status"] == "ok"


def test_low_stock_flags_ors():
    assert "ors-sachet" in client.get("/low-stock").json()


def test_reserve_reduces_stock():
    before = client.get("/items/paracetamol-500").json()["qty"]
    r = client.post("/reserve", json={"sku": "paracetamol-500", "qty": 2})
    assert r.status_code == 200
    assert r.json()["remaining"] == before - 2


def test_reserve_too_much_fails():
    r = client.post("/reserve", json={"sku": "ors-sachet", "qty": 9999})
    assert r.status_code == 409

def test_amoxicillin_in_stock():
    r = client.get("/items/amoxicillin-500")
    assert r.status_code == 200
    assert r.json()["name"] == "Amoxicillin 500mg"
