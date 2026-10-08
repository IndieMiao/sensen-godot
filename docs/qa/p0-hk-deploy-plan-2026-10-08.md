# P0 演示服务端部署方案：香港 ECS（SGODOT-232 D1，2026-10-08）

**状态：用户已确认，定于 2026-10-08 22:00 部署（未执行）。** 三项都按推荐：镜像在 devserver 构建后传到服务器、给 farm 加只含 P0 备份的 crontab、今晚 22:00。前提：#23、#26 先合入 farm-dev，镜像从合并后的 farm-dev 构建；21:30 前由奕星确认合并状态，没合入就顺延。白天线上机器只读。

**执行脚本**：`server/deploy/p0/deploy-hk.sh <步骤>`。每一步单独运行，出错即停，结果记在 `output/p0-deploy/<日期>/`。顺序：
`preflight` → `build origin/farm-dev` → `transfer <sha>` → `backup-caddy` → `up <sha>` → `verify-internal` → `caddy` → `smoke` → `crontab` → `stats`；出问题时执行 `rollback`；部署完执行 `clean-devserver <sha>`。观察员工具：`players` / `energy <id> <值>` / `report <id> [日期]`（见 2.6）。

## 1. 只读检查结果（2026-10-08 10:20 服务器时间，`ssh farm@47.76.226.41`）

只执行了 `uptime`、`free`、`df`、`docker ps / inspect / stats / compose ls / network ls / system df / images`、`ss -tln`、`cat /opt/farm/Caddyfile`、`crontab -l`，以及 Journey compose 中网络相关的几行。没有改动任何东西，也没有读 .env 和密钥。

| 项 | 结果 |
|---|---|
| SSH | 本机能登录（farm 用户，属 docker 组） |
| 实例 | 运行 33 天，负载 0.47 / 0.25 / 0.18；x86_64，2 核 |
| 内存 | 共 3.5 GB，已用 1.8 GB，**可用 1.67 GB**；没有 swap |
| 磁盘 | `/` 40 GB，已用 22 GB，**剩 16 GB**；Docker 构建缓存 6.7 GB（其中 3 GB 可回收） |
| Docker | 29.8.0，Compose v5.5.1；BuildKit 默认开启（`Dockerfile.dockerignore` 生效）；镜像源 `docker.m.daocloud.io` |
| 反向代理 | **是 Caddy，不是 nginx**：容器 `farm-caddy-1` 占 80 / 443，配置是 bind mount 的单个文件 `/opt/farm/Caddyfile`，在 `farm_default` 网络上 |
| 宿主端口 | 22、80、443，另有 LiveKit 的 7880 / 7881 / 17880 / 17881（host 网络）。P0 不占宿主端口 |

**正在运行的 compose 项目**

| 项目 | 位置 | 容器 | 内存（实际 / 上限） |
|---|---|---|---|
| farm | /opt/farm/docker-compose.yml | farm-app-1、farm-postgres-1、farm-caddy-1、farm-backup-1 | 55 MB / 1 GB 等 |
| **sensen-journey-preview（Journey 线上服）** | /opt/farm/journey-preview/compose.yml | journey-app-1（别名 `journey-preview`）、journey-db-1 | 226 MB / 1 GB；165 MB / 512 MB |
| sensen-social-demo | /home/farm/sensen-social-demo | app、db | 82 MB；27 MB |
| sensen-voice | /opt/sensen-voice | livekit prod / dev（host 网络） | 48 MB；27 MB |

**线上 Caddyfile（farm.sensenjoy.cn 块）**：`/downloads/*` 静态文件 → `/preview/journey/*` 转 `journey-preview:3000` → 兜底 `handle` 转 `farm-app-1:3000`。另有 demo.sensenjoy.cn、voice / voice-dev 三个站点。仓库里的 `server/deploy/Caddyfile` 已经落后于线上，**不能拿仓库版本覆盖**。

