#!/bin/sh
# pg_dump → age 加密 → 上传 OSS。私钥不在服务器上：age 用公钥加密，解密只能在本机
# （~/.config/sensen/farm-backup.key）。OSS 用**只写**子账号，恢复用另一个只读子账号。
# .env 需要：AGE_RECIPIENT、OSS_BUCKET、AWS_ACCESS_KEY_ID、AWS_SECRET_ACCESS_KEY（SGODOT-304 ②）。
set -eu
: "${AGE_RECIPIENT:?}" "${OSS_BUCKET:?}" "${POSTGRES_PASSWORD:?}"
# OSS 的两个要求（2026-10-16 香港实测）：只认虚拟主机式地址（路径式报 SecondLevelDomainForbidden）；
# 不接受 aws-cli 2.34 默认加的流式校验尾（报 NotImplemented），校验只在必需时做。
export AWS_CONFIG_FILE=/tmp/aws-oss.config AWS_DEFAULT_REGION=oss-cn-hongkong
printf '[default]\nregion = oss-cn-hongkong\nrequest_checksum_calculation = when_required\nresponse_checksum_validation = when_required\ns3 =\n  addressing_style = virtual\n' > "$AWS_CONFIG_FILE"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUT="/backups/farm-${STAMP}.dump.age"
PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -h postgres -U farm -d sensen_farm -Fc \
  | age -r "$AGE_RECIPIENT" -o "$OUT"
SIZE=$(wc -c < "$OUT")
[ "$SIZE" -gt 1024 ] || { echo "备份文件过小（$SIZE 字节），中止"; exit 1; }
# 放在 farm/ 前缀下：桶的 30 天生命周期规则按前缀生效（farm/、p0/），journey/ 不过期。
aws --no-progress --endpoint-url "https://oss-cn-hongkong.aliyuncs.com" s3 cp "$OUT" "s3://${OSS_BUCKET}/farm/${STAMP}.dump.age"
# 本地只留 2 份，OSS 侧靠 farm/ 的生命周期规则留 30 天。
ls -1t /backups/*.dump.age | tail -n +3 | xargs -r rm -f
echo "备份完成 ${OUT} (${SIZE} 字节) → farm/${STAMP}.dump.age"
