# farm-server

街角四季的权威状态服务。数值逻辑全部在这里，客户端不算钱（方案 D4）。

## 本地开发

数据库跑在局域网测试机 devserver（`192.168.124.53`）的容器里，本机不装 Docker 也不装
PostgreSQL。

```bash
# 首次：在 devserver 上起库
scp deploy/devserver-pg.compose.yml zhangshaojie@192.168.124.53:~/pg16-farm/compose.yml
ssh zhangshaojie@192.168.124.53 'cd ~/pg16-farm && echo "POSTGRES_PASSWORD=$(openssl rand -hex 16)" > .env && chmod 600 .env && docker compose up -d'

cp .env.example .env      # 填 DATABASE_URL / TEST_DATABASE_URL / TOKEN_PEPPER
pnpm install              # 在仓库根跑，workspace 会带上 blueprint-core
pnpm test                 # 154 个用例；没有 TEST_DATABASE_URL 时 DB 套件跳过
pnpm typecheck
```

国内直连 Docker Hub 拉 postgres 镜像会断（`short read: unexpected EOF`），compose 里
已改用 daocloud 镜像源。

## 跑起来

```bash
node --experimental-strip-types src/index.ts     # 需要 DATABASE_URL 与 TOKEN_PEPPER
curl localhost:3000/v1/healthz
```

启动时会校验全部在架蓝图，任一不过直接退出——不带病上线。

## 测试分层

| 目录 | 内容 |
|---|---|
| `test/domain/` | reducer 每条命令的成功与失败路径、Grant 物化顺序、时间与派生 |
| `test/ledger.test.ts` | 四条路径只用公开命令跑出 PRD §7.5 的全部目标数字 |
| `test/matrices.test.ts` | 会话切分矩阵、天气轮换矩阵、高频 bot 上界 |
| `test/http/` | 鉴权五项、409 三种、三个 DTO 的精确字段与四种隐私组合 |
| `test/db/` | 真库：单写者、幂等并发、版本门控顺序 |

**账本数字对不上时改内容表或 reducer，不许改断言。**

## 构建镜像

构建上下文是**仓库根目录**，不是 `server/`：服务端 import workspace 包 `blueprint-core`。

```bash
docker build -f server/Dockerfile -t farm-server:dev ..
```

## 部署

```bash
# 1. 建 ECS（默认 dry-run，打印规格与预估月费）
KEY_PAIR=my-key SSH_ALLOW_CIDRS=1.2.3.4/32 deploy/provision-ecs.sh
KEY_PAIR=my-key SSH_ALLOW_CIDRS=1.2.3.4/32 deploy/provision-ecs.sh --apply

# 2. DNS（先查后建或改，重跑安全）
deploy/dns.sh <公网IP>

# 3. 部署（只接受 CI 产出的 release-manifest.json 里的 digest）
DEPLOY_HOST=farm@<IP> deploy/deploy.sh release-manifest.json
```

`.env.production` 放在本机（gitignored），deploy 时推上去并 `chmod 600`。

## QA 白名单

`QA_PLAYER_IDS` 是逗号分隔的 player_id。只有他们建的农场带 `qa` 标记，导演命令才生效；
客户端不能自设。正式农场调 QA 命令返回 403。

## 重置农场

只在开发环境可用，三个条件同时成立：DSN 主机在 `192.168.124.0/24` 或 localhost、
`ALLOW_RESET=1`、只删 `qa=true` 或版本字段不符的农场。生产 DSN 直接拒绝。

## 备份与恢复

`deploy/backup.sh` 每天 03:30 UTC 由 supercronic 触发：`pg_dump` → age 公钥加密 → 传 OSS。
私钥只在本机 `~/.config/sensen/farm-backup.key`，服务器上没有。

`deploy/restore-drill.sh` 是恢复演练：拉最近一份 → 本机解密 → 恢复到 devserver 的
`sensen_farm_restore` → 比对表行数、表数量、10 个农场的 state 哈希、`max(version)` → 删库。
脚本硬拒绝非 devserver 网段与非该库名的目标。

## 线上真机 QA（2026-09-04 起的流程）

线上只有香港这一套环境，没有 staging——QA 造出来的匿名账号与农场都会留在生产库里。

```bash
# 1. 打包装机（约 130 MB；设备用 adb devices 确认）
godot --headless --path . --export-debug "Android" build/sensen-g2-debug.apk
adb install -r build/sensen-g2-debug.apk          # -r 保留 App 数据（安装密钥、已选城市/蓝图）
adb shell pm clear com.sensen.avatarphase1        # 想要一个全新玩家 / 回到选地流程时用

# 2. 客户端默认连 https://farm.sensenjoy.cn/v1；要指到别的服务器，往 user:// 放一行 URL
adb shell run-as com.sensen.avatarphase1 sh -c 'echo http://192.168.124.53:3000/v1 > files/server.txt'

# 3. 观察
adb logcat -s godot:* GodotApp:*                  # 客户端
ssh farm@47.76.226.41 'cd /opt/farm && docker compose logs -f app'   # 服务端
```

**导演模式（加速时间）**：农场里长按标题 3 秒开面板 → 任意按一下 → 面板显示
`This farm is not a QA instance · player <id>` → 把这个 id 加进服务器白名单：

```bash
ssh farm@47.76.226.41 'cd /opt/farm && sed -i "s/^QA_PLAYER_IDS=.*/QA_PLAYER_IDS=<id1>,<id2>/" .env && docker compose up -d app'
```

app 容器重建后再按即生效；480x = 3 分钟走完一个玩家日。白名单只认 player_id，
`pm clear` 之后是新玩家，要重新加。

检查清单在 Plane SGODOT-33。
