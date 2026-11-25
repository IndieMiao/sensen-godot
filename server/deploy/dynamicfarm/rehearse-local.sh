#!/usr/bin/env bash
# 动态农场正式服的本机隔离演练（C-96）：不连任何服务器，不需要 Docker，ops.sh 原样运行。
# - postgres 容器 → 临时的 PostgreSQL 16（只听 unix 套接字，trust 认证）；
# - app 镜像 → 仓库提交的源码快照（按 server/Dockerfile 的 COPY 清单从 git archive 取出，node_modules 用本仓库已装好的）；
# - docker → 一个只认 ops.sh 用到的那几种调用的替身（bin/docker），compose 的 environment 写死项从 compose.yml 读。
# 走一遍：空库部署 → 只读冒烟 → 建邀请账号 → 两个账号认领并存档 → 备份 → 删库 → 恢复并核对 →
#         部署下一版（加一列的模拟迁移）→ 回滚 → 再部署下一版 → 带恢复的回滚。
# 当前版本取 HEAD（工作区要干净）；“下一版”是 HEAD 的副本，schema.sql 多一行加列；“修复版”是 HEAD 的另一个副本。
# 后两个的提交号是演练用的假值。
# 依赖：PostgreSQL 16 命令行（PGBIN，默认 /opt/homebrew/opt/postgresql@16/bin）、age、node、已 pnpm install 的仓库。
# 日志里没有密码；密钥、邀请账号和数据库都在临时目录里，结束时（含失败）删掉。
set -euo pipefail
umask 077
export LC_ALL="${LC_ALL:-en_US.UTF-8}" LANG="${LANG:-en_US.UTF-8}"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@16/bin}"
[ -z "$(git -C "$REPO" status --porcelain)" ] || { echo "工作区不干净：演练用的是 HEAD 的提交内容" >&2; exit 1; }
HEAD_SHA=$(git -C "$REPO" rev-parse HEAD)
NEXT_SHA=$(printf 'rehearsal-next-%s' "$HEAD_SHA" | shasum | cut -d' ' -f1)
FIX_SHA=$(printf 'rehearsal-fix-%s' "$HEAD_SHA" | shasum | cut -d' ' -f1)
R=$(mktemp -d "${TMPDIR:-/tmp}/dfr.XXXXXX")
PGPORT_LOCAL=5498
APP_PORT=$(node -e "const s=require('net').createServer();s.listen(0,'127.0.0.1',()=>{console.log(s.address().port);s.close()})")
DEPLOY="$R/deploy"
STEP=0

cleanup() {
  [ -f "$R/app.pid" ] && kill "$(cat "$R/app.pid")" 2>/dev/null || true
  "$PGBIN/pg_ctl" -D "$R/pgdata" -m fast stop >/dev/null 2>&1 || true
  rm -rf "$R"
}
trap cleanup EXIT
step() { STEP=$((STEP + 1)); echo; echo "### $STEP. $*"; }
ok() { echo "  ✓ $*"; }
fail() { echo "  ✗ $*" >&2; exit 1; }
ops() { "$DEPLOY/ops.sh" "$@"; }
sql() { "$PGBIN/psql" -h "$R" -p "$PGPORT_LOCAL" -U dynamicfarm -X -q -tA -d "${2:-sensen_dynamicfarm}" -c "$1"; }

# —— app 镜像：按 Dockerfile 的 COPY 清单取源码 ——
image() {
  local sha="$1" dir="$R/images/$1"
  mkdir -p "$dir"
  git -C "$REPO" archive "$HEAD_SHA" package.json pnpm-lock.yaml pnpm-workspace.yaml packages/blueprint-core server \
    assets/farm/data assets/ponds/catalog.json assets/avatar/parts_manifest.json assets/avatar/demo_denylist.json assets/blueprints \
    | tar -x -C "$dir"
  ln -s "$REPO/node_modules" "$dir/node_modules"
  ln -s "$REPO/server/node_modules" "$dir/server/node_modules"
  [ ! -d "$REPO/packages/blueprint-core/node_modules" ] || ln -s "$REPO/packages/blueprint-core/node_modules" "$dir/packages/blueprint-core/node_modules"
}
image_id() { printf 'sha256:%s' "$(printf '%s' "dynamicfarm-server:$1" | shasum -a 256 | cut -d' ' -f1)"; }

