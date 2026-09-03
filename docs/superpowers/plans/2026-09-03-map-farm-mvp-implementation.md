# 街角四季 MVP：PRD 评估与实施方案

- 日期：2026-09-03（同日按拍板结果修订，见 §0.1）
- 评估对象：`docs/product/map-farm-life-sim-direction.md` v0.4（尚未入库，`docs/product/` 整目录 untracked）
- 代码基线：main@0b4323b（2026-09-04 内部 Demo 分支已合入）
- 性质：工程侧评估 + 按 PRD §12.2 的 G0-G4 分阶段路线。每个 Gate 开工时再按仓库现有 plan 格式拆成可执行任务单，本文不替代任务单。

---

## 0. 结论

### 0.1 已拍板（2026-09-03）

| 项 | 决定 | 对方案的影响 |
|---|---|---|
| 演示城市 | **上海 + 洛杉矶** 两城 | 管线跑两遍（各 3 候选 + 1 安全蓝图）；region 配置两套时区；城市选择页 + 「使用当前城市」一次性定位真正有意义；洛杉矶有夏令时 |
| 农场归一化尺寸 | 按 §6 默认值 | 0.1 直接开工 |
| 服务端 | **要有 server**；融资演示只是用途之一，按**完整可体验切片**做 | D4 改为服务端权威；工期从 43-45 人天升到 50-54；不再按「融资切片」砍内容，只保留应急裁剪顺序（§5） |
| 服务端栈与部署 | **Node.js**（TypeScript + Fastify + PostgreSQL），部署**阿里云香港**；Java 维护资源已不在，后续服务统一 Node | D4 重写：数值逻辑只在服务端，客户端不算钱；账本测试搬到服务端 vitest |
| 蓝图管线语言 | **Node.js**（同日追加拍板，与服务端同栈） | G0-A 任务单按 Node/TypeScript 编写；`geos-wasm` 3.1.1 本机 spike 通过（unary union / polygonize / buffer / prepared contains） |
| 缺失动画 | 全部记录为占位 | 建动画占位登记表 + 运行时回退；测试守「每个动作要么有真实 clip 要么在登记表里」 |
| Gate 测试规模 | 内部 QA + 5-8 名熟人 | 正式 Gate 留到融资后，PRD 原文不改 |

### 0.2 结论

1. **PRD 可以直接作为制作依据。** 范围冻结（§0.1）、三个 id 分离（§4.1）、Gate 顺序（§12.2）都对。§7.5 的七日账本我逐日核过钱包、种子支出、XP 累计、三名居民关系点四套算术，全部自洽（D6 钱包 305 / 扩地 145 / 账户价值 545 / XP 301 / 关系 58·62·31），可以原样编成一条自动化模拟测试，客户端与服务端各跑一遍。
2. **目标范围 = 完整可体验切片（G0-G4 + 服务端 + 双城）。** 约 50-54 人天（单人 + AI 辅助编码、含单测、占位美术、不含正式 playtest），按每周 5 人天约 10-11 周。这比 Plane「项目方向讨论」的 6-8 周口径长 2-3 周；若 8 周是硬线，按 §5 的顺序裁剪，最多省约 9 人天。
3. **可复用比例高于表面。** avatar 装配/换装/存档、Mapbox 底图桥、相机同步与地理锚定、design token、gdUnit4 基建直接用。真正从零的五块：蓝图离线管线、农场场景（移动/劳作/作物）、服务端权威状态层与接口、客户端同步层、内容脚本系统。
4. **数值逻辑只在服务端。** 服务端 Node/TypeScript，钱包、XP、关系、`ready_at`、`player_day_id` 全在服务端算，七日账本测试在服务端跑；客户端不算钱，只做劳作动作的视觉预测，回包后对账（D4）。
5. **融资演示不是一个单独范围。** 它是完整构建上的导演模式 + 一份 D0-D6 十五分钟脚本 + 一个 tag。
6. Plane 上的 urgent 卡点 **SGODOT-21「地图选地方→私有农场」就是本方案的 G0**，按 §4.1 七条挂子任务。

---

## 1. PRD 评估

### 1.1 站得住的部分

