"""Guestbook API.

Endpoints (all under /api so CloudFront can route the path to the ALB):
  GET  /api/health    liveness  - process is up, no dependencies checked
  GET  /api/ready     readiness - database reachable
  GET  /api/messages  latest messages
  POST /api/messages  add a message
"""

import logging
import time
from contextlib import asynccontextmanager
from datetime import datetime

from fastapi import Depends, FastAPI, Request, Response
from pydantic import BaseModel, Field

from app.config import settings
from app.logging_setup import configure_logging
from app.repository import MessageRepository, PostgresRepository

configure_logging(settings.log_level)
log = logging.getLogger("guestbook")


@asynccontextmanager
async def lifespan(app: FastAPI):
    repo = PostgresRepository(settings.dsn)
    repo.open()
    app.state.repo = repo
    log.info("startup complete", extra={"extra_fields": {"version": settings.app_version}})
    yield
    repo.close()


app = FastAPI(title="Guestbook API", version=settings.app_version, lifespan=lifespan)


def get_repo(request: Request) -> MessageRepository:
    return request.app.state.repo


class MessageIn(BaseModel):
    author: str = Field(min_length=1, max_length=64)
    body: str = Field(min_length=1, max_length=500)


class MessageOut(BaseModel):
    id: int
    author: str
    body: str
    created_at: datetime


@app.middleware("http")
async def request_log(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    fields = {
        "method": request.method,
        "path": request.url.path,
        "status": response.status_code,
        "duration_ms": round((time.perf_counter() - start) * 1000, 2),
    }
    level = logging.ERROR if response.status_code >= 500 else logging.INFO
    log.log(level, "request", extra={"extra_fields": fields})
    return response


@app.get("/api/health")
def health() -> dict:
    return {"status": "ok", "version": settings.app_version, "env": settings.app_env}


@app.get("/api/ready")
def ready(response: Response, repo: MessageRepository = Depends(get_repo)) -> dict:
    if not repo.ping():
        response.status_code = 503
        return {"status": "unavailable", "database": "down"}
    return {"status": "ready", "database": "up"}


@app.get("/api/messages", response_model=list[MessageOut])
def list_messages(limit: int = 20, repo: MessageRepository = Depends(get_repo)):
    return repo.list_messages(min(max(limit, 1), 100))


@app.post("/api/messages", response_model=MessageOut, status_code=201)
def add_message(msg: MessageIn, repo: MessageRepository = Depends(get_repo)):
    return repo.add_message(msg.author.strip(), msg.body.strip())
