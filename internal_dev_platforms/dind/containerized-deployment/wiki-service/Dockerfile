# Build stage: install dependencies with uv
FROM python:3.13-slim AS builder

WORKDIR /app

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Copy dependency manifests and install (no dev dependencies).
# Omit --frozen so deps from pyproject.toml are installed even when uv.lock is missing some (e.g. asyncpg).
COPY pyproject.toml uv.lock ./
RUN uv sync --no-dev --no-install-project

# Test stage: has pytest and test deps (use: docker build --target test)
FROM python:3.13-slim AS test
WORKDIR /app
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-install-project \
    && uv pip install pytest pytest-asyncio httpx asyncpg
COPY app ./app
ENV PATH="/app/.venv/bin:$PATH"
CMD ["python", "-m", "pytest", "app/tests/", "-v", "--tb=short"]

# Runtime stage: serve the app (default)
FROM python:3.13-slim

WORKDIR /app

# Create non-root user
RUN adduser --disabled-password --gecos "" appuser

# Copy virtual environment from builder
COPY --from=builder /app/.venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH"

# Copy application code
COPY app ./app
COPY pyproject.toml ./

# Own files
RUN chown -R appuser:appuser /app
USER appuser

EXPOSE 8080

# Run FastAPI with uvicorn
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
