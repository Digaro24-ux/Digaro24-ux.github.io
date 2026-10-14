#!/usr/bin/env bash
# Downloads the models listed in ALLOWED_MODELS (.env) into Ollama.
set -euo pipefail
cd "$(dirname "$0")/.."
MODELS=$(grep -E '^ALLOWED_MODELS=' .env 2>/dev/null | cut -d= -f2 || true)
MODELS=${MODELS:-llama3.2:3b,qwen2.5:3b,qwen2.5-coder:3b}
for m in ${MODELS//,/ }; do echo "==> Pulling $m"; docker compose exec -T ollama ollama pull "$m"; done
docker compose exec -T ollama ollama list
