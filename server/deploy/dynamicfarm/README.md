# 动态农场正式服部署材料（C-96）

**状态：只准备，未部署。** 部署由 C-97 的主机操作员按本文执行。主机费用和正式建库开工前，先请所有者本人批准。准备过程中没有登录任何服务器。

**C-101 更新**：本目录的 compose 已改为开放邮箱注册和 Google 登录。正式服重新部署之前仍是只用邀请账号。重新部署要所有者本人同意，部署前先在 `.env` 填好 `SMTP_URL`、`MAIL_FROM`，并确认 Google Cloud 里已有动态农场安卓包的 Android 客户端。

## 部署的是什么

- **服务**：Journey 服务端（`server/`，镜像用 `server/Dockerfile` 构建）。动态农场用到的是地块认领、地块存档、市场（出售）和木匠（领蓝图），接口见 [docs/plans/C-31.md](../../../docs/plans/C-31.md)。Journey 的其它接口仍在，同样要账号。
- **隔离**：独立的 compose 项目 `dynamicfarm`（`compose.yml`），里面是 app 和 PostgreSQL 16。
  - 数据卷 `dynamicfarm_pgdata`，网络 `dynamicfarm_default`，都是本项目自己的。
  - 不加入 P0 或旧 farm 的网络，不挂它们的卷，不连 P0 演示服的数据。
  - 只有 app 在主机回环地址 `127.0.0.1:3160` 发布端口；数据库不发布端口。
- **正式配置**：以下设置写死在 `compose.yml`，`.env` 里写同名项不生效。`ops.sh check` 发现 `.env` 里有这些项会拒绝。
  - 开放邮箱注册（`ACCOUNT_SIGNUP=open`，C-101），邀请账号照常登录。注册后发验证码，找回密码和站外删号也发验证码，所以 `SMTP_URL`、`MAIL_FROM` 是 `.env` 必填项；`ops.sh check` 和 `deploy` 缺它们会拒绝（备份、回滚、恢复不查）。
  - Google 登录开启（C-101）：`GOOGLE_CLIENT_IDS` 写死为正式包实际使用的 OAuth Web 客户端 ID（`project.godot` 的 `sensen/auth/google_web_client_id`，所有者的正式 Google Cloud 项目，870347303349 开头；不是秘密），两边不一致时 `server/test/ops/dynamicfarm.test.ts` 和 `tools/android/test_worker_apk.py` 会失败。手机上能拿到令牌，还要求同一个项目里有包名 `com.gensen.mapfarm`（C-142 改名）加签名证书 SHA-1 的 Android 客户端，这一项由所有者在 Google Cloud 控制台配置（C-172 已建好正式包和内部包 `com.gensen.mapfarm.internal` 的两个客户端）。
  - Apple 登录关闭，返回 503 `APPLE_UNAVAILABLE`。
  - 以后要回到只用邀请账号：把 `ACCOUNT_SIGNUP` 改回 `closed` 再部署，邮箱注册和 Google 首次登录建号都回 403 `SIGNUP_CLOSED`，已有账号照常登录。
  - 没有游客入口（`GUEST_ACCOUNTS=closed`，C-146）：`/v1/auth/anonymous` 对新安装和已有游客一律回 403 `GUEST_CLOSED`，不建游客号；之前发出的游客 token 不再算登录（回 401 `UNAUTHENTICATED`）。已有的游客号按所有者在 Q-265 的选择删除，见下文“删除游客号”。
  - “放弃并重选”关闭：返回 403 `RESELECT_DISABLED`。
  - 不用 QA 固定验证码和 QA 玩家，验证码不写进日志。
- **数据**：从空库开始，不搬内网测试服的数据（C-95#5）。

## 入口路径

建议客户端（C-98）连 `https://farm.sensenjoy.cn/dynamicfarm/v1`，健康检查是 `…/dynamicfarm/v1/healthz`。最终地址以 C-97 实际接入的为准。

入口反向代理归美西迁移方。把下面这段加进 `farm.sensenjoy.cn` 的站点块，放在兜底转发之前：

```
handle_path /dynamicfarm/* {
    reverse_proxy 127.0.0.1:3160
}
```

`handle_path` 会去掉 `/dynamicfarm` 前缀，app 收到的是 `/v1/…`。联机用的 WebSocket（`/v1/online`）走同一条转发。

