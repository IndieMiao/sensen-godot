#!/usr/bin/env bash
# 动态农场正式服运维脚本（C-96）。放在主机的部署目录里运行，同目录有 compose.yml 和 .env（0600），备份写到 backups/。
# 每一步单独运行，出错即停，不自动回滚。步骤和顺序见 README.md。
#
#   ops.sh check                              核对 .env 和 compose 配置
#   ops.sh load <镜像包.tar.gz> <sha256>       核对镜像包哈希后 docker load，打印镜像 ID
#   ops.sh deploy <完整提交号> <镜像ID>         核对镜像 → 有数据先备份 → 建表（空库建库、已有库补齐）→ 起 app → 健康检查
#   ops.sh init-db                            只建表：起数据库并执行当前镜像里的 schema.sql（可重复执行）
#   ops.sh rollback [<提交号>] [--restore <备份>]  换回上一版（或指定版本）镜像；带 --restore 时先把库恢复到那份备份
#   ops.sh backup [标签]                       备份：pg_dump → 在临时库里试恢复并记下行数和指纹 → 有 AGE_RECIPIENT 就加密
#   ops.sh restore <备份> --confirm-drop       停 app → 先备份现库 → 删库重建 → 恢复 → 核对行数和指纹 → 起 app
#   ops.sh invites <create|list|reset|disable> ...  邀请账号；create / reset 的输出必须重定向到受控存储
#   ops.sh smoke [<入口地址>]                   冒烟（只读，不认领地块）；邀请账号从标准输入读一行 email,password（可选）
#   ops.sh status                             容器、健康检查、最近的发布和备份
set -euo pipefail
umask 077

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$DIR/.env"
RELEASES="$DIR/releases.log"
DB=sensen_dynamicfarm
DB_USER=dynamicfarm
VERIFY_DB=sensen_dynamicfarm_verify
IMAGE_REPO=dynamicfarm-server

die() { echo "✗ $*" >&2; exit 1; }
say() { echo "== $*" >&2; }
envget() { local line; line=$(grep -E "^$1=" "$ENV_FILE" 2>/dev/null | tail -n1 || true); printf '%s' "${line#*=}"; }
# 首次部署前 .env 里还没有 APP_IMAGE / GIT_SHA，compose 解析整份文件会报缺；先给占位值（不存在的镜像，起不来 app）。
dc() {
  local img sha; img=$(envget APP_IMAGE); sha=$(envget GIT_SHA)
  APP_IMAGE="${img:-$IMAGE_REPO:unset}" GIT_SHA="${sha:-unset}" docker compose -f "$DIR/compose.yml" --env-file "$ENV_FILE" "$@"
}
# 原子改写 .env 的一行，保持 0600。
envset() {
  local tmp; tmp=$(mktemp "$DIR/.env.XXXXXX")
  { grep -vE "^$1=" "$ENV_FILE" || true; printf '%s=%s\n' "$1" "$2"; } > "$tmp"
  chmod 600 "$tmp"; mv "$tmp" "$ENV_FILE"
}
port() { local p; p=$(envget DF_HOST_PORT); printf '%s' "${p:-3160}"; }
backup_dir() { local d; d=$(envget DF_BACKUP_DIR); printf '%s' "${d:-$DIR/backups}"; }
psql_in() { local db="$1"; shift; dc exec -T postgres psql -v ON_ERROR_STOP=1 -X -q -U "$DB_USER" -d "$db" "$@"; }
q() { psql_in "$DB" -tA -c "$1"; }
db_exists() { [ "$(psql_in postgres -tA -c "SELECT count(*) FROM pg_database WHERE datname = '$DB'")" = 1 ]; }
user_tables() { q "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public'"; }

