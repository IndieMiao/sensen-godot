#!/usr/bin/env bash
# F2 for the playtest observers (SGODOT-150, q(53)): one player's session report (tools/p0_session_report.ts) and the
# day's command / refusal counts from the observation log. Run on the Hong Kong host:
#   /opt/farm/p0/p0-report.sh <player id> [YYYY-MM-DD]
# The log is one file per UTC day (p0-events-<day>.jsonl); a Shanghai evening session falls in one UTC day.
set -euo pipefail
player="${1:?player id}"; day="${2:-$(date -u +%Y-%m-%d)}"
[[ "$player" =~ ^[A-Za-z0-9_-]{8,64}$ ]] || { echo "bad player id: $player"; exit 2; }
[[ "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "bad day: $day"; exit 2; }
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
docker exec p0-p0-1 cat "/data/events/p0-events-$day.jsonl" | grep -F "\"player\":\"$player\"" > "$tmp" || true
echo "player $player · $day (UTC) · $(wc -l < "$tmp") log lines"
[ -s "$tmp" ] || exit 0
docker cp "$tmp" p0-p0-1:/tmp/report.jsonl
docker exec p0-p0-1 ./node_modules/.bin/tsx tools/p0_session_report.ts /tmp/report.jsonl
echo; echo "commands:"; grep -o '"type":"[a-z_]*"' "$tmp" | sort | uniq -c | sort -rn | head -15 || true
echo "refusals:"; grep -o '"code":"[a-z_]*"' "$tmp" | sort | uniq -c | sort -rn | head -10 || true
