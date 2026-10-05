# 真实账户体系 + 全球开放城市 + 新用户自由选城：方案（2026-09-28）

> **资料范围（2026-10-05 清理）**：当前玩法、数值、操作与分期统一以 [玩法方案 v2](gameplay-plan-v2-2026-10-02.md) 为准。保留账号、删号、全球城市技术与位置处理边界；旧实施批次和设备状态仅为历史记录，玩法、首启与旅行按 v2。

> 状态：需求方案，五项决策已于 2026-09-28 拍板（见 §5），未开发。当前处于 pitch / 测试阶段。Plane 总卡见 SGODOT「【需求】真实账户体系 + 全球开放城市 + 自由选城」。
> 三条需求来自 2026-09-28 用户口述：1) 真正的用户/账户体系；2) 不再只限上海、洛杉矶，全面开放全球；3) 新用户自由选城，默认定位到所在城市。

## 0. 核查到的现状（本次逐项确认）

### 0.1 身份：线上仍是匿名安装身份
- `server/src/http/auth.ts`：客户端首装生成 128 位随机 `install_key`，服务端只存 HMAC，换 opaque token（最多 5 个活跃 token、90 天闲置失效）。`players` 表只有 `install_key_hmac`，没有邮箱或任何账号字段。
- 后果已经发生过：`docs/qa/fresh-install-geography-2026-09-23.md` 记录 Joey 卸载重装后成了新身份，旧农场（版本 335、58 块地）还在库里但找不回。
- 账户体系**已有设计并做过一版实现**，但在另一条分支上：
  - 设计：`docs/superpowers/specs/2026-08-30-overseas-refactor-research.md` §4.1，定 Firebase Authentication（邮箱密码 + 验证邮件、Sign in with Apple、Google；不做短信），账号主键用自有 user id。
  - 实现：分支 `feat/next-feature`（本机 checkout `../sensen-godot-v2-next`，最后提交 2026-09-08）。客户端 `modules/net/firebase_auth.gd`、`modules/net/auth_session.gd`、`scenes/app/login_page.gd`、`scenes/app/age_gate_page.gd`；服务端 `server/src/http/accounts.ts`、`firebase_token.ts`，表 `users` / `user_identities` / `account_deletions`，接口 `POST /v1/auth/firebase`、`GET /v1/users/me`、`GET /v1/users/me/export`、`DELETE /v1/users/me`、`POST /v1/account/delete`。
  - Plane：SGODOT-67 B1 登录页（Done）、SGODOT-76 D2 账号服务（In Progress，剩 Apple revocation 与 Web 删号页对接）、SGODOT-88 A1 会话/ApiClient（Done）、SGODOT-57 R2 年龄门（Done）、SGODOT-58 R3 同意（Done）、SGODOT-56 R1 删号双入口（In Progress）、SGODOT-96 C1 原生 Apple/Google 登录插件（Backlog）。
  - 分叉程度：与 farm-dev 的共同祖先是 2026-09-05 的 a7426ef；next-feature 之后 102 个提交，farm-dev 之后 45 个提交，**32 个文件两边都改过**（`server/src/http/app.ts`、`server/src/db/schema.sql`、`modules/ui/app_router.gd`、`scenes/map_poc/map_poc.gd`、`modules/net/api_client.gd` 等）。schema 注释原话：「players 是农场分支的匿名玩家，两者暂不关联」。

