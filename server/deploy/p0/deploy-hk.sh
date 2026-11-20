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
#   server/deploy/p0/deploy-hk.sh players [--ids]               # player counts; --ids: ids by join time, terminal only
#   server/deploy/p0/deploy-hk.sh energy <player id> <value>     # F1: set one player's Energy (day-4 revisit, ~80)
#   server/deploy/p0/deploy-hk.sh report <player id> [YYYY-MM-DD] # F2: that player's session report + the day's lines
# Accounts (SGODOT-488, contract-accounts §4.1; on the live server only 83 runs these, and asks 奕星 first):
#   server/deploy/p0/deploy-hk.sh token <player id>            # an admin token for a test device (30 days, kept through
#                                                                #   other devices' sign-ins): printed once, terminal only
#   server/deploy/p0/deploy-hk.sh claim-reset <player id>      # clear its claim and revoke every token, admin ones too
#   server/deploy/p0/deploy-hk.sh delete <player|support-code> [--confirm] # preview by default; live execution by 83 after PM approval
#   server/deploy/p0/deploy-hk.sh delete-incomplete            # read-only unfinished deletion list, terminal only
#   server/deploy/p0/deploy-hk.sh reports-retention [--confirm] # one-year active report/queue cleanup, preview by default
#   server/deploy/p0/deploy-hk.sh code <player id|new> <note>  # a test code (contract v1.4 §4) for that account or a new one;
#                                                                #   note an id such as review-play / cn-tester-03, never a name
#   server/deploy/p0/deploy-hk.sh code-batch <count> <prefix>   # that many new accounts' codes, notes <prefix>-01 …
#   server/deploy/p0/deploy-hk.sh code-revoke <player id>      # withdraw its code and the tokens it gave
#                                                                # codes are printed once, terminal only, never saved
# SYS-MAINT / SYS-UPDATE (gate.ts; kept in the data volume, so a restart keeps them; healthz and admin stay open):
#   server/deploy/p0/deploy-hk.sh maint-on [back at]             # every /v1/p0 request answers 503 maintenance; back at =
#                                                                #   any time, e.g. 2026-10-09T23:30+08:00 (sent as UTC ISO)
#   server/deploy/p0/deploy-hk.sh maint-off                      # back to normal (then run smoke)
#   server/deploy/p0/deploy-hk.sh min-version <versionCode> [url] # older clients (x-p0-version) get 426 update_required;
#                                                                #   a minimum needs a download url (set once, then kept)
#   server/deploy/p0/deploy-hk.sh gate                           # what is in force
#
# The access key: P0_KEY=… in the environment, else output/p0-deploy/key; the admin key likewise P0_ADMIN_KEY or
# output/p0-deploy/admin-key (both created once with openssl, never committed).
#
# --target us (first word, before the step): the US West P0 the 10-28 migration moved to (43.110.146.219, run by the
# migration side; contract in pm/migration/p0-migration-decision-2026-10-27.md, E answer 8). Without it every step is
# the Hong Kong one (frozen, below). On us:
#   login       ssh -F $P0_US_SSH_CONFIG $P0_US_HOST (default the migration side's ssh_config, host tgt-us-p0)
#   compose     $REMOTE/compose.production.json; the service and the container are both p0-p0-1
#   settings    in that compose file (mode 600), kept by the migration side: `up` changes only
#               services["p0-p0-1"].image in it (a dated copy first; the rest must parse the same) and writes no
#               .env / .env.p0 and no key; then it reminds you to send the new tag / config to the migration side,
#               whose Caddy answers the X-P0-Release / X-P0-Image-Config headers
#   transfer    an archive on this Mac → sha256 → $P0_US_STAGING (default …/p0/staging, made 0700, archive 0600;
#               never under the production data) → sha256 again → docker load; the archive's config digest must
#               equal the image ID US docker reports (both IDs go to image.txt), and `up` takes only a tag a
#               transfer checked this way
#   verify-internal  the host's loopback Caddy (127.0.0.1:18090), with the X-P0-* response headers
#   report      p0-report.sh streamed over ssh (nothing copied)
#   preflight / build / smoke / stats / players / energy / maint-on / maint-off / min-version / gate / clean-devserver
#               as on Hong Kong
#   backup-caddy / caddy / crontab / rollback   not here: the US Caddy, backups and route are the migration side's
#   --expect-config sha256:<64 hex> (before the step, us only): transfer stops before sending and up before touching
#               anything unless the archive's config / the checked transfer's ID is exactly this one. The script checks
#               the archive against US docker, not against what runs there now: a rebuilt p0-server:<sha> on the
#               devserver can have another digest. For e64d4b33 = live that is sha256:5603ce0b…905ef59 (周瑜 on #547).
#   up recreates p0-p0-1 (the compose's image string changes even for the same image): a few seconds offline, the
#               clients reconnect. At an agreed time, with maint-on first when needed.
#   back to the last version: `--target us up <its sha>` (e64d4b33 before the first new one; the transfer of that sha
#               must be on record and the image still on the US host). Without this script the migration side puts the
#               dated compose copy back and runs `docker compose -f … up -d --no-deps p0-p0-1`.
#
# --target preview: p0-preview on the same US West host, the weekly preview build for the user only (奕星 11-02,
# user-approved: pm/preview/auth-preview.md). Everything of its own: compose $REMOTE/compose.preview.json (mode 600,
# its env and keys kept by the migration side like production's), service and container p0-preview-1, data
# $REMOTE/preview/data, its own gate (maintenance, minimum version), 256 MB / 0.5 CPU, public at
# $SITE/preview/p0-next/v1 (the migration side's Caddy). Steps as on us, with these differences:
#   up          only services["p0-preview-1"].image in compose.preview.json; /data must be the preview directory.
#               It takes a tag a transfer checked on us or preview (one docker on that host)
#   fetch-key   the preview access key out of compose.preview.json → output/p0-deploy/preview-key (0600, never
#               printed), for smoke and the preview APK; smoke never makes one up
#   smoke       $SITE/preview/p0-next with that key, and the production /preview/p0 healthz before and after
#   verify-internal  the loopback Caddy at /preview/p0-next/v1/healthz
#   min-version its url must be under https://oss2.sensenjoy.cn/p0/demo/preview/ (the preview APK, not the release)
#   --expect-config  as on us
# Production's compose, container and data are never named by a preview step.
#
# Hong Kong is frozen (奕星, 10-29): since the 10-28 move it is the fallback — P0 stopped, data frozen — until 11-01
# 16:00 +08:00, and the machine goes on 11-05. Every step that writes there (transfer backup-caddy up caddy crontab
# rollback energy maint-on maint-off min-version) refuses unless --confirm-hk-frozen-override comes first as well,
# e.g. `--target hk --confirm-hk-frozen-override up <sha>`, which only a fallback the PM has called justifies. The
# read-only and observer steps run as before. --target and that flag go before the step; after it they are refused.
set -euo pipefail

