# syntax=docker/dockerfile:1
# Standalone UAT temp-ECR GC — separate from the RaSCaaS IDP image.
FROM python:3.11-slim-bookworm

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

COPY cleanup.py .

USER nobody:nogroup

ENTRYPOINT ["python", "/app/cleanup.py"]
