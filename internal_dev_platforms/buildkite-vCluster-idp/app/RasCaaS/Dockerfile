# syntax=docker/dockerfile:1

# -----------------------------------------------------------------------------
# Stage 1 — install deps for Python 3.11 (must match distroless runtime)
# -----------------------------------------------------------------------------
FROM python:3.11-slim-bookworm AS builder

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /build

COPY requirements.txt .
# --target avoids venv symlinks that break across stages
RUN pip install --upgrade pip \
    && pip install --no-cache-dir --target=/deps -r requirements.txt

# -----------------------------------------------------------------------------
# Stage 2 — minimal rootless runtime (distroless python3-debian12 = Python 3.11)
# -----------------------------------------------------------------------------
FROM gcr.io/distroless/python3-debian12:nonroot AS runtime

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH=/deps:/app

WORKDIR /app

COPY --from=builder --chown=65532:65532 /deps /deps
COPY --chown=65532:65532 app ./app

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["/usr/bin/python3", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2)"]

ENTRYPOINT ["/usr/bin/python3"]
CMD ["-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
