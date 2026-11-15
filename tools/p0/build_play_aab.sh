#!/usr/bin/env bash
# Build and verify a local Play AAB, then copy it to Downloads. Never uploads.
# Submission prerequisites: the approved accounts backend + q(320) must be live,
# gensen.app/terms must be live, and the TERMS_LIVE change must be merged.
# Until then artifacts are for Play internal testing only. Release/phone/server actions
# still use the separately approved release checklist; this command grants none of them.
# Reserve the Mac build window before export; the script checks USB and uses private ADB.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec python3 "$REPO_ROOT/tools/p0/play_aab.py" "$@"