check_env() {
  [ -f "$ENV_FILE" ] || die "缺少 $ENV_FILE（照 env.example 建，chmod 600）"
  [ -n "$(find "$ENV_FILE" -maxdepth 0 -perm 600)" ] || die ".env 权限必须是 600"
  local k
  for k in POSTGRES_PASSWORD TOKEN_PEPPER TRUSTED_PROXIES INVITE_EMAIL_DOMAIN PG_IMAGE; do
    [ -n "$(envget "$k")" ] || die ".env 缺少 $k"
  done
  [[ "$(envget POSTGRES_PASSWORD)" =~ ^[A-Za-z0-9]{24,}$ ]] || die "POSTGRES_PASSWORD 要 24 位以上字母数字（它会拼进连接串）"
  local pepper; pepper=$(envget TOKEN_PEPPER); [ "${#pepper}" -ge 32 ] || die "TOKEN_PEPPER 至少 32 个字符"
  [[ "$(envget PG_IMAGE)" == *@sha256:* ]] || die "PG_IMAGE 要按 digest 引用"
  [[ "$(envget TRUSTED_PROXIES)" != *0.0.0.0* ]] || die "TRUSTED_PROXIES 不能是 0.0.0.0/0"
  # 这些开关由 compose.yml 写死；.env 里出现说明有人想改正式配置，先停下来问。
  for k in ACCOUNT_SIGNUP GUEST_WRITES DYNAMIC_FARM_RESELECT QA_EMAIL_DOMAIN QA_EMAIL_CODE GOOGLE_CLIENT_IDS APPLE_BUNDLE_IDS; do
    ! grep -qE "^$k=" "$ENV_FILE" || die ".env 里不要写 $k：正式配置写死在 compose.yml"
  done
}
check_release_env() {
  [[ "$(envget GIT_SHA)" =~ ^[0-9a-f]{40}$ ]] || die ".env 的 GIT_SHA 不是完整提交号"
  [ "$(envget APP_IMAGE)" = "$IMAGE_REPO:$(envget GIT_SHA)" ] || die "APP_IMAGE 要是 $IMAGE_REPO:<GIT_SHA>"
  local id; id=$(docker image inspect --format '{{.Id}}' "$(envget APP_IMAGE)" 2>/dev/null) || die "主机上没有镜像 $(envget APP_IMAGE)"
  [ "$id" = "$(envget APP_IMAGE_ID)" ] || die "镜像 ID 不符：主机上是 $id，.env 记的是 $(envget APP_IMAGE_ID)"
}

wait_pg() {
  dc up -d postgres >/dev/null
  local i
  for i in $(seq 60); do dc exec -T postgres pg_isready -U "$DB_USER" -d postgres >/dev/null 2>&1 && return 0; sleep 2; done
  die "数据库 2 分钟内没有就绪"
}
health() {
  local want i body=""; want=$(envget GIT_SHA)
  for i in $(seq 45); do
    body=$(curl --noproxy '*' -fsS "http://127.0.0.1:$(port)/v1/healthz" 2>/dev/null || true)
    if [[ "$body" == *'"ok":true'* && "$body" == *"\"git_sha\":\"$want\""* ]]; then say "健康检查通过：$want"; return 0; fi
    sleep 2
  done
  die "健康检查 90 秒内没有通过（期望 git_sha=$want）。看日志：docker compose -f $DIR/compose.yml logs --tail 100 app"
}

# 当前库的行数和指纹；备份和恢复都用它核对。
FINGERPRINT_SQL="
SELECT 'users', count(*)::text FROM users
UNION ALL SELECT 'user_identities', count(*)::text FROM user_identities
UNION ALL SELECT 'players', count(*)::text FROM players
UNION ALL SELECT 'parcel_claims', count(*)::text FROM parcel_claims
UNION ALL SELECT 'users_md5', md5(coalesce(string_agg(id::text || '|' || coalesce(email, '') || '|' || coalesce(password_hash, '') || '|' || coalesce(display_name, ''), ',' ORDER BY id), '')) FROM users
UNION ALL SELECT 'parcel_claims_md5', md5(coalesce(string_agg(community_id || '|' || layer || '|' || parcel_id || '|' || player_id || '|' || farm_version || '|' || farm_state::text, ',' ORDER BY community_id, layer, parcel_id), '')) FROM parcel_claims;"
fingerprint() { psql_in "$1" -tA -F ' ' -c "$FINGERPRINT_SQL"; }

