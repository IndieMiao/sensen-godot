#!/usr/bin/env bash
# 恢复演练：拉最近一份备份 → 本机解密 → 恢复到 devserver 的 sensen_farm_restore →
# 比对四项 → 删库。
#
# 只接受 devserver 网段与恰好 sensen_farm_restore 这个库名（Codex 三审 O-I7）：
# 恢复脚本末尾有 DROP DATABASE，指错目标就是灾难。
set -euo pipefail
RESTORE_DSN="${RESTORE_DSN:?需要 RESTORE_DSN}"
LIVE_DSN="${LIVE_DSN:?需要 LIVE_DSN（只读比对用）}"
AGE_KEY="${AGE_KEY:-$HOME/.config/sensen/farm-backup.key}"

host=$(python3 -c "import urllib.parse,sys;print(urllib.parse.urlparse(sys.argv[1]).hostname)" "$RESTORE_DSN")
db=$(python3 -c "import urllib.parse,sys;print(urllib.parse.urlparse(sys.argv[1]).path.lstrip('/'))" "$RESTORE_DSN")
[[ "$host" =~ ^192\.168\.124\.[0-9]+$ ]] || { echo "拒绝：恢复目标必须在 devserver 网段，收到 $host"; exit 1; }
[[ "$db" == "sensen_farm_restore" ]] || { echo "拒绝：库名必须是 sensen_farm_restore，收到 $db"; exit 1; }

latest=$(aws --endpoint-url https://oss-cn-hongkong.aliyuncs.com s3 ls "s3://${OSS_BUCKET:?}/" | sort | tail -1 | awk '{print $4}')
[ -n "$latest" ] || { echo "OSS 里没有备份"; exit 1; }
tmp=$(mktemp -d)
aws --endpoint-url https://oss-cn-hongkong.aliyuncs.com s3 cp "s3://${OSS_BUCKET}/${latest}" "$tmp/b.age"
age -d -i "$AGE_KEY" -o "$tmp/b.dump" "$tmp/b.age"

psql "$RESTORE_DSN" -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public;' >/dev/null
pg_restore -d "$RESTORE_DSN" --no-owner "$tmp/b.dump"

q() { psql -tA "$1" -c "$2"; }
fail=0
for t in players tokens farms commands; do
  a=$(q "$RESTORE_DSN" "SELECT count(*) FROM $t")
  b=$(q "$LIVE_DSN" "SELECT count(*) FROM $t")
  echo "行数 $t: 恢复 $a / 线上 $b"
  [ "$a" -le "$b" ] || { echo "  ✗ 恢复的行数多于线上，备份可能错乱"; fail=1; }
done
# 迁移版本：schema.sql 全是 IF NOT EXISTS，用表数量代替
ta=$(q "$RESTORE_DSN" "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'")
tb=$(q "$LIVE_DSN" "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'")
echo "表数量: 恢复 $ta / 线上 $tb"; [ "$ta" = "$tb" ] || fail=1
# 抽样 10 个农场的 state 哈希
ha=$(q "$RESTORE_DSN" "SELECT md5(string_agg(state::text, '' ORDER BY id)) FROM (SELECT id, state FROM farms ORDER BY id LIMIT 10) x")
hb=$(q "$LIVE_DSN" "SELECT md5(string_agg(state::text, '' ORDER BY id)) FROM (SELECT id, state FROM farms ORDER BY id LIMIT 10) x")
echo "state 抽样哈希: $ha vs $hb"
va=$(q "$RESTORE_DSN" "SELECT coalesce(max(version),0) FROM farms")
vb=$(q "$LIVE_DSN" "SELECT coalesce(max(version),0) FROM farms")
echo "max(version): 恢复 $va / 线上 $vb"

psql "$RESTORE_DSN" -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public;' >/dev/null
rm -rf "$tmp"
[ "$fail" = 0 ] && echo "恢复演练通过" || { echo "恢复演练失败"; exit 1; }