- 两层可见空间 + `region_id / layout_patch_id / farm_instance_id` 分离：数据模型干净；蓝图 revision 冻结让老存档不受道路更新影响。
- 「拓扑影响个性，不影响经济」把真实地图最大的隐患（地区阶级）从设计上排除，工程上只需要一个公平校验器。
- 七日账本是确定性夹具，Gate 2 的「守恒错误为 0」可以用一条模拟测试兜住，而不是靠 30 个人跑七天。
- §11.5 移动端指引（静态 Mesh、MultiMesh、网格 A*、合并碰撞体、iOS 桥不传大段 GeoJSON）全部落在 Godot 4.7 mobile 渲染器和现有桥的边界内。
- §11.2 要求接口保留幂等键、版本号和服务端时间语义，正好是服务端权威模型需要的全部约束，不用改 PRD。
- Gate 顺序先蓝图、再劳作、再居民，和「不得先批量做居民」的红线一致。

### 1.2 与仓库现状的冲突（需要明确决定，不是漏洞）

| PRD 要求 | 仓库现状 | 处理 |
|---|---|---|
| 地图固定 `zoom 16 / pitch 45 / north-up`，禁缩放旋转，只能在街区边界内平移（§3.1） | 09-04 Demo 是自由漫游：拖拽惯性、双击变焦、2D/3D 切换、飞洛杉矶、12+10 随机路人 | 09-04 Demo 打 tag 留档；main 上地图改为受限模式，手势代码保留但默认关闭；「飞洛杉矶」改造成城市切换 |
| 定位只在「使用当前城市」时前台请求一次，不展示陌生人 GPS 点（§3.1 / §4.3 / §11.3） | 刚做完 GPS+NETWORK 双 provider 持续订阅 + 角色钉真实位置（Demo③） | `start_location()` 改一次性，只用来在上海/洛杉矶之间选城市；人数簇改为 `region_id` 下的服务端玩家列表 |
| 正常地图不画任何土地边界；候选高亮只在创建流程（§3.1 / §4.3） | 留言 marker 层（Demo④） | marker 层退役，或改造成苗圃/小馆/庭院三个地点入口 |
| 地图高亮与农场由同一份蓝图编译（§4.5） | 原生桥只有 create / camera / visible / location 四类能力，Android、iOS 都没有 GeoJSON 图层 | 见 §3 决策 D1：高亮在 Godot 透明层画，不动原生桥 |
| 两层切换后必须恢复原相机、选中角色、列表滚动、预览开合（§10.3） | `AppRouter` 用 `change_scene_to_file`，地图场景整个销毁重建 | 见 §3 决策 D2：场景栈，地图常驻 |

### 1.3 PRD 没写但会卡住实施的缺口

1. **农场归一化尺寸。** PRD 定了 9/12/16/24 格和 3-7 区块，没定游玩区物理尺寸、田格边长、步道最窄宽度。已按 §6 默认值拍板。
2. **选择页与固定缩放矛盾。** §3.1 只允许 zoom 16 街区级浏览，§4.3 又要「地图展示三个公开候选区域」。同城三个 250-450 米街区在 zoom 16 下不可能同屏。解法：选择页用卡片轮播，切卡时 `set_camera` 飞到对应候选（接口已有），不在正常浏览开放缩放。
3. **劳作动画来源。** 清理、翻土、播种、天气照料（浇水/疏水/覆盖）、收获、挥手至少 6 条。Unity 库能借的只有 `dt@basket`（提篮）和表情类，其余要新做。已拍板：全部占位登记。
4. **时区。** `player_day_id` 按城市时区 04:00 切日，但 Godot 没有 IANA 时区库。拍板双城后洛杉矶带夏令时，所以 `player_day_id` 由服务端用 IANA 时区（luxon）计算，客户端只显示。
5. **演示节奏。** 作物 4-18 小时、主会话间隔 18 小时，融资现场无法跑七日。§9.1 的「QA 时间倍率」升级成一等交付物**导演模式**（时间倍率、跳日、田况种子、跳章、载入某一天的账本快照），只作用于服务端标记为 QA 的农场实例。
6. **两城的数据与网络。** 上海 OSM 主路可用但细路稀，候选要人工挑；洛杉矶 OSM 质量高。服务端要同时能被上海和洛杉矶稳定访问，VPS 选址要考虑大陆连通性（§8）。
7. **Gate 测试规模。** 已拍板缩为内部 QA + 5-8 名熟人；正式 Gate 留到融资后。