### 0.2 地区：只有两城是"目录"限制，不是地理能力限制
- `assets/farm/data/regions.json` 只有 `shanghai`、`los_angeles` 两条（`placement_bounds`、`timezone`、`center`、3 个候选蓝图）。
- 服务端按这份目录校验：建农场 `LOCATION_OUTSIDE_REGION`（`farm_location.ts`）、`/v1/nearby` 与 `/v1/ponds` 按 `region_id` 查、`ponds/catalog.ts` 硬编码 `['los_angeles','shanghai']`、`party_travel.ts` 用 regions 的时区表、农场时钟 `player_day_id` 用 `region.timezone`（luxon）。
- 客户端按同一目录：`FarmRegions.load_default()`、`CityMapData.has_city()`（只认 `assets/map/cities/<id>.json`）、`landmark_scenes.gd` 的 `los_angeles` 特判、`map_poc.gd` 的 `_in_la` 与 LA 压测夹具、`city_map_view.gd` 默认文案 "Los Angeles"。
- **地理生成本身已经是全球的**：`server/src/geography/osm.ts` 按经纬度查 Overpass（路网、地类、岸线），`land_cover.ts` 按经纬度取 ESA WorldCover 2021 全球栅格；Mapbox 底图全球可用。所以"开放全球"的核心工作是把城市从静态目录变成运行时实体，以及给没有人工内容的城市做降级。
- 每城人工内容目前有：概览视角、5 个地标（含上海/LA 专属美术、Griffith 3D 场景）、3 个居民 NPC 锚点（nursery / bistro / courtyard，七日 Journey 依赖它们）。

### 0.3 选城：已有"手选优先 + 一次定位推荐"
- `scenes/city_select/city_select.gd`：首启列出 regions 里的城市；「Use my current city」只请求一次前台大致定位，`nearest_region_id` 取最近城市中心；3 秒超时回手选。已有农场的用户跳过选城直接落在自己农场。
- 保留的既有位置处理技术边界：五种位置状态分开；`operating_region_id` 是受保护位置数据；首启手选与定位平权；大致位置只用来推荐、精度不够就要求手动确认，不能静默落入更细网格；拒绝/超时不伪造"当前位置"。
- 合规边界（SSLAUNCH）：中国主体 Demo 只走 TestFlight/内测；美国精确位置 >1,000 人触发 DOJ 阈值；中国大陆发行需 GCJ-02 与地图资质（SGODOT-86 P7 未决）。

## 1. 目标与拆分

| 包 | 目标 | 交付物 |
|---|---|---|
| A 账户 | 玩家有可找回、可多设备、可删除的账号；游客只能浏览 | 邮箱账户（自建）、Apple/Google（Firebase）、游客登录墙、删号级联农场 |
| B 全球 | 任何城市都能选点建农场并跑完整玩法 | 城市实体化、去两城硬编码、内容降级、Overpass 容量 |
| C 选城 | 新用户自由选城，默认落到所在城市，不申请定位权限 | 选城页重做：IP 预填 / 搜索 / 推荐 / 城市气泡 |

三包独立立卡；A 与 B/C 可并行；C 依赖 B 的服务端城市实体（B0）。

## 2. A：真实账户体系

### 2.1 决策：移植 feat/next-feature 的账户三件套，不整支合并（已拍板）
- 只拿：客户端 FirebaseAuth + AuthSession + 登录页 + 年龄门/同意页 + boot 去向矩阵；服务端 accounts / firebase_token + users / user_identities / account_deletions 三表 + 五个账号接口。
- 不拿：feed、IM、语音房、关注、推送（与街角四季主线无关，且是冲突大头）。
- 理由：32 个双改文件里大部分冲突来自社交页面与 app 路由；账户模块边界清晰，按文件移植 + 重跑测试比整支合并可控。

### 2.2 身份模型（按"测试阶段不迁旧数据"简化）
```
users (自有 uuid) ──< user_identities (provider, provider_uid)   # 已有（D2）；provider 新增 'email'
users ──1 farms (owner_id 改为指向 users.id)                     # 农场归账号，不再归设备
players (install_key) = 游客身份，只读                             # 保留现有匿名鉴权，不再拥有农场
tokens 加 user_id 可空：auth() 返回 {player_id, user_id?}；所有写接口要求 user_id
```
- 因为决定 4（测试阶段用户重新定位重新创建），**不做 players↔users 绑定、不做农场继承与冲突处理**：线上 75 个匿名农场不迁移，发布时备份归档后不再可达。
- 一个账号一个农场；多设备登录同一账号看到同一农场（现有 token 表最多 5 个活跃 token 的规则沿用）。
- 会话仍是自有 opaque token：邮箱账户由自有服务端直接签发；Apple/Google 走 `POST /v1/auth/firebase` 用 Firebase ID token 换 token（已实现）。

