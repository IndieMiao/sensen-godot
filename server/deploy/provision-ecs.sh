#!/usr/bin/env bash
# 新建香港 ECS。**默认 --dry-run**：先打印规格与预估月费，人工确认后再加 --apply。
#
# 两个必填项没有默认值（Codex 三审 N-I10）：
#   --key-pair       没有它 cloud-init 关掉密码登录后就再也进不去了
#   SSH_ALLOW_CIDRS  为空直接退出，不允许 22 对 0.0.0.0/0 敞开
set -euo pipefail
REGION=cn-hongkong
TYPE="${ECS_TYPE:-ecs.e-c1m2.large}"      # 2 vCPU / 4 GiB 经济型
DISK_GB="${DISK_GB:-40}"
# 峰值带宽上限，**按流量计费**（PayByTraffic）：只为实际出网流量付费，这个数字只是限速。
BANDWIDTH="${BANDWIDTH:-5}"
# 包月（PrePaid）比按量便宜 38%：2026-09-04 查计费接口，e-c1m2.large 包月 125.8 元/月，
# 按量 0.2765 元/小时 ≈ 201.8 元/月。用户 2026-09-04 拍板走包月。
CHARGE="${CHARGE:-PrePaid}"
PERIOD="${PERIOD:-1}"
# 镜像 ID 带发布日期，会随阿里云更新而变——写死会在几个月后变成 InvalidImageId.NotFound
# （2026-09-04 实测）。留空则自动挑当前最新的 Ubuntu 24.04 x86_64。
IMAGE="${IMAGE:-}"
NAME="${NAME:-HK-farm-server}"
KEY_PAIR="${KEY_PAIR:-}"
SSH_ALLOW_CIDRS="${SSH_ALLOW_CIDRS:-}"
APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

[ -n "$KEY_PAIR" ]        || { echo "必须提供 KEY_PAIR（阿里云密钥对名称）"; exit 1; }
if [ -z "$IMAGE" ]; then
  IMAGE=$(aliyun ecs DescribeImages --RegionId $REGION --ImageOwnerAlias system --OSType linux --PageSize 100 \
    | python3 -c "
import json,sys
d=json.load(sys.stdin)['Images']['Image']
u=[i['ImageId'] for i in d
   if i['ImageId'].startswith('ubuntu_24_04_x64_20G_alibase') and i['Architecture']=='x86_64']
print(sorted(u)[-1] if u else '')")
  [ -n "$IMAGE" ] || { echo "找不到 Ubuntu 24.04 x86_64 公共镜像"; exit 1; }
fi
[ -n "$SSH_ALLOW_CIDRS" ] || { echo "必须提供 SSH_ALLOW_CIDRS（逗号分隔），不允许 22 对全网开放"; exit 1; }

PERIOD_NOTE=""
[ "$CHARGE" = "PrePaid" ] && PERIOD_NOTE="，周期 ${PERIOD} 个月"
cat <<PLAN
将创建的实例
  区域      $REGION
  规格      ${TYPE}（2 vCPU / 4 GiB 经济型）
  计费      ${CHARGE}${PERIOD_NOTE}
  系统盘    ${DISK_GB} GiB ESSD PL0
  公网      按流量计费，峰值上限 ${BANDWIDTH} Mbps
  镜像      $IMAGE
  名称      $NAME
  密钥对    $KEY_PAIR
  安全组    80/443 全网；22 仅 $SSH_ALLOW_CIDRS
月费（2026-09-04 查阿里云计费接口的实价，非估算）
  实例      ¥125.8 / 月（包月；按量为 ¥201.8）
  系统盘    ¥26.9 / 月
  出网流量  按实际用量计费，MVP 阶段可忽略
  合计      约 ¥153 / 月
PLAN

if [ "$APPLY" != 1 ]; then
  echo; echo "这是 dry-run。确认无误后加 --apply 执行。"; exit 0
fi

vpc=$(aliyun ecs DescribeVpcs --RegionId $REGION | python3 -c 'import json,sys;d=json.load(sys.stdin)["Vpcs"]["Vpc"];print(d[0]["VpcId"] if d else "")')
[ -n "$vpc" ] || { echo "该区域没有 VPC，请先在控制台建一个"; exit 1; }
vsw=$(aliyun ecs DescribeVSwitches --RegionId $REGION --VpcId "$vpc" | python3 -c 'import json,sys;d=json.load(sys.stdin)["VSwitches"]["VSwitch"];print(d[0]["VSwitchId"] if d else "")')
# 复用同名安全组：上一次跑到一半失败时组已经建出来了，再建会留一堆孤儿。
sg=$(aliyun ecs DescribeSecurityGroups --RegionId $REGION --SecurityGroupName "${NAME}-sg" \
  | python3 -c 'import json,sys;g=json.load(sys.stdin)["SecurityGroups"]["SecurityGroup"];print(g[0]["SecurityGroupId"] if g else "")')
if [ -z "$sg" ]; then
  sg=$(aliyun ecs CreateSecurityGroup --RegionId $REGION --VpcId "$vpc" --SecurityGroupName "${NAME}-sg" | python3 -c 'import json,sys;print(json.load(sys.stdin)["SecurityGroupId"])')
fi
for port in 80 443; do
  aliyun ecs AuthorizeSecurityGroup --RegionId $REGION --SecurityGroupId "$sg" \
    --IpProtocol tcp --PortRange "$port/$port" --SourceCidrIp 0.0.0.0/0 --Policy accept >/dev/null 2>&1 || true
done
IFS=',' read -ra cidrs <<< "$SSH_ALLOW_CIDRS"
for c in "${cidrs[@]}"; do
  aliyun ecs AuthorizeSecurityGroup --RegionId $REGION --SecurityGroupId "$sg" \
    --IpProtocol tcp --PortRange 22/22 --SourceCidrIp "$c" --Policy accept >/dev/null 2>&1 || true
done
period_args=()
[ "$CHARGE" = "PrePaid" ] && period_args=(--PeriodUnit Month --Period "$PERIOD" --AutoRenew false)
aliyun ecs RunInstances --RegionId $REGION --ImageId "$IMAGE" --InstanceType "$TYPE" \
  --SecurityGroupId "$sg" --VSwitchId "$vsw" --InstanceName "$NAME" --HostName farm \
  --KeyPairName "$KEY_PAIR" --InstanceChargeType "$CHARGE" "${period_args[@]}" \
  --SystemDisk.Category cloud_essd --SystemDisk.Size "$DISK_GB" --SystemDisk.PerformanceLevel PL0 \
  --InternetChargeType PayByTraffic --InternetMaxBandwidthOut "$BANDWIDTH" \
  --UserData "$(base64 < "$(dirname "$0")/cloud-init.sh")" --Amount 1
echo "创建完成。用 aliyun ecs DescribeInstances --RegionId $REGION 查公网 IP，再跑 dns.sh。"
