"""Data access for guestbook messages.

`MessageRepository` is the interface the API depends on; `PostgresRepository`
is the real implementation and tests swap in an in-memory one.
"""

from datetime import datetime
from typing import Protocol

from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

# Idempotent schema migration. The advisory lock makes concurrent task
# start-ups (rolling deploy, scale-out) serialize instead of racing.
MIGRATION_LOCK_ID = 727274
SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS messages (
    id         BIGSERIAL PRIMARY KEY,
    author     VARCHAR(64)  NOT NULL,
    body       VARCHAR(500) NOT NULL,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);
"""


class MessageRepository(Protocol):
    def list_messages(self, limit: int) -> list[dict]: ...

    def add_message(self, author: str, body: str) -> dict: ...

    def ping(self) -> bool: ...


class PostgresRepository:
    def __init__(self, dsn: str) -> None:
        self._pool = ConnectionPool(dsn, min_size=1, max_size=5, open=False)

    def open(self) -> None:
        self._pool.open(wait=True, timeout=30)
        with self._pool.connection() as conn:
            conn.execute("SELECT pg_advisory_lock(%s)", (MIGRATION_LOCK_ID,))
            try:
                conn.execute(SCHEMA_SQL)
            finally:
                conn.execute("SELECT pg_advisory_unlock(%s)", (MIGRATION_LOCK_ID,))

    def close(self) -> None:
        self._pool.close()

    def list_messages(self, limit: int) -> list[dict]:
        with self._pool.connection() as conn, conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT id, author, body, created_at FROM messages ORDER BY id DESC LIMIT %s",
                (limit,),
            )
            return cur.fetchall()

    def add_message(self, author: str, body: str) -> dict:
        with self._pool.connection() as conn, conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "INSERT INTO messages (author, body) VALUES (%s, %s) "
                "RETURNING id, author, body, created_at",
                (author, body),
            )
            return cur.fetchone()

    def ping(self) -> bool:
        try:
            with self._pool.connection(timeout=3) as conn:
                conn.execute("SELECT 1")
            return True
        except Exception:  # noqa: BLE001 - readiness must never raise
            return False


class InMemoryRepository:
    """Used by unit tests; behaves like the Postgres repo without a database."""

    def __init__(self) -> None:
        self._rows: list[dict] = []

    def list_messages(self, limit: int) -> list[dict]:
        return list(reversed(self._rows))[:limit]

    def add_message(self, author: str, body: str) -> dict:
        row = {
            "id": len(self._rows) + 1,
            "author": author,
            "body": body,
            "created_at": datetime.now(),
        }
        self._rows.append(row)
        return row

    def ping(self) -> bool:
        return True