### 1.4 小问题

- §3.1「点击玩家 Avatar 先进入预览」与 §3.3「人数簇→横向列表→选中」是两条入口，MVP 只做列表一条。
- §4.4 / §6.1 田畦 3 格制下「16 格」不能整除（9→12→15 才对，或者改畦长）。
- 老案 `map-farm-game-design.md` 引用的三张概念图和新案的 `output/imagegen/current-app-*-v1.png` 混在同目录，索引没更新。

---

## 2. 现状盘点

| 能力 | 仓库现状 | 复用方式 |
|---|---|---|
| 角色装配 / 换装 / 存档 | `modules/avatar`：toon shader、merged/direct 两策略、denylist、运行时缩略图；155 用例 | 玩家、三名居民、访客农场主人全用同一套。居民 = 固定 outfit 的 `AvatarConfig`，零新角色美术 |
| 角色动画 | `animations.res` 只有 idle / walk / run | 劳作动画追加进同一动画库；缺的走占位登记表回退 |
| 地图底图 | Android Kotlin 插件 + iOS Swift/UDP 桥；`MapBridge` 抽象：`create_map / set_camera / set_map_visible / start_location` | 不改原生；进入实例时 `set_map_visible(false)`；上海/洛杉矶两个锚点现有代码里都有 |
| 相机同步 + 地理锚定 | `map_poc.gd`：f64 权威中心、浮动原点、日界线、剔除、地面射线 | 候选高亮 mesh 用同一投影贴地 |
| 路由 | `AppRouter`：`change_scene_to_file` + Android 返回键语义 | 扩成场景栈（D2） |
| UI | `design_tokens.gd` + `app_theme.tres` + `SafeAreaMargin`；薄荷绿体系 | 全部 HUD 沿用；§10.4 的珊瑚色补进 token |
| 管线模式 | Python 阶段 → JSON → Godot headless bake（`tools/unity_export` → `tools/pipeline`） | 蓝图管线照抄这个两段式 |
| 测试 | gdUnit4 + `tools/run_tests.sh`，orphans 计入失败 | 新模块同结构；服务端用 vitest，账本模拟测试放服务端 |
| **缺** | 蓝图管线（Node 包待建）、农场场景、作物、服务端（Node 工程）、客户端同步层、对话/章节系统、天气 VFX、地点场景 | 全新 |

---

## 3. 关键技术决策

**D1 候选高亮在 Godot 透明层绘制，不给原生桥加 GeoJSON 图层。**
Android、iOS 要写两遍；iOS UDP 桥不适合传大段 GeoJSON（§11.5 明令禁止）；G2 已真机验证 Godot 层与 Mapbox 的相机同步，贴地 mesh 和角色是同一套投影。做法：蓝图携带 WGS84 的 overlay 多边形（主路线 + 区块面），运行时投影到浮动原点坐标生成 `ArrayMesh`，选中态换材质。这天然满足「高亮与农场同源」。代价：pitch 45° 下贴地 mesh 有 z-fighting，用少量抬高 + 关深度写入解决；不行再退到 Android 原生 fill layer。

**D2 两层空间用场景栈，地图常驻不销毁。**
原生 MapView 本来就随 Activity 常驻，只有 Godot 侧在重建；09-04 Demo 的定位闩死锁正是 `change_scene` 重建地图引起的。§10.3 要求返回恢复相机/选中/滚动，常驻最省。做法：`AppRouter` 增加 `push_instance(scene)` / `pop_instance()`；push 时地图根节点 `process_mode = DISABLED` + `visible = false` + `bridge.set_map_visible(false)`，pop 反向；换装房也迁到栈上。内存：街区级地图只有 1 个自己 + 少量簇角色，可接受；真机 RSS 放 G0 出口验。

