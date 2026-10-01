"""Runtime configuration, read once from environment variables.

Nothing secret has a default: the DB password is injected at runtime
(docker compose locally, ECS task secret from Secrets Manager in AWS).
"""

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    db_host: str = os.getenv("DB_HOST", "localhost")
    db_port: int = int(os.getenv("DB_PORT", "5432"))
    db_name: str = os.getenv("DB_NAME", "guestbook")
    db_user: str = os.getenv("DB_USER", "guestbook")
    db_password: str = os.getenv("DB_PASSWORD", "")
    db_sslmode: str = os.getenv("DB_SSLMODE", "prefer")
    app_env: str = os.getenv("APP_ENV", "local")
    app_version: str = os.getenv("APP_VERSION", "dev")
    log_level: str = os.getenv("LOG_LEVEL", "INFO")

    @property
    def dsn(self) -> str:
        return (
            f"host={self.db_host} port={self.db_port} dbname={self.db_name} "
            f"user={self.db_user} password={self.db_password} "
            f"sslmode={self.db_sslmode} connect_timeout=5"
        )


settings = Settings()
