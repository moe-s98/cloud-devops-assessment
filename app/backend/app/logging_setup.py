"""Structured JSON logging to stdout.

CloudWatch Logs ingests stdout from the ECS awslogs driver; JSON lines let us
build metric filters on fields such as `level` and `status`.
"""

import json
import logging
import sys
from datetime import UTC, datetime


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "ts": datetime.now(UTC).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
        }
        payload.update(getattr(record, "extra_fields", {}))
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)
        return json.dumps(payload)


def configure_logging(level: str) -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(level)
    # uvicorn's access log duplicates our request middleware
    logging.getLogger("uvicorn.access").disabled = True
