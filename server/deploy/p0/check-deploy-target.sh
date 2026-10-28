#!/usr/bin/env bash
# Offline check of deploy-hk.sh's --target (SGODOT-232; the US West target after the 10-29 migration). Connects to
# nothing: ssh, scp, curl and date are stubs that log what they were asked and answer canned lines.
#   server/deploy/p0/check-deploy-target.sh [<git ref of the old script>]   # default origin/farm-dev
# 1. Hong Kong unchanged: every step run by the old script and by this one (with no --target and with --target hk)
#    gives the same stdout, exit code and stub log — the same remote commands, the same stdin, byte for byte.
# 2. us: the Hong Kong-only steps refuse; transfer / up / verify-internal / report print the commands they would send.
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
f=$(mktemp); cat > "$f"
# gzip puts the time in its header: hash what is inside, so two runs of the same archive compare equal
if gzip -t < "$f" 2>/dev/null; then in="gz:$(gunzip -c < "$f" | shasum -a 256 | cut -c1-16)"; else in=$(shasum -a 256 < "$f" | cut -c1-16); fi
rm -f "$f"
printf 'ssh %s | stdin %s\n' "$*" "$in" >> "$STUB_LOG"
case "$*" in
  *State.Health.Status*) echo healthy ;;
  *Mounts*) echo /srv/migration-data/services/p0/production/20261029/data ;;
  *"cat /opt/farm/Caddyfile"*) printf 'farm.sensenjoy.cn {\n    handle {\n        reverse_proxy farm-app-1:3000\n    }\n}\n' ;;
  *"docker save"*) cat "$STUB_DIR/image.tar.gz" ;;
  *"docker image inspect"*) echo sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef ;;
  *"python3 -"*) echo 'service p0: p0-server:e64d4b33 -> p0-server:abc1234' ;;
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
  rm -rf "$repo/output/p0-deploy/2099-01-01"
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
for s in backup-caddy caddy crontab rollback; do
  r=$(run us "$here/deploy-hk.sh" --target us "$s")
  case "$r" in *"Hong Kong only"*"exit 2") echo "refuses  $s" ;; *) echo "FAIL  $s on us did not refuse"; echo "$r"; fail=1 ;; esac
done
r=$(run us "$here/deploy-hk.sh" --target nowhere preflight)
case "$r" in *"unknown target"*"exit 2") echo "refuses  --target nowhere" ;; *) echo "FAIL  --target nowhere"; fail=1 ;; esac
for s in "transfer abc1234" "up abc1234" "verify-internal" "report p0-check-player 2026-10-28" "maint-off"; do
  read -r -a a <<< "$s"
  echo; echo "-- us $s"; run us "$here/deploy-hk.sh" --target us "${a[@]}"
done
echo
[ "$fail" = 0 ] && echo "check-deploy-target: OK" || { echo "check-deploy-target: FAILED"; exit 1; }