**D3 蓝图离线管线：Node/TypeScript 生成，Godot 运行时加载，双城同一条管线。**
数据来源 OSM 一次性 Overpass 抓取（开发期，走本机 7890 代理），存 `source / license / revision`，不碰 Mapbox Streets。Node/TypeScript（`tools/geo_blueprint/`：`geos-wasm` 即 GEOS 本体、`proj4` 做横轴墨卡托、`pngjs` 出预览，vitest 测试；所有几何指针收口在一个 `geos.ts` 封装里）：本地横轴墨卡托投影 → 道路拓扑修复 → polygonize → 区块筛选 3-7 → 简化/合并微区块 → 等比缩放到固定游玩区 → 栅格化 `visual / walkable / buildable / cultivable` 四张 mask → 锚点（出生、房屋、储物、出口、三田畦、水井）→ 可达性与公平校验 → 输出 `farm_blueprint.json` + `map_overlay.geojson` + 预览 PNG。Godot 侧 G0 直接在运行时从 JSON 生成地表 `ArrayMesh` 与 `AStarGrid2D`（4096 个格子毫秒级），烘焙成 .res 留到 G4；checksum 由 Godot 按同一 canonical 字符串重算，双语言一致性用测试守。目录按 `assets/blueprints/{layout_patch_id}/rNN/`，revision 不可变。城市只是管线参数：`--city shanghai` / `--city los_angeles`。

**D4 权威状态在服务端；服务端用 Node.js，数值逻辑只在服务端算。**
- 栈：Node 22 LTS + TypeScript + Fastify + TypeBox（请求/响应的 JSON Schema 即类型）+ Drizzle + PostgreSQL + luxon（IANA 时区）+ vitest + pino。Java 维护资源已不在，后续服务统一 Node。
- 协议：REST over HTTPS + JSON。MVP 不用长连接：农场是单人的，命令都是请求回包；作物成熟靠 `ready_at` 倒计时；访问和人数簇是只读拉取。WebSocket 等 IM 或实时功能再加。
- 接口 v1：`POST /auth/anonymous`（device_id → 令牌）、`GET /regions`（两城 + 候选 + 预览）、`POST /farms`（创建实例，冻结 `blueprint_revision`）、`GET /farms/me`（state + version + server_time）、`POST /farms/me/commands`（`idempotency_key` + `base_version` + type + payload → version + state + server_time）、`GET /regions/{id}/nearby`、`GET /farms/{id}/snapshot`、`POST /qa/...`（仅 QA 实例）、`GET /healthz`。
- 领域层 `server/src/domain`：State（纯数据）+ Command + Reducer（纯函数，无 IO）。钱包、库存、XP、关系、章节、`ready_at`、`player_day_id`、天气脚本推进全在这里；七日账本测试直接驱动 Reducer。
- 存储 PostgreSQL：`farms(id, owner_id, layout_patch_id, blueprint_revision, version, state jsonb, qa bool)`；`commands(farm_id, idempotency_key unique, base_version, payload, result, applied_at)`；`snapshots(farm_id, revision, visible_props jsonb, weather jsonb)`。apply 走一个事务：`SELECT ... FOR UPDATE` 锁农场行（单写者）；幂等键命中直接回放上次结果；`base_version` 过期返回 409 并带最新 state。
- 鉴权：MVP 匿名 `device_id → player_id` 签 JWT；日后接 Firebase Auth ID token 校验，与海外版选型一致。
- 客户端：不算钱、不算 XP、不算 `ready_at`。只保留一个薄预测器 `modules/farm_predict` 预测田格视觉状态，好让动作立刻播；回包按 `version` 覆盖，漂移一律以服务端为准。断网进只读态并显示横幅，不排队离线命令；访客快照按 PRD §11.2 随包兜底。导演模式命令只对 `qa=true` 的实例生效，正式实例返回 403。
- 内容数据 `assets/farm/data/*.json` 是单一来源，服务端构建时打进镜像。
- 部署：阿里云香港 ECS 2C4G，docker-compose 三个容器（app + PostgreSQL + Caddy 自动 TLS）；免 ICP 备案；需要一个域名；代码不用阿里云专属 SDK，配置全走环境变量，将来迁 AWS 只换机器。

**D5 农场移动 = `AStarGrid2D` + 摇杆/点按。**
Godot 内置 `AStarGrid2D` 就是 PRD 要的「预计算网格」，不烘 NavMesh；`walkable_mask` 直接喂进去。左侧虚拟摇杆 + 点按地面寻路；相机固定 45° 跟随，不开旋转。

**D6 劳作 = 网格刷子。**
右手拖拽在地面投射轨迹，逐格命中、排队播放动作；点按 = 单格；行级工具 = 一次命中整畦 3 格但仍逐格播放。摇杆与刷子按 touch index 分流；靠近对象只显示一个上下文按钮。动作判定走本地乐观副本，结算以服务端回包为准。