### 2.3 登录方式与大陆可用性（决定 1）
- **邮箱账户改为自建**（不经 Firebase）：`users.email` + 密码哈希（argon2）+ 邮箱验证码（注册验证、找回密码）+ 限流。海外用户也走这一套，避免同一邮箱在 Firebase 与自建两边各建一个账号。
- Firebase 只承担 Sign in with Apple / Google 的 id_token 换 token（C1 插件 SGODOT-96 之后接入），大陆链路上没有任何 Google 域名。
- 开发阶段大陆可用的依赖清单：自有服务端（香港）、Mapbox（大陆可达，偏慢）、Overpass / ESA 由香港服务端代取。验证码邮件用香港可用的发信服务（阿里云邮件推送或 SES）；开发期 QA 白名单邮箱可固定验证码或打服务端日志，不阻塞联调。
- 与 08-30 调研 §4.1「Firebase 做邮箱登录」的偏离原因：开发阶段大陆必须可用；正式上线前按地域政策分区时再评估是否把海外邮箱迁回 Firebase。

### 2.4 游客模式：只能浏览，不能创建（决定 2）
- 游客可做：地图浏览、切城、看城市气泡与地标、看别人农场的访客快照、Nearby 列表。
- 游客不可做：建农场、农场命令、搬迁、组队/语音、任何写操作。点到这些入口弹**登录墙**（登录/注册后回到当前浏览位置继续）。
- 服务端硬约束：`POST /v1/farms`、`/v1/farms/me/*`、组队与联机写接口要求 `user_id`，游客 token 一律 401 + `LOGIN_REQUIRED`。

### 2.5 首启流程
年龄门 → 同意 → 登录 / 以游客浏览 → 选城（C）→ 选点建农场（此处需登录）。

### 2.6 删号
R1（SGODOT-56）级联补农场域：farms、farm_snapshots、commands、farm_creations、online_*；Apple revocation 与 Web 删号页按原卡收尾。

## 3. B：全面开放全球

### 3.1 城市实体化（B0，服务端先行）
- 新表 `cities`：`id`、`name`、`country_code`、`admin`、`center`、`bbox`、`timezone`、`source`、`created_at`、`farm_count`（聚合缓存）。
- `POST /v1/cities/resolve {lat,lng}`：服务端权威地解析所在城市并落表（首次创建），返回 city。数据源两层：客户端 Mapbox Geocoding/Search Box 只做搜索建议；服务端用离线数据集（Natural Earth populated places + OSM admin boundary 或 GeoNames）做规范化与 bbox，不信任客户端传来的城市名。
- 时区：服务端按经纬度算 IANA 时区（`geo-tz` 或 `tz-lookup`），写入 `cities.timezone`；农场时钟、party_travel 的时区表改从 city 读。
- `farms.region_id` 语义改为 `city_id`；建农场校验改为"位置在 city.bbox 内 + 现有 300 m 脚印边距"。
- `GET /v1/regions` 改为 `GET /v1/cities`（分页 + 按 farm_count 排序 + 我的城市），旧接口保留一个版本给 0.16.x 客户端。

### 3.2 去两城硬编码（B1，客户端 + 服务端）
需要改的点清单：`app.ts` 三处 `regions.regions.find`、`ponds/catalog.ts` 硬编码、`party_travel.ts` zones Map、`FarmRegions.load_default`、`CityMapData.has_city`、`landmark_scenes.gd`、`map_poc.gd` 的 `_in_la` 与 LA 夹具、`city_map_view.gd` 默认文案、`online_navigation.json` 的 `la_*/sh_*` key（确认 street 空间已按 terrain layout 走，不依赖预烘焙）。

