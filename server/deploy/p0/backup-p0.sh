#!/usr/bin/env bash
# Nightly copy of the P0 data volume (saves, hourly snapshots, observation log) — SGODOT-232 D1. Run on the host:
#   /opt/farm/p0/backup-p0.sh   (crontab: 40 3 * * * /opt/farm/p0/backup-p0.sh >> /opt/farm/p0/backups/backup.log 2>&1)
# Keeps 14 nightly archives in /opt/farm/p0/backups. Restore: stop p0, untar into the volume, start p0.
# The volume is found by its compose labels (project P0_PROJECT, default p0), not by a hard-coded name.
#
# Offsite (SGODOT-304 ③): the night's archive is then encrypted to the backup age public key and put in the backup
# bucket under p0/, with the write-only RAM user (it can neither read, list nor delete). Its settings are in
# /opt/farm/p0/.env.backup (chmod 600, never committed): AGE_RECIPIENT, OSS_BUCKET, AWS_ACCESS_KEY_ID,
# AWS_SECRET_ACCESS_KEY. Without that file the offsite step is skipped and the local copy is all there is.
# The upload comes last: when it fails the night's local archive is already kept, and the script exits non-zero.
# Restore from offsite: download p0/p0-data-<day>.tgz.age with an account that may read, `age -d -i <private key>`,
# then as above. The private key is never on this host.
set -euo pipefail
OUT="${P0_BACKUP_DIR:-/opt/farm/p0/backups}"
PROJECT="${P0_PROJECT:-p0}"
OFFSITE_ENV="${P0_BACKUP_ENV:-/opt/farm/p0/.env.backup}"
PREFIX="${P0_BACKUP_PREFIX:-p0/}"
# age and the aws CLI for the offsite step, on a pinned base image
TOOLS_IMAGE=alpine:3.20@sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc
say() { echo "$(date -u +%FT%TZ) $*"; }

VOL=$(docker volume ls -q --filter "label=com.docker.compose.project=$PROJECT" --filter "label=com.docker.compose.volume=p0data")
[ "$(printf '%s\n' "$VOL" | grep -c .)" = 1 ] || { say "expected one p0data volume for compose project $PROJECT, found: ${VOL:-none}"; exit 1; }
mkdir -p "$OUT"
DAY=$(date -u +%Y%m%d)
NAME="p0-data-$DAY.tgz"

# 1. Pack. The store writes p0-state.json.tmp and renames it over p0-state.json (atomic), so the archive holds a whole
#    save, old or new; a .tmp caught half-written is left out.
docker run --rm -v "$VOL":/data:ro -v "$OUT":/out alpine tar -czf "/out/$NAME" --exclude='*.tmp' -C /data .

# 2. The saves in the archive must parse; an archive that does not is kept for a look but never sent offsite.
if ! PLAYERS=$(tar -xzOf "$OUT/$NAME" ./p0-state.json | python3 -c 'import json, sys; print(len(json.load(sys.stdin)))' 2>/dev/null); then
  say "check FAILED: p0-state.json in $OUT/$NAME does not parse; not sent offsite"
  exit 1
fi
say "packed $OUT/$NAME ($(stat -c %s "$OUT/$NAME") bytes, $PLAYERS players)"

# 3. Local rotation: 14 nights.
ls -1t "$OUT"/p0-data-*.tgz | tail -n +15 | xargs -r rm -f

# 4. Offsite, last.
if [ ! -s "$OFFSITE_ENV" ]; then say "offsite: skipped (no $OFFSITE_ENV)"; exit 0; fi
docker run --rm --env-file "$OFFSITE_ENV" -e NAME="$NAME" -e PREFIX="$PREFIX" -v "$OUT":/out:ro "$TOOLS_IMAGE" sh -euc '
  apk add --no-cache age aws-cli >/dev/null
  : "${AGE_RECIPIENT:?}" "${OSS_BUCKET:?}" "${AWS_ACCESS_KEY_ID:?}" "${AWS_SECRET_ACCESS_KEY:?}"
  # OSS takes virtual-hosted addressing only, and none of the newer aws CLI streaming checksums (NotImplemented)
  printf "[default]\nregion = oss-cn-hongkong\nrequest_checksum_calculation = when_required\nresponse_checksum_validation = when_required\ns3 =\n  addressing_style = virtual\n" > /tmp/aws.cfg
  age -r "$AGE_RECIPIENT" -o "/tmp/$NAME.age" "/out/$NAME"
  AWS_CONFIG_FILE=/tmp/aws.cfg aws --no-progress --endpoint-url https://oss-cn-hongkong.aliyuncs.com \
    s3 cp "/tmp/$NAME.age" "s3://$OSS_BUCKET/$PREFIX$NAME.age" >/dev/null
  echo "$(stat -c %s "/tmp/$NAME.age")"' > "$OUT/.offsite-size" \
  || { say "offsite FAILED: $PREFIX$NAME.age not uploaded (the local archive is kept)"; exit 1; }
say "offsite: $PREFIX$NAME.age uploaded ($(cat "$OUT/.offsite-size") bytes, encrypted)"
