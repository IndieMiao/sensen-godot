#!/usr/bin/env bash
# farm.sensenjoy.cn 的 A 记录：**先查后建或改**，重跑不会撞「记录已存在」（Codex 三审 N-I10）。
set -euo pipefail
DOMAIN=sensenjoy.cn
RR=farm
IP="${1:?用法: dns.sh <公网IP>}"
existing=$(aliyun alidns DescribeDomainRecords --DomainName "$DOMAIN" --RRKeyWord "$RR" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)['DomainRecords']['Record']
m=[r for r in d if r['RR']=='$RR' and r['Type']=='A']
print(m[0]['RecordId'] if m else '')")
if [ -n "$existing" ]; then
  aliyun alidns UpdateDomainRecord --RecordId "$existing" --RR "$RR" --Type A --Value "$IP" --TTL 600
  echo "已更新 $RR.$DOMAIN -> $IP"
else
  aliyun alidns AddDomainRecord --DomainName "$DOMAIN" --RR "$RR" --Type A --Value "$IP" --TTL 600
  echo "已新建 $RR.$DOMAIN -> $IP"
fi
