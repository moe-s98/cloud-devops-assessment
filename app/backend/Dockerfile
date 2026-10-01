# ---- Stage 1: build dependencies into an isolated virtualenv ---------------
FROM python:3.12-alpine AS builder
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /build
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY requirements.txt .
RUN pip install -r requirements.txt \
 && pip uninstall -y pip setuptools wheel \
 && find /opt/venv -type d -name "__pycache__" -prune -exec rm -rf {} +

# ---- Stage 2: minimal runtime ----------------------------------------------
FROM python:3.12-alpine AS runtime
ARG APP_VERSION=dev
LABEL org.opencontainers.image.title="guestbook-api" \
      org.opencontainers.image.version="${APP_VERSION}"

# Alpine base + no pip/setuptools: smaller image, fewer packages to scan and patch.
RUN pip uninstall -y pip setuptools wheel 2>/dev/null; \
    addgroup -S -g 10001 app \
 && adduser -S -D -H -u 10001 -G app -s /sbin/nologin app

COPY --from=builder /opt/venv /opt/venv
WORKDIR /srv
COPY --chown=root:root app ./app

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_VERSION=${APP_VERSION}

# Numeric UID so Kubernetes/ECS "runAsNonRoot" style checks can verify it.
USER 10001
EXPOSE 8000

HEALTHCHECK --interval=15s --timeout=3s --start-period=20s --retries=3 \
  CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/api/health', timeout=2).status == 200 else 1)"]

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2", "--no-server-header", "--proxy-headers", "--forwarded-allow-ips", "*"]
