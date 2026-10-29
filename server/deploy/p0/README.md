# P0 演示服务端上线准备（SGODOT-232 D1，2026-10-08）

**状态：只准备，未部署。** 部署、改线上 Caddy、在任何服务器上构建镜像，都要先经用户批准。香港 ECS 原定 10-04 到期；团队记录里 9-29 开了按月自动续费（10-04 起从余额扣），但扣费是否成功没有确认。准备过程中没有登录任何服务器。

## 服务端加了什么

都在 `server/src/p0/guard.ts` 和 `server/tools/p0_server.ts`，本地试玩不设环境变量时行为不变。

| 项 | 做法 | 环境变量 |
|---|---|---|
| 演示口令 | `/v1/p0/*` 的每个 HTTP 请求都要带 `x-p0-key`，不在名单里返回 401 `bad_key`。按 Fastify 实际匹配到的路由判断，`/v1/%70%30/state` 这类编码路径同样要口令（刘邦审核 #26）。`/v1/healthz` 不需要口令，给容器健康检查用。据点房间的 WebSocket（`/v1/p0/online`，#14）在原始 upgrade 事件上建立，不经过这些钩子，由它自己按同一份口令校验（后裔 641905fd） | `P0_ACCESS_KEYS=k1,k2`（不设 = 不校验，本地试玩） |
| 限流 | 两道：每个地址每分钟总数（不管它报什么玩家 id），再按「地址 + 玩家 id」每分钟计数；超出返回 429 `rate_limited`。只作用于 `/v1/p0/*`。在 Caddy 后面要打开 `P0_TRUST_PROXY=1`（只信任回环和私网上的代理，取 Caddy 写入的那个地址），否则所有请求的地址都是 Caddy；直接发布端口时不要打开（客户端能伪造 X-Forwarded-For） | `P0_RATE_PER_IP`（默认 2000）、`P0_RATE_PER_MINUTE`（默认 600）、`P0_TRUST_PROXY` |
| 请求体上限 | 32 KB，超出返回 413 | — |
| dev 路由 | `P0_DEV=0` 时不注册（时钟快进、重置存档等） | 镜像里固定 `P0_DEV=0` |
| 存档快照 | 每小时把存档复制成 `snapshots/p0-state-YYYYMMDDHH.json`，保留最近 48 份 | `P0_SNAPSHOT_DIR`（默认存档旁的 `snapshots/`） |
| 健康检查 | `/v1/healthz` 返回内容版本、玩家数、运行秒数 | — |
| 观察日志 | S7（PR #23）合入后生效，写到 `/data/events` | `P0_EVENT_DIR` |
| 强制更新 SYS-UPDATE | `server/src/p0/gate.ts`。请求头 `x-p0-version`（演示包的 versionCode，`build_demo_apk.sh` 写进 `demo_server.json`）低于最低版本时，`/v1/p0/*` 和据点 WebSocket 握手都返回 426 `{"ok":false,"code":"update_required","url"}`。不带这个头（桌面、编辑器、测试包）一律放行。**没有下载地址就不启用下限**（q(74)）：管理接口设下限却没有地址回 400 `need_url`；启动时只配了 `P0_MIN_VERSION` 没配地址，只打一行 `min_version_without_update_url` 警告，不拦人，healthz 的 `min_version` 显示 0。运行中用 `deploy-hk.sh min-version <versionCode> [url]` 改 | `P0_MIN_VERSION`（0 或不设 = 不拦）、`P0_UPDATE_URL` |
| 维护 SYS-MAINT | 打开时 `/v1/p0/*`（含 presence、telemetry）和据点 WebSocket 握手都返回 503 `{"ok":false,"code":"maintenance","back_at"}`，back_at 是 UTC ISO，不知道就不写。顺序：口令 401 → 更新 426 → 维护 503 → 限流（§10.7.1 更新优先）。`/v1/healthz` 和管理口不受影响，healthz 多返回 `maintenance` 和 `min_version`。运行中用 `deploy-hk.sh maint-on [回来时间]` / `maint-off`；设置写在数据卷的 `gate.json`，容器重启后仍保持。环境变量只能更严：最低版本取两者较大者，`P0_MAINT=1` 时维护一直开着。维护期间 smoke 会失败，先 `maint-off` 再跑 | `P0_MAINT=1`、`P0_MAINT_UNTIL` |