- **代理在主机上**：连 `127.0.0.1:3160`。app 看到的来源是本项目网段的网关，默认 `172.30.96.1`，`TRUSTED_PROXIES` 填这个地址。
- **代理在容器里**：把代理容器加入 `dynamicfarm_default` 网络，转发到 `dynamicfarm-app-1:3000`，`TRUSTED_PROXIES` 填本项目网段（默认 `172.30.96.0/24`）。

接好以后要确认 app 记下的是玩家的地址，而不是代理的地址：临时在 `.env` 加 `HTTP_LOG=1` 后重启 app，看日志里请求的 `remoteAddress`，确认完删掉。地址不对时，所有玩家会共用一份登录限流额度。

## 必需配置项（只列名字）

值只放在主机的 `.env` 里（0600），不进仓库、不进卡片。模板见 `env.example`。

| 类别 | 名字 |
|---|---|
| `.env` 必填 | `POSTGRES_PASSWORD`、`TOKEN_PEPPER`、`TRUSTED_PROXIES`、`INVITE_EMAIL_DOMAIN`、`PG_IMAGE`、`AGE_RECIPIENT`、`SMTP_URL`、`MAIL_FROM`（后两项 C-101 起必填，含发信密码，只放 `.env`） |
| `ops.sh deploy` / `rollback` 写入，不要手改 | `APP_IMAGE`、`APP_IMAGE_ID`、`GIT_SHA` |
| `.env` 选填 | `DF_HOST_PORT`、`DF_SUBNET`、`DF_BACKUP_DIR`、`DF_BACKUP_KEEP`、`PARCEL_IDLE_RECLAIM_DAYS`（游客地块闲置多少天收回，不写为 30，0 为不收回；C-100）、`ANONYMOUS_SIGNUPS_PER_NETWORK_HOUR` / `ANONYMOUS_SIGNUPS_PER_BLOCK_HOUR` / `ANONYMOUS_SIGNUPS_PER_HOUR`（每小时新建匿名玩家的上限：每个网络、每个 IPv6 /48、合计，不写为 10 / 50 / 1000；C-120）、`PARCEL_STARTER_ZONE`（起步区，不写按配置文件、0 关、1 开；C-130）、`LOGIN_ATTEMPTS_PER_NETWORK_15MIN` / `LOGIN_ATTEMPTS_PER_ACCOUNT_15MIN` / `LOGIN_TRUSTED_NETWORK_DAYS`（密码尝试：每个邮箱每个网络、每个邮箱来自没登录过的网络合计，不写为 10 / 10；登录过的网络记 90 天；C-132）、`MAIL_PER_RECIPIENT_HOUR` / `MAIL_PER_RECIPIENT_DAY` / `MAIL_PER_HOUR` / `MAIL_PER_DAY`（验证信：每个收件邮箱、整个服务，不写为 5 / 10 / 200 / 1000；C-132）、`MIXPANEL_PROJECT_TOKEN` / `MIXPANEL_API_HOST`（产品分析上报，两项都填才开，不填不上报；见下文“产品分析（Mixpanel）”；C-203）、`MIXPANEL_GDPR_TOKEN`（删号时同步删除 Mixpanel 数据用的 GDPR OAuth 令牌，只能和前两项一起填；C-205） |
| `compose.yml` 写死 | `ACCOUNT_SIGNUP`、`GUEST_ACCOUNTS`、`GUEST_WRITES`、`PARCEL_GUEST_WRITES`、`DYNAMIC_FARM_RESELECT`、`GOOGLE_CLIENT_IDS`、`APPLE_BUNDLE_IDS`、`QA_EMAIL_DOMAIN`、`QA_EMAIL_CODE`、`QA_PLAYER_IDS`、`EMAIL_LOG_CODES`、`NODE_OPTIONS`、`DATABASE_URL` |
| 只在操作员一侧，恢复加密备份时用 | `AGE_IDENTITY`（age 私钥文件的路径；私钥不放在服务器上） |

## 主机资源需求

括号里的数字来自本机演练（3 个邀请账号、2 块地），只作参考。