**D7 内容数据化，居民复用 avatar。**
`assets/farm/data/`：`crops.json`、`recipes.json`、`residents.json`（含 outfit）、`chapters.json`（step_flags / 完成条件）、`weather_script.json`、`dialogs/*.json`、`requests.json`、`events.json`。同一份数据客户端与服务端都读，服务端构建时打进镜像。三名居民 = 固定 `AvatarConfig`，只做名字、地点布景和台词。

**D8 导演模式是一等交付物。**
独立入口（构建参数或长按标题），提供：时间倍率、跳到下一活跃日、指定田况种子、跳章、载入目标账本任意一天的状态快照。产出「D0-D6 十五分钟演示脚本」，融资现场按脚本走。

**D9 美术分三档；缺失动画全部占位登记。**
灰盒（G0）：Godot 原语 + 平涂。占位低模（G1-G3）：作物 4×4 阶段用简单 mesh + 颜色；雨用 `GPUParticles3D`，风用顶点摆动 shader；道具从 Unity `_Gensen/InteractiveProps/farm`、`well`、`Space/SpaceThemes/Farm` 挖。正式（G4 / 融资后）：一次统一美术过线。动画：`assets/avatar/base/anim_placeholders.json` 登记每条需要的 clip（`clip_id`、被哪个动作引用、占位策略、状态）；运行时找不到真实 clip 就按登记表回退（默认 idle + 程序化俯身/摆臂），QA 构建在角色头顶显示占位标记；测试守「数据里引用的每个动作，要么有真实 clip，要么在登记表里」。

---

## 4. 分阶段实施

估算口径：单人 + AI 辅助编码，含单测与评审修复，占位美术，不含正式 playtest。09-04 Demo 六项估 3.2 天实际按期交付，按同一速率估。

### 4.1 G0 蓝图证明（≈11.5 人天）— 对应 SGODOT-21

| # | 任务 | 产出 | 人天 |
|---|---|---|---:|
| 0.1 | 蓝图管线 v1 + 上海 | `tools/geo_blueprint/`；上海 3 个候选的 json / geojson / png + 1 个安全降级蓝图；许可记录 | 3 |
| 0.1b | 洛杉矶 + 双城配置 | 洛杉矶 3 个候选；`regions.json`（两城时区/夏令时规则/边界）；城市选择页（手选 + 「使用当前城市」一次性定位） | 1.5 |
| 0.2 | 蓝图运行时 | `modules/blueprint`：加载、checksum 校验、mask 查询、`AStarGrid2D`、运行时地表 mesh（.res 烘焙留 G4） | 1.5 |
| 0.3 | 地图受限模式 + 候选高亮 + 候选卡 | 固定相机与边界；Godot 层高亮 mesh；三候选卡片（同容量文案）+ 缩略图；切卡飞相机 | 2 |
| 0.4 | 场景栈与转场 | `AppRouter` push/pop；卡片扩展 → 农场；返回恢复地图状态 | 1 |
| 0.5 | 农场灰盒 | `scenes/farm`：地表、锚点、摇杆/点按移动、45° 相机、出口 | 1.5 |
| 0.6 | 公平校验 | 自动 bot：出生点 → 最远田畦时间、九格巡回时间，六蓝图差 <10%；人工走查不可达/卡死 | 1 |

出口：Android 真机能选城市、从三个候选里选一个进入灰盒农场并返回；去标签后六蓝图轮廓可辨；bot 报告过线；SGODOT-21 关闭。

### 4.2 G1 劳作证明（≈15.5 人天）

| # | 任务 | 人天 |
|---|---|---:|
| 1.1 | 服务端领域层（TypeScript）：State / Command / Reducer / 幂等 / 版本 + 客户端薄预测器 `modules/farm_predict`（只管田格视觉） | 2 |
| 1.2 | 作物状态机 + `ready_at` + 4 阶段 MultiMesh | 1.5 |
| 1.3 | 五种劳作手势 + 点按替代 + 上下文动作 + 行级工具 | 2.5 |
| 1.4 | 天气脚本 + 三种田况照料动作替换（VFX 占位） | 1.5 |
| 1.5 | 动画占位登记表 + 回退机制 + 6 条占位 clip + 守卫测试 | 1.5 |
| 1.6 | 导演模式 v1：倍率 / 跳日 / 田况种子（服务端 QA 实例） | 1 |
| 1.7 | HUD：金币、种子栏、库存、田况、成熟提示 | 1 |
| 1.8 | 服务端骨架：Fastify 工程、匿名鉴权、PostgreSQL（命令日志 + 状态 + 幂等索引）、单写者 apply、Docker + Caddy 部署到阿里云香港、健康检查 | 3 |
| 1.9 | 客户端同步：`HTTPRequest` 封装、时间偏移、乐观预测、version 对账、断线只读态、幂等重试 | 1.5 |

