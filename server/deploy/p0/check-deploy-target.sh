#!/usr/bin/env bash
# Offline check of deploy-hk.sh's --target (SGODOT-232; the US West target after the 10-29 migration). Connects to
# nothing: ssh, scp, curl and date are stubs that log what they were asked and answer canned lines.
#   server/deploy/p0/check-deploy-target.sh [<git ref of the old script>]   # default origin/farm-dev
# 1. Hong Kong unchanged: every step run by the old script and by this one (with no --target and with --target hk)
#    gives the same stdout, exit code and stub log — the same remote commands, the same stdin, byte for byte.
# 2. us: the Hong Kong-only steps refuse; transfer checks the archive and records it; up edits a stub
#    compose.production.json for real (the remote python runs here, on a copy under a temp dir) — only
#    services["p0-p0-1"].image changes, a dated copy is kept, the mode stays — and refuses a tag no transfer
#    checked, a missing service, an image string that is there twice or is a variable, a staging path under
#    production; verify-internal / report / maint-off print the commands they would send.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
ref="${1:-origin/farm-dev}"
work=$(mktemp -d)
old="$here/.deploy-hk.check-old.sh"   # next to the new one, so both see the same $here
trap 'rm -rf "$work" "$old" "$repo/output/p0-deploy/2099-01-01"' EXIT
git -C "$repo" show "$ref:server/deploy/p0/deploy-hk.sh" > "$old"

mkdir -p "$work/bin"
cat > "$work/bin/ssh" <<'SH'
#!/usr/bin/env bash
f=$(mktemp); cat > "$f"; cp "$f" "$f.in"
# gzip puts the time in its header: hash what is inside, so two runs of the same archive compare equal
if gzip -t < "$f" 2>/dev/null; then in="gz:$(gunzip -c < "$f" | shasum -a 256 | cut -c1-16)"; else in=$(shasum -a 256 < "$f" | cut -c1-16); fi
rm -f "$f"
trap 'rm -f "$f.in"' EXIT
printf 'ssh %s | stdin %s\n' "$*" "$in" >> "$STUB_LOG"
case "$*" in
  *State.Health.Status*) echo healthy ;;
  *Mounts*) echo /srv/migration-data/services/p0/production/20261029/data ;;
  *"cat /opt/farm/Caddyfile"*) printf 'farm.sensenjoy.cn {\n    handle {\n        reverse_proxy farm-app-1:3000\n    }\n}\n' ;;
  *"docker save"*) cat "$STUB_DIR/image.tar.gz" ;;
  *"docker image inspect"*) echo "${STUB_IMAGE_ID:-sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef}" ;;
  *"python3 -"*compose.production.json*)   # run the edit for real on the stub copy of the remote directory
    cmd="${@: -1}"; bash -c "${cmd//\/srv\/migration-data\/services\/p0/$STUB_DIR/remote}" < "$f.in"; exit $? ;;
  *) echo "stub-out" ;;
esac
SH
cat > "$work/bin/scp" <<'SH'
#!/usr/bin/env bash
printf 'scp %s\n' "$*" >> "$STUB_LOG"
SH
cat > "$work/bin/curl" <<'SH'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "$STUB_LOG"
for a in "$@"; do case "$a" in %{http_code}) printf 200; exit 0 ;; esac; done
echo '{"ok":true}'
SH
cat > "$work/bin/date" <<'SH'
#!/usr/bin/env bash
case "$*" in *%Y-%m-%d*) echo 2099-01-01 ;; *%Y%m%d-%H%M%S*) echo 20990101-000000 ;; *%Y%m%dT%H%M%S*) echo 20990101T000000 ;; *%s*) echo 4070908800 ;; *) echo 2099-01-01T00:00:00Z ;; esac
SH
chmod +x "$work/bin/"*
printf '[{"Config":"blobs/sha256/0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","Layers":[]}]' > "$work/manifest.json"
tar -C "$work" -czf "$work/image.tar.gz" manifest.json   # made once: every docker save answers the same bytes
export PATH="$work/bin:$PATH" STUB_DIR="$work" P0_KEY=check-key P0_ADMIN_KEY=check-admin-key

