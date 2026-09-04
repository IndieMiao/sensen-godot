#!/bin/bash
# ECS 首次启动。密码登录关掉之后只能靠密钥对进来，所以 provision 脚本把 --key-pair 设成必填。
set -eux
apt-get update
apt-get install -y ca-certificates curl fail2ban
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
useradd -m -s /bin/bash farm || true
usermod -aG docker farm
# 阿里云的 KeyPairName 只把公钥装到 root 上；deploy.sh 用的是 farm 用户，要自己复制过去，
# 否则关掉密码登录后 farm 永远登不进来（2026-09-04 实测遗漏）。
install -d -m 700 -o farm -g farm /home/farm/.ssh
cp /root/.ssh/authorized_keys /home/farm/.ssh/authorized_keys
chown farm:farm /home/farm/.ssh/authorized_keys
chmod 600 /home/farm/.ssh/authorized_keys
mkdir -p /opt/farm && chown farm:farm /opt/farm
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
systemctl restart ssh
systemctl enable --now fail2ban