**Journey 的接入方式**（P0 照抄）：独立 compose 项目，`default` 网络设为 `internal`，再以外部网络加入 `farm_default`，给 app 加别名 `journey-preview`，Caddy 按别名转发。

## 2. 部署方案

| 项 | 方案 |
|---|---|
| 访问地址 | `https://farm.sensenjoy.cn/preview/p0/v1`（演示包 `--server` 就填这个） |
| 位置 | `/opt/farm/p0/`（farm 用户可写，与 journey-preview 并列）：`docker-compose.p0.yml`、`.env.p0`（口令，chmod 600）、`backup-p0.sh`、`backups/`、`src/<sha>/`（构建上下文） |
| 容器 | compose 项目 `p0`，服务 `p0`，镜像 `p0-server:<sha>`，网络 `farm_default`，别名 **`p0-demo`**，端口 3110 **只在容器网络内**；`mem_limit 256m`、`cpus 0.5`、日志轮转 20 MB × 5 |
| 数据 | Docker 卷 `p0_p0data` 挂到 `/data`：存档 `p0-state.json`（每条命令写一次，先写临时文件再改名）、`snapshots/`（每小时一份，留 48 份）、`events/`（观察日志，#23）。**没有数据库**，不碰 farm 和 Journey 的 Postgres |
| 运行配置 | `P0_DEV=0`（不注册 dev 路由）、`P0_TRUST_PROXY=1`（在 Caddy 后面，只信任回环和私网上的代理，取 Caddy 写入的那个地址）、`P0_ACCESS_KEYS`（演示口令，本机 `openssl rand -hex 8` 生成，只放 .env.p0 和演示包） |
| 备份 | 每小时快照在卷里；另在 farm 用户的 crontab 加一行（目前 farm 没有 crontab）：`40 3 * * * /opt/farm/p0/backup-p0.sh`，每晚打包到 `/opt/farm/p0/backups/`，留 14 份 |

### 步骤（用户确认、#23 / #26 合入之后执行）

1. **部署前检查**：`docker ps`、`free -m`，`curl -fsS https://farm.sensenjoy.cn/preview/journey/v1/healthz` 和 `/v1/healthz`，结果记下来，部署后对比。
2. **备份 Caddyfile**：`mkdir -p /opt/farm/p0/backups && cp /opt/farm/Caddyfile /opt/farm/p0/backups/Caddyfile.before-p0-<时间>`。
3. **准备构建上下文**（farm-dev 合入后的那个提交）：`package.json`、`pnpm-lock.yaml`、`pnpm-workspace.yaml`、`packages/blueprint-core`、`server`、`assets/p0/p0_content.json`，用 tar 传到 devserver（默认）或服务器的 `/opt/farm/p0/src/<sha>/`。
4. **构建（默认在 devserver 上）**：服务器只有 2 核、没有 swap，pnpm install 的内存峰值可能波及 Journey（刘邦审核建议），所以默认在局域网 devserver（192.168.124.53，同为 x86_64）上构建：`docker build -f server/deploy/p0/Dockerfile -t p0-server:<sha> .`，再用 `docker save p0-server:<sha> | gzip | ssh farm@47.76.226.41 'gunzip | docker load'` 传到服务器。服务器上只 load，不构建。只有 devserver 不可用时，才在非高峰时段直接在服务器上构建。
5. **配置并启动**：拷入 `docker-compose.p0.yml`、`.env.p0`；`P0_IMAGE=p0-server:<sha> docker compose -p p0 -f docker-compose.p0.yml up -d`，等健康检查变成 healthy。
6. **改 Caddy 之前先在内网验证**：`docker exec farm-caddy-1 wget -qO- http://p0-demo:3110/v1/healthz`，确认 Caddy 所在的网络能通。
7. **改 Caddy**：把 `Caddyfile.p0.snippet` 插到 `/preview/journey/*` 那一块后面。
   - 必须**原地写回同一个文件**（`cp 新文件 /opt/farm/Caddyfile` 或 `cat > /opt/farm/Caddyfile`），不能用 `mv`，也不能用会换文件的编辑器保存：单文件 bind mount 认的是 inode，换了文件容器里看到的还是旧文件。
   - 先校验 `docker exec farm-caddy-1 caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile`，通过后再 `caddy reload`。reload 不重启容器、不动证书；新配置有错时 reload 会失败，旧配置继续生效。