出口：一个蓝图上跑通 荒地 → 收获 全状态机，且状态由部署好的服务端持有；九格基础农活 P75 ≤120 s（自测 + bot）；未照料安全暂停可验证；杀进程重开后恢复到下一可行动作；导演模式 3 分钟走完一日；账本测试在服务端绿。

### 4.3 G2 访问骨架（≈4.5 人天）

| # | 任务 | 人天 |
|---|---|---:|
| 2.1 | 区域人数簇 + Nearby Farmers 横向列表 + 静态预览卡 | 1.5 |
| 2.2 | 服务端 `nearby(region_id)` 与 `snapshot(farm_instance_id)` 接口 + 快照版本化 + 2 个预置农场随包兜底 + 访客实例（只读、挥手、印章） | 2.5 |
| 2.3 | 返回恢复 + UI state 持久化 | 0.5 |

出口：D4 流程完整；访客态零写入（服务端拒绝 + 客户端不显示工具）；服务端不可用时自动落到随包快照；退出恢复率 100%。

### 4.4 G3 七日纵切（≈13.5 人天）

| # | 任务 | 人天 |
|---|---|---:|
| 3.1 | 经济：自助摊 100/日预算、种子商店、成长选择 `intent / purchase` 互斥、工程篮预留、安全线种苗包 | 2 |
| 3.2 | 章节：服务端 `player_day_id`（两城偏移 + 洛杉矶夏令时 + 04:00）、7 章 step_flags、完成条件、每日最多开一章 | 2 |
| 3.3 | 居民：对话 runner、请求、关系五阶段开三、赠礼线索；3 名居民 | 2.5 |
| 3.4 | 地点实例骨架 + 3 布景 + 5 个固定事件 + D6 结算 / 合照 | 2.5 |
| 3.5 | 料理 2 道 + 手账 / XP / 7 级 | 1.5 |
| 3.6 | 苗圃入口 3 状态 × 2 外观 + 6 件摆件布置 | 1.5 |
| 3.7 | 七日账本模拟测试：生活优先 / 出售优先 × 工具 / 扩地 × D2-D4-D6 田况轮换；服务端 vitest 跑 | 1.5 |

出口：`test_seven_day_ledger` 全绿（D6 钱包 305 / 145、账户价值 545、`2C+4H` 交齐、两名完整居民熟悉）；导演模式可完整走 D0-D6；一份 15 分钟融资演示脚本。

### 4.5 G4 真机整合（≈7 人天）

六蓝图正式地表、三天气完整包、弱网 / 断电 / 断线重连恢复、Android 与 iOS checksum 一致、性能矩阵、1080×2344 与窄屏安全区、上海与洛杉矶两地各一轮真机。

### 4.6 汇总

| 口径 | 范围 | 人天 | 自然周 |
|---|---|---:|---:|
| **目标：完整可体验切片** | G0-G4 + 服务端 + 双城 | 50-54 | 10-11 |
| 其中服务端 | 1.1 领域层、1.8、1.9、2.2 服务端部分、3.2 服务端部分、G4 断线 | ≈8.5 | |
| 其中第二城市 | 0.1b + G4 洛杉矶真机 | ≈2 | |
| 原 PRD 估算（无服务端、单城） | G0-G4 | 43-45 | 9-10 |
| 应急裁剪空间 | §5 顺序全部执行 | −9 | −2 |

---

## 5. 融资演示与应急裁剪

融资演示不单独排期：完整构建 + 导演模式 + 15 分钟脚本（D0 选城选街区进农场 → D1 雨天照料 → D3 料理 → D4 访问 → D5 风天与选择 → D6 竣工合照）+ 一个 tag。

若 8 周是硬线，按下面顺序裁，裁到够为止；每条都是延后不是取消：