### 3.3 无人工内容城市的降级（B1）
- 地标：无人工配置时，自动从瓦片 POI / OSM（tourism=attraction、historic、著名公园）取前 N 个作"自动地标"，用通用 POI 美术（SGODOT-133 的两级映射）；上海/LA 继续用精品地标与 3D 场景。
- 居民 NPC：由"每城手工经纬度"改为"按玩家农场位置自动落位"——在农场周边 1–3 km 的路网/POI 点上选三个位置，服务端生成并固化到农场状态，保证任何城市都能跑七日 Journey。
- 池塘：公共池塘目录改为按城市生成或允许无公共池塘（私有农场自带池塘，见 `farm-pond-retirement-2026-09-25.md`）。
- 海洋、极地、无路网区域：Overpass 返回空或 ESA 全水 → `GEOGRAPHY_INCOMPLETE`，UI 引导换点，不伪造陆地。

### 3.4 Overpass 容量（B2）
- 现状已出过一次超时事故（09-23）。全球开放后请求量与地域分散度都上升：加服务端结果缓存（按 100 m 网格 key）、备用自建 Overpass 实例、失败重试与排队提示。
- 验收城市：东京、伦敦、新加坡、悉尼、多伦多各建一次农场并跑到 D1；再选一个小城（如 Boise）和一个沿海点验证降级。

### 3.5 地区与合规（决定 1：大陆暂时算全球）
- 开发与 pitch 阶段大陆按普通地区对待：服务端在香港，Overpass / ESA 由服务端代取；客户端只连自有服务端与 Mapbox；Firebase 不在大陆链路上（见 §2.3）。
- 正式上线前再按地域政策做分区调整：GCJ-02 偏移与地图资质（SGODOT-86）、美国 DOJ 位置阈值、GDPR。当前不做。

## 4. C：新用户自由选城，默认所在城市（决定 3：不申请定位权限）

- 选城页重做为四段，**整条链路不请求定位权限**，现有「Use my current city」定位按钮移除：
  1. 默认卡：服务端按请求 IP 粗定位到城市（`GET /v1/cities/suggest`，服务端用 IP 库解析后走 `cities/resolve`），页面预填「You seem to be in Tokyo」，用户点确认才落城；IP 解析失败则不预填。
  2. 搜索框：Mapbox Geocoding 只返回 place / locality 级结果，选中后走 resolve。
  3. 推荐列表：有玩家的城市（`cities` 按 farm_count），上海/LA 自然在前。
  4. 地图浏览：国家级视野点城市气泡（已有 z2 国家级 + 城市气泡逻辑，`2026-09-23-map-seamless-zoom-city-switch.md`）。
- 选定城市 → 地图飞到城市 overview → 进入已有的选点建农场流程（游客到此弹登录墙）。
- 已有农场用户不进选城页；「Change city」入口在设置，走已有的一次搬迁（relocation）规则，全球化后允许跨城搬迁一次。
- 现有地图页里的定位按钮与 Android 定位落点不在本需求范围内，保持现状；本需求只保证选城与建农场不依赖定位。
- 文案全部英文（2026-09-04 要求）；城市名走 Mapbox 本地化名 + 英文名。
- SGODOT-127「街区自由选择」是同一需求的雏形，并入本包。

## 5. 已拍板（2026-09-28，pitch 阶段）
| # | 决定 | 对方案的影响 |
|---|---|---|
| 1 | 大陆暂时算全球，开发阶段必须在大陆可用；正式上线前再按地域政策分区。大陆用邮箱账户 | 邮箱账户自建、Firebase 只做 Apple/Google；分区调整移出当前范围（§2.3、§3.5） |
| 2 | 游客模式保留，但只能浏览，不能创建 | 游客 = 现有匿名 token 只读；写接口登录墙（§2.4） |
| 3 | 先不启动定位权限 | 选城默认改 IP 预填；去掉定位按钮（§4） |
| 4 | 测试阶段，用户重新定位重新创建 | 不迁旧匿名农场，不做 players↔users 绑定与冲突处理；farms.owner_id 直接指向 users（§2.2） |
| 5 | 移植 | 按模块移植账户三件套，不整支合并（§2.1） |