TARGET=hk
HK_OVERRIDE=
EXPECT_CONFIG=
while :; do
  case "${1:-}" in
    --target)
      TARGET="${2:?--target hk|us}"; shift 2
      case "$TARGET" in hk|us|preview) ;; *) echo "unknown target: $TARGET (hk, us or preview)"; exit 2 ;; esac ;;
    --confirm-hk-frozen-override) HK_OVERRIDE=1; shift ;;
    --expect-config)
      EXPECT_CONFIG="${2:?--expect-config sha256:<64 hex>}"; shift 2
      [[ "$EXPECT_CONFIG" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "--expect-config takes sha256:<64 hex>: $EXPECT_CONFIG"; exit 2; } ;;
    *) break ;;
  esac
done
# `up --target us abc` would otherwise be Hong Kong's up of a sha "--target" (周瑜 on #547)
for a in "$@"; do
  case "$a" in
    --target|--target=*|--confirm-hk-frozen-override|--expect-config|--expect-config=*)
      echo "$a goes before the step: deploy-hk.sh [--target hk|us] [--confirm-hk-frozen-override] [--expect-config sha256:…] <step> …"; exit 2 ;;
  esac
done
if [ -n "$HK_OVERRIDE" ] && [ "$TARGET" != hk ]; then echo "--confirm-hk-frozen-override is for Hong Kong only"; exit 2; fi
if [ -n "$EXPECT_CONFIG" ] && [ "$TARGET" = hk ]; then echo "--expect-config is for --target us or preview only"; exit 2; fi