| 项 | 需求 |
|---|---|
| 内存 | app 上限 768 MB（演练常驻约 250 MB），PostgreSQL 上限 512 MB（演练约 90 MB）。合计预留约 1.3 GB |
| CPU | app 上限 1 核；平时空闲，认领和存档都是单条 SQL 事务 |
| 磁盘 | 每个版本的镜像约 0.5 GB，保留当前版和上一版 → 约 1 GB；库（演练 8.4 MB，每块地的存档只有几 KB）；本机备份 14 份（演练每份加密后约 36 KB）。合计预留 5 GB 足够 |
| 端口 | 只占 `127.0.0.1:3160`（`DF_HOST_PORT` 可改） |
| 软件 | Docker 和 compose v2、curl、`sha256sum`、age |

P0 正式服那台机器还剩多少资源没有核过。C-97 开工前先看 `free -m`、`df -h`、`docker stats --no-stream` 和 `uname -m`（镜像要按主机架构构建）。不够时，加主机的费用先请所有者批。

## 首次部署（空库）

1. **构建镜像**：在能构建的机器上、仓库根目录执行，`<sha>` 写要部署的完整提交号。
   ```
   git checkout <sha>
   docker build --platform linux/amd64 -f server/Dockerfile -t dynamicfarm-server:<sha> .
   docker image inspect --format '{{.Id}}' dynamicfarm-server:<sha>      # 记下镜像 ID
   docker save dynamicfarm-server:<sha> | gzip > dynamicfarm-<sha>.tar.gz
   sha256sum dynamicfarm-<sha>.tar.gz                                   # 记下压缩包哈希
   ```
   主机是 arm64 时，把 `--platform` 改成 `linux/arm64`。
2. **建部署目录**：主机上建 `/opt/dynamicfarm`（0700），放 `compose.yml`、`ops.sh`、`env.example`。照 `env.example` 写 `.env`，`chmod 600`，填齐必填项。`POSTGRES_PASSWORD` 用 `openssl rand -hex 24` 生成，`TOKEN_PEPPER` 用 `openssl rand -hex 32` 生成。
3. `./ops.sh check`：核对 `.env` 和 compose 配置。
4. `./ops.sh load dynamicfarm-<sha>.tar.gz <压缩包哈希>`：先核对哈希再 `docker load`，打印出的镜像 ID 要和第 1 步记下的一致。
5. `./ops.sh deploy <sha> <镜像ID>`，依次做这几件事：
   - 核对镜像 ID；
   - 起数据库（容器第一次启动时按 `POSTGRES_DB` 建出空库 `sensen_dynamicfarm`）；
   - 用镜像里的 `schema.sql` 建表；
   - 起 app，等健康检查报出这个提交号。
6. **接入口**：按上面的“入口路径”接好，然后走正式入口跑一遍冒烟：`./ops.sh smoke https://farm.sensenjoy.cn/dynamicfarm/v1`。
7. **建邀请账号**：见下文“邀请账号”。
8. **定时备份**：在主机 crontab 加一行 `30 3 * * * /opt/dynamicfarm/ops.sh backup >> /opt/dynamicfarm/backup.log 2>&1`，照抄即可。cron 的 PATH 只有 `/usr/bin:/bin`，`ops.sh` 开头会自己补上 `/usr/local/sbin`、`/usr/local/bin`、`/usr/sbin`、`/sbin`、`/snap/bin`，装在这些地方的 docker（compose 是它的插件）和 age 都找得到。装在别处时，在 crontab 里这一行上面加一行 `PATH=<docker 和 age 所在目录>:/usr/bin:/bin`。异地副本交给主机现有的备份方案（美西的备份归迁移方），复制的是 `backups/` 下的 `*.dump.age` 和同名的 `*.counts`。

`ops.sh` 的每一步都单独运行，出错就停下，不会自动回滚。会改东西的步骤（`load`、`deploy`、`init-db`、`rollback`、`backup`、`restore`）互斥：同时只能跑一个，另一个直接报错退出（例如定时备份撞上手工部署）。步骤被强行杀掉留下的锁目录 `.ops.lock`，确认没有 `ops.sh` 在跑后手工删掉。

## 升级

先 `ops.sh load`，再 `ops.sh deploy <新提交号> <新镜像ID>`。库里已有数据时，部署前会自动备份一份，标签是 `pre-<新提交号前 12 位>`。表结构只加不改（`schema.sql` 全是 `IF NOT EXISTS`），app 启动时也会再执行一遍。

## 回滚

