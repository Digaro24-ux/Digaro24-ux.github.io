#!/usr/bin/env bash
# Usage: ./check-domain.sh <domain> [vps_ip]
# Optional: API_KEY=sk-xxxx ./check-domain.sh <domain> [vps_ip]
DOMAIN="${1:?Usage: $0 <domain> [vps_ip]}"; IP="${2:-}"
pass(){ echo "  [PASS] $*"; }; fail(){ echo "  [FAIL] $*"; FAILS=$((FAILS+1)); }; FAILS=0

echo "1) DNS"
RES=$(getent hosts "$DOMAIN" 2>/dev/null | awk '{print $1}' | head -1)
[ -z "$RES" ] && RES=$(nslookup "$DOMAIN" 2>/dev/null | awk '/^Address: /{print $2}' | tail -1)
if [ -n "$RES" ]; then pass "$DOMAIN -> $RES"; else fail "domain does not resolve"; fi
if [ -n "$IP" ] && [ -n "$RES" ]; then [ "$RES" = "$IP" ] && pass "matches VPS IP" || fail "resolves to $RES, expected $IP"; fi

echo "2) HTTP -> HTTPS redirect"
C=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "http://$DOMAIN")
case "$C" in 301|302|307|308) pass "HTTP $C";; *) fail "got HTTP $C";; esac

echo "3) HTTPS and certificate"
C=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "https://$DOMAIN/health")
[ "$C" = "200" ] && pass "/health returned 200" || fail "/health returned $C"
if command -v openssl >/dev/null; then
  END=$(echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN:443" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
  [ -n "$END" ] && pass "certificate valid until $END" || fail "could not read certificate"
fi

echo "4) API requires a key"
C=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "https://$DOMAIN/api/models")
case "$C" in 401|403) pass "no key -> $C (blocked)";; *) fail "no key -> $C (expected 401/403)";; esac
if [ -n "${API_KEY:-}" ]; then
  C=$(curl -s -o /dev/null -m 15 -w '%{http_code}' -H "Authorization: Bearer $API_KEY" "https://$DOMAIN/api/models")
  [ "$C" = "200" ] && pass "valid key -> 200" || fail "valid key -> $C"
fi

echo "5) Internal ports are closed to the internet"
TARGET="${IP:-$DOMAIN}"
for P in 11434 5432; do
  if timeout 4 bash -c "echo > /dev/tcp/$TARGET/$P" 2>/dev/null; then fail "port $P is OPEN"; else pass "port $P closed"; fi
done

echo; [ "$FAILS" -eq 0 ] && echo "All checks passed." || echo "$FAILS check(s) failed."
exit "$FAILS"