存档是一个 JSON 文件，存全部玩家，每条命令写一次（先写临时文件再改名）。演示规模够用；人数上来要换数据库，不在这次范围内。

## 文件

| 文件 | 用途 |
|---|---|
| `Dockerfile` | P0 镜像。构建上下文是仓库根，镜像里只有服务端代码和启动时要读的数据：`assets/p0/p0_content.json`、据点表 `assets/p0/p0_outposts.json`、鱼塘清单 `assets/p0/p0_ponds.json`（每口塘的地图点位，SGODOT-270）、据点房间校验外观用的 `assets/avatar/` 下三个清单（SGODOT-304 起不再经由 Journey 的 `assets/farm/data/regions.json`）；以非 root 用户运行；数据在 `/data` 卷 |
| `Dockerfile.dockerignore` | 这个镜像专用的放行清单（BuildKit 优先读它，不读根目录给 farm 用的 `.dockerignore`，那份没放行 `assets/p0`）。不会打进演示包的 `demo_server.json` |
| `docker-compose.p0.yml` | 香港 ECS：加入 farm 项目的网络 `farm_default`，由 farm 的 Caddy 转发；内存上限 256 MB |
| `docker-compose.devserver.yml` | 局域网 devserver：同一个镜像直接发布到 3150 端口，不经 Caddy |
| `Caddyfile.p0.snippet` | 要并入线上 Caddyfile 的一段：`/preview/p0/*` 去掉前缀后转给 `p0-demo:3110`（容器在 farm_default 上的别名） |
| `deploy-hk.sh` | 香港部署的逐步脚本（preflight / build / transfer / backup-caddy / up / verify-internal / caddy / smoke / crontab / stats / rollback），每步单独运行 |
| `smoke.sh` | 冒烟：healthz、无口令 401、带口令读状态、一条命令往返、dev 路由 404、UI 上报。用一次性玩家 id `smoke-<时间戳>`，不碰真实玩家 |
| `backup-p0.sh` | 每晚把 `/data` 卷打包（排除写了一半的 `*.tmp`），先写成 `.part`，校验包里的 `p0-state.json` 能解析后才替换当天那份（校验不过的另存为 `p0-data-<日>-<时>.bad.tgz` 待查，不会覆盖好包，也不上传），本机保留 14 份；有 `/opt/farm/p0/.env.backup` 时再用 age 公钥加密、以只写子账号传到备份桶的 `p0/` 前缀（SGODOT-304 ③）。按 compose 标签找卷（项目名 `P0_PROJECT`，默认 p0），不写死卷名 |

## 目标 A：香港 ECS（首选）

> 2026-10-08 用户决定部署到这台机器。只读检查的结果和逐步部署方案见 `docs/qa/p0-hk-deploy-plan-2026-10-08.md`，以那份为准；下面是准备阶段的通用步骤。


地址 `https://farm.sensenjoy.cn/preview/p0/v1`，客户端 base URL 就填它。和 farm、Journey 共用一台 2C4G、一个 Caddy，P0 是独立的 compose 项目 `p0`，不改 farm 的 compose。

批准后的步骤（都在 ECS 上，目录 `/opt/farm/p0/`）：

1. **先由用户确认 ECS 还在**（续费），不要为确认而登录改动。
2. **构建镜像**：本机没有 Docker，沿用 `deploy.sh` 的做法，在服务器上构建：
   ```sh
   tar -C <repo> --exclude node_modules --exclude '.env*' -czf - \
     package.json pnpm-lock.yaml pnpm-workspace.yaml packages/blueprint-core server assets/p0/p0_content.json \
     assets/p0/p0_outposts.json assets/p0/p0_ponds.json assets/ponds/catalog.json \
     assets/avatar/parts_manifest.json assets/avatar/demo_denylist.json assets/avatar/npc_only.json \
     | ssh "$HOST" 'mkdir -p /opt/farm/p0/src && tar -C /opt/farm/p0/src -xzf -'
   # Near you（q(188) ①）：Dockerfile 里 ARG DBIP_MONTH 那个月份的 DB-IP City Lite，放进构建目录的 dbip/
   # （平时由 deploy-hk.sh build 从 devserver 的 ~/p0-cache/dbip 拷；DB-IP 网站只留最近两个月，过期从缓存或 OSS 备份取）
   ssh "$HOST" 'mkdir -p /opt/farm/p0/src/dbip'
   scp dbip-city-lite-<YYYY-MM>.csv.gz "$HOST":/opt/farm/p0/src/dbip/
   ssh "$HOST" "cd /opt/farm/p0/src && DOCKER_BUILDKIT=1 docker build -f server/deploy/p0/Dockerfile -t p0-server:<sha> ."
   ```
   构建时校验这份文件的 sha256（Dockerfile 里的 `DBIP_SHA256`），对不上就停。
   服务器上 Docker 版本低于 23 时，要确认 BuildKit 打开，否则 `Dockerfile.dockerignore` 不生效、构建会缺 `assets/p0`。