- **只换回镜像**：`./ops.sh rollback`，回到部署当前版本那一刻正在跑的那一版（按 `releases.log`，deploy 和 rollback 记录都算；例如 A → B → 回滚到 A → C，再回滚回到 A，不会回到 B）；也可以写明 `./ops.sh rollback <提交号>`。已经回滚过一次时（最后一条记录是回滚），必须写明提交号，脚本不猜。新版加的表和列会留着，旧版不读它们，照常工作。
- **连数据一起回到升级前**：
  ```
  AGE_IDENTITY=<私钥文件> ./ops.sh rollback <旧提交号> --restore backups/dynamicfarm-<时间>-pre-<新版前12位>.dump.age
  ```
  这份备份之后写入的数据（新的认领、存档）都会丢，先约好停服时间。恢复前，脚本会再把当前的库备份一份，标签是 `pre-restore`。
- **脚本不可用时**：把 `.env` 里 `APP_IMAGE`、`APP_IMAGE_ID`、`GIT_SHA` 三行改回上一版（`releases.log` 里有），再执行 `docker compose -f compose.yml --env-file .env up -d --no-deps app`。

## 备份与恢复

`./ops.sh backup [标签]` 依次做这几件事：

1. `pg_dump -Fc`。
2. 在同一个数据库实例里建临时库 `sensen_dynamicfarm_verify`，真恢复一遍，从恢复出来的库算行数和指纹，写进同名的 `.counts`，然后删掉临时库。指纹包括账号、玩家、认领的条数，以及账号和地块存档的 md5。
3. 用 `AGE_RECIPIENT` 加密成 `.dump.age`，删掉明文（备份里有邮箱和密码哈希，一律加密）。中途失败时，写了一半的文件在退出时删掉。
4. 不带标签的（定时备份）本机保留最近 `DF_BACKUP_KEEP` 份（默认 14）。带标签的（部署前 `pre-<提交号>`、恢复前 `pre-restore`、手工加的标签）不参与轮换，回滚时要用；确认升级没问题、不再需要后，连同同名 `.counts` 手工删掉。

所有文件都是 0600，目录是 0700。

`AGE_IDENTITY=<私钥文件> ./ops.sh restore <备份> --confirm-drop` 依次做这几件事：

1. 读出 `.counts`，把备份解密到备份目录里的临时文件；停 app。
2. 先把当前的库备份一份（标签 `pre-restore`）。这一份不做轮换，不会删掉正要恢复的备份。
3. 删库、重建。
4. `pg_restore`。
5. 核对行数和指纹，必须和 `.counts` 完全一致，不一致就让 app 保持停止。
6. 起 app，等健康检查通过。

解密出来的明文在脚本退出时删掉。私钥只在恢复时临时带到主机，用完即删。

## 邀请账号

邀请账号是普通的邮箱加密码账号。客户端在现有登录面板用“邮箱 + 密码”登录（`/v1/auth/email/login`）。邮箱形如 `df-k3mq7hxa@<INVITE_EMAIL_DOMAIN>`，只当登录名用，不收信。密码形如 `k3mq-7hxa-pt2d-wz9e`，不含容易看错的字符。库里只存密码的 scrypt 哈希。

| 操作 | 命令（在操作员自己的机器上执行） |
|---|---|
| 建一批 | `ssh <主机> '/opt/dynamicfarm/ops.sh invites create --count 20 --batch wave-1' > <受控目录>/dynamicfarm-wave-1.csv` |
| 列出（不含密码） | `ssh <主机> '/opt/dynamicfarm/ops.sh invites list [--batch wave-1]'` |
| 忘了密码，重置 | `ssh <主机> '/opt/dynamicfarm/ops.sh invites reset --email <邮箱>' > <受控目录>/reset.csv`（同时作废这个账号的全部登录令牌） |
| 停用 | `ssh <主机> '/opt/dynamicfarm/ops.sh invites disable --email <邮箱>'`（不能再登录，登录令牌作废；地块和存档保留） |

重置和停用之后，旧令牌发出的 HTTP 请求立即被拒。工具在 app 进程外运行，关不掉已经连着的联机（WebSocket）连接：它会保持到对方断线重连；要立刻断开，就重启 app（`docker compose -f compose.yml --env-file .env restart app`）。

