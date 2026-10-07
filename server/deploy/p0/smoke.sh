#!/usr/bin/env bash
# P0 server smoke test (SGODOT-232 D1): P0_BASE=https://host/preview/p0 P0_KEY=… server/deploy/p0/smoke.sh
# Checks: health, a request without the key refused, state read with the key, one command round trip, dev routes
# absent, a UI moment accepted. Uses a throwaway player id; touches no real player's save.
set -euo pipefail
BASE="${P0_BASE:?P0_BASE=https://host/preview/p0 或 http://host:3150}"
KEY="${P0_KEY:?P0_KEY=演示口令}"
PLAYER="smoke-$(date +%s)"
c() { curl --noproxy '*' -s -o /tmp/p0_smoke_body -w '%{http_code}' "$@"; }
fail() { echo "FAIL: $1"; cat /tmp/p0_smoke_body; echo; exit 1; }
[ "$(c "$BASE/v1/healthz")" = 200 ] || fail healthz
[ "$(c -H "x-p0-player: $PLAYER" "$BASE/v1/p0/state")" = 401 ] || fail "no key should be 401"
[ "$(c -H "x-p0-player: $PLAYER" -H "x-p0-key: $KEY" "$BASE/v1/p0/state")" = 200 ] || fail "state with key"
code=$(c -X POST -H "x-p0-player: $PLAYER" -H "x-p0-key: $KEY" -H 'content-type: application/json' -d '{"type":"sow","plot":0,"seed":"seed_radish","space":"home"}' "$BASE/v1/p0/commands")
[ "$code" = 200 ] && grep -q '"ok":true' /tmp/p0_smoke_body || fail "sow round trip"
[ "$(c -X POST -H "x-p0-player: $PLAYER" -H "x-p0-key: $KEY" -H 'content-type: application/json' -d '{"minutes":60}' "$BASE/v1/p0/dev/skip")" = 404 ] || fail "dev route must be off"
[ "$(c -X POST -H "x-p0-player: $PLAYER" -H "x-p0-key: $KEY" -H 'content-type: application/json' -d '{"events":[{"kind":"screen","name":"smoke"}]}' "$BASE/v1/p0/telemetry")" != 401 ] || fail "telemetry"
echo "P0 smoke OK ($BASE, player $PLAYER)"