## 6. 工期与顺序（单人估算，按 §5 决定后）
| 包 | 内容 | 人周 |
|---|---|---|
| A | 移植 0.7 + 自建邮箱账户（注册/验证码/找回/限流）0.5 + 游客登录墙与 owner 改 user 0.4 + 删号级联农场 0.2；C1 原生插件 1（可并行、不阻塞） | ≈1.8 |
| B0 | cities 表 / resolve / 时区 / bbox 校验 / 新接口 / IP suggest | 1 |
| B1 | 去硬编码 + 自动地标 + 居民自动落位 + 池塘降级 | 1–1.5 |
| B2 | Overpass 缓存与备用源 + 五城验收 | 1 |
| C | 选城页重做 + IP 预填 + 搜索 | 0.75 |
| 合计 | | ≈5.5–6（两人并行约 3.5 周） |

顺序：B0 → C → B1 → B2；A 独立并行。B0 完成前不要动客户端选城页。

## 7. 实施状态（2026-09-28 第一批，分支 feat/accounts-global-cities）

### 7.1 已完成
- **服务端账号（A）**：自建邮箱账户——scrypt 密码、HMAC 存储的 6 位验证码（10 分钟过期、60 秒冷却、错 5 次作废）、邮箱验证、找回密码（改密即撤销该账号全部会话）、数据导出、应用内删号（需再输密码，农场与联机状态级联删除，只留不含邮箱的墓碑）。接口：`/v1/auth/email/{register,login,code,verify,reset}`、`/v1/users/me`、`/v1/users/me/export`、`DELETE /v1/users/me`。Firebase 验签模块已从 feat/next-feature 移植，留给 C1 的 Apple/Google 登录。
- **身份模型**：每个账号恰好一个"账号玩家"行（`players.user_id`），农场、联机、队伍照旧按 player id 走，改动面最小。游客（install_key）token 只读：建农场、命令、搬迁、联机都返回 `LOGIN_REQUIRED`；`/farms/me` 对游客返回 404，旧匿名农场不迁移（决定 4）。
- **全球城市（B0）**：GeoNames cities15000 压成 `server/data/cities.tsv`（21209 座城市，卫星城并入所在都市），服务端按坐标解析城市与 IANA 时区；上海、洛杉矶保留精品 id 与边界。接口：`GET /v1/cities`、`/v1/cities/search`、`/v1/cities/suggest`（IP 粗定位）、`POST /v1/cities/resolve`、`GET /v1/cities/:id`。农场风格按国家选（东亚 / 北美澳新 / 其他）。
- **客户端**：账号面板（登录、注册、找回密码、验证邮箱、我的账号 / 登出 / 删号），地图与选城页右上角账号入口；建农场前的登录墙；账号会话持久化、启动恢复、token 失效回游客、离线保留账号。选城页重做：IP 预填确认卡、按名字搜索、热门城市，去掉定位按钮（决定 3）。全球城市进入本地城市缓存，地图、选址框、城市切换对任意城市生效；非精品城市自动生成城市配置（概览视角、三位居民放在城市中心附近）。
- **测试**：服务端 851 → 901 用例，内存与 PostgreSQL 两套存储同跑账号场景；客户端新增账号会话、账号面板、城市缓存、选城页、全球城市地图、游客登录墙用例；`tools/dev/account_e2e.tscn` 用真 HTTP 打本地服走完注册 → 东京建农场 → 多设备 → 登出 → 删号全链路（18 项全过）。

### 7.2 与原方案的偏差
- 城市目录放在内存（启动时读 tsv），没有建 `cities` 表：数据是静态的，农场数用 `farms` 按 `region_id` 聚合即可。
- 搜索走服务端离线城市库，没有接 Mapbox Geocoding：大陆开发阶段可用、零额外成本，结果同样经服务端归属。
- 跨城搬迁仍未开放，搬迁照旧限本城。

### 7.3 上线前的部署步骤（未执行，需要时再做）
1. 服务器下载 DB-IP City Lite（`dbip-city-lite-YYYY-MM.mmdb.gz`，约 60 MB），解压后挂进容器，设 `IP_CITY_DB`。
2. 设 `TRUSTED_PROXIES` 为 Caddy 所在的 Docker 网段，否则服务端拿到的是代理内网 IP，IP 预填永远为空。
3. 配 `SMTP_URL` / `MAIL_FROM`（阿里云邮件推送或 SES）；未配时验证码只打在服务端日志里。
4. 生产不设 `GUEST_WRITES`；QA 邮箱域名与固定验证码按需配置。
5. 迁移会给已有库补 `users.password_hash` 与邮箱唯一索引；若库里已有 D2 旧 users 表且存在重复邮箱，迁移会失败，需先清理。