mkdir -p "$R/bin" "$R/secrets" "$DEPLOY"
step "准备：当前版本 ${HEAD_SHA}，下一版（模拟）$NEXT_SHA"
image "$HEAD_SHA"
image "$NEXT_SHA"
image "$FIX_SHA"
printf '\n-- rehearsal: the next release adds a column\nALTER TABLE parcel_claims ADD COLUMN IF NOT EXISTS rehearsal_probe text;\n' \
  >> "$R/images/$NEXT_SHA/server/src/db/schema.sql"
ok "两个镜像快照就绪"

# —— docker 替身 ——
cat > "$R/bin/docker" <<FAKE
#!/usr/bin/env bash
set -euo pipefail
R='$R'; PGBIN='$PGBIN'; PGPORT_LOCAL='$PGPORT_LOCAL'; DEPLOY='$DEPLOY'
FAKE
cat >> "$R/bin/docker" <<'FAKE'
if [ "$1" = image ] && [ "$2" = inspect ]; then
  tag="${@: -1}"; [ -d "$R/images/${tag#dynamicfarm-server:}" ] || exit 1
  printf 'sha256:%s\n' "$(printf '%s' "$tag" | shasum -a 256 | cut -d' ' -f1)"; exit 0
fi
[ "$1" = compose ] || { echo "docker 替身不支持：$*" >&2; exit 2; }
shift
while [ $# -gt 0 ]; do case "$1" in -f|--env-file) shift 2 ;; *) break ;; esac; done
sub="$1"; shift
pgenv=(PGHOST="$R" PGPORT="$PGPORT_LOCAL")
appdir() { local d="$R/images/${APP_IMAGE#dynamicfarm-server:}/server"; [ -d "$d" ] || { echo "没有镜像 $APP_IMAGE" >&2; exit 1; }; printf '%s' "$d"; }
# compose 语义：env_file 的值，再被 app 的 environment 写死项覆盖；DATABASE_URL 换成本机临时库。
appenv() {
  local line
  while IFS= read -r line; do [[ "$line" =~ ^[A-Z_][A-Z0-9_]*= ]] && printf '%s\n' "$line"; done < "$DEPLOY/.env"
  awk '/^  app:/{a=1} a&&/^    environment:/{e=1;next} e&&/^    [a-z_]+:/{exit} e&&/^      [A-Z_]+:/{k=$1; sub(":","",k); v=$0; sub(/^ *[A-Z_]+: */,"",v); gsub(/"/,"",v); print k"="v}' "$DEPLOY/compose.yml" \
    | grep -vE '^(DATABASE_URL|GIT_SHA)='
  printf 'DATABASE_URL=postgres://dynamicfarm@localhost/sensen_dynamicfarm?host=%s&port=%s\n' "$R" "$PGPORT_LOCAL"
  printf 'GIT_SHA=%s\nPORT=%s\n' "$GIT_SHA" "$(grep -E '^DF_HOST_PORT=' "$DEPLOY/.env" | cut -d= -f2)"
}
runapp() { local -a e=(); local l; while IFS= read -r l; do e+=("$l"); done < <(appenv); exec env -i PATH="$PATH" HOME="$HOME" "${e[@]}" "$@"; }
stopapp() { if [ -f "$R/app.pid" ]; then kill "$(cat "$R/app.pid")" 2>/dev/null || true; while kill -0 "$(cat "$R/app.pid")" 2>/dev/null; do sleep 0.2; done; rm -f "$R/app.pid"; fi; }
case "$sub" in
  config) exit 0 ;;
  ps) [ -f "$R/app.pid" ] && echo "app pid $(cat "$R/app.pid") $APP_IMAGE" || echo "app stopped"; echo "postgres $PGPORT_LOCAL" ;;
  up)
    [ "${@: -1}" = postgres ] && exit 0
    stopapp
    d=$(appdir)
    (cd "$d" && runapp ./node_modules/.bin/tsx src/index.ts >> "$R/app.log" 2>&1 & echo $! > "$R/app.pid") ;;
  stop) stopapp ;;
  run) # run --rm --no-deps -T --entrypoint cat app <file>
    cat "$(appdir)/${@: -1}" ;;
  exec)
    [ "$1" = -T ] && shift
    svc="$1"; shift
    # 容器里的 -h 127.0.0.1（走 TCP）换成本机临时库的套接字。
    if [ "$svc" = postgres ]; then
      args=(); while [ $# -gt 0 ]; do if [ "$1" = -h ]; then shift 2; else args+=("$1"); shift; fi; done
      env "${pgenv[@]}" PATH="$PGBIN:$PATH" "${args[@]}"
    else d=$(appdir); cd "$d" && runapp "$@"; fi ;;
  *) echo "docker 替身不支持 compose $sub" >&2; exit 2 ;;
