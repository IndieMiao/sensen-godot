#!/usr/bin/env bash
# P0 server smoke test (SGODOT-232 D1): P0_BASE=https://host/preview/p0 P0_KEY=… server/deploy/p0/smoke.sh
# Checks: health (and P0_LEGACY_ID off, SGODOT-488), a request without the key refused (also by an encoded path), state read with the key, one command
# round trip, dev routes absent, a UI moment accepted; with the wipe's second guard on (healthz require_features, SGODOT-396
# ①) a request without those features refused with 426. Every keyed request carries save_v7 alone (FEATURES): the other
# features a client sends change how a new save starts (choose_home: a home to pick first; guide_v3: the guide), which a
# throwaway player must not get. Touches no real player's save.
# Who it plays as (SGODOT-488, 奕星 11-13): P0_SMOKE_TOKEN / P0_SMOKE_PLAYER — the fixed smoke account deploy-hk.sh smoke
# makes afresh through the admin port (/admin/smoke), a token for an hour — so the run is a token's, as a client's after
# the forced update, and no save is made per run; a made-up token is refused too. Without them (an image before
# /admin/smoke) a throwaway id alone, as before. The token is only ever in this process's environment.
set -euo pipefail
BASE="${P0_BASE:?P0_BASE=https://host/preview/p0 或 http://host:3150}"
KEY="${P0_KEY:?P0_KEY=演示口令}"
TOKEN="${P0_SMOKE_TOKEN:-}"
if [ -n "$TOKEN" ]; then
  PLAYER="${P0_SMOKE_PLAYER:?P0_SMOKE_PLAYER with P0_SMOKE_TOKEN}"; AUTH="authorization: Bearer $TOKEN"
else
  PLAYER="smoke-$(date +%s)"; AUTH="x-p0-smoke: id-only"   # a harmless header, so every keyed request is written the same
  echo "no P0_SMOKE_TOKEN: a throwaway id alone (an image before /admin/smoke)"
fi
FEATURES="save_v7"   # the wipe's required feature (397); not choose_home / guide_v3, see above
c() { curl --noproxy '*' -s -o /tmp/p0_smoke_body -w '%{http_code}' "$@"; }
fail() { echo "FAIL: $1"; cat /tmp/p0_smoke_body; echo; exit 1; }
[ "$(c "$BASE/v1/healthz")" = 200 ] || fail healthz
REQUIRED=$(grep -o '"require_features":\[[^]]*\]' /tmp/p0_smoke_body || true)
# SGODOT-488: P0_LEGACY_ID takes any player by its id alone — never on the live server. A devserver run that means to
# have it on says so with P0_SMOKE_ALLOW_LEGACY=1.
if grep -q '"legacy_id":true' /tmp/p0_smoke_body && [ "${P0_SMOKE_ALLOW_LEGACY:-0}" != 1 ]; then fail "P0_LEGACY_ID is on (healthz legacy_id true)"; fi
if grep -q '"guest_ok":true' /tmp/p0_smoke_body && [ "${P0_SMOKE_ALLOW_LEGACY:-0}" != 1 ]; then fail "P0_GUEST_OK is on (healthz guest_ok true)"; fi
[ "$(c -H "x-p0-player: $PLAYER" "$BASE/v1/p0/state")" = 401 ] || fail "no key should be 401"
[ "$(c -H "x-p0-player: $PLAYER" -H "x-p0-key: $KEY" -H "x-p0-features: $FEATURES" -H "$AUTH" "$BASE/v1/p0/state")" = 200 ] || fail "state with key"
if [ -n "$TOKEN" ]; then   # a token the server never gave is refused, the id beside it notwithstanding (identify)
  [ "$(c -H "x-p0-player: $PLAYER" -H "x-p0-key: $KEY" -H "x-p0-features: $FEATURES" -H "authorization: Bearer $(printf '0%.0s' $(seq 64))" "$BASE/v1/p0/state")" = 401 ] || fail "a made-up token should be 401"
fi
if [ -n "$REQUIRED" ] && [ "$REQUIRED" != '"require_features":[]' ]; then   # the second guard is on: a pre-wipe build is turned away
  [ "$(c -H "x-p0-player: $PLAYER" -H "x-p0-key: $KEY" "$BASE/v1/p0/state")" = 426 ] && grep -q '"update_required"' /tmp/p0_smoke_body || fail "no features should be 426 ($REQUIRED)"
  [ "$(c -H "x-p0-player: $PLAYER" -H "x-p0-key: $KEY" -H "x-p0-features: choose_home,guide_v3,locals" "$BASE/v1/p0/state")" = 426 ] || fail "features without save_v7 should be 426"
fi
code=$(c -X POST -H "x-p0-player: $PLAYER" -H "x-p0-key: $KEY" -H "x-p0-features: $FEATURES" -H "$AUTH" -H 'content-type: application/json' -d '{"type":"sow","plot":0,"seed":"seed_radish","space":"home"}' "$BASE/v1/p0/commands")
[ "$code" = 200 ] && grep -q '"ok":true' /tmp/p0_smoke_body || fail "sow round trip"
[ "$(c -X POST -H "x-p0-player: $PLAYER" -H "x-p0-key: $KEY" -H "x-p0-features: $FEATURES" -H "$AUTH" -H 'content-type: application/json' -d '{"minutes":60}' "$BASE/v1/p0/dev/skip")" = 404 ] || fail "dev route must be off"
[ "$(c -H "x-p0-player: $PLAYER" "$BASE/v1/%70%30/state")" = 401 ] || fail "an encoded path without the key should be 401"
code=$(c -X POST -H "x-p0-player: $PLAYER" -H "x-p0-key: $KEY" -H "x-p0-features: $FEATURES" -H "$AUTH" -H 'content-type: application/json' -d '{"events":[{"kind":"screen","name":"smoke"}]}' "$BASE/v1/p0/telemetry")
[ "$code" = 200 ] && grep -q '"ok":true' /tmp/p0_smoke_body || fail "telemetry (needs the observation log, PR #23)"
echo "P0 smoke OK ($BASE, player $PLAYER$([ -n "$TOKEN" ] && echo ' by its token'), ${REQUIRED:-require_features absent})"