### 7.4 还没做
- C1 原生 Apple / Google 登录插件（SGODOT-96）。
- B1 后半：居民按玩家农场周边路网落位（现为城市中心固定偏移）、非精品城市的自动地标、公共池塘按城市生成。
- B2：Overpass 结果缓存与备用源、五城实机验收。
- 真机巡检（按惯例过一遍主要页面），以及线上部署。

## 8. 第二批：账号资料、完整密码体系、站外删号（2026-09-28）

### 8.1 已完成
- **账号资料**：昵称必填（2–24 字符，不能是邮箱、不能含零宽等不可见字符，不唯一）；性别选填，选项按北美常见做法：Woman / Man / Non-binary / Prefer to self-describe（可自填 32 字内）/ Prefer not to say；生日选填，月/日/年三项要么全填要么全空，填了必须满 13 岁（COPPA：不满 13 岁整条拒绝、不落库），账号页显示周岁。注册后先验证邮箱（可"稍后"），然后必须补昵称；已登录但没昵称的玩家在建农场时同样先补资料。
- **公开展示**：昵称目前只在本人账号页显示，没有进附近农场列表和访客快照（PRD 写明公共地图不展示可识别账号），要不要公开另行决定。
- **密码体系**：注册与重置都要"确认密码"；登录；忘记密码 → 邮箱验证码 → 新密码两次；登录状态下改密码（当前密码 + 新密码两次，不能与当前相同，改完其他设备全部退出、本设备保持登录）；"显示密码"开关；已填内容的输入框上方保留小标题。
- **站外删号页**：`GET /v1/account/delete`（纯静态、英文、无外部资源，CSP 只放行同源请求）。两种证明方式：邮箱 + 密码，或忘了密码时用邮箱删号验证码（验证码用途与找回密码隔离，互不通用）。删除范围与应用内删号相同。线上地址将是 `https://farm.sensenjoy.cn/preview/journey/v1/account/delete`（按当前 Journey 路由），填进 Play Data Safety 的删号链接。
- **测试**：服务端账号场景 36 个（内存 + PostgreSQL）；客户端账号面板 11 个；浏览器实测删号页两种路径都删除成功。

### 8.2 云服务：现在要不要迁到 AWS / 海外云
**建议：pitch 阶段继续用阿里云香港，不现在迁；但从现在起按"随时可迁"来做，并定好迁移触发点。**

理由：
- **团队在大陆开发**（决定 1）：香港对大陆和北美都能用，迁到美西后大陆开发调试、真机连服的延迟与稳定性都会变差，SSH/部署也更依赖代理。
- **数据会重置**（决定 4）：测试期用户重新建号建场，迁移不背历史数据包袱，晚迁的成本并不比早迁高。
- **服务已经可移植**：整套服务是 docker compose（应用 + PostgreSQL + Caddy），不依赖阿里云专有服务；发信走通用 SMTP、IP 库是本地文件、地理数据来自 Overpass / ESA，换云只是换机器和 DNS。唯一的阿里云绑定是备份上传到 OSS，需要换成 S3 / R2。
- **北美延迟可接受**：农场是异步玩法，香港到北美的往返延迟对种田、访问影响不大；实时多人空间会更明显，但 pitch 演示可控。

**迁移触发点（任一满足就迁，目标 AWS us-west-2 或与 SSLAUNCH 选定一致）**：
1. 开始对北美真实用户发内测（TestFlight / Play 封闭测试超出团队与投资人范围）；
2. 美国新主体成立、准备公开上架（数据控制者要在美方，DOJ 精确位置数据规则与尽调都要求）；
3. 北美演示时实时多人空间的延迟明显影响体验。