esac
FAKE
chmod +x "$R/bin/docker"
export PATH="$R/bin:$PGBIN:$PATH"

step "临时 PostgreSQL 16（相当于 postgres 容器首次启动：建空库 sensen_dynamicfarm）"
"$PGBIN/initdb" -D "$R/pgdata" -U dynamicfarm --auth=trust -E UTF8 >/dev/null
"$PGBIN/pg_ctl" -D "$R/pgdata" -o "-k $R -c listen_addresses='' -p $PGPORT_LOCAL" -l "$R/pg.log" -w start >/dev/null
"$PGBIN/createdb" -h "$R" -p "$PGPORT_LOCAL" -U dynamicfarm sensen_dynamicfarm
ok "空库：public 下 $(sql "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'") 张表"

step "部署目录：compose.yml、ops.sh、env.example 取自 HEAD；.env 按模板填（值只在临时目录）"
cp "$R/images/$HEAD_SHA/server/deploy/dynamicfarm/"{compose.yml,ops.sh,env.example} "$DEPLOY/"
age-keygen -o "$R/secrets/age.key" 2>/dev/null
sed -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(openssl rand -hex 24)|" -e "s|^TOKEN_PEPPER=.*|TOKEN_PEPPER=$(openssl rand -hex 32)|" \
  -e "s|^TRUSTED_PROXIES=.*|TRUSTED_PROXIES=127.0.0.1|" -e "s|^INVITE_EMAIL_DOMAIN=.*|INVITE_EMAIL_DOMAIN=invite.rehearsal.invalid|" \
  -e "s|^PG_IMAGE=.*|PG_IMAGE=postgres@sha256:$(printf 'rehearsal' | shasum -a 256 | cut -d' ' -f1)|" -e "s|^DF_HOST_PORT=.*|DF_HOST_PORT=$APP_PORT|" \
  -e "s|^AGE_RECIPIENT=.*|AGE_RECIPIENT=$(grep -o 'age1[0-9a-z]*' "$R/secrets/age.key")|" \
  -e "s|^SMTP_URL=.*|SMTP_URL=smtp://127.0.0.1:9|" -e "s|^MAIL_FROM=.*|MAIL_FROM=Rehearsal <no-reply@rehearsal.invalid>|" \
  "$DEPLOY/env.example" > "$DEPLOY/.env"
chmod 600 "$DEPLOY/.env"
ops check
ok "ops.sh check 通过"

step "空库部署当前版本：ops.sh deploy"
ops deploy "$HEAD_SHA" "$(image_id "$HEAD_SHA")"
ok "建表后 public 下 $(sql "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'") 张表；服务日志：$(grep -o 'farm-server listening.*' "$R/app.log" | tail -n1 | sed 's/content=[^ ]* //')"

step "只读冒烟（没有账号、不建号）：健康检查、邮箱注册和 Google 登录已开放、游客能读不能认领"
ops smoke "http://127.0.0.1:$APP_PORT/v1"