HK="${P0_HK:-farm@47.76.226.41}"
DEV="${P0_DEV_HOST:-zhangshaojie@192.168.124.53}"
SITE="${P0_SITE:-https://farm.sensenjoy.cn}"
REMOTE=/opt/farm/p0
CADDY=farm-caddy-1
US_SERVICE=p0-p0-1   # the P0 container admin() and the observer steps reach (Hong Kong's has the same name)
PREFIX=/preview/p0   # the public path
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
out="$repo/output/p0-deploy/$(date +%Y-%m-%d)"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=15)
HOST_OPTS=("${SSH_OPTS[@]}")   # the target host's; the devserver keeps SSH_OPTS
if [ "$TARGET" != hk ]; then
  HK="${P0_US_HOST:-tgt-us-p0}"
  REMOTE=/srv/migration-data/services/p0
  US_COMPOSE=compose.production.json
  US_SERVICE=p0-p0-1   # the service key and the container name (迁移方, D2 point 4)
  US_DATA=/srv/migration-data/services/p0/production/20261029/data
  US_STAGING="${P0_US_STAGING:-/srv/migration-data/services/p0/staging}"
  case "$US_STAGING" in
    /*) ;; *) echo "P0_US_STAGING must be an absolute path: $US_STAGING"; exit 2 ;;
  esac
  case "$US_STAGING/" in
    */../*|*/./*|"$US_DATA"/*|/srv/migration-data/services/p0/production/*|/) echo "P0_US_STAGING may not be $US_STAGING"; exit 2 ;;
  esac
  HOST_OPTS=(-F "${P0_US_SSH_CONFIG:-$HOME/.local/share/aliyun-migrations/liusen-20261026/private/ssh_config}" "${SSH_OPTS[@]}")
  out="$out/us"
fi
if [ "$TARGET" = preview ]; then
  US_COMPOSE=compose.preview.json
  US_SERVICE=p0-preview-1
  US_DATA=/srv/migration-data/services/p0/preview/data
  PREFIX=/preview/p0-next
  out="${out%/us}/preview"
fi
mkdir -p "$out"
hk() { ssh "${HOST_OPTS[@]}" "$HK" "$@"; }
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
  hk "docker exec -i $US_SERVICE node --input-type=module -" <<JS
const r = await fetch('http://127.0.0.1:3111$1', { method: '$method',
  headers: { 'x-p0-admin': process.env.P0_ADMIN_KEY ?? '', 'content-type': 'application/json' },
  ...('$method' === 'POST' ? { body: JSON.stringify($body) } : {}) });
console.log(await r.text());
process.exit(r.ok ? 0 : 1);
JS
}

health() {   # $1 = label: Journey and farm healthz, saved for the before / after comparison
  # The Journey server is retired (SGODOT-304) and so is the old farm since the 10-30 move to US West: both paths
  # answer 410 Gone, which is fine (200 too, should either come back). On us and preview the production P0 must answer 200.
  local urls=("$SITE/preview/journey/v1/healthz" "$SITE/v1/healthz")
  [ "$TARGET" = hk ] || urls+=("$SITE/preview/p0/v1/healthz")   # production P0 (a preview step never touches it)
  for u in "${urls[@]}"; do
    code=$(curl_ -o "$out/hz.tmp" -w '%{http_code}' "$u" || echo 000)
    printf '%s %s %s %s\n' "$1" "$code" "$u" "$(head -c 200 "$out/hz.tmp")" | tee -a "$out/health.txt"
    case "$u:$code" in
      */preview/journey/*:410|"$SITE"/v1/healthz:410|*:200) ;;
      *) echo "FAIL: $u is $code"; return 1 ;;
    esac
  done
}

step="${1:-}"; shift || true
if [ "$TARGET" = hk ] && [ -z "$HK_OVERRIDE" ]; then
  case "$step" in
    transfer|backup-caddy|up|caddy|crontab|rollback|energy|maint-on|maint-off|min-version|token|claim-reset|code|code-batch|code-revoke|delete|reports-retention)
      echo "$step writes to Hong Kong, the frozen fallback (P0 stopped, data frozen) until 2026-11-01 16:00 +08:00: refused."
      echo "The live P0 is US West: deploy-hk.sh --target us $step …"
      echo "Only for a fallback the PM has called: deploy-hk.sh --target hk --confirm-hk-frozen-override $step …"
      exit 2 ;;
  esac
fi
if [ "$TARGET" != hk ]; then
  case "$step" in
    backup-caddy|caddy|crontab|rollback)
      echo "$step is Hong Kong only: on $TARGET the Caddy, the backups and the route are the migration side's"; exit 2 ;;
    fetch-key)
      [ "$TARGET" = preview ] || { echo "fetch-key is for --target preview only: production's key stays with the migration side"; exit 2; }
      f="$repo/output/p0-deploy/preview-key"
      say "the preview access key from $HK:$REMOTE/$US_COMPOSE → $f (0600, not printed)"
      ( umask 077; hk "python3 - $REMOTE/$US_COMPOSE $US_SERVICE" > "$f.tmp" <<'PY'
import json, sys
env = json.load(open(sys.argv[1]))['services'][sys.argv[2]].get('environment', {})
if isinstance(env, list): env = dict(e.split('=', 1) for e in env if '=' in e)
k = (env.get('P0_ACCESS_KEYS') or '').split(',')[0].strip()
if not k: sys.exit('no P0_ACCESS_KEYS for ' + sys.argv[2])
print(k)
PY
      ) || { rm -f "$f.tmp"; exit 1; }
      # One line, one key: anything else the remote side printed (a login banner, a warning) must not become the key.
      [ "$(wc -l < "$f.tmp" | tr -d ' ')" = 1 ] && grep -Eq '^[A-Za-z0-9_-]{8,128}$' "$f.tmp" \
        || { rm -f "$f.tmp"; echo "FAIL: what came back is not one key line (not printed): nothing written" >&2; exit 1; }
      mv "$f.tmp" "$f"
      echo "written $(wc -c < "$f" | tr -d ' ') bytes"
      exit 0 ;;
    transfer)
      sha="${1:?transfer <sha>}"
      arc="$out/p0-server-$sha.tar.gz"
      say "docker save p0-server:$sha | gzip  →  $arc (this Mac)"
      dev "docker save p0-server:$sha | gzip -1" > "$arc"
      sum=$(shasum -a 256 "$arc" | cut -d' ' -f1)
      # The config digest inside the archive: what US docker must report as the image ID after the load, whatever
      # ID the devserver shows (an OCI index ID there is not the same string; 迁移方 E answer 8).
      cfg=$(python3 - "$arc" <<'PY'
import json, sys, tarfile
with tarfile.open(sys.argv[1], 'r:gz') as t:
    m = json.load(t.extractfile('manifest.json'))
print('sha256:' + m[0]['Config'].split('/')[-1].removesuffix('.json'))
PY
)
      { echo "source p0-server:$sha $(dev "docker images --no-trunc p0-server:$sha --format '{{.ID}}'")"
        echo "archive $(basename "$arc") sha256 $sum config $cfg"; } | tee -a "$out/image.txt"
      [ -z "$EXPECT_CONFIG" ] || [ "$cfg" = "$EXPECT_CONFIG" ] || { echo "FAIL: the archive's config is $cfg, not the expected $EXPECT_CONFIG: nothing sent" >&2; exit 1; }
      say "→ $HK:$US_STAGING (0700, the archive 0600), sha256 there, docker load"
      hk "install -d -m 700 $US_STAGING"
      scp "${HOST_OPTS[@]}" -q "$arc" "$HK:$US_STAGING/"
      hk "cd $US_STAGING && chmod 600 $(basename "$arc") && echo '$sum  $(basename "$arc")' | sha256sum -c - && gunzip -c $(basename "$arc") | docker load"
      id=$(hk "docker image inspect p0-server:$sha --format '{{.Id}}'")
      [ "$id" = "$cfg" ] || { echo "FAIL: US image ID $id is not the archive's config $cfg" >&2; exit 1; }
      echo "us p0-server:$sha $id" | tee -a "$out/image.txt"   # written only once checked: up looks for this line
      exit 0 ;;
    up)
      sha="${1:?up <sha>}"
      [[ "$sha" =~ ^[0-9a-f]{7,40}$ ]] || { echo "bad sha: $sha"; exit 2; }
      # Only a tag a transfer here checked: its line in some day's us/image.txt, and US docker still reports that ID.
      # us and preview share the host's docker, so a transfer checked for either serves both.
      want=$({ cat "$repo"/output/p0-deploy/*/us/image.txt "$repo"/output/p0-deploy/*/preview/image.txt 2>/dev/null || true; } | sed -n "s/^us p0-server:$sha //p" | tail -1)
      [ -n "$want" ] || { echo "no checked transfer of p0-server:$sha in output/p0-deploy/*/{us,preview}/image.txt: run transfer first" >&2; exit 1; }
      [ -z "$EXPECT_CONFIG" ] || [ "$want" = "$EXPECT_CONFIG" ] || { echo "FAIL: the checked transfer of p0-server:$sha is $want, not the expected $EXPECT_CONFIG: nothing changed" >&2; exit 1; }
      id=$(hk "docker image inspect p0-server:$sha --format '{{.Id}}'")
      [ "$id" = "$want" ] || { echo "FAIL: US p0-server:$sha is $id, the transfer checked $want" >&2; exit 1; }
      ts=$(date +%Y%m%dT%H%M%S)
      say "services[\"$US_SERVICE\"].image → p0-server:$sha in $HK:$REMOTE/$US_COMPOSE (a copy first)"
      # The settings in the file stay byte for byte: only the one JSON string that is services[$US_SERVICE].image is
      # replaced, it must be in the file once, and the result must parse to the same document but for that field.
      # No key is read, written or printed here.
      hk "cd $REMOTE && cp -p $US_COMPOSE $US_COMPOSE.before-$sha-$ts && python3 - $US_COMPOSE $US_SERVICE $sha" <<'PY' | tee -a "$out/up.txt"
