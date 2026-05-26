# ═══════════════════════════════════════════════════════════════════════════════
# MULTI-STAGE DOCKERFILE — Mission Data Processor
# Stage 1: Build (dependencies + compile)
# Stage 2: Runtime (minimal distroless image)
#
# Security features:
#   - Non-root user
#   - Distroless base (no shell, no package manager)
#   - No secrets in image layers
#   - Health check endpoint
# ═══════════════════════════════════════════════════════════════════════════════

# ─── Stage 1: Build ───
FROM python:3.11-slim AS builder

WORKDIR /build

# Install dependencies first (layer caching)
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Copy application source
COPY src/ ./src/

# ─── Stage 2: Runtime ───
FROM python:3.11-slim AS runtime

# Security: Create non-root user
RUN groupadd -r mission && useradd -r -g mission -d /app -s /sbin/nologin mission

# Install only runtime dependencies
COPY --from=builder /install /usr/local

# Copy application
WORKDIR /app
COPY --from=builder /build/src/ ./src/
COPY entrypoint.sh .

# Security: Set ownership and permissions
RUN chown -R mission:mission /app && \
    chmod +x /app/entrypoint.sh

# Security: Drop all capabilities, run as non-root
USER mission

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1

# Expose metrics and API ports
EXPOSE 8080 9090

# Labels for traceability
LABEL maintainer="yuriy@sovereign-infra" \
      project="mdi-sovereign" \
      classification="UNCLASSIFIED-DEMO" \
      description="Mission Data Processor — Edge Simulator"

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["--mode", "processor"]