- **输出位置**：`create` 和 `reset` 输出的 CSV（`email,password,batch`）含密码，只写到重定向的地方。标准输出是终端时，`ops.sh` 在连库之前就拒绝。不要在服务器上落文件，不要贴进卡片、仓库或聊天。
- **受控存储**：所有者指定的密码库或加密目录。导入之后删掉本地的 CSV。
- **发给玩家**：由所有者本人发（C-95#5）。
- **直接调工具**：`tools/invite_accounts.ts` 也可以直接用。用 `--out <新文件>` 时，文件必须是新建的（0600），而且不能在 Git 工作区里。

## 删除游客号

所有者在 Q-265 选了删除所有游客号和它们的地块、进度（C-146）。游客号是 `players` 里没有账号（`user_id` 为空）、`install_key_hmac` 是安装密钥 HMAC（64 位十六进制）的行；邮箱账号、邀请账号和预置农场的系统玩家都不会被选中。一并删除的是这些玩家的登录令牌、Journey 农场（含建农场记录、命令记录、访客快照）、联机座位、地块和地块存档、收回地块的存档。库里出现别的表引用这些表时，工具拒绝运行。

| 步骤 | 命令（在主机部署目录） |
|---|---|
| 预演（只看不删） | `./ops.sh guests plan`：列出每张表会删的条数和保留的账号玩家数，不改数据 |
| 删除 | `./ops.sh guests purge --confirm-delete` |
| 恢复 | `AGE_IDENTITY=<私钥文件> ./ops.sh guests restore <backups/dynamicfarm-guests-….txt.age> --confirm-restore` |

`purge` 的顺序，任何一步失败都停下，什么都不删：

1. 整库备份（标签 `pre-guest-purge`，同“备份与恢复”，试恢复核对后加密）。
2. 游客数据单独备份到主机上的明文临时文件，`verify` 核对格式、SHA-256 和每张表的条数。
3. 用 `AGE_RECIPIENT` 加密成 `backups/dynamicfarm-guests-<时间>.txt.age`。
4. 把同一份备份交给工具删：工具锁住这些表，重新取一遍游客数据，必须和备份逐字节相同才删（备份之后有人登录、存档就不删，重跑一次即可）；删完核对每张表删掉的条数等于备份条数、账号玩家和系统玩家一条没少，不对就整体回滚。
5. 删掉明文临时文件，只留 `.age`。

恢复把备份里的行原样插回，再核对和备份逐字节相同才提交；那块地已经被别人认领等冲突时整体回滚，库保持原样。整库备份 `pre-guest-purge` 仍可按“备份与恢复”整体恢复。

工具也可以直接用（`tools/guest_purge.ts plan | backup --out <新文件|-> | verify | purge | restore`，只连 `DATABASE_URL`），`purge` 和 `restore` 要写 `--confirm-database <库名>`。正式服上实际删除随正式服部署（H-71）另行确认，由主机操作员执行。

## 产品分析（Mixpanel）

C-203。服务端把玩家的关键行为批量上报到 Mixpanel，游戏客户端不上报。默认关闭：`.env` 里 `MIXPANEL_PROJECT_TOKEN`、`MIXPANEL_API_HOST` 都空着时不建队列、不发任何外部请求；只填一项或地址不是 Mixpanel 的地区接口，app 拒绝启动。启动日志最后的 `analytics=` 显示 `off` 或接口主机名。事件和属性清单见 `docs/plans/C-203.md`。

开启前必须先完成：所有者建好 Mixpanel 项目（数据存放地区建项目后不能改）、隐私政策加上分析服务商、Google Play 数据安全表单补“应用活动”。之后：

1. 在 `.env` 填 `MIXPANEL_PROJECT_TOKEN`（项目设置里的 Project Token）、`MIXPANEL_API_HOST`（美国 `https://api.mixpanel.com`、欧盟 `https://api-eu.mixpanel.com`、印度 `https://api-in.mixpanel.com`，按项目地区）和 `MIXPANEL_GDPR_TOKEN`（删号同步删除用，见下文），然后 `ops.sh deploy` 或重启 app。
2. 看启动日志的 `analytics=` 是接口主机名、`analytics_delete=on`；在 Mixpanel 的 Events 页面能看到新的 `login` 等事件。日志里出现 `[analytics]` 开头的行表示某批没发出去（重试一次后已丢弃，玩家不受影响）。
3. 可选：把已有注册补进去，方便从开服第一天算留存。在部署目录里先只数：`docker compose -f compose.yml --env-file .env exec -T app ./node_modules/.bin/tsx tools/mixpanel_backfill_signups.ts`，确认数量后加 `--send` 再跑一次（可加 `--since YYYY-MM-DD`）。重跑或与实时上报重叠都不会重复计数。

