#!/usr/bin/env bash
# P0 demo server → Hong Kong ECS, one step at a time (SGODOT-232 D1; plan: docs/qa/p0-hk-deploy-plan-2026-10-08.md).
# Run from the repo root on the Mac. Every step is its own command, prints what it does and stops on the first error;
# nothing runs unless you name it. Results go to output/p0-deploy/<date>/.
#
#   server/deploy/p0/deploy-hk.sh preflight            # read-only: containers, memory, Journey / farm healthz
#   server/deploy/p0/deploy-hk.sh build <git ref>      # on the LAN devserver: git archive → docker build p0-server:<sha>
#   server/deploy/p0/deploy-hk.sh transfer <sha>       # devserver → Mac → HK: docker save | gzip | docker load
#   server/deploy/p0/deploy-hk.sh backup-caddy         # copy the live Caddyfile to /opt/farm/p0/backups/
#   server/deploy/p0/deploy-hk.sh up <sha>             # files + .env.p0 to /opt/farm/p0, compose up, wait healthy
#   server/deploy/p0/deploy-hk.sh verify-internal      # from inside farm-caddy-1: http://p0-demo:3110/v1/healthz
#   server/deploy/p0/deploy-hk.sh caddy                # insert /preview/p0, validate a copy, write in place, reload
#   server/deploy/p0/deploy-hk.sh smoke                # public smoke + Journey / farm healthz compared with preflight
#   server/deploy/p0/deploy-hk.sh crontab              # farm's crontab: the nightly p0 data backup line only
#   server/deploy/p0/deploy-hk.sh stats                # docker stats (P0 headroom under 256 MB, Journey unchanged)
#   server/deploy/p0/deploy-hk.sh rollback             # compose down (data kept), Caddyfile back in place, reload
#   server/deploy/p0/deploy-hk.sh clean-devserver <sha> # remove the build directory and image on the devserver
# Observer tools for the playtest (SGODOT-150, q(53)), through docker exec to 127.0.0.1:3111 inside the container:
#   server/deploy/p0/deploy-hk.sh players                       # player ids by join time (the name ↔ id table)
#   server/deploy/p0/deploy-hk.sh energy <player id> <value>     # F1: set one player's Energy (day-4 revisit, ~80)
#   server/deploy/p0/deploy-hk.sh report <player id> [YYYY-MM-DD] # F2: that player's session report + the day's lines
#
# The access key: P0_KEY=… in the environment, else output/p0-deploy/key; the admin key likewise P0_ADMIN_KEY or
# output/p0-deploy/admin-key (both created once with openssl, never committed).
set -euo pipefail

HK="${P0_HK:-farm@47.76.226.41}"
DEV="${P0_DEV_HOST:-zhangshaojie@192.168.124.53}"
SITE="${P0_SITE:-https://farm.sensenjoy.cn}"
REMOTE=/opt/farm/p0
CADDY=farm-caddy-1
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
out="$repo/output/p0-deploy/$(date +%Y-%m-%d)"
mkdir -p "$out"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=15)
hk() { ssh "${SSH_OPTS[@]}" "$HK" "$@"; }
dev() { ssh "${SSH_OPTS[@]}" "$DEV" "$@"; }
say() { printf '\n== %s\n' "$*"; }
curl_() { command curl --noproxy '*' -s --max-time 20 "$@"; }   # direct: a local HTTPS_PROXY breaks TLS to the site

secret() {   # $1 = env value, $2 = file under output/p0-deploy, $3 = bytes
  if [ -n "$1" ]; then printf '%s' "$1"; return; fi
  local f="$repo/output/p0-deploy/$2"
  [ -s "$f" ] || { umask 077; openssl rand -hex "$3" > "$f"; }
  tr -d '\n' < "$f"
}
key() { secret "${P0_KEY:-}" key 8; }
admin_key() { secret "${P0_ADMIN_KEY:-}" admin-key 16; }
# One admin call inside the container: loopback only, never reachable through Caddy. The image's own node sends it
# and reads the key from its environment in-process, so the key is in no process's arguments, host or container
# (a wget there would show it to the host's ps). The script arrives on stdin; the body is built from checked values.
admin() {   # $1 = path, $2 = JSON body (POST) or empty (GET)
  local method=GET body=null
  if [ -n "${2:-}" ]; then method=POST; body="$2"; fi
  hk 'docker exec -i p0-p0-1 node --input-type=module -' <<JS
const r = await fetch('http://127.0.0.1:3111$1', { method: '$method',
  headers: { 'x-p0-admin': process.env.P0_ADMIN_KEY ?? '', 'content-type': 'application/json' },
  ...('$method' === 'POST' ? { body: JSON.stringify($body) } : {}) });
console.log(await r.text());
process.exit(r.ok ? 0 : 1);
JS
}