| 序 | 裁什么 | 省 | 备注 |
|---:|---|---:|---|
| 1 | iOS 平行验收（只保构建能过） | 2 | PRD 本就允许 iOS 非阻断 |
| 2 | 第二个竣工外观 | 0.7 | |
| 3 | 装饰商店（先 6 件免费摆件） | 0.8 | |
| 4 | 料理 2 道 → 1 道 | 0.5 | |
| 5 | 第二名完整居民（先 1 完整 + 1 次要） | 1.5 | 影响 H5 |
| 6 | 实况天气 shadow log | 0.5 | |
| 7 | 三天气正式 VFX（保占位） | 1.5 | |
| 8 | 洛杉矶（保管线与配置，首发只开上海） | 1.5 | 最后才裁 |

不动：六个蓝图的管线、九格劳作与三种田况、D4 访问、服务端权威、七日账本测试、导演模式。

---

## 6. 已定的数（默认值，可改）

| 项 | 值 | 依据 |
|---|---|---|
| 游玩区 | 归一化到 64×64 m 正方形，地面网格 1 m | 250-450 m 街区等比缩到手机一屏可读 |
| 田格 / 田畦 | 田格 2×2 m，田畦 3 格一列 = 2×6 m，步道最窄 3 m | Avatar 3.5 头身可读；行级工具覆盖一畦 |
| 移动 | 走 2.5 m/s；出生点到最远田畦 ≤12 s | §4.4 时间差 <10% 需要绝对值先小 |
| 单格动作 | 1.8-2.2 s（含起手），36 次动作 ≈ 65-80 s + 移动/换工具 20-30 s | 落在 §6.3 P50 95-105 s 区间，按真机 P75 调 |
| 城市 | 上海 + 洛杉矶，各 3 候选 + 共用 1 个安全蓝图 | 已拍板 |
| region 时区 | 上海 UTC+8 无夏令时；洛杉矶 UTC−8，3 月第二个周日至 11 月第一个周日 UTC−7；由服务端算 `player_day_id` | Godot 无 IANA 库 |
| 权威状态 | 服务端；客户端 `user://farm/cache_{farm_instance_id}.json` 只是乐观副本与离线只读缓存 | D4 |
| 服务端栈 | Node 22 LTS + TypeScript + Fastify + TypeBox + Drizzle + PostgreSQL + luxon + vitest + pino；REST over HTTPS，MVP 不用长连接 | 已拍板 Node |
| 服务端部署 | 阿里云香港 ECS 2C4G + docker-compose（app + PostgreSQL + Caddy 自动 TLS）；需要一个域名；免 ICP 备案 | 上海与洛杉矶双向可达 |

---

## 7. 验证策略

自动化（gdUnit4，与模块目录对齐）：

- 蓝图：checksum 稳定；四张 mask 尺寸一致；所有锚点落在 walkable 上；A* 全锚点可达；六个蓝图全过。
- 公平 bot：六蓝图巡回时间差 <10%。
- 服务端领域层（vitest）：幂等重放返回同一结果、不复制货币或物品；`ready_at` 语义；跨日安全暂停；`base_version` 过期被拒；QA 命令对正式实例 403。
- 接口层（Fastify inject）：单写者串行；断线后幂等重试结果与首发一致；客户端预测器与服务端对同一命令序列的田格状态一致。
- 章节：04:00 边界；每个 `player_day_id` 至多开一章；洛杉矶夏令时切换日两侧各一例；改设备时区不提前。
- 七日账本：四条路线（生活/出售 × 工具/扩地）数值全等；D2-D4-D6 田况轮换矩阵下差异 <5%；服务端跑。
- 动画：数据引用的每个动作要么有真实 clip 要么在占位登记表里。
- 客户端：杀进程重开后从服务端状态恢复到下一可行动作；访客命令全部被拒；返回状态恢复。

人工（每 Gate 一份清单，沿用 `2026-09-01-internal-demo-handoff.md` 的「机器验证 / 人工验收」两栏格式）：真机手感、轮廓识别度、转场、三条降级路径、两城各一轮。

---

## 8. 风险

