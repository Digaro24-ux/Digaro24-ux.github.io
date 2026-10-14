#!/usr/bin/env bash
# Creates .env with random secrets. Run on the server inside the divine-ollama folder.
set -euo pipefail
cd "$(dirname "$0")"
command -v openssl >/dev/null || { echo "openssl is required (sudo apt install -y openssl)"; exit 1; }
if [ -f .env ]; then read -rp ".env already exists. Overwrite? (y/N) " a; [[ "$a" =~ ^[Yy]$ ]] || exit 0; fi
ask(){ local v; read -rp "$1 [$2]: " v; echo "${v:-$2}"; }
API=$(ask "API domain" "divine-ollama.duckdns.org")
ADM=$(ask "Admin domain" "divine-admin.duckdns.org")
SBU=$(ask "Supabase URL" "https://pqtcwnyeowcycvkmmjow.supabase.co")
ORIG=$(ask "Front page address" "https://digaro24-ux.github.io")
read -rp "Email for HTTPS certificates: " EMAIL
read -rp "Supabase anon/publishable key (public key ONLY): " KEY
[[ "$EMAIL" == *@*.* ]] || { echo "Enter a valid email."; exit 1; }
[ -n "$KEY" ] || { echo "The anon key is required."; exit 1; }
case "$KEY" in *service_role*|sb_secret_*) echo "That looks like a SECRET key. Use the anon/publishable key."; exit 1;; esac
SBU="${SBU%/}"; SBU="${SBU%/rest/v1}"; ORIG="${ORIG%/}"
cat > .env <<ENV
API_DOMAIN=$API
ADMIN_DOMAIN=$ADM
ACME_EMAIL=$EMAIL
SUPABASE_URL=$SBU
SUPABASE_ANON_KEY=$KEY
ALLOWED_ORIGINS=$ORIG
ALLOWED_MODELS=llama3.2:3b,qwen2.5:3b,qwen2.5-coder:3b
RATE_PER_MIN=20
POSTGRES_USER=divine
POSTGRES_PASSWORD=$(openssl rand -hex 24)
POSTGRES_DB=divine_admin
WEBUI_SECRET_KEY=$(openssl rand -hex 32)
ENABLE_SIGNUP=true
ENV
chmod 600 .env
echo ".env created. Next: docker compose up -d --build"
echo "After you create your admin account in the admin console, set ENABLE_SIGNUP=false in .env and run: docker compose up -d"