run() {   # $1 = label, $2 = script, rest = arguments; prints the stub log, stdout and exit code
  export STUB_LOG="$work/$1.log"; : > "$STUB_LOG"
  [ -n "${KEEP:-}" ] || rm -rf "$repo/output/p0-deploy/2099-01-01"
  out=$(bash "$2" "${@:3}" 2>&1 < /dev/null); code=$?
  out=$(printf '%s' "${out//$2/SCRIPT}" | sed -E 's/\t[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:.]+( [+-][0-9]{4})?$//')   # diff -u's file times
  printf '%s\n--- stdout ---\n%s\n--- exit %s\n' "$(cat "$STUB_LOG")" "$out" "$code"
}

steps=(
  "preflight" "build $ref" "transfer abc1234" "backup-caddy" "up abc1234" "verify-internal" "caddy" "smoke"
  "crontab" "stats" "rollback" "players" "energy p0-check-player 80" "maint-on 2026-10-29T16:00+08:00" "maint-off"
  "min-version 2026100903 https://oss.example/p0/a.apk" "gate" "report p0-check-player 2026-10-28"
  "clean-devserver abc1234" "no-such-step" ""
)
fail=0
echo "== 1. Hong Kong: old ($ref) vs new, with no --target and with --target hk"
for s in "${steps[@]}"; do
  read -r -a a <<< "$s"
  o=$(run old "$old" ${a[@]+"${a[@]}"})
  n=$(run new "$here/deploy-hk.sh" ${a[@]+"${a[@]}"})
  t=$(run hk "$here/deploy-hk.sh" --target hk ${a[@]+"${a[@]}"})
  if [ "$o" = "$n" ] && [ "$o" = "$t" ]; then echo "same  ${s:-<no step>}"
  else echo "DIFF  ${s:-<no step>}"; diff <(echo "$o") <(echo "$n"); diff <(echo "$o") <(echo "$t"); fail=1; fi
done

echo; echo "== 2. us"
compose() {   # $1 = the image value as JSON; a stub of the migration side's compose.production.json, mode 600
  mkdir -p "$work/remote"; rm -f "$work/remote/"compose.production.json*
  cat > "$work/remote/compose.production.json" <<JSON
{
  "name": "liusen-p0-staging",
  "services": {
    "p0-p0-1": {
      "image": $1,
      "container_name": "p0-p0-1",
      "pull_policy": "never",
      "environment": { "P0_ACCESS_KEYS": "stub-access", "P0_ADMIN_KEY": "stub-admin", "P0_TRUST_PROXY": "1" },
      "volumes": [ { "type": "bind", "source": "/srv/migration-data/services/p0/production/20261029/data", "target": "/data" } ]
    },
    "farm-caddy-1": { "image": "caddy:2" }
  }
}
JSON
  chmod 600 "$work/remote/compose.production.json"; cp -p "$work/remote/compose.production.json" "$work/compose.orig"
}
expect() {   # $1 = label, $2 = pattern the run must match (case glob), $3 = the run
  # shellcheck disable=SC2254   # $2 is a glob on purpose
  case "$3" in $2) echo "ok    $1" ;; *) echo "FAIL  $1"; echo "$3"; fail=1 ;; esac
}
unchanged() { cmp -s "$work/remote/compose.production.json" "$work/compose.orig" && echo "ok    $1: compose untouched" || { echo "FAIL  $1: compose changed"; fail=1; }; }

for s in backup-caddy caddy crontab rollback; do
  expect "refuses $s" "*Hong Kong only*exit 2" "$(run us "$here/deploy-hk.sh" --target us "$s")"
done
expect "refuses --target nowhere" "*unknown target*exit 2" "$(run us "$here/deploy-hk.sh" --target nowhere preflight)"
expect "refuses a staging path under production" "*P0_US_STAGING may not be*exit 2" \
  "$(P0_US_STAGING=/srv/migration-data/services/p0/production/20261029/data/x run us "$here/deploy-hk.sh" --target us transfer abc1234)"
expect "refuses a relative staging path" "*must be an absolute path*exit 2" \
  "$(P0_US_STAGING=staging run us "$here/deploy-hk.sh" --target us transfer abc1234)"