do_init_db() {
  check_env; check_release_env; wait_pg
  db_exists || die "库 $DB 不存在（postgres 容器首次启动时按 POSTGRES_DB 建；被删了就用 restore）"
  say "建表前 public 下有 $(user_tables) 张表"
  # 用即将运行的镜像里的 schema.sql：全是 IF NOT EXISTS / ADD COLUMN IF NOT EXISTS，可重复执行；app 启动时也会再执行一遍。
  dc run --rm --no-deps -T --entrypoint cat app src/db/schema.sql | psql_in "$DB"
  local t
  for t in players tokens users user_identities parcel_claims; do
    [ "$(q "SELECT to_regclass('public.$t') IS NOT NULL")" = t ] || die "建表后缺少 $t"
  done
  say "建表完成：public 下 $(user_tables) 张表"
}

do_backup() {
  local label="${1:-}"
  [[ -z "$label" || "$label" =~ ^[a-z0-9-]{1,40}$ ]] || die "备份标签只能用小写字母、数字和 -"
  check_env; wait_pg
  local dir; dir=$(backup_dir); mkdir -p "$dir"; chmod 700 "$dir"
  local base; base="$dir/dynamicfarm-$(date -u +%Y%m%dT%H%M%SZ)${label:+-$label}"
  # 先写 .part，核对完才改名：失败的那次不会留下一个看起来像备份的文件。
  dc exec -T postgres pg_dump -U "$DB_USER" -d "$DB" -Fc > "$base.dump.part" || { rm -f "$base.dump.part"; die "pg_dump 失败"; }
  [ -s "$base.dump.part" ] || { rm -f "$base.dump.part"; die "备份是空文件"; }
  # 在同一个数据库实例的临时库里真恢复一遍，行数和指纹从恢复出来的库算：记下的就是这份备份里的内容。
  psql_in postgres -c "DROP DATABASE IF EXISTS $VERIFY_DB" -c "CREATE DATABASE $VERIFY_DB OWNER $DB_USER"
  if ! dc exec -T postgres pg_restore -U "$DB_USER" -d "$VERIFY_DB" --no-owner --exit-on-error < "$base.dump.part"; then
    psql_in postgres -c "DROP DATABASE IF EXISTS $VERIFY_DB"; rm -f "$base.dump.part"; die "备份试恢复失败"
  fi
  fingerprint "$VERIFY_DB" > "$base.counts"
  psql_in postgres -c "DROP DATABASE IF EXISTS $VERIFY_DB"
  local recipient out; recipient=$(envget AGE_RECIPIENT)
  if [ -n "$recipient" ]; then
    age -r "$recipient" -o "$base.dump.age.part" "$base.dump.part" || { rm -f "$base.dump.part" "$base.dump.age.part" "$base.counts"; die "age 加密失败"; }
    rm -f "$base.dump.part"; mv "$base.dump.age.part" "$base.dump.age"; out="$base.dump.age"
  else
    mv "$base.dump.part" "$base.dump"; out="$base.dump"
  fi
  chmod 600 "$out" "$base.counts"
  # 本机保留最近 DF_BACKUP_KEEP 份（默认 14）；异地副本由主机的备份方案负责，见 README。
  local keep; keep=$(envget DF_BACKUP_KEEP); keep=${keep:-14}
  { ls -1t "$dir"/dynamicfarm-*.dump "$dir"/dynamicfarm-*.dump.age 2>/dev/null || true; } | tail -n +"$((keep + 1))" | while read -r old; do
    rm -f "$old" "${old%.dump*}.counts"
  done
  say "备份完成：$out（$(wc -c < "$out" | tr -d ' ') 字节）；$(tr '\n' ' ' < "$base.counts")"
  printf '%s\n' "$out"
}