import copy, json, os, sys
os.umask(0o077)   # the .tmp holds the keys in the environment: 0600 from the start, not 0644 until the chmod (周瑜 on #547)
path, name, sha = sys.argv[1], sys.argv[2], sys.argv[3]
raw = open(path).read()
doc = json.loads(raw)
svc = doc.get('services', {}).get(name)
if not isinstance(svc, dict): sys.exit(f'no services["{name}"] in {path}')
old = svc.get('image')
if not isinstance(old, str) or not old or '$' in old: sys.exit(f'services["{name}"].image is not a plain string: {old!r}')
lit = json.dumps(old)
if raw.count(lit) != 1: sys.exit(f'{lit} is in the file {raw.count(lit)} times, not once')
new_raw = raw.replace(lit, json.dumps('p0-server:' + sha))
want = copy.deepcopy(doc); want['services'][name]['image'] = 'p0-server:' + sha
if json.loads(new_raw) != want: sys.exit('the edit changed more than services["%s"].image' % name)
tmp = path + '.tmp'
if os.path.lexists(tmp): os.unlink(tmp)   # a stale one would keep its own mode
with open(tmp, 'w') as f: f.write(new_raw)
os.chmod(tmp, os.stat(path).st_mode & 0o777)
os.replace(tmp, path)
print(f'services["{name}"].image: {old} -> p0-server:{sha}')
PY
      say "compose up $US_SERVICE only"
      hk "docker compose -f $REMOTE/$US_COMPOSE up -d --no-deps $US_SERVICE"
      say "wait for healthy"
      for _ in $(seq 1 40); do
        st=$(hk "docker inspect --format '{{.State.Health.Status}}' $US_SERVICE" 2>/dev/null || echo starting)
        [ "$st" = healthy ] && break
        [ "$st" = unhealthy ] && { hk "docker compose -f $REMOTE/$US_COMPOSE logs --tail 40 $US_SERVICE"; exit 1; }
        sleep 3
      done
      [ "$st" = healthy ] || { echo "still $st after 2 minutes"; exit 1; }
      # Never a rehearsal copy under production's name: /data must be the production directory.
      src=$(hk "docker inspect --format '{{range .Mounts}}{{if eq .Destination \"/data\"}}{{.Source}}{{end}}{{end}}' $US_SERVICE")
      [ "$src" = "$US_DATA" ] || { echo "FAIL: /data is $src, not $US_DATA" >&2; exit 1; }
      echo "$US_SERVICE healthy, /data = $src"
      [ "$TARGET" = preview ] || echo "NEXT: send p0-server:$sha / $id to the migration side: their Caddy answers X-P0-Release / X-P0-Image-Config"
      exit 0 ;;
    verify-internal)
      say "on $HK: http://127.0.0.1:18090$PREFIX/v1/healthz (the loopback Caddy), with headers"
      hk "curl -sS -D - http://127.0.0.1:18090$PREFIX/v1/healthz" | tee "$out/internal.txt"
      echo
      exit 0 ;;
    report)
      player="${1:?report <player id> [YYYY-MM-DD]}"; day="${2:-$(date -u +%Y-%m-%d)}"
      [[ "$player" =~ ^[A-Za-z0-9_-]{8,64}$ && "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "bad player id or day"; exit 2; }
      say "F2: $player on $day (UTC) — session report, then the day's command and refusal counts"
      # Terminal only (data B, 11-12): one player's day stays on the US host, nothing of it is kept on this Mac
      hk "bash -s -- '$player' '$day' '$US_SERVICE'" < "$here/p0-report.sh"
      exit 0 ;;
  esac
fi
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
      assets/p0/p0_content.json assets/p0/content assets/p0/p0_outposts.json assets/p0/p0_ponds.json assets/ponds/catalog.json \
      assets/p0/city_clusters.json assets/p0/legal/versions.json assets/avatar/parts_manifest.json assets/avatar/demo_denylist.json assets/avatar/npc_only.json | gzip | dev "rm -rf ~/$dir && mkdir -p ~/$dir && tar -C ~/$dir -xzf -"
    # q(188) ① Near you: the pinned DB-IP City Lite month from the devserver's cache (DB-IP keeps only the last two
    # months online; 周瑜 on #447) into the context's dbip/, read by the Dockerfile through a bind mount (no layer).
    month=$(git -C "$repo" show "$ref:server/deploy/p0/Dockerfile" | sed -n 's/^ARG DBIP_MONTH=//p')
    say "DB-IP City Lite $month from the devserver cache ~/p0-cache/dbip"
    dev "test -s ~/p0-cache/dbip/dbip-city-lite-$month.csv.gz && mkdir -p ~/$dir/dbip && cp ~/p0-cache/dbip/dbip-city-lite-$month.csv.gz ~/$dir/dbip/" \
      || { echo "no ~/p0-cache/dbip/dbip-city-lite-$month.csv.gz on the devserver: put the pinned file there (sha256 in the Dockerfile)" >&2; exit 1; }
    say "docker build p0-server:$sha on the devserver"
    dev "cd ~/$dir && docker build -f server/deploy/p0/Dockerfile -t p0-server:$sha ." 2>&1 | tail -5
    dev "docker images p0-server:$sha --format '{{.Repository}}:{{.Tag}} {{.Size}} {{.ID}}'" | tee "$out/image.txt"
    # Every file the server reads at start is in the image and the content loads with its city clusters: a missing
    # member table ends the process at start (李元芳, 0.2.0), so it stops the build here, not on Hong Kong.
    say "start-up data in the image (tools/p0_image_check.ts)"
    dev "docker run --rm --entrypoint ./node_modules/.bin/tsx p0-server:$sha tools/p0_image_check.ts" | tee -a "$out/image.txt" \
      || { echo "image check failed: see $out/image.txt" >&2; exit 1; }
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
    scp "${HOST_OPTS[@]}" -q "$here/docker-compose.p0.yml" "$here/backup-p0.sh" "$here/p0-report.sh" "$HK:$REMOTE/"
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
# After the Journey block while it is there — its proxy (handle_path /preview/journey/*) or, once SGODOT-304 retires
# the Journey server, its 410 (handle /preview/journey* { respond … 410 }); without it, before the site's fallback
# block (the first bare `handle {`), at its indent. Neither: stop, never guess (蒙恬 on #450: the live fallback proxies
# farm-app-1:3000 inside that handle block, not the repo's reverse_proxy app:3000).
import re
def block_end(i):
    depth = 0
    for k in range(i, len(lines)):
        depth += lines[k].count('{') - lines[k].count('}')
        if depth == 0: return k + 1
    sys.exit('Caddyfile: unbalanced braces after line %d' % (i + 1))
journey = next((i for i, l in enumerate(lines) if re.match(r'^\s*handle(_path)?\s+/preview/journey', l)), None)
fallback = next((i for i, l in enumerate(lines) if re.match(r'^\s*handle\s*\{\s*$', l)), None)
if journey is not None:
    at, ref = block_end(journey), lines[journey]
elif fallback is not None:
    at, ref = fallback, lines[fallback]
else:
    sys.exit('Caddyfile: neither a /preview/journey block nor a bare `handle {` fallback block to place /preview/p0 by')
indent = ref[:len(ref) - len(ref.lstrip())]
block = [f'{indent}handle_path /preview/p0/* {{', f'{indent}    reverse_proxy p0-demo:3110', f'{indent}}}']
open(dst, 'w').write('\n'.join(lines[:at] + block + lines[at:]))
PY
    say "the change"
    diff -u "$out/Caddyfile.live" "$out/Caddyfile.new" || true
    say "validate a copy inside $CADDY"
    scp "${HOST_OPTS[@]}" -q "$out/Caddyfile.new" "$HK:$REMOTE/Caddyfile.candidate"
    hk "docker cp $REMOTE/Caddyfile.candidate $CADDY:/tmp/Caddyfile.p0 && docker exec $CADDY caddy validate --config /tmp/Caddyfile.p0 --adapter caddyfile"
    say "write in place (same inode: the file is bind-mounted alone) and reload"
    hk "cat $REMOTE/Caddyfile.candidate > /opt/farm/Caddyfile && docker exec $CADDY caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile && echo reloaded"
    ;;
  smoke)
    if [ "$TARGET" = preview ]; then
      # Its key only from fetch-key: secret() would make up a new one the preview server does not know.
      [ -n "${P0_KEY:-}" ] || [ -s "$repo/output/p0-deploy/preview-key" ] || { echo "no preview key: run --target preview fetch-key first" >&2; exit 1; }
      pkey="${P0_KEY:-$(tr -d '\n' < "$repo/output/p0-deploy/preview-key")}"
      say "production healthz before"
      health before
    else
      pkey="$(key)"
    fi
    # SGODOT-488 (奕星 11-13): the fixed smoke account made afresh with an hour's token (admin port, loopback in the
    # container) — the token stays in this shell and goes to smoke.sh in its environment, never to a file or the output.
    # An image before /admin/smoke answers 404: smoke.sh runs a throwaway id alone then, as before.
    sresp=$(admin /admin/smoke '{}' 2>/dev/null) || sresp=""
    stoken=$(printf '%s' "$sresp" | python3 -c 'import json, sys
try: print(json.load(sys.stdin)["token"])
except Exception: pass') || stoken=""
    splayer=$(printf '%s' "$sresp" | python3 -c 'import json, sys
try: print(json.load(sys.stdin)["player"])
except Exception: pass') || splayer=""
    say "public smoke at $SITE$PREFIX${stoken:+ as the smoke account $splayer (its token, an hour)}"
    P0_BASE="$SITE$PREFIX" P0_KEY="$pkey" P0_SMOKE_TOKEN="$stoken" P0_SMOKE_PLAYER="$splayer" "$here/smoke.sh" | tee "$out/smoke.txt"
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
    # Data B (the user, 11-11): no copy of the live players on this Mac. By default only counts, kept in players.txt;
    # with --ids the list by join time goes to the terminal only (matching an install to an id), never to a file.
    if [ "${1:-}" = "--ids" ]; then
      say "players by join time (admin, loopback inside $US_SERVICE) — terminal only, not saved"
      admin /admin/players; echo
    else
      say "player counts (admin, loopback inside $US_SERVICE); the ids stay on the server (--ids to see them, not saved)"
      admin /admin/players | python3 -c '
import json, sys, time
p = json.load(sys.stdin)["players"]; now = time.time() * 1000; day = 86400000
seen = lambda d: sum(1 for x in p if (x.get("last_at") or 0) >= now - d * day)
joined = sum(1 for x in p if (x.get("created_at") or 0) >= now - day)
print(f"players {len(p)}; joined in 24 h {joined}; seen in 24 h {seen(1)}, 7 days {seen(7)}")
t = sorted(a["expires_at"] for x in p for a in x.get("admin_tokens", []))   # SGODOT-488: given to test devices
end = time.strftime("%Y-%m-%d", time.gmtime(t[0] / 1000)) if t else ""
if t: print(f"admin tokens in force {len(t)}, the first ends {end} (--ids: whose)")' \
        | tee -a "$out/players.txt"
    fi
    ;;
  energy)
    player="${1:?energy <player id> <value>}"; value="${2:?energy <player id> <value>}"
    [[ "$player" =~ ^[A-Za-z0-9_-]{8,64}$ ]] || { echo "bad player id: $player"; exit 2; }   # the server's PLAYER_RE
    [[ "$value" =~ ^[0-9]{1,4}$ ]] || { echo "value must be a whole number: $value"; exit 2; }
    say "F1: Energy of $player → $value (logged in the container log as an admin line)"
    admin /admin/energy "{\"player\":\"$player\",\"value\":$value}"; echo
    echo "$(date -u +%FT%TZ) energy …${player: -6} → $value" >> "$out/admin.txt"   # data B: the full id is not kept here
    ;;
  token)
    # A test account on a test device (tech-plan §2.5): the token is that account's key, so it goes to this terminal
    # once and nowhere else — no file, no tee; admin.txt keeps the id's tail and the end only.
    player="${1:?token <player id>}"
    [[ "$player" =~ ^[A-Za-z0-9_-]{8,64}$ ]] || { echo "bad player id: $player"; exit 2; }   # the server's PLAYER_RE
    say "admin token for …${player: -6} (30 days): printed once below, terminal only — write it into the test device"
    resp=$(admin /admin/session "{\"player\":\"$player\"}") || { echo "$resp"; exit 1; }
    echo "$resp"
    ends=$(printf '%s' "$resp" | python3 -c 'import json, sys, time; print(time.strftime("%Y-%m-%dT%H:%MZ", time.gmtime(json.load(sys.stdin)["expires_at"] / 1000)))')
    echo "$(date -u +%FT%TZ) token …${player: -6} ends $ends" >> "$out/admin.txt"   # data B: no full id, never the token
    ;;
  code)
    # A test code (contract v1.4 §4): the code is that account's key, so it goes to this terminal once and nowhere else;
    # admin.txt keeps the note and the id's tail. Notes are ids (review-play, cn-tester-03), never a person's anything.
    who="${1:?code <player id|new> <note>}"; note="${2:?code <player id|new> <note>}"
    [[ "$note" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$ ]] || { echo "the note is an id such as review-play or cn-tester-03, no names: $note"; exit 2; }
    if [ "$who" = new ]; then body="{\"note\":\"$note\"}"
    else [[ "$who" =~ ^[A-Za-z0-9_-]{8,64}$ ]] || { echo "bad player id: $who"; exit 2; }; body="{\"player\":\"$who\",\"note\":\"$note\"}"; fi
    say "test code ($note) for $([ "$who" = new ] && echo 'a new account' || echo "…${who: -6}"): printed once below, terminal only"
    resp=$(admin /admin/code "$body") || { echo "$resp"; exit 1; }
    echo "$resp"
    tail=$(printf '%s' "$resp" | python3 -c 'import json, sys; print(json.load(sys.stdin)["player"][-6:])')
    echo "$(date -u +%FT%TZ) code $note …$tail" >> "$out/admin.txt"   # never the code
    ;;
  code-batch)
    count="${1:?code-batch <count> <note prefix>}"; prefix="${2:?code-batch <count> <note prefix>}"
    [[ "$count" =~ ^[0-9]{1,2}$ ]] && [ "$count" -ge 1 ] && [ "$count" -le 50 ] || { echo "count 1–50: $count"; exit 2; }
    [[ "$prefix" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,35}$ ]] || { echo "the prefix is an id such as cn-tester, no names: $prefix"; exit 2; }
    say "$count test codes for new accounts, notes $prefix-01 …: printed once below, terminal only"
    for i in $(seq 1 "$count"); do
      note="$prefix-$(printf '%02d' "$i")"
      resp=$(admin /admin/code "{\"note\":\"$note\"}") || { echo "$note: $resp"; exit 1; }
      printf '%s' "$resp" | python3 -c 'import json, sys; r = json.load(sys.stdin); print(r["note"], r["code"], "…" + r["player"][-6:], sep="\t")'
      echo "$(date -u +%FT%TZ) code $note …$(printf '%s' "$resp" | python3 -c 'import json, sys; print(json.load(sys.stdin)["player"][-6:])')" >> "$out/admin.txt"
    done
    ;;
  code-revoke)
    player="${1:?code-revoke <player id>}"
    [[ "$player" =~ ^[A-Za-z0-9_-]{8,64}$ ]] || { echo "bad player id: $player"; exit 2; }
    say "withdraw the test code of …${player: -6} and the tokens it gave (its other sign-ins stay)"
    admin /admin/code/revoke "{\"player\":\"$player\"}"; echo
    echo "$(date -u +%FT%TZ) code-revoke …${player: -6}" >> "$out/admin.txt"
    ;;
  reports-retention)
    [ "$#" -le 1 ] && { [ -z "${1:-}" ] || [ "$1" = --confirm ]; } || { echo 'use reports-retention [--confirm]'; exit 2; }
    say 'report retention preview (counts only; active JSONL and queue, no backups)'
    admin /admin/reports/retention; echo
    if [ "${1:-}" = --confirm ]; then admin /admin/reports/retention '{"apply":true}'; echo; fi
    ;;
  delete-incomplete)
    say "unfinished deletion records (admin, terminal only; not all cleanup failures are in this list)"
    admin /admin/delete/incomplete; echo
    ;;
  delete)
    selector="${1:?delete <player|support-code> [--confirm]}"
    confirmation="${2:-}"
    [ "$#" -le 2 ] && { [ -z "$confirmation" ] || [ "$confirmation" = --confirm ]; } || { echo 'use delete <player|support-code> [--confirm]'; exit 2; }
    if [[ "$selector" =~ ^[0-9A-HJKMNP-TV-Z]{5}-[0-9A-HJKMNP-TV-Z]{5}$ ]]; then
      field=support_code
    elif [[ "$selector" =~ ^[A-Za-z0-9_-]{8,64}$ ]]; then
      field=player
    else
      echo 'invalid player/support-code'; exit 2
    fi
    say "delete preview (terminal only; production apply is for 83 after PM approval)"
    admin "/admin/delete/preview?$field=$selector"; echo
    if [ "$confirmation" = --confirm ]; then
      admin /admin/delete "{\"$field\":\"$selector\"}"; echo
      echo "$(date -u +%FT%TZ) delete …${selector: -6}" >> "$out/admin.txt"
    else
      say 'preview only; --confirm applies deletion after approval'
    fi
    ;;
  claim-reset)
    player="${1:?claim-reset <player id>}"
    [[ "$player" =~ ^[A-Za-z0-9_-]{8,64}$ ]] || { echo "bad player id: $player"; exit 2; }
    say "claim reset for …${player: -6}: its claim cleared, every token revoked (admin ones too); its old id can claim again"
    admin /admin/claim/reset "{\"player\":\"$player\"}"; echo
    echo "$(date -u +%FT%TZ) claim-reset …${player: -6}" >> "$out/admin.txt"
    ;;
  maint-on)
    back="${1:-}"
    [[ -z "$back" || "$back" =~ ^[0-9T:.+Z-]{10,32}$ ]] || { echo "back at must be a time like 2026-10-09T23:30+08:00: $back"; exit 2; }
    say "maintenance ON${back:+ (back at $back)}: every /v1/p0 request answers 503 maintenance; healthz and admin stay open"
    if [ -n "$back" ]; then admin /admin/maintenance "{\"on\":true,\"back_at\":\"$back\"}"; else admin /admin/maintenance '{"on":true}'; fi | tee -a "$out/admin.txt"; echo
    ;;
  maint-off)
    say "maintenance OFF (run smoke next)"
    admin /admin/maintenance '{"on":false}' | tee -a "$out/admin.txt"; echo
    ;;
  min-version)
    v="${1:?min-version <versionCode> [download url]}"; url="${2:-}"
    [[ "$v" =~ ^[0-9]{1,10}$ ]] || { echo "versionCode must be a whole number: $v"; exit 2; }
    re_url='^https://[A-Za-z0-9./:_~%?=&-]+$'   # no quotes or spaces: it goes into the JSON body as is
    [[ -z "$url" || "$url" =~ $re_url ]] || { echo "url must be an https link: $url"; exit 2; }
    # The preview gate's Update must land on the preview APK, never the release one (奕星 11-02).
    [ "$TARGET" != preview ] || [ -z "$url" ] || [[ "$url" == https://oss2.sensenjoy.cn/p0/demo/preview/* ]] \
      || { echo "on preview the update url must be under https://oss2.sensenjoy.cn/p0/demo/preview/: $url"; exit 2; }
    say "minimum client versionCode $v${url:+ (update at $url)}; 0 = no minimum"
    if [ -n "$url" ]; then admin /admin/min-version "{\"version\":$v,\"url\":\"$url\"}"; else admin /admin/min-version "{\"version\":$v}"; fi | tee -a "$out/admin.txt"; echo
    ;;
  gate)
    admin /admin/gate; echo
    ;;
  report)
    player="${1:?report <player id> [YYYY-MM-DD]}"; day="${2:-$(date -u +%Y-%m-%d)}"
    [[ "$player" =~ ^[A-Za-z0-9_-]{8,64}$ && "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "bad player id or day"; exit 2; }
    say "F2: $player on $day (UTC) — session report, then the day's command and refusal counts"
    hk "$REMOTE/p0-report.sh '$player' '$day'"   # terminal only (data B, 11-12)
    ;;
  clean-devserver)
    sha="${1:?clean-devserver <sha>}"
    dev "docker rmi p0-server:$sha >/dev/null 2>&1 || true; rm -rf ~/p0-build-$sha; docker images p0-server --format '{{.Tag}}'"
    ;;
  *)
    sed -n '2,20p' "$0"
    [ "$TARGET" = hk ] || sed -n "/^# --target $TARGET/,/^#\$/p" "$0"
    exit 2 ;;
esac