删号同步删除（C-205）：玩家删号后，服务端丢掉队列里这个人还没发出的事件，并向 Mixpanel 的 GDPR 删除接口（与上报同地区：`mixpanel.com`、`eu.mixpanel.com`、`in.mixpanel.com` 的 `/api/app/data-deletions/v3.0/`）提交删除任务，Mixpanel 最长 30 天内删完。这个接口要另一个凭据 `MIXPANEL_GDPR_TOKEN`：项目所有者或管理员在 Mixpanel 右上角头像 → Profile & Preferences → Data & Privacy 生成的 GDPR OAuth 令牌，有效期一年，到期前生成新的、换进 `.env` 并重启 app。启动日志 `analytics_delete=on/off` 显示是否已配。没配或提交失败时删号照常成功，日志记一行（`MIXPANEL_GDPR_TOKEN not set ...` 或 `Mixpanel deletion for user <编号> not requested ...`，含用户编号），由人在 Mixpanel 后台按该编号补删；成功时记 `Mixpanel deletion requested for user <编号>, task <任务号>`。

关停时限（C-205）：app 关停时最后一次发送（含删除请求）最多等 5 秒，超时丢弃剩下的并记 `[analytics] shutdown limit ...`，保证在 `docker stop` 的 10 秒宽限期内退出。

关闭：把两项（和 `MIXPANEL_GDPR_TOKEN`）清空后重启 app。已经发到 Mixpanel 的数据要在 Mixpanel 后台删。

## 冒烟

`./ops.sh smoke [--invite] [<入口地址>]` 默认在 app 容器里打它自己的端口。逐项检查：

- 健康检查通过，运行的是 `.env` 里写的提交号；
- 邮箱注册已开放：用一个太短的密码试注册，应回 400 `WEAK_PASSWORD`（不建号、不发信）；
- Google 登录已开启：用一个不成形的令牌试登录，应回 401 `GOOGLE_TOKEN_*`（不去 Google 取公钥）；
- 游客入口已关：用一个随机安装密钥试游客登录，应回 403 `GUEST_CLOSED`（不建号）；
- 不登录不能认领、不能存档（401 `UNAUTHENTICATED`）。

带 `--invite` 并从标准输入给一行 `email,password` 时，再加两项：邀请账号能登录，“放弃并重选”被拒。例如 `ssh <主机> '/opt/dynamicfarm/ops.sh smoke --invite' < 冒烟账号.csv`。

冒烟不建号，也不留游客玩家行（C-146 之前每次冒烟会留下一个，它们由下文“删除游客号”一并删掉）。正式服上的冒烟不认领地块，因为认领会永久占用一块地。认领和存档只在隔离环境里验证，见下文“隔离演练”。

## 隔离演练

`server/deploy/dynamicfarm/rehearse-local.sh` 在本机走完整套流程，不连服务器，也不需要 Docker：

- 用临时的 PostgreSQL 16 代替数据库容器；
- 用提交的源码快照代替镜像；
- 用一个替身代替 docker 命令，替身只支持 `ops.sh` 用到的那几种调用；
- `ops.sh` 原样运行。

走一遍的顺序：

1. 空库部署；
2. 只读冒烟；
3. 建邀请账号，确认输出到终端时被拒；
4. 两个邀请账号认领、进入、存档并读回；
5. 备份；
6. 删库；
7. 恢复，核对指纹，读回的存档和备份前逐字节相同；
8. 部署下一版（模拟迁移：加一列）；
9. 回滚；
10. 再部署下一版，然后带恢复回滚。

需要的环境：

- 工作区干净；
- 已执行 `pnpm install`；
- 本机有 PostgreSQL 16 和 age。

结果记录在 [docs/plans/C-96.md](../../../docs/plans/C-96.md)。

演练没有覆盖这几项，第一次在主机上执行时要看：

- 真实的 `docker build` / `save` / `load`；
- compose 解析；
- 入口代理和 `TRUSTED_PROXIES`。