do_restore() {
  local file="${1:-}" confirm="${2:-}"
  [ -n "$file" ] && [ -f "$file" ] || die "用法：ops.sh restore <备份文件> --confirm-drop"
  [ "$confirm" = --confirm-drop ] || die "恢复会删掉现在的 $DB 再重建；确认后加 --confirm-drop"
  check_env; wait_pg
  local counts="${file%.dump*}.counts"
  [ -f "$counts" ] || die "缺少 $counts（备份时记下的行数和指纹），不知道恢复得对不对"
  local plain="$file"
  if [[ "$file" == *.age ]]; then
    [ -n "${AGE_IDENTITY:-}" ] && [ -f "$AGE_IDENTITY" ] || die "加密备份要用 AGE_IDENTITY=<私钥文件> 解密（私钥不放在服务器上，用完即删）"
    # 解密出来的是玩家数据：放在 0700 的备份目录里，脚本退出时（含失败）删掉。
    RESTORE_PLAIN=$(mktemp "$(backup_dir)/restore.XXXXXX"); plain="$RESTORE_PLAIN"
    trap 'rm -f "${RESTORE_PLAIN:-}"' EXIT
    age -d -i "$AGE_IDENTITY" -o "$plain" "$file"
  fi
  say "停 app"
  dc stop app >/dev/null 2>&1 || true
  if db_exists && [ "$(user_tables)" != 0 ]; then
    say "先备份现在的库（标签 pre-restore），恢复错了还能回来"
    do_backup pre-restore >/dev/null
  fi
  psql_in postgres -c "DROP DATABASE IF EXISTS $DB WITH (FORCE)" -c "CREATE DATABASE $DB OWNER $DB_USER"
  dc exec -T postgres pg_restore -U "$DB_USER" -d "$DB" --no-owner --exit-on-error < "$plain" || die "pg_restore 失败；库现在是半恢复状态，app 保持停止"
  local got; got=$(fingerprint "$DB")
  if [ "$got" != "$(cat "$counts")" ]; then
    echo "期望：$(tr '\n' ' ' < "$counts")" >&2; echo "实际：$(printf '%s' "$got" | tr '\n' ' ')" >&2
    die "恢复后的行数或指纹和备份时记下的不一致；app 保持停止"
  fi
  say "恢复核对通过：$(printf '%s' "$got" | tr '\n' ' ')"
}

record_release() { printf '%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" >> "$RELEASES"; }
start_app() { dc up -d --no-deps app >/dev/null; health; }

do_deploy() {
  local sha="${1:-}" id="${2:-}"
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || die "用法：ops.sh deploy <完整提交号> <镜像ID sha256:...>"
  [[ "$id" =~ ^sha256:[0-9a-f]{64}$ ]] || die "镜像 ID 要写完整的 sha256:<64 位>"
  check_env
  local got; got=$(docker image inspect --format '{{.Id}}' "$IMAGE_REPO:$sha" 2>/dev/null) || die "主机上没有 $IMAGE_REPO:$sha（先 ops.sh load）"
  [ "$got" = "$id" ] || die "镜像 ID 不符：主机上是 $got，要部署的是 $id"
  wait_pg
  if db_exists && [ "$(user_tables)" != 0 ]; then
    say "库里已有数据，部署前先备份（标签 pre-${sha:0:12}）"
    do_backup "pre-${sha:0:12}" >/dev/null
  fi
  envset APP_IMAGE "$IMAGE_REPO:$sha"; envset APP_IMAGE_ID "$id"; envset GIT_SHA "$sha"
  record_release deploy "$sha" "$id"
  do_init_db
  start_app
}

do_rollback() {
  local target="" restore=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --restore) restore="${2:-}"; [ -n "$restore" ] || die "--restore 后面要跟备份文件"; shift 2 ;;
      *) [[ "$1" =~ ^[0-9a-f]{40}$ ]] || die "要回到的版本写完整提交号"; target="$1"; shift ;;
    esac
  done
  check_env
  [ -f "$RELEASES" ] || die "没有 releases.log，不知道上一版是什么"
  local current line; current=$(envget GIT_SHA)
  if [ -z "$target" ]; then
    # 上一版 = 发布记录里最近一条和当前不同的版本。
    target=$(awk -F '\t' -v cur="$current" '$3 != cur { t = $3 } END { print t }' "$RELEASES")
    [ -n "$target" ] || die "发布记录里没有比当前更早的其它版本"
  fi
  line=$(awk -F '\t' -v t="$target" '$3 == t { l = $0 } END { print l }' "$RELEASES")
  [ -n "$line" ] || die "发布记录里没有 $target"
  local id; id=$(printf '%s' "$line" | cut -f4)
  local got; got=$(docker image inspect --format '{{.Id}}' "$IMAGE_REPO:$target" 2>/dev/null) || die "主机上已经没有 $IMAGE_REPO:$target"
  [ "$got" = "$id" ] || die "镜像 ID 不符：主机上是 $got，记录的是 $id"
  say "回滚：$current → $target"
  [ -z "$restore" ] || do_restore "$restore" --confirm-drop
  envset APP_IMAGE "$IMAGE_REPO:$target"; envset APP_IMAGE_ID "$id"; envset GIT_SHA "$target"
  record_release rollback "$target" "$id"
  start_app
}