step "邀请账号：ops.sh invites create，输出重定向到受控文件（0600）"
ops invites create --count 3 --batch rehearsal > "$R/secrets/invites.csv"
[ "$(wc -l < "$R/secrets/invites.csv" | tr -d ' ')" = 4 ] || fail "应有表头加 3 个账号"
[ "$(stat -f %Lp "$R/secrets/invites.csv" 2>/dev/null || stat -c %a "$R/secrets/invites.csv")" = 600 ] || fail "账号文件不是 0600"
ok "3 个账号写进受控文件（日志不打密码）"
ops invites list
# 用 script 给 ops.sh 一个终端做标准输出：应在连库之前就拒绝（输出整个丢弃，万一没拒绝也不留密码）。
# 只看退出码（script 带回 ops.sh 的退出码）和有没有输出 CSV 表头：终端输出的时序和多字节字符都不可靠。
rc=0; script -q /dev/null "$DEPLOY/ops.sh" invites create --count 1 --batch rehearsal > "$R/tty.out" 2>&1 || rc=$?
[ "$rc" != 0 ] && ! grep -q 'email,password' "$R/tty.out" || fail "标准输出是终端时应拒绝"
rm -f "$R/tty.out"
[ "$(sql "SELECT count(*) FROM users")" = 3 ] || fail "被拒绝时不应建账号"
ok "标准输出是终端时，create 在连库前被 ops.sh 拒绝，没有多建账号"

step "两个邀请账号登录、认领、首次进入、存档（放房、开垦、播种）并读回；“放弃并重选”被拒"
farm() { # farm <账号行号> <地块> <输出文件>
  sed -n "$1p" "$R/secrets/invites.csv" | (cd "$R/images/$HEAD_SHA/server" && ./node_modules/.bin/tsx tools/dynamicfarm_smoke.ts \
    --base "http://127.0.0.1:$APP_PORT/v1" --invite-stdin --write "sf-dynamic-farm-20261124-r6,$2,-122.4194,37.7749") > "$3"
}
farm 2 p-9100001 "$R/farm-a.json"; farm 3 p-9100002 "$R/farm-b.json"
ok "存档：$(sql "SELECT string_agg(parcel_id || ' v' || farm_version, ', ' ORDER BY parcel_id) FROM parcel_claims")"

step "备份：ops.sh backup（pg_dump → 临时库试恢复并记行数和指纹 → age 加密）"
BACKUP=$(ops backup rehearsal)
ok "$(basename "$BACKUP")；记下：$(tr '\n' ' ' < "${BACKUP%.dump*}.counts")"
[ -z "$(ls "$(dirname "$BACKUP")"/*.dump* 2>/dev/null | grep -v "\.dump\.age$")" ] || fail "加密后不应留下明文 dump"

step "删库：停 app，DROP DATABASE sensen_dynamicfarm"
docker compose stop app
sql "DROP DATABASE sensen_dynamicfarm WITH (FORCE)" postgres
[ "$(sql "SELECT count(*) FROM pg_database WHERE datname='sensen_dynamicfarm'" postgres)" = 0 ] || fail "库还在"
ok "库已删除"

step "恢复：AGE_IDENTITY=<私钥> ops.sh restore <备份> --confirm-drop"
AGE_IDENTITY="$R/secrets/age.key" ops restore "$BACKUP" --confirm-drop
farm 2 p-9100001 "$R/farm-a.after.json"; farm 3 p-9100002 "$R/farm-b.after.json"
cmp -s "$R/farm-a.json" "$R/farm-a.after.json" && cmp -s "$R/farm-b.json" "$R/farm-b.after.json" || fail "恢复后读回的地块存档和备份前不同"
ok "恢复后两个账号照常登录，读回的地块存档与备份前逐字节相同"
[ -z "$(ls "$(dirname "$BACKUP")"/restore.* 2>/dev/null)" ] || fail "解密出的临时文件没删"

step "部署下一版（模拟迁移：parcel_claims 加一列）"
ops deploy "$NEXT_SHA" "$(image_id "$NEXT_SHA")"
PRE_NEXT=$(ls -1t "$DEPLOY/backups/"*"-pre-${NEXT_SHA:0:12}.dump.age" | head -n1)
[ "$(sql "SELECT count(*) FROM information_schema.columns WHERE table_name='parcel_claims' AND column_name='rehearsal_probe'")" = 1 ] || fail "下一版的迁移没生效"
ok "下一版运行中，部署前自动备份：$(basename "$PRE_NEXT")"