health() {   # $1 = label: Journey and farm healthz, saved for the before / after comparison
  for u in "$SITE/preview/journey/v1/healthz" "$SITE/v1/healthz"; do
    code=$(curl_ -o "$out/hz.tmp" -w '%{http_code}' "$u" || echo 000)
    printf '%s %s %s %s\n' "$1" "$code" "$u" "$(head -c 200 "$out/hz.tmp")" | tee -a "$out/health.txt"
    [ "$code" = 200 ] || { echo "FAIL: $u is $code"; return 1; }
  done
}

step="${1:-}"; shift || true
case "$step" in
  preflight)
    say "containers / memory / disk on $HK (read-only)"
    hk 'docker ps --format "table {{.Names}}\t{{.Status}}" && free -m && df -h / | tail -1' | tee "$out/preflight.txt"
    say "Journey and farm healthz before"
    health before
    ;;
  build)
    ref="${1:?build <git ref>, e.g. origin/farm-dev}"
    sha=$(git -C "$repo" rev-parse --short "$ref")
    dir="p0-build-$sha"
    say "build context of $ref ($sha) → $DEV:~/$dir"
    git -C "$repo" archive --format=tar "$ref" package.json pnpm-lock.yaml pnpm-workspace.yaml packages/blueprint-core server \
      assets/p0/p0_content.json | gzip | dev "rm -rf ~/$dir && mkdir -p ~/$dir && tar -C ~/$dir -xzf -"
    say "docker build p0-server:$sha on the devserver"
    dev "cd ~/$dir && docker build -f server/deploy/p0/Dockerfile -t p0-server:$sha ." 2>&1 | tail -5
    dev "docker images p0-server:$sha --format '{{.Repository}}:{{.Tag}} {{.Size}} {{.ID}}'" | tee "$out/image.txt"
    echo "$sha" > "$out/sha.txt"
    ;;
  transfer)
    sha="${1:?transfer <sha>}"
    say "docker save p0-server:$sha | gzip  →  $HK docker load (streams through this Mac)"
    dev "docker save p0-server:$sha | gzip -1" | hk 'gunzip | docker load'
    hk "docker images p0-server:$sha --format '{{.Repository}}:{{.Tag}} {{.Size}} {{.ID}}'" | tee -a "$out/image.txt"
    ;;
  backup-caddy)
    ts=$(date +%Y%m%d-%H%M%S)
    say "back up the live Caddyfile → $REMOTE/backups/Caddyfile.before-p0-$ts"
    hk "mkdir -p $REMOTE/backups && cp /opt/farm/Caddyfile $REMOTE/backups/Caddyfile.before-p0-$ts && ls -l $REMOTE/backups/ | tail -3"
    echo "$ts" > "$out/caddy-backup.txt"
    ;;
  up)
    sha="${1:?up <sha>}"
    say "files → $HK:$REMOTE"
    hk "mkdir -p $REMOTE/backups"
    scp "${SSH_OPTS[@]}" -q "$here/docker-compose.p0.yml" "$here/backup-p0.sh" "$here/p0-report.sh" "$HK:$REMOTE/"
    # .env.p0: the container's settings (the demo key, the admin key), written from stdin so neither key is on a
    # command line; .env: what compose itself interpolates (the image), so `docker compose -p p0 ps / logs` work later
    printf 'P0_ACCESS_KEYS=%s\nP0_ADMIN_KEY=%s\n' "$(key)" "$(admin_key)" | hk "umask 077 && cat > $REMOTE/.env.p0"
    hk "printf 'P0_IMAGE=p0-server:%s\n' '$sha' > $REMOTE/.env && chmod +x $REMOTE/backup-p0.sh $REMOTE/p0-report.sh"
    say "compose up (project p0)"
    hk "cd $REMOTE && docker compose -p p0 -f docker-compose.p0.yml up -d"
    say "wait for healthy"
    for i in $(seq 1 40); do
      st=$(hk "docker inspect --format '{{.State.Health.Status}}' p0-p0-1" 2>/dev/null || echo starting)
      [ "$st" = healthy ] && break
      [ "$st" = unhealthy ] && { hk "cd $REMOTE && docker compose -p p0 -f docker-compose.p0.yml logs --tail 40"; exit 1; }
      sleep 3
    done
    [ "$st" = healthy ] || { echo "still $st after 2 minutes"; exit 1; }
    echo "p0-p0-1 healthy"
    ;;
  verify-internal)
    say "from inside $CADDY (farm_default): http://p0-demo:3110/v1/healthz"
    hk "docker exec $CADDY wget -qO- http://p0-demo:3110/v1/healthz" | tee "$out/internal.txt"
    echo
    ;;
  caddy)
    say "fetch the live Caddyfile"
    hk "cat /opt/farm/Caddyfile" > "$out/Caddyfile.live"
    if grep -q 'handle_path /preview/p0/\*' "$out/Caddyfile.live"; then echo "already has /preview/p0 — nothing to do"; exit 0; fi
    python3 - "$out/Caddyfile.live" "$out/Caddyfile.new" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
