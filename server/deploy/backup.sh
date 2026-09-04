#!/bin/sh
# pg_dump → age 加密 → 上传 OSS。私钥不在服务器上：age 用公钥加密，解密只能在本机
# （~/.config/sensen/farm-backup.key）。OSS 用**只写**子账号，恢复用另一个只读子账号。
set -eu
: "${AGE_RECIPIENT:?}" "${OSS_BUCKET:?}" "${POSTGRES_PASSWORD:?}"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUT="/backups/farm-${STAMP}.dump.age"
PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -h postgres -U farm -d sensen_farm -Fc \
  | age -r "$AGE_RECIPIENT" -o "$OUT"
SIZE=$(wc -c < "$OUT")
[ "$SIZE" -gt 1024 ] || { echo "备份文件过小（$SIZE 字节），中止"; exit 1; }
aws --endpoint-url "https://oss-cn-hongkong.aliyuncs.com" s3 cp "$OUT" "s3://${OSS_BUCKET}/${STAMP}.dump.age"
# 本地只留 2 份，OSS 侧靠生命周期规则留 14 天。
ls -1t /backups/*.dump.age | tail -n +3 | xargs -r rm -f
echo "备份完成 ${OUT} (${SIZE} 字节)"
