#!/usr/bin/env bash
# Nightly copy of the P0 data volume (saves, hourly snapshots, observation log) — SGODOT-232 D1. Run on the host:
#   /opt/farm/p0/backup-p0.sh   (crontab: 40 3 * * * /opt/farm/p0/backup-p0.sh)
# Keeps 14 nightly archives in /opt/farm/p0/backups. Restore: stop p0, untar into the volume, start p0.
# The volume is found by its compose labels (project P0_PROJECT, default p0), not by a hard-coded name.
set -euo pipefail
OUT=/opt/farm/p0/backups
PROJECT="${P0_PROJECT:-p0}"
VOL=$(docker volume ls -q --filter "label=com.docker.compose.project=$PROJECT" --filter "label=com.docker.compose.volume=p0data")
[ "$(printf '%s\n' "$VOL" | grep -c .)" = 1 ] || { echo "expected one p0data volume for compose project $PROJECT, found: ${VOL:-none}"; exit 1; }
mkdir -p "$OUT"
docker run --rm -v "$VOL":/data:ro -v "$OUT":/out alpine tar -czf "/out/p0-data-$(date -u +%Y%m%d).tgz" -C /data .
ls -1t "$OUT"/p0-data-*.tgz | tail -n +15 | xargs -r rm -f