compose '"liusen-migration/image:61da79e6f537e1e0"'
r=$(run us "$here/deploy-hk.sh" --target us up abc1234)
expect "up refuses a tag no transfer checked" "*no checked transfer*exit 1" "$r"; unchanged "up without transfer"

r=$(run us "$here/deploy-hk.sh" --target us transfer abc1234)
expect "transfer: staging 0700, archive 0600, sha256 there, ID = archive config, recorded" \
  "*install -d -m 700 /srv/migration-data/services/p0/staging*chmod 600 p0-server-abc1234.tar.gz*sha256sum -c*us p0-server:abc1234 sha256:0123*exit 0" "$r"
echo "$r" | sed -n '/--- stdout ---/,$p'

r=$(STUB_IMAGE_ID=sha256:ffff KEEP=1 run us "$here/deploy-hk.sh" --target us up abc1234)
expect "up refuses when US docker's ID is not the checked one" "*the transfer checked*exit 1" "$r"; unchanged "up with another ID"

r=$(KEEP=1 run us "$here/deploy-hk.sh" --target us up abc1234)
expect "up: one service, compose -f … up -d --no-deps p0-p0-1, production /data, NEXT reminder" \
  "*docker compose -f /srv/migration-data/services/p0/compose.production.json up -d --no-deps p0-p0-1*liusen-migration/image:61da79e6f537e1e0 -> p0-server:abc1234*/data = /srv/migration-data/services/p0/production/20261029/data*NEXT: send p0-server:abc1234*exit 0" "$r"
echo "$r" | sed -n '/--- stdout ---/,$p'
d=$(diff "$work/compose.orig" "$work/remote/compose.production.json")
expect "up: the only change is the image line" \
  '5c5
<       "image": "liusen-migration/image:61da79e6f537e1e0",
---
>       "image": "p0-server:abc1234",' "$d"
b=("$work/remote/"compose.production.json.before-*)
[ "${#b[@]}" = 1 ] && [ "${b[0]##*/}" = compose.production.json.before-abc1234-20990101T000000 ] && cmp -s "${b[0]}" "$work/compose.orig" \
  && echo "ok    up: the dated copy is the original" || { echo "FAIL  up: dated copy"; fail=1; }
m=$(stat -f %Lp "$work/remote/compose.production.json")
[ "$m" = 600 ] && echo "ok    up: mode stays 600" || { echo "FAIL  up: mode $m"; fail=1; }

compose '"liusen-migration/image:61da79e6f537e1e0"'
sed -i '' 's/"caddy:2"/"caddy:2", "labels": { "was": "liusen-migration\/image:61da79e6f537e1e0" }/' "$work/remote/compose.production.json"
cp -p "$work/remote/compose.production.json" "$work/compose.orig"
expect "up refuses an image string that is in the file twice" "*2 times, not once*exit 1" "$(KEEP=1 run us "$here/deploy-hk.sh" --target us up abc1234)"
unchanged "image string twice"
compose '"${P0_IMAGE}"'
expect "up refuses an image that is a variable" "*not a plain string*exit 1" "$(KEEP=1 run us "$here/deploy-hk.sh" --target us up abc1234)"
unchanged "image variable"
compose '"liusen-migration/image:61da79e6f537e1e0"'
sed -i '' 's/"p0-p0-1": {/"p0": {/' "$work/remote/compose.production.json"; cp -p "$work/remote/compose.production.json" "$work/compose.orig"
expect "up refuses a compose without services[\"p0-p0-1\"]" '*no services\["p0-p0-1"\]*exit 1' "$(KEEP=1 run us "$here/deploy-hk.sh" --target us up abc1234)"
unchanged "no p0-p0-1"

for s in "verify-internal" "report p0-check-player 2026-10-28" "maint-off"; do
  read -r -a a <<< "$s"
  echo; echo "-- us $s"; run us "$here/deploy-hk.sh" --target us "${a[@]}"
done
echo
[ "$fail" = 0 ] && echo "check-deploy-target: OK" || { echo "check-deploy-target: FAILED"; exit 1; }
