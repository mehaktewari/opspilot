from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app import app

client = TestClient(app)


def test_health():
    assert client.get("/healthz").json()["status"] == "ok"


@patch("app.httpx.post")
def test_create_order_ok(mock_post):
    mock_post.return_value = MagicMock(status_code=200, json=lambda: {"remaining": 5})
    r = client.post("/orders", json={"sku": "ors-sachet", "qty": 1})
    assert r.status_code == 201
    assert r.json()["status"] == "confirmed"


@patch("app.httpx.post")
def test_create_order_inventory_error(mock_post):
    mock_post.return_value = MagicMock(status_code=409, json=lambda: {"detail": "insufficient stock"})
    r = client.post("/orders", json={"sku": "ors-sachet", "qty": 999})
    assert r.status_code == 409
