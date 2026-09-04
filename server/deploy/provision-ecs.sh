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
BANDWIDTH="${BANDWIDTH:-5}"                # Mbps，按流量计费
IMAGE="${IMAGE:-ubuntu_24_04_x64_20G_alibase_20250115.vhd}"
NAME="${NAME:-HK-farm-server}"
KEY_PAIR="${KEY_PAIR:-}"
SSH_ALLOW_CIDRS="${SSH_ALLOW_CIDRS:-}"
APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

[ -n "$KEY_PAIR" ]        || { echo "必须提供 KEY_PAIR（阿里云密钥对名称）"; exit 1; }
[ -n "$SSH_ALLOW_CIDRS" ] || { echo "必须提供 SSH_ALLOW_CIDRS（逗号分隔），不允许 22 对全网开放"; exit 1; }

cat <<PLAN
将创建的实例
  区域      $REGION
  规格      $TYPE
  系统盘    ${DISK_GB} GiB ESSD Entry
  带宽      ${BANDWIDTH} Mbps 按流量
  镜像      $IMAGE
  名称      $NAME
  密钥对    $KEY_PAIR
  安全组    80/443 全网；22 仅 $SSH_ALLOW_CIDRS
预估月费（按量付费，仅供参考，以账单为准）
  实例      约 ¥110 / 月
  系统盘    约 ¥14 / 月
  公网流量  按用量，5 Mbps 峰值
PLAN

if [ "$APPLY" != 1 ]; then
  echo; echo "这是 dry-run。确认无误后加 --apply 执行。"; exit 0
fi

vpc=$(aliyun ecs DescribeVpcs --RegionId $REGION | python3 -c 'import json,sys;d=json.load(sys.stdin)["Vpcs"]["Vpc"];print(d[0]["VpcId"] if d else "")')
[ -n "$vpc" ] || { echo "该区域没有 VPC，请先在控制台建一个"; exit 1; }
vsw=$(aliyun ecs DescribeVSwitches --RegionId $REGION --VpcId "$vpc" | python3 -c 'import json,sys;d=json.load(sys.stdin)["VSwitches"]["VSwitch"];print(d[0]["VSwitchId"] if d else "")')
sg=$(aliyun ecs CreateSecurityGroup --RegionId $REGION --VpcId "$vpc" --SecurityGroupName "${NAME}-sg" | python3 -c 'import json,sys;print(json.load(sys.stdin)["SecurityGroupId"])')
for port in 80 443; do
  aliyun ecs AuthorizeSecurityGroup --RegionId $REGION --SecurityGroupId "$sg" \
    --IpProtocol tcp --PortRange "$port/$port" --SourceCidrIp 0.0.0.0/0 --Policy accept >/dev/null
done
IFS=',' read -ra cidrs <<< "$SSH_ALLOW_CIDRS"
for c in "${cidrs[@]}"; do
  aliyun ecs AuthorizeSecurityGroup --RegionId $REGION --SecurityGroupId "$sg" \
    --IpProtocol tcp --PortRange 22/22 --SourceCidrIp "$c" --Policy accept >/dev/null
done
aliyun ecs RunInstances --RegionId $REGION --ImageId "$IMAGE" --InstanceType "$TYPE" \
  --SecurityGroupId "$sg" --VSwitchId "$vsw" --InstanceName "$NAME" --HostName farm \
  --KeyPairName "$KEY_PAIR" --InstanceChargeType PostPaid \
  --SystemDisk.Category cloud_essd --SystemDisk.Size "$DISK_GB" --SystemDisk.PerformanceLevel PL0 \
  --InternetChargeType PayByTraffic --InternetMaxBandwidthOut "$BANDWIDTH" \
  --UserData "$(base64 < "$(dirname "$0")/cloud-init.sh")" --Amount 1
echo "创建完成。用 aliyun ecs DescribeInstances --RegionId $REGION 查公网 IP，再跑 dns.sh。"