lines = open(src).read().split('\n')
start = next(i for i, l in enumerate(lines) if l.strip().startswith('handle_path /preview/journey/*'))
depth, end = 0, None
for i in range(start, len(lines)):
    depth += lines[i].count('{') - lines[i].count('}')
    if depth == 0: end = i; break
indent = lines[start][:len(lines[start]) - len(lines[start].lstrip())]
block = [f'{indent}handle_path /preview/p0/* {{', f'{indent}    reverse_proxy p0-demo:3110', f'{indent}}}']
open(dst, 'w').write('\n'.join(lines[:end + 1] + block + lines[end + 1:]))
PY
    say "the change"
    diff -u "$out/Caddyfile.live" "$out/Caddyfile.new" || true
    say "validate a copy inside $CADDY"
    scp "${SSH_OPTS[@]}" -q "$out/Caddyfile.new" "$HK:$REMOTE/Caddyfile.candidate"
    hk "docker cp $REMOTE/Caddyfile.candidate $CADDY:/tmp/Caddyfile.p0 && docker exec $CADDY caddy validate --config /tmp/Caddyfile.p0 --adapter caddyfile"
    say "write in place (same inode: the file is bind-mounted alone) and reload"
    hk "cat $REMOTE/Caddyfile.candidate > /opt/farm/Caddyfile && docker exec $CADDY caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile && echo reloaded"
    ;;
  smoke)
    say "public smoke at $SITE/preview/p0"
    P0_BASE="$SITE/preview/p0" P0_KEY="$(key)" "$here/smoke.sh" | tee "$out/smoke.txt"
    say "Journey and farm healthz after"
    health after
    ;;
  crontab)
    line="40 3 * * * $REMOTE/backup-p0.sh >> $REMOTE/backups/backup.log 2>&1"
    say "farm's crontab: the nightly p0 backup line only"
    hk "(crontab -l 2>/dev/null | grep -v 'backup-p0.sh'; echo '$line') | crontab - && crontab -l"
    ;;
  stats)
    hk 'docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"' | tee "$out/stats.txt"
    ;;
  rollback)
    ts=$(cat "$out/caddy-backup.txt" 2>/dev/null || hk "ls $REMOTE/backups | grep Caddyfile.before-p0 | sort | tail -1 | sed 's/Caddyfile.before-p0-//'")
    say "compose down (the p0data volume is kept)"
    hk "cd $REMOTE && docker compose -p p0 -f docker-compose.p0.yml down" || true
    say "Caddyfile back from Caddyfile.before-p0-$ts, in place, validate, reload"
    hk "docker cp $REMOTE/backups/Caddyfile.before-p0-$ts $CADDY:/tmp/Caddyfile.back && docker exec $CADDY caddy validate --config /tmp/Caddyfile.back --adapter caddyfile && cat $REMOTE/backups/Caddyfile.before-p0-$ts > /opt/farm/Caddyfile && docker exec $CADDY caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile && echo reloaded"
    say "Journey and farm healthz after rollback"
    health rollback
    ;;
  players)
    say "players by join time (admin, loopback inside p0-p0-1)"
    admin /admin/players | tee "$out/players.json"; echo
    ;;
  energy)
    player="${1:?energy <player id> <value>}"; value="${2:?energy <player id> <value>}"
    [[ "$player" =~ ^[A-Za-z0-9_-]{8,64}$ ]] || { echo "bad player id: $player"; exit 2; }   # the server's PLAYER_RE
    [[ "$value" =~ ^[0-9]{1,4}$ ]] || { echo "value must be a whole number: $value"; exit 2; }
    say "F1: Energy of $player → $value (logged in the container log as an admin line)"
    admin /admin/energy "{\"player\":\"$player\",\"value\":$value}" | tee -a "$out/admin.txt"; echo
    ;;
  report)
    player="${1:?report <player id> [YYYY-MM-DD]}"; day="${2:-$(date -u +%Y-%m-%d)}"
    [[ "$player" =~ ^[A-Za-z0-9_-]{8,64}$ && "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "bad player id or day"; exit 2; }
    say "F2: $player on $day (UTC) — session report, then the day's command and refusal counts"
    hk "$REMOTE/p0-report.sh '$player' '$day'" | tee "$out/report-$player-$day.txt"
    ;;
  clean-devserver)
    sha="${1:?clean-devserver <sha>}"
    dev "docker rmi p0-server:$sha >/dev/null 2>&1 || true; rm -rf ~/p0-build-$sha; docker images p0-server --format '{{.Tag}}'"
    ;;
  *)
    sed -n '2,20p' "$0"; exit 2 ;;
esac