3. **口令文件** `/opt/farm/p0/.env.p0`（不入库，`chmod 600`）：`P0_ACCESS_KEYS=<每批演示一个>`。
4. **启动**：`P0_IMAGE=p0-server:<sha> docker compose -p p0 -f docker-compose.p0.yml up -d`。固定用 `-p p0`：备份脚本按项目名 p0 的标签找数据卷（换了项目名就设 `P0_PROJECT`）。
5. **Caddy**：线上配置已经和仓库里的 `server/deploy/Caddyfile` 不同：Journey 预览服 `/preview/journey/` 由 `/opt/farm/journey-preview` 的 compose 项目 `sensen-journey-preview` 提供，部署记录里有单独的 `Caddyfile.preview`（docs/qa/partner-connectivity-2026-09-08.md）。所以动手前先在服务器上看清两件事：Caddy 实际加载的是哪个配置文件，Journey 预览服是怎么接进 Caddy 所在网络的。P0 按同样的方式接：把 `Caddyfile.p0.snippet` 并进那个文件的 `farm.sensenjoy.cn` 块（放在兜底的 `reverse_proxy app:3000` 之前）；如果 Caddy 不在 `farm_default` 网络上，就把 `docker-compose.p0.yml` 的网络名改成 Caddy 所在的网络。**不要用仓库版本覆盖线上文件。** 改之前先备份；用 `docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile` 热加载，不重建 caddy 容器（证书在 caddy_data 卷里，重建会重新申请）。Journey 预览服的 compose 需要 root（`/opt/sensen-voice/private/` 只有 root 可读），P0 自己的 compose 用 farm 用户即可。
6. **冒烟**：`P0_BASE=https://farm.sensenjoy.cn/preview/p0 P0_KEY=<口令> server/deploy/p0/smoke.sh`。
7. **演示包**：`tools/p0/build_demo_apk.sh --server https://farm.sensenjoy.cn/preview/p0/v1 --key <口令>`。
8. **备份**：把 `backup-p0.sh` 放到 `/opt/farm/p0/`，crontab 加 `40 3 * * * /opt/farm/p0/backup-p0.sh`。异地加密：在 `/opt/farm/p0/.env.backup`（600，不进仓库）写 `AGE_RECIPIENT`、`OSS_BUCKET`、只写子账号的 `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`；没有这个文件就只留本机那份。私钥不放在香港。

回滚：`docker compose -p p0 -f docker-compose.p0.yml down`（不加 `-v`，数据卷保留），删掉 Caddy 里那一段再热加载。farm 和 Journey 不受影响。

## 目标 B：局域网 devserver（备选）

`192.168.124.53`（Ubuntu 24.04 + Docker，SSH 免密）。地址 `http://192.168.124.53:3150/v1`，只有同一 Wi-Fi 下的设备能连。

批准后：同样传上下文并构建，然后 `P0_IMAGE=p0-server:<sha> docker compose -p p0 -f docker-compose.devserver.yml up -d`，冒烟用 `P0_BASE=http://192.168.124.53:3150`。HTTP 明文在演示包上可用（D2 模拟器用 `http://10.0.2.2` 连通过）。

## 目标 C：美西（10-28 晚迁移之后，`--target us`）

10-28 20:33 切流起 P0 的权威服务在美西 `43.110.146.219`（由迁移方运维；约定见 pm/migration/p0-migration-decision-2026-10-27.md 的「E 答复」第 8 项）。客户端地址不变，仍是 `https://farm.sensenjoy.cn/preview/p0/v1`，由 farm 的入口转发到美西。

