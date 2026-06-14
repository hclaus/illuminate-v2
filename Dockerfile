# Stage 1: Build frontend
FROM node:22-slim AS frontend
WORKDIR /build
RUN npm install -g pnpm
COPY ui/package.json ui/pnpm-lock.yaml ui/pnpm-workspace.yaml ui/.npmrc ./
RUN pnpm install --frozen-lockfile
COPY ui/ ./
ARG BASE_PATH=
ARG VITE_API_URL=/api/v1
RUN BASE_PATH=${BASE_PATH} VITE_API_URL=${VITE_API_URL} pnpm build

# Stage 2: Runtime
FROM python:3.12-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends git && rm -rf /var/lib/apt/lists/*
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
COPY api/pyproject.toml api/uv.lock ./
RUN uv sync --frozen --no-dev --no-editable
COPY VERSION .
COPY api/ .
COPY --from=frontend /build/build /app/frontend
RUN mkdir /data && useradd -m -u 1000 appuser && chown -R appuser:appuser /app && chown -R appuser:appuser /data
USER appuser
# Pre-warm matplotlib font cache so first plot request isn't slow
RUN /app/.venv/bin/python -c "import matplotlib.pyplot as plt; plt.figure(); plt.close()"
ENV STATIC_DIR=/app/frontend
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD /app/.venv/bin/python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/api/v1/health')"
# Single worker required: in-memory session manager does not support multi-worker
CMD ["/app/.venv/bin/uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