step "回滚（只换镜像）：ops.sh rollback"
ops rollback
farm 2 p-9100001 "$R/farm-a.rb.json"
cmp -s "$R/farm-a.json" "$R/farm-a.rb.json" || fail "回滚后读回的存档不同"
ok "回到 ${HEAD_SHA}；新加的列还在（只加不改，旧版照常读写），存档不变"
if ops rollback 2>/dev/null; then fail "上一条是回滚时，不写版本的 rollback 应拒绝"; fi
ok "已经回滚过时，不写版本的 rollback 被拒绝（不会又滚回坏的那版）"
mkdir "$DEPLOY/.ops.lock"
if ops backup 2>/dev/null; then fail "有锁时 backup 应拒绝"; fi
rmdir "$DEPLOY/.ops.lock"
ok "另一个步骤在跑（有锁）时，backup 直接退出"

step "回滚后再部署修复版，修复版也出问题时 ops.sh rollback 回到部署修复版之前在跑的版本，而不是之前坏的那版"
ops deploy "$FIX_SHA" "$(image_id "$FIX_SHA")"
ops rollback
[ "$(grep -E '^GIT_SHA=' "$DEPLOY/.env" | cut -d= -f2)" = "$HEAD_SHA" ] || fail "应回到 ${HEAD_SHA}，不应回到下一版"
ok "当前 → 下一版 → 回滚到当前 → 修复版 → rollback：回到 ${HEAD_SHA}"

step "备份轮换：定时备份（不带标签）只留 DF_BACKUP_KEEP 份，带标签的部署前备份不轮换"
sed -i.bak 's/^DF_BACKUP_KEEP=.*/DF_BACKUP_KEEP=1/' "$DEPLOY/.env"; rm -f "$DEPLOY/.env.bak"; chmod 600 "$DEPLOY/.env"
ops backup >/dev/null; sleep 1; ops backup >/dev/null
[ "$(ls "$DEPLOY/backups/" | grep -cE '^dynamicfarm-[0-9]{8}T[0-9]{6}Z\.dump\.age$')" = 1 ] || fail "不带标签的应只剩 1 份"
[ -f "$PRE_NEXT" ] || fail "部署前备份不应被轮换"
ok "不带标签的只剩 1 份；部署前备份 $(basename "$PRE_NEXT") 还在"

step "再部署下一版，然后带恢复的回滚：ops.sh rollback <当前版本> --restore <部署前备份>"
ops deploy "$NEXT_SHA" "$(image_id "$NEXT_SHA")"
AGE_IDENTITY="$R/secrets/age.key" ops rollback "$HEAD_SHA" --restore "$PRE_NEXT"
[ "$(sql "SELECT count(*) FROM information_schema.columns WHERE table_name='parcel_claims' AND column_name='rehearsal_probe'")" = 0 ] || fail "恢复后不应有下一版加的列"
farm 2 p-9100001 "$R/farm-a.rb2.json"
cmp -s "$R/farm-a.json" "$R/farm-a.rb2.json" || fail "带恢复的回滚后读回的存档不同"
ok "库回到部署下一版之前，存档不变"
ops status | sed 's/^/  /'

step "资源占用（本机演练，只作参考）"
rss_tree() { local pids="$1" kids; kids=$(pgrep -d, -P "$1" || true); [ -z "$kids" ] || pids="$pids,$kids"; ps -o rss= -p "$pids" | awk '{s+=$1} END {print int(s/1024)}'; }
echo "  app 进程（tsx 与 node）常驻内存合计：$(rss_tree "$(cat "$R/app.pid")") MB"
echo "  PostgreSQL 进程常驻内存合计（含共享内存重复计数）：$(rss_tree "$(head -n1 "$R/pgdata/postmaster.pid")") MB"
echo "  库大小：$(sql "SELECT pg_size_pretty(pg_database_size('sensen_dynamicfarm'))")；加密备份：$(wc -c < "$BACKUP" | tr -d ' ') 字节"
echo
echo "演练全部通过"
