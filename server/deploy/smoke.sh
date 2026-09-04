#!/usr/bin/env bash
# 线上冒烟：healthz → 登录 → 建场 → 三条命令 → 重启 app → 状态仍在。
set -euo pipefail
BASE="${BASE_URL:-https://farm.sensenjoy.cn/v1}"
j() { python3 -c "import json,sys;print(json.load(sys.stdin)$1)"; }
# 本机可能配了 HTTPS_PROXY；冒烟必须直连，否则测的是代理能不能连上而不是服务
# （2026-09-04 实测代理会让 TLS 握手直接失败）。
curl() { command curl --noproxy '*' "$@"; }

echo "1. healthz"
curl -fsS "$BASE/healthz" | j "['ok']" | grep -q True

key=$(openssl rand -hex 16)
echo "2. 匿名登录"
tok=$(curl -fsS -X POST "$BASE/auth/anonymous" -H 'content-type: application/json' \
  -d "{\"install_key\":\"$key\"}" | j "['token']")

echo "3. 建农场"
farm=$(curl -fsS -X POST "$BASE/farms" -H "authorization: Bearer $tok" -H 'content-type: application/json' \
  -d '{"idempotency_key":"smoke-1","region_id":"shanghai","layout_patch_id":"sh_a","blueprint_revision":2}')
# 必须挑**已解锁**的初始畦：按字典序取前三格会选中预留畦，那三格要扩地后才能动
# （2026-09-04 实测报 CELL_LOCKED）。cells 的插入顺序就是「先九格初始畦，后三格预留畦」。
cells=$(echo "$farm" | python3 -c "import json,sys;print(' '.join(list(json.load(sys.stdin)['state']['cells'])[:3]))")
ver=$(echo "$farm" | j "['version']")

echo "4. 三条命令"
i=0
for c in $cells; do
  ver=$(curl -fsS -X POST "$BASE/farms/me/commands" -H "authorization: Bearer $tok" -H 'content-type: application/json' \
    -d "{\"idempotency_key\":\"smoke-c$i\",\"base_version\":$ver,\"type\":\"clear_cells\",\"payload\":{\"cell_ids\":[\"$c\"]}}" | j "['version']")
  i=$((i+1))
done
[ "$ver" = 3 ] || { echo "版本应为 3，实际 $ver"; exit 1; }

echo "5. 重启 app 后状态仍在"
ssh "${DEPLOY_HOST:?}" 'cd /opt/farm && docker compose restart app' >/dev/null
for _ in $(seq 30); do curl -fsS "$BASE/healthz" >/dev/null 2>&1 && break; sleep 2; done
after=$(curl -fsS "$BASE/farms/me" -H "authorization: Bearer $tok" | j "['version']")
[ "$after" = 3 ] || { echo "重启后版本应为 3，实际 $after"; exit 1; }
echo "冒烟通过"
