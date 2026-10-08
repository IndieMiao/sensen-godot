# P0 演示服务端部署方案：香港 ECS（SGODOT-232 D1，2026-10-08）

**状态：方案，未执行。** 用户已决定部署到 farm.sensenjoy.cn（47.76.226.41），按奕星要求先只读检查、写方案，用户确认后再部署。部署要等 #26 合入（#26 的冒烟脚本要求 #23 先合入）。

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
| 运行配置 | `P0_DEV=0`（不注册 dev 路由）、`P0_TRUST_PROXY=1`（在 Caddy 后面）、`P0_ACCESS_KEYS`（演示口令，本机 `openssl rand -hex 8` 生成，只放 .env.p0 和演示包） |
| 备份 | 每小时快照在卷里；另在 farm 用户的 crontab 加一行（目前 farm 没有 crontab）：`40 3 * * * /opt/farm/p0/backup-p0.sh`，每晚打包到 `/opt/farm/p0/backups/`，留 14 份 |

### 步骤（用户确认、#23 / #26 合入之后执行）

1. **部署前检查**：`docker ps`、`free -m`，`curl -fsS https://farm.sensenjoy.cn/preview/journey/v1/healthz` 和 `/v1/healthz`，结果记下来，部署后对比。
2. **备份 Caddyfile**：`mkdir -p /opt/farm/p0/backups && cp /opt/farm/Caddyfile /opt/farm/p0/backups/Caddyfile.before-p0-<时间>`。
3. **传构建上下文**（farm-dev 合入后的那个提交）：`package.json`、`pnpm-lock.yaml`、`pnpm-workspace.yaml`、`packages/blueprint-core`、`server`、`assets/p0/p0_content.json`，用 tar 经 ssh 传到 `/opt/farm/p0/src/<sha>/`。
4. **构建**：`cd /opt/farm/p0/src/<sha> && docker build -f server/deploy/p0/Dockerfile -t p0-server:<sha> .`。和 farm、Journey 一样在服务器上构建；会占用 CPU 几分钟，选非高峰时段。也可以在局域网 devserver（同为 x86_64）构建，再用 `docker save | ssh docker load` 传上去，服务器 CPU 就不受影响。
5. **配置并启动**：拷入 `docker-compose.p0.yml`、`.env.p0`；`P0_IMAGE=p0-server:<sha> docker compose -p p0 -f docker-compose.p0.yml up -d`，等健康检查变成 healthy。
6. **改 Caddy 之前先在内网验证**：`docker exec farm-caddy-1 wget -qO- http://p0-demo:3110/v1/healthz`，确认 Caddy 所在的网络能通。
7. **改 Caddy**：把 `Caddyfile.p0.snippet` 插到 `/preview/journey/*` 那一块后面。
   - 必须**原地写回同一个文件**（`cp 新文件 /opt/farm/Caddyfile` 或 `cat > /opt/farm/Caddyfile`），不能用 `mv`，也不能用会换文件的编辑器保存：单文件 bind mount 认的是 inode，换了文件容器里看到的还是旧文件。
   - 先校验 `docker exec farm-caddy-1 caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile`，通过后再 `caddy reload`。reload 不重启容器、不动证书；新配置有错时 reload 会失败，旧配置继续生效。
8. **冒烟**：`P0_BASE=https://farm.sensenjoy.cn/preview/p0 P0_KEY=<口令> server/deploy/p0/smoke.sh`（health、无口令 401、编码路径 401、读状态、一条命令往返、dev 路由 404、UI 上报）。再测一遍第 1 步的 Journey 和 farm healthz，确认和部署前一致。
9. **装 crontab**，最后看一眼 `docker stats`。

### 回滚

- **只回滚 P0**：`docker compose -p p0 -f docker-compose.p0.yml down`（不加 `-v`，数据卷保留）→ 用第 2 步的备份原地写回 Caddyfile → validate → reload。几分钟内恢复到部署前的状态。
- **Caddy reload 失败**：旧配置一直在生效，不需要回滚，修好片段再试。
- **部署后 Journey 有异常**：先 `docker compose -p p0 stop`，再查。P0 和 Journey 只在 Caddyfile 那一处有交集。

## 3. 怎么保证不影响 Journey 线上服

1. **不碰 Journey 的任何东西**：`/opt/farm/journey-preview` 下的 compose、镜像、容器、数据库和密钥都不动；不重启 farm 项目的任何容器。
2. **唯一的交集是 Caddyfile**：只在 farm.sensenjoy.cn 块里加一个 `handle_path /preview/p0/*`，Journey 的 `/preview/journey/*` 和兜底路由一字不改。先在内网验证、再 validate、最后 reload；reload 不重启 Caddy，正在进行的连接按旧配置收尾。
3. **资源有上限**：P0 限 256 MB 内存、半个核。服务器可用内存 1.67 GB，Journey app 上限 1 GB、实际约 226 MB。P0 占满也不会挤到 Journey。
4. **没有宿主端口、没有共享数据库**：只通过 Caddy 进来，存档在自己的卷里。
5. **前后对比**：部署前后各测一次 Journey 和 farm 的 healthz；有异常先停 P0。
6. **构建的 CPU 峰值**：在服务器上构建会占几分钟 CPU（farm 和 Journey 一直也是这样构建的）。不想占用服务器 CPU 就走第 4 步的 devserver 构建方案。

## 4. 部署后不会立刻有的东西

- **地图标记**（`view.map_markers`，分支 `feat/p0-map-markers`）：服务端要额外读 `assets/p0/p0_outposts.json` 和 `assets/ponds/catalog.json`。合入后，Dockerfile 和 `Dockerfile.dockerignore` 要补上这两个文件，镜像重新构建一次；没补之前，地图上只有鱼塘和农场的标记。
- **演示包**：设备冻结解除后，用上面的地址和口令打包，只发内部。

## 5. 要用户确认的事

1. 按上面的方案部署到香港 ECS（构建放服务器上，还是放 devserver 上）。
2. 给 farm 用户新建一个 crontab，只装 P0 的每晚备份这一行。
3. 部署时间：#23 和 #26 合入后，选非高峰时段。
