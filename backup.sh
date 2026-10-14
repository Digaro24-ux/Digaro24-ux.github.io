#!/usr/bin/env bash
# Backs up the admin-console database and settings. Chats live in Supabase (see Supabase backups/export).
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a
DEST="$HOME/backups"; mkdir -p "$DEST"; STAMP=$(date +%F_%H%M)
docker compose exec -T postgres pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" | gzip > "$DEST/admin-db-$STAMP.sql.gz"
docker run --rm -v divine-ollama_openwebui_data:/d -v "$DEST":/b alpine tar czf "/b/admin-data-$STAMP.tgz" -C /d .
find "$DEST" -type f -mtime +14 -delete
echo "Backup written to $DEST ($STAMP)"