**现在就要做的两件事**：
- 香港 ECS **2026-10-04 到期、未开自动续费**。建议按月续费（不要包年），保持随时可迁。
- 验证码发信直接用 **Amazon SES**（北美到达率好，大陆也能调用），这样迁云时发信不用换。需要开 AWS 账号、验证发信域名、申请脱离 SES 沙箱。

### 8.3 仍未做（账号相关）
- 年龄门与隐私同意页（next-feature 上已有，未移植）。
- 发信服务未开通；验证码目前只打在服务端日志里。
- Apple / Google 原生登录。
- 注册无人机验证；邮箱验证不强制（可被抢注，靠找回密码夺回）。
- 改邮箱（服务端与客户端都没做）；数据导出、"退出所有设备"（服务端有接口，客户端没有入口）。
- 真机软键盘与输入法测试。

## 9. 第三批：Sign in with Apple（2026-09-28）

- **服务端** `POST /v1/auth/apple {identity_token, nonce, given_name?, family_name?}`：RS256 + Apple JWKS（`appleid.apple.com/auth/keys`）验签，
  校验 iss、aud ∈ `APPLE_BUNDLE_IDS`（默认 `app.gensen.maps`）、exp、签发不超过 10 分钟、`nonce == sha256(原始 nonce)`。
  找号顺序：Apple sub → Apple 验证过的邮箱对应的**已验证**邮箱账号（挂身份）→ 新建无密码账号。邮箱被未验证账号占着回 `EMAIL_IN_USE`（防抢注劫持）。
  Apple 只在首次授权给名字，用作默认昵称。所有账号回包新增 `has_password`。
- **删号**：Apple 账号无密码，应用内删号不要密码；墓碑 `provider_uid = apple:<sub>`、`apple_revocation = pending`。
  真正调 Apple `/auth/revoke` 需要 Sign in with Apple 私钥（.p8）生成 client secret，**未做**，上架前补。
- **iOS 原生**：`tools/ios/AppleSignIn.swift` 监听回环 UDP 46465，收 `APPLE|<nonce 哈希>` 弹系统授权，回 `APPLE_OK|token|名|姓|邮箱` 或 `APPLE_ERR|原因`。
  `inject_apple_sign_in.py` 编入工程并加 entitlement；自动签名 + `-allowProvisioningUpdates` 会给 App ID 开能力，若团队权限不够需在开发者后台手动勾 Sign in with Apple。
- **客户端**：iOS 上登录 / 注册页第二个按钮是黑色 "Sign in with Apple"；无密码账号隐藏"改密码"、删号不要密码、无邮箱时显示 "Signed in with Apple"。
  取消授权不提示。按钮暂无 Apple 标志（Apple 人机指南要求自绘按钮带 logo），上架前换官方素材或原生 ASAuthorizationAppleIDButton。
- **验证**：服务端 925 例全绿（含 PG）；客户端新增 8 例全绿，全量只剩 8 个既有基线失败；Swift 对 iOS SDK 类型检查通过；注入脚本对 0.16.42 发布工程副本重复执行结果一致。
  **尚未真机验证**（需要 iPhone，且 Apple ID 登录的 Xcode 能为 XN4Z77ZX73 团队开此能力）。

## 10. 取消游客模式（2026-09-29 用户要求，改写决定 2）

- **先登录**：没登录时选城页上盖一个关不掉的登录面板（无关闭按钮，登录成功前 dismiss 无效）。冷启动只有本机存有账号时才直接进自己的农场。
  地图上登出、删号，或启动时发现保存的 token 已失效，都回到选城页的登录墙，并清掉本机农场缓存。
- **新用户**：登录之后才选城（登录墙在选城页之上，登录完露出选城页）。已有农场的账号登录后直接回自己的农场。
- **默认城市自动填写**：搜索框预填城市名，下面一个 "Continue with <城市>" 一键确认。优先"上次选择的城市"（本机 region_choice.json），
  没有才用服务端 IP 粗定位；玩家一改搜索框，"继续"按钮收起，清空后恢复。IP 回包晚到也不会覆盖玩家已经输入的内容。
- 服务端不变：匿名 token 仍用于公开只读接口（城市目录、搜索），写接口照旧 LOGIN_REQUIRED。