do_load() {
  local file="${1:-}" sum="${2:-}"
  [ -f "$file" ] && [[ "$sum" =~ ^[0-9a-f]{64}$ ]] || die "用法：ops.sh load <镜像包.tar.gz> <sha256>"
  local got; got=$( (sha256sum "$file" 2>/dev/null || shasum -a 256 "$file") | cut -d' ' -f1)
  [ "$got" = "$sum" ] || die "镜像包哈希不符：$got"
  docker load -i "$file" | tee /dev/stderr | grep -q "Loaded image: $IMAGE_REPO:" || die "镜像包里没有 $IMAGE_REPO:<提交号>"
  docker image ls --no-trunc --format '{{.Repository}}:{{.Tag}} {{.ID}}' "$IMAGE_REPO" >&2
}

do_invites() {
  local sub="${1:-}" extra=()
  case "$sub" in
    create|reset)
      # 密码只写到重定向的地方（受控存储）；不往终端打，也不留在服务器上。
      [ ! -t 1 ] || die "invites $sub 的输出含密码：请重定向到受控存储，例如 ssh 主机 '…/ops.sh invites create …' > 本机受控目录/xxx.csv"
      extra=(--out -) ;;
    list|disable) ;;
    *) die "用法：ops.sh invites <create|list|reset|disable> ..." ;;
  esac
  check_env; check_release_env
  dc exec -T app ./node_modules/.bin/tsx tools/invite_accounts.ts "$@" ${extra[@]+"${extra[@]}"}
}

do_smoke() {
  check_env; check_release_env
  # 默认在 app 容器里打它自己的 3000 端口；给了入口地址（如 https://…/dynamicfarm/v1）就走入口。
  local base="${1:-http://127.0.0.1:3000/v1}" args
  args=(--base "$base" --git-sha "$(envget GIT_SHA)")
  [ -t 0 ] || args+=(--invite-stdin)
  dc exec -T app ./node_modules/.bin/tsx tools/dynamicfarm_smoke.ts "${args[@]}"
}

do_status() {
  dc ps
  curl --noproxy '*' -fsS "http://127.0.0.1:$(port)/v1/healthz" || echo "健康检查不通" >&2
  echo; [ -f "$RELEASES" ] && tail -n 5 "$RELEASES"
  ls -lt "$(backup_dir)" 2>/dev/null | head -n 8 || true
}

cmd="${1:-}"; [ $# -gt 0 ] && shift
case "$cmd" in
  check) check_env; dc config -q; say ".env 和 compose 配置通过" ;;
  load) do_load "$@" ;;
  deploy) do_deploy "$@" ;;
  init-db) do_init_db ;;
  rollback) do_rollback "$@" ;;
  backup) do_backup "$@" ;;
  restore) do_restore "$@"; start_app ;;
  invites) do_invites "$@" ;;
  smoke) do_smoke "$@" ;;
  status) do_status ;;
  *) sed -n '2,15p' "$0" >&2; exit 2 ;;
esac
