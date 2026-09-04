#!/usr/bin/env bash
# 部署。**只接受带 digest 的镜像**，不接受 tag：tag 可以被重新推送，部署什么就得是什么。
# digest 从 CI 产出的 release-manifest.json 里读。
set -euo pipefail
HOST="${DEPLOY_HOST:?需要 DEPLOY_HOST，如 farm@1.2.3.4}"
MANIFEST="${1:?用法: deploy.sh <release-manifest.json>}"
digest=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['image_digest'])" "$MANIFEST")
sha=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['git_sha'])" "$MANIFEST")
[[ "$digest" == *"@sha256:"* ]] || { echo "manifest 里的 image_digest 必须带 @sha256:"; exit 1; }

here=$(dirname "$0")
scp "$here/docker-compose.yml" "$here/Caddyfile" "$here/crontab" "$here/backup.sh" "$HOST:/opt/farm/"
# .env 从本机推上去并立刻收紧权限；它不入库（Codex 三审 N-I9）。
scp "$here/../.env.production" "$HOST:/opt/farm/.env"
ssh "$HOST" "chmod 600 /opt/farm/.env && chmod +x /opt/farm/backup.sh"
ssh "$HOST" "cd /opt/farm && APP_IMAGE='$digest' GIT_SHA='$sha' docker compose pull && APP_IMAGE='$digest' GIT_SHA='$sha' docker compose up -d"
"$here/smoke.sh"
