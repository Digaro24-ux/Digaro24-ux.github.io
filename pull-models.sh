#!/usr/bin/env bash
# Downloads the models listed in GARO_MODELS (.env) into Ollama.
set -euo pipefail
cd "$(dirname "$0")/.."
RAW=$(grep -E '^GARO_MODELS=' .env 2>/dev/null | cut -d= -f2- || true)
RAW=${RAW:-garo-chat=llama3.2:3b,garo-think=qwen2.5:3b,garo-code=qwen2.5-coder:3b}
for pair in ${RAW//,/ }; do
  m=${pair#*=}
  echo "==> Pulling $m"; docker compose exec -T ollama ollama pull "$m"
done
docker compose exec -T ollama ollama list
