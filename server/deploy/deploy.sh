#!/usr/bin/env bash
# 部署。**只接受带 digest 的镜像**，不接受 tag：tag 可以被重新推送，部署什么就得是什么。
# digest 从 CI 产出的 release-manifest.json 里读。
set -euo pipefail
HOST="${DEPLOY_HOST:?需要 DEPLOY_HOST，如 farm@1.2.3.4}"
here=$(dirname "$0")
repo=$(cd "$here/../.." && pwd)
sha=$(git -C "$repo" rev-parse --short HEAD)

# 有 manifest 就用 CI 构建好的镜像；没有就**在服务器上构建**（本机没装 Docker）。
# 无论哪条路，compose 最终都按 digest 引用——tag 可以被重新推送，digest 不能。
if [ -n "${1:-}" ]; then
  digest=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['image_digest'])" "$1")
  sha=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['git_sha'])" "$1")
  [[ "$digest" == *"@sha256:"* ]] || { echo "manifest 里的 image_digest 必须带 @sha256:"; exit 1; }
  ssh "$HOST" "cd /opt/farm && docker pull '$digest'"
else
  echo "没有 manifest，改为在服务器上构建（本机无 Docker）"
  ssh "$HOST" 'mkdir -p /opt/farm/src'
  # 只传构建上下文需要的部分，与 .dockerignore 的放行清单一致。
  # --exclude 必须在文件列表**之前**：BSD tar 会把它后面的当成路径（macOS 上实测）。
  tar -C "$repo" --exclude 'node_modules' --exclude '.env' --exclude '.env.production' -czf - \
    package.json pnpm-lock.yaml pnpm-workspace.yaml packages/blueprint-core server \
    assets/farm/data $(cd "$repo" && ls -d assets/blueprints/*/r2/farm_blueprint.json) \
    | ssh "$HOST" 'tar -C /opt/farm/src -xzf -'
  ssh "$HOST" "cd /opt/farm/src && docker build -f server/Dockerfile -t farm-server:$sha ."
  digest="farm-server:$sha"
fi

scp "$here/docker-compose.yml" "$here/crontab" "$here/backup.sh" "$HOST:/opt/farm/"
# .env 和 Caddyfile 以服务器上的为准，已有就不覆盖（SGODOT-304，2026-10-17）：线上 .env 里有换过的库密码和备份
# 凭据，本机那份是旧的；线上 Caddyfile 并入了 P0 转发和 Journey 的 410，仓库版本没有。只有首次部署（服务器上
# 还没有这个文件）才从本机推。要改线上的 .env / Caddyfile，在服务器上改，并先备份。
keep_or_push() {   # <本机文件> <服务器上的文件名>
  if ssh "$HOST" "test -e /opt/farm/$2"; then
    echo "保留服务器上的 /opt/farm/$2（不覆盖）"
  else
    [ -s "$1" ] || { echo "服务器上没有 /opt/farm/$2，本机也没有 $1，中止"; exit 1; }
    echo "首次部署：推本机 $1 到 /opt/farm/$2"
    scp "$1" "$HOST:/opt/farm/$2"
  fi
}
keep_or_push "$here/../.env.production" .env   # .env 不入库（Codex 三审 N-I9）
keep_or_push "$here/Caddyfile" Caddyfile
ssh "$HOST" "chmod 600 /opt/farm/.env && chmod +x /opt/farm/backup.sh"

# postgres / caddy 的 digest 从镜像源解析一次并固定下来。
pgd=$(ssh "$HOST" "docker pull -q docker.m.daocloud.io/library/postgres:16-alpine >/dev/null && docker inspect --format '{{index .RepoDigests 0}}' docker.m.daocloud.io/library/postgres:16-alpine | cut -d@ -f2")
cad=$(ssh "$HOST" "docker pull -q docker.m.daocloud.io/library/caddy:2-alpine >/dev/null && docker inspect --format '{{index .RepoDigests 0}}' docker.m.daocloud.io/library/caddy:2-alpine | cut -d@ -f2")
# digest 必须写进 .env 而不是只在 up 那一刻传环境变量：否则之后任何 docker compose
# 命令（ps / logs / restart）都会因缺变量而失败，运维时完全看不了状态（2026-09-04 实测）。
ssh "$HOST" "cd /opt/farm && sed -i '/^APP_IMAGE=/d;/^GIT_SHA=/d;/^PG_DIGEST=/d;/^CADDY_DIGEST=/d' .env && cat >> .env <<EOF
APP_IMAGE=$digest
GIT_SHA=$sha
PG_DIGEST=${pgd#sha256:}
CADDY_DIGEST=${cad#sha256:}
EOF
chmod 600 .env && docker compose up -d"

# 等容器真的健康再冒烟。`up -d` 一返回就打过去必然 502——健康检查有 40 秒的
# start-period，Caddy 在那之前没有可转发的上游（2026-09-04 连续两次踩到）。
echo "等待 app 健康"
for i in $(seq 1 60); do
  st=$(ssh "$HOST" "docker inspect --format '{{.State.Health.Status}}' farm-app-1" 2>/dev/null || echo starting)
  [ "$st" = healthy ] && break
  [ "$st" = unhealthy ] && { echo "app 健康检查失败"; ssh "$HOST" 'cd /opt/farm && docker compose logs app --tail 40'; exit 1; }
  sleep 3
done
[ "$st" = healthy ] || { echo "等待超时，app 仍是 $st"; exit 1; }

DEPLOY_HOST="$HOST" "$here/smoke.sh"