8. **冒烟**：`P0_BASE=https://farm.sensenjoy.cn/preview/p0 P0_KEY=<口令> server/deploy/p0/smoke.sh`（health、无口令 401、编码路径 401、读状态、一条命令往返、dev 路由 404、UI 上报）。再测一遍第 1 步的 Journey 和 farm healthz，确认和部署前一致。
9. **装 crontab**，最后看 `docker stats`：记下 P0 容器的内存，确认离 256 MB 上限有足够余量（tsx 运行时预计 100–150 MB；如果超过 200 MB，就把上限调到 384 MB 再部署一次），同时确认 Journey 容器的内存和部署前一致。

### 回滚

- **只回滚 P0**：`docker compose -p p0 -f docker-compose.p0.yml down`（不加 `-v`，数据卷保留）→ 用第 2 步的备份原地写回 Caddyfile → validate → reload。几分钟内恢复到部署前的状态。
- **Caddy reload 失败**：旧配置一直在生效，不需要回滚，修好片段再试。
- **部署后 Journey 有异常**：先 `docker compose -p p0 stop`，再查。P0 和 Journey 只在 Caddyfile 那一处有交集。

## 2.5 devserver 试构建与演练（2026-10-08 白天，线上机器未动）

- **构建**：#26 分支（8cd3b67a）在 devserver 上 58 秒建完，镜像 391 MB，`docker save | gzip -1` 后 86 MB，经本机中转传到香港。第一次构建卡在拉基础镜像：devserver 默认的镜像源拉不动 `node:22-alpine`。改从 `docker.m.daocloud.io/library/node:22-alpine` 拉下来并打上 `node:22-alpine` 标签后就通了。这个基础镜像留在 devserver 上作缓存，今晚构建不用再拉。
- **运行演练**：在 devserver 上用临时容器、临时卷按线上配置跑了一遍（`P0_DEV=0`、口令、`P0_TRUST_PROXY=1`、管理端口、256 MB / 0.5 核）：
  - 健康检查 healthy；
  - 别的容器能连到游戏端口 3110；
  - 管理端口 3111 从别的容器连接被拒（只听容器内的 127.0.0.1）；
  - 容器内不带管理密钥返回 401，带密钥能列出玩家、能设体力，容器日志里有一行审计记录；
  - 存档写在 /data 卷里；
  - 内存 52 MB / 256 MB。
- **清理**：试建的镜像、临时容器、临时卷和构建目录都已删掉。

## 2.6 观察员工具（SGODOT-150 手册，q(53)）

**F1 第 4 天回访前设体力（只用一次）**：不走 dev 接口（线上 `P0_DEV=0`，dev 路由根本不注册）。
- 服务端另起一个管理端口 3111，只监听**容器内的 127.0.0.1**。Caddy 和公网只能到 3110，连不到它；同一个 Docker 网络里的其他容器也连不到（演练已验证）。
- 每次调用还要带单独的管理密钥（`P0_ADMIN_KEY`，16 字节随机数，只放在服务器的 `.env.p0` 和本机 `output/p0-deploy/admin-key`，不进 git，不进演示包）。
- 只能改已经存在的玩家，不会凭空建号；体力不能超过上限 + 奖励区。每次修改在容器日志里留一行 `{"admin":"energy","player":…,"from":…,"to":…}`。
- 调用：`server/deploy/p0/deploy-hk.sh energy <玩家 id> 80`。它在本机执行，通过 ssh 到服务器跑 `docker exec p0-p0-1 wget … http://127.0.0.1:3111/admin/energy`，所以要能 ssh 到服务器的人才用得了。

