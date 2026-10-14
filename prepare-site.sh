#!/usr/bin/env bash
# Run inside the folder with index.html, terms.html and privacy.html (Mac, Linux, WSL or Git Bash).
# It fills in your details so no placeholders are left. Nothing here is a secret.
set -euo pipefail
cd "$(dirname "$0")"
esc(){ printf '%s' "$1" | sed 's/[&|\\]/\\&/g'; }
read -rp "Your name or organisation (shown in Terms/Privacy): " NAME
read -rp "Contact email: " EMAIL
read -rp "Country whose law governs the Terms (e.g. Nigeria): " COUNTRY
read -rp "Supabase anon/publishable key (public key ONLY): " KEY
[[ -n "$NAME" && -n "$EMAIL" && -n "$COUNTRY" && -n "$KEY" ]] || { echo "All four answers are required."; exit 1; }
case "$KEY" in *service_role*|sb_secret_*) echo "That looks like a SECRET key. Use the anon/publishable key."; exit 1;; esac
sed -i.bak "s|YOUR-NAME|$(esc "$NAME")|g; s|YOUR-EMAIL@example.com|$(esc "$EMAIL")|g; s|YOUR-COUNTRY|$(esc "$COUNTRY")|g" terms.html privacy.html
sed -i.bak "s|YOUR-ANON-OR-PUBLISHABLE-KEY|$(esc "$KEY")|g" index.html
rm -f ./*.bak
if grep -n "YOUR-" index.html terms.html privacy.html; then echo "Placeholders remain above."; exit 1; fi
echo "Done. Upload index.html, terms.html and privacy.html to your GitHub repo."