- 每个步骤前加 `--target us`，例如 `server/deploy/p0/deploy-hk.sh --target us up <sha>`。不加就是香港，行为和原来逐字一致。
- 登录用迁移方的 ssh_config（`P0_US_SSH_CONFIG`，主机 `P0_US_HOST`，默认 `tgt-us-p0`）。镜像压缩包的暂存目录默认 `/srv/migration-data/services/p0/staging`（首次 transfer 建成 0700，压缩包 0600），用 `P0_US_STAGING` 改，必须是绝对路径，不能在正式数据目录下。
- 美西的设置写在迁移方维护的 `compose.production.json`（权限 600）里，服务名和容器名都是 `p0-p0-1`，镜像是写死的字符串。`up` 只改 `services["p0-p0-1"].image` 这一处：改前留一份带日期的副本；这个字符串在文件里必须只出现一次；改完重新解析，除这个字段外必须和原来完全一样；保留权限，原子替换。然后只执行 `docker compose -f …/compose.production.json up -d --no-deps p0-p0-1`。不写 .env / .env.p0，也不生成密钥。`up` 只接受 transfer 核过的 tag。
- 美西的 X-P0-Release / X-P0-Image-Config 响应头是迁移方的 Caddy 给的。`up` 完会提示把新 tag 和 config ID 报给迁移方，由他们同步。
- `transfer` 先在本机做压缩包并记 SHA-256，传到美西后再核一次；美西 docker 报出的镜像 ID 必须等于压缩包里的 config 摘要。两个 ID 都记进 image.txt。
- `up` 之后会核对 `/data` 挂的是正式数据目录，不是就报错。
- `backup-caddy`、`caddy`、`crontab`、`rollback` 只有香港有。美西的 Caddy、备份和转发归迁移方。
- 离线自检：`server/deploy/p0/check-deploy-target.sh`。它用桩代替 ssh / scp / curl，不连任何机器；先比对旧脚本和新脚本在香港各步骤的输出和远端命令（逐字相同），再打印美西各步骤会发出的命令。

## 两个目标的差异

| | 香港 ECS | 局域网 devserver |
|---|---|---|
| 客户端地址 | `https://farm.sensenjoy.cn/preview/p0/v1` | `http://192.168.124.53:3150/v1` |
| 谁能连 | 任何网络（靠口令挡） | 只有同一局域网 |
| TLS | 有（farm 的 Caddy 证书） | 无，HTTP 明文 |
| 反向代理 | 并入线上 Caddyfile，要改线上配置 | 不经代理，直接发布端口 |
| 对线上的影响 | 与 farm、Journey 共用机器和 Caddy；P0 限 256 MB 内存 | 无 |
| 风险 | ECS 可能已到期；改 Caddy 有误会影响 farm/Journey 的转发 | 演示必须在办公室网络；机器重启后容器靠 `restart: unless-stopped` 自启 |
| 备份 | `backup-p0.sh` 每晚打包，另有每小时快照 | 每小时快照；需要时同样装 `backup-p0.sh` |
| 适合 | 异地演示、外部网络 | 办公室内部演示，零线上风险 |

## 安全提醒

- 口令和 Mapbox token 都打在 APK 里，解包就能读到。口令只是挡随手乱连，不当密码用：每批演示单独发一个，演示后从 `P0_ACCESS_KEYS` 删掉并重启容器；APK 不外发（AGENTS.md：对外只发 Journey）。
- 玩家 id 是客户端自报的，所以限流先按地址算总数，换 id 绕不过去；真正的门槛仍是口令。
- 观察日志只记随机玩家 id，不记 IP、口令和现实位置。

## 本机验证（2026-10-08）

- 单元测试 `server/test/p0/p0_guard.test.ts`：口令、限流、413、快照轮换、dev 路由关闭。
- 本机用上线配置起服务（`P0_DEV=0`、两个口令、端口 3153，按记录的 PID 关闭）：`smoke.sh` 全部通过；40 KB 请求体返回 413；healthz 正常。
- 镜像没有构建过（本机没有 Docker）。批准后先在 devserver 上构建并跑冒烟，再考虑 ECS。