**F2 每次会话后拿报告**：在服务器上执行 `/opt/farm/p0/p0-report.sh <玩家 id> [UTC 日期]`，或在本机执行 `server/deploy/p0/deploy-hk.sh report <玩家 id> [日期]`。输出三部分：
- 这个玩家的会话报告（`tools/p0_session_report.ts`：里程碑分钟、结束体力、每笔体力花费和按法、拒绝次数）；
- 当天的命令计数；
- 当天的拒绝计数。
- 观察日志按 UTC 日期分文件，上海晚上的一场会话落在同一个文件里。
- 依赖 #23（观察日志和报告脚本），所以今晚之前必须合入 #23。如果需要每天定时导出，可以再加一行 crontab（这次不加，等手册定了再说）。

## 2.7 开测前要准备的两样

| 东西 | 从哪里来 | 谁做 |
|---|---|---|
| **预览包**（232 D2，`com.sensen.p0demo`） | 部署完、设备冻结解除后，用 `tools/p0/build_demo_apk.sh --server https://farm.sensenjoy.cn/preview/p0/v1 --key <口令>` 打包。口令在本机 `output/p0-deploy/key`，与服务器 `.env.p0` 一致 | 蒙恬打包，并在自己的模拟器上验证能连上线上服；只发内部，装到测试机由奕星安排的人来做（对外分发需要用户批准） |
| **玩家名字 ↔ 账号 id 对照表** | 每台测试机第一次打开演示包时，客户端会生成玩家 id，存在 `files/p0_player.txt`。装机的人在打开 App 后执行 `adb -s <设备> shell run-as com.sensen.p0demo cat files/p0_player.txt`（演示包是 debug 签名，可以读），把 id 和测试者名字一起记下。兜底办法：`deploy-hk.sh players` 按建号时间列出所有玩家，对照装机顺序也能配上 | 装机的人当场记录；表放在观察员手册指定的位置 |

## 3. 怎么保证不影响 Journey 线上服

1. **不碰 Journey 的任何东西**：`/opt/farm/journey-preview` 下的 compose、镜像、容器、数据库和密钥都不动；不重启 farm 项目的任何容器。
2. **唯一的交集是 Caddyfile**：只在 farm.sensenjoy.cn 块里加一个 `handle_path /preview/p0/*`，Journey 的 `/preview/journey/*` 和兜底路由一字不改。先在内网验证、再 validate、最后 reload；reload 不重启 Caddy，正在进行的连接按旧配置收尾。
3. **资源有上限**：P0 限 256 MB 内存、半个核。服务器可用内存 1.67 GB，Journey app 上限 1 GB、实际约 226 MB。P0 占满也不会挤到 Journey。
4. **没有宿主端口、没有共享数据库**：只通过 Caddy 进来，存档在自己的卷里。
5. **前后对比**：部署前后各测一次 Journey 和 farm 的 healthz；有异常先停 P0。
6. **构建不在服务器上做**：默认在 devserver 上构建，服务器只 `docker load`，没有构建时的 CPU 和内存峰值。

## 4. 部署后不会立刻有的东西

- **地图标记**（`view.map_markers`，分支 `feat/p0-map-markers`）：服务端要额外读 `assets/p0/p0_outposts.json` 和 `assets/ponds/catalog.json`。合入后，Dockerfile 和 `Dockerfile.dockerignore` 要补上这两个文件，镜像重新构建一次；没补之前，地图上只有鱼塘和农场的标记。
- **演示包**：设备冻结解除后，用上面的地址和口令打包，只发内部。

## 5. 要用户确认的事

1. 按上面的方案部署到香港 ECS（镜像默认在 devserver 上构建，再传到服务器）。
2. 给 farm 用户新建一个 crontab，只装 P0 的每晚备份这一行。
3. 部署时间：#23 和 #26 合入后，选非高峰时段。