| 风险 | 影响 | 对策 | 拍板时机 |
|---|---|---|---|
| 客户端预测器与服务端 reducer 语义漂移 | 动作后画面回跳 | 预测器只管田格视觉，不碰钱；对同一命令序列做双端一致性测试；漂移一律以回包覆盖 | 1.9 |
| 阿里云香港到上海 / 洛杉矶抖动 | 农场进不去 | 断线只读态 + 幂等重试；随包快照兜底访问；真不行迁 AWS us-west，compose 原样 | 1.8 |
| 域名与证书 | 没域名 Caddy 签不了证书，Godot 对自签证书很麻烦 | 先用公司现有域名的子域 | 1.8 前 |
| 洛杉矶夏令时算错 | 章节错位一天 | 规则写死 + 切换日两侧测试 | 3.2 |
| 劳作动画全是占位 | 观感 | 登记表 + QA 可视标记，正式动画外包按表交付 | G3 出口前 |
| OSM 在上海质量差 / 许可 | G0 返工 | 0.1 第一天先抓一次看主路完整度；候选人工挑；保存许可记录 | 0.1 第一天 |
| 贴地高亮在 pitch 45° 撕裂 / z-fight | 首屏印象 | 抬高 + 关深度写；退路 Android 原生 fill layer | 0.3 |
| 场景栈常驻地图内存 | 低端机 OOM | G0 出口测 RSS；超线改序列化 + 重建 | 0.4 |
| 手势与摇杆冲突 | H3 手感 | touch index 分流 + 点按替代 | 1.3 |
| 范围回涨（先做居民 / 季节） | 工期爆 | 只按 §4 顺序开任务；Plane 上没有的不做 | 全程 |
| 09-04 Demo 与 PRD 地图互斥 | 合伙人演示口径混乱 | 打 tag `demo-2026-09-04`，README 写清两条线 | 立刻 |

---

## 9. 目录规划

```
modules/blueprint/        蓝图加载、mask 查询、AStarGrid2D、高亮 mesh 生成
modules/farm_predict/     田格视觉预测器（薄，不碰经济）
modules/farm/             作物状态机、田畦、工具与手势、劳作动作队列、乐观副本
modules/net/              HTTPRequest 封装、鉴权令牌、时间偏移、幂等重试、断线状态
modules/world/            天气脚本、章节调度、导演模式（客户端侧）
modules/npc/              对话 runner、请求、关系
modules/visit/            快照、访客模式
server/                   Node 工程：src/domain（State/Command/Reducer）、src/http、src/db、test/、Dockerfile
scenes/city_select/       上海 / 洛杉矶 + 使用当前城市
scenes/map/               由 map_poc 演化：受限模式、候选高亮、簇与列表
scenes/select/            三候选选择流
scenes/farm/              农场实例（自有 / 访客共用，模式开关）
scenes/place/             地点实例骨架 + 3 布景
assets/blueprints/{layout_patch_id}/rNN/   json + mesh.res + preview.png
assets/farm/data/         全部内容 JSON + regions.json
assets/avatar/base/anim_placeholders.json  动画占位登记表
tools/geo_blueprint/      Node/TS 管线（geos-wasm + proj4 + pngjs，vitest）
tools/pipeline/bake_blueprint.gd   G4 再做（G0 运行时生成）
tools/deploy/             docker-compose.yml、Caddyfile、阿里云香港部署脚本
tests/{blueprint,farm_predict,farm,net,world,npc,visit}/   Godot 侧；服务端测试在 server/test/
```

---

## 10. Plane 对接与下一步

- G0 已拆成两份可执行任务单：`2026-09-03-g0a-blueprint-pipeline.md`（Node 管线）与 `2026-09-03-g0b-map-select-farm-greybox.md`（Godot 侧）。
- 建父任务「街角四季 MVP（G0-G4）」；SGODOT-21 改名挂为 G0 总览，子任务按 §4.1 七条；G1-G4 各建一条占位，开工前再拆。
- 本周可并行开工三条互不依赖的：**0.1**（先抓一次上海 OSM 看质量、确认许可）、**0.3 的地图受限模式部分**（不依赖蓝图）、**1.1 服务端领域层**（TypeScript，先把七日账本测试写出来）。
- 先把 09-04 Demo 打 tag，再在 main 上动地图场景。
- 1.8 开工第一天先在阿里云香港把 Fastify + PostgreSQL + Caddy 跑通一条链：鉴权 → 创建农场 → apply 一条命令 → 重启容器状态还在，再写业务。
