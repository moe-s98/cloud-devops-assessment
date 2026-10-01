"""Unit tests: run the real FastAPI app against an in-memory repository."""

from contextlib import asynccontextmanager

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app import main
from app.repository import InMemoryRepository


@pytest.fixture
def client(monkeypatch):
    # Skip the Postgres lifespan; inject an in-memory repo instead.
    repo = InMemoryRepository()

    @asynccontextmanager
    async def noop_lifespan(app: FastAPI):
        app.state.repo = repo
        yield

    monkeypatch.setattr(main.app.router, "lifespan_context", noop_lifespan)
    with TestClient(main.app) as c:
        yield c


def test_health(client):
    r = client.get("/api/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_ready_when_db_up(client):
    r = client.get("/api/ready")
    assert r.status_code == 200
    assert r.json()["database"] == "up"


def test_ready_when_db_down(client, monkeypatch):
    monkeypatch.setattr(InMemoryRepository, "ping", lambda self: False)
    r = client.get("/api/ready")
    assert r.status_code == 503


def test_create_and_list_messages(client):
    r = client.post("/api/messages", json={"author": " Moe ", "body": "Hello AWS"})
    assert r.status_code == 201
    assert r.json()["author"] == "Moe"

    r = client.get("/api/messages")
    assert r.status_code == 200
    assert [m["body"] for m in r.json()] == ["Hello AWS"]


def test_newest_message_first(client):
    for body in ("first", "second"):
        client.post("/api/messages", json={"author": "a", "body": body})
    assert client.get("/api/messages").json()[0]["body"] == "second"


@pytest.mark.parametrize(
    "payload",
    [{"author": "", "body": "x"}, {"author": "a", "body": ""}, {"author": "a" * 65, "body": "x"}],
)
def test_validation_rejects_bad_input(client, payload):
    assert client.post("/api/messages", json=payload).status_code == 422


def test_limit_is_clamped(client):
    for i in range(3):
        client.post("/api/messages", json={"author": "a", "body": str(i)})
    assert len(client.get("/api/messages?limit=0").json()) == 1
    assert len(client.get("/api/messages?limit=1000").json()) == 3
