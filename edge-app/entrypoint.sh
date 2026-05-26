#!/bin/sh
# ═══════════════════════════════════════════════════════════════════════════════
# ENTRYPOINT — Mission Data Processor
# Validates environment and starts the application
# ═══════════════════════════════════════════════════════════════════════════════

set -e

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Mission Data Processor — Starting                           ║"
echo "║  Environment: ${ENVIRONMENT:-unknown}                        ║"
echo "║  Cloud: ${CLOUD_PROVIDER:-unknown}                           ║"
echo "║  Mode: ${1:-processor}                                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# Validate required environment variables
if [ -z "$ENVIRONMENT" ]; then
  echo "[ERROR] ENVIRONMENT variable not set"
  exit 1
fi

if [ -z "$CLOUD_PROVIDER" ]; then
  echo "[ERROR] CLOUD_PROVIDER variable not set"
  exit 1
fi

# Start the application
exec python -m uvicorn src.main:app \
  --host 0.0.0.0 \
  --port 8080 \
  --workers ${WORKERS:-2} \
  --log-level ${LOG_LEVEL:-info} \
  --access-log
