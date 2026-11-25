# farm-server

> 文档范围（2026-10-05）：P0 当前规则以 [玩法方案 v2](../docs/product/gameplay-plan-v2-2026-10-02.md) 为准，独立实现位于 `src/p0/`。下文是既有 Journey 服务的接口、持久化、迁移与历史版本记录；其中旧玩法、版本号和手机状态不代表当前 P0 或当前线上状态。发布请查 [发布流程](../docs/qa/release-playbook-android-ios.md) 及对应日期的 QA。

街角四季的权威状态服务。数值逻辑全部在这里，客户端不算钱（方案 D4）。

2026-09-21 的历史线上服务：`shoreline-farm-20260921`，domain `27` / content `50c2dbdde04c9678`；当时下载客户端为 Journey 0.16.9。OSM 陆地标注不足时，补充 ESA WorldCover 2021 地表覆盖数据，保留真实水体，不把未知区域当作土地。32×32 米布局、旧 v1/v2 地形和冻结预览保持兼容，无领域或数据迁移。836 项服务端测试通过；原失败选址、47 格真实存档的隔离副本搬迁、钓鱼和矿井验证通过，628 个原水体格全部保留。

手机当时继续运行 0.16.8：同一原选址已通过线上预览，当时页面保留，尚未确认搬迁；原账号、47 个作物格、资产、旧地形及选址机会保持。0.16.9 改善错误提示与水岸表现，原签名、无观察器 APK 已在模拟器验证并完成两站完整下载、哈希与 Range 核对；为保留当时预览，**该轮未在手机安装 0.16.9**。见[发布与验证记录](../docs/qa/farm-generation-error-2026-09-21.md)。

多人服务使用同源 `/v1/online` WebSocket，默认启用。生产入口通过 PostgreSQL 会话锁保证
同一数据库只有一个实时进程；HTTP 副本可设置 `REALTIME_ENABLED=0`，反向代理将该路径
固定送至实时进程。现有 Caddy `reverse_proxy` 支持 WebSocket；不可将多个独立房间进程随机负载均衡。
新增 `online_rooms`、`online_players`、`online_parties` 表由启动迁移创建，不重写旧农场存档。
协议、容量、恢复及测试命令见[多人架构](../docs/architecture/online-spaces.md)。

## 本地开发

Journey 钓鱼首版使用领域版本 `23`，结构版本仍为 `1`。domain 22 → 23 保留存档 JSON 与历史命令，钓鱼会话在首次主动抛竿时建立；见[钓鱼发布与真机验证](../docs/qa/fishing-2026-09-18.md)。存档内容版本不一致会拒绝写入，不能仅以 GET 或健康检查成功判断可玩。用 `tools/migrate_domain.ts` 先 dry-run，指定精确旧内容指纹，再于备份和停止旧 writer 后 apply；旧作物、成熟时间和历史命令保留。见[完整闭环、迁移与线上发布](../docs/qa/free-farm-online-2026-09-17.md)。本文下方带旧版本号的章节保留为历史说明。

数据库跑在局域网测试机 devserver（`192.168.124.53`）的容器里，本机不装 Docker 也不装
PostgreSQL。

```bash
# 首次：在 devserver 上起库
scp deploy/devserver-pg.compose.yml zhangshaojie@192.168.124.53:~/pg16-farm/compose.yml
ssh zhangshaojie@192.168.124.53 'cd ~/pg16-farm && echo "POSTGRES_PASSWORD=$(openssl rand -hex 16)" > .env && chmod 600 .env && docker compose up -d'

cp .env.example .env      # 填 DATABASE_URL / TEST_DATABASE_URL / TOKEN_PEPPER
pnpm install              # 在仓库根跑，workspace 会带上 blueprint-core
pnpm test                 # 当前 836 个用例；没有 TEST_DATABASE_URL 时 DB 套件跳过
pnpm typecheck
```

国内直连 Docker Hub 拉 postgres 镜像会断（`short read: unexpected EOF`），compose 里
已改用 daocloud 镜像源。

## 跑起来

```bash
pnpm exec tsx src/index.ts     # 需要 DATABASE_URL 与 TOKEN_PEPPER
curl localhost:3000/v1/healthz
```

启动时会校验全部在架蓝图，任一不过直接退出——不带病上线。

## 矿井战斗（领域版本 19）

共享数值位于 `mining.json`、`character.json` 和 `items.json`。
`mine_combat` 使用 `{run, floor, sequence, targets, hurt_by?}`，目标 ID 为本层的
`slime_1..3`；客户端上报命中，服务端从装备和怪物配置结算伤害、真实时钟攻击间隔、
全局受击保护、怪物生命、材料掉落及救援。客户端不指定伤害或奖励数量。
场景位置、AI 和命中几何使用客户端 Godot 导航；当前是单人战斗，不能当作联网动作防作弊方案。

新增独立 `weapon` 槽。首次入矿补发一次旧短剑，旧档已在矿中时也会投影补齐；
背包 ID 分配器与序号单调推进，原工具与所有物品保留。
角色保存 `hp`，穿脱装备只改变派生上限、不回血；`rest_character` 只在矿外恢复。
`use_bag_item` 同时支持料理回血，有效加成存在时不刷新次数。
怪物掉落属于自动奖励，可在满包时进入暂存；普通岩石保持原有满包回滚。

显式迁移接受领域 `1..18 -> 19`，原始存档和历史命令结果不重写。
旧档已清楼层不追补怪物，电梯解锁永久保留。规则和技术边界见
[战斗规则](https://github.com/IndieMiao/sensen-godot/blob/25b7a8a6e0574f9b0c4c97f480238e98d5d9985c/docs/product/mine-combat-2026-09-15.md)。
独立数据库回归：`node server/tools/test_combat_isolated.mjs`（仓库根目录）。
模拟器人工夹具：在 `server` 目录运行 `pnpm exec tsx tools/prepare_combat_qa.ts materials|full|restore`，
该工具只操作固定的战斗测试库、要求恰好一个普通农场，并在每次写入前备份完整行。

## 动态农场地块（C-31，0.4.2）

`/v1/parcels` 提供动态农场的地块认领、区域归属查询和地块内农场存档，身份沿用 `/v1/auth`。
启动迁移新增 `parcel_claims` 表（只新增，不改旧表）：主键保证一块地只有一个主人，
部分唯一索引保证每人一块免费地。首次进入自家地块（`/v1/parcels/mine/enter`）只发一次赠品；
数值在 `assets/farm/data/dynamic_farm.json`（所有者拍板 Q-39、Q-40）。
进入时客户端带上这次打开农场用的数据集，旧数据集上的认领会换到新数据集（C-136，所有者拍板 Q-168），见 [docs/plans/C-136.md](../docs/plans/C-136.md)。
“放弃并重选”只在设置 `DYNAMIC_FARM_RESELECT=1` 的内部测试服可用，正式配置不设，调用返回 403。
接口、表结构和选型理由见 [docs/plans/C-31.md](../docs/plans/C-31.md)。
正式服（C-96）只用邀请账号：`ACCOUNT_SIGNUP=closed` 时邮箱注册和 Apple / Google 首登建号都回 403 `SIGNUP_CLOSED`，
账号由 `tools/invite_accounts.ts` 直接写库。部署包、建库、备份恢复和回滚见 [deploy/dynamicfarm/README.md](deploy/dynamicfarm/README.md)。
起步区（C-130）：`assets/farm/data/dynamic_farm_starter_zone.json` 开着时，还没有地块的玩家只能认领区内地块
（按地块编号判定，区外回 403 `OUTSIDE_STARTER_ZONE`；区内核心格不足客户端 `min_core_cells` 的太小地块回 403
`PARCEL_TOO_SMALL`，C-143）；已有地块的玩家和他们的地块不受影响。
`GET /v1/parcels/starter-zone?dataset_version=…` 公开返回边界、地图默认落点和区内地块编号。
`PARCEL_STARTER_ZONE=0/1` 覆盖文件里的开关；扩大范围用 `tools/starter_zone_build.ts` 按新边界重新生成。
文件不合法时服务端不启动。说明见 [docs/plans/C-130.md](../docs/plans/C-130.md)。

## 自由选址（SGODOT-37）

`POST /v1/farms` 接受可选的 `location: {"lat": 31.225, "lng": 121.485}`。
`layout_patch_id` 仍决定逻辑格、寻路和种植规则，位置只平移地图上的布局。
同一模板可用于不同玩家的独立位置；每位玩家仍只有一座农场，接口不提供迁移或覆盖已有农场的行为。

`GET /v1/regions` 返回 `farm_placement_version: 1`，以及每个地区的
`placement_bounds: [south, west, north, east]`。这是游戏支持的选址范围，
不是现实土地所有权或可耕种性判断；选址校验在边缘预留 300 米以容纳地图布局。
客户端必须确认服务支持该版本，再发送带位置的建场请求，防止旧服务忽略新字段。

迁移只新增可空的 `farms.location` JSONB 列，旧农场没有位置值，继续使用原蓝图位置。
主人回包始终包含已保存位置；附近列表和访客快照仅在 `location_visible` 为真时包含位置。
关闭位置展示即时覆盖同一时间槽中的缓存快照，不必等待 15 分钟。

本地设备验证使用独立数据库，避免测试套件中的 `truncateAll` 清空正在体验的存档。
数据库名通过 `DATABASE_URL` 指定，服务用 `PORT=3101` 启动后，可通过
`adb reverse tcp:3101 tcp:3101` 和客户端 `user://server.txt` 中的
`http://127.0.0.1:3101/v1` 连接。测试服务不需要发布到公网。

## 领域语义 1 → 2（SGODOT-41）

本次 `DOMAIN_VERSION` 从 `1` 升到 `2`，`STATE_SCHEMA_VERSION` 仍为 `1`。
新增的居民 `choice_memories` 为可选字段，章节仍使用已有的 `step_flags`，无需改表结构。
启动入口中的 `db/migrate.ts` 只负责幂等 DDL，**不会自动执行本次规则迁移**。
未迁移的旧农场对新命令继续返回版本不匹配；旧幂等键仍先查历史命令，返回原结果。

显式工具为 `tools/migrate_domain.ts`，仅接受独立设置的 `MIGRATION_DATABASE_URL`，
不会加载 `.env` 或回退使用 `DATABASE_URL`。内容版本从本次发布的内容文件计算；
设置 `ASSET_ROOT` 时与服务启动入口使用相同目录，否则使用仓库内容目录。

```bash
# 在 server/ 下运行；MIGRATION_DATABASE_URL 必须由执行环境显式设置。
pnpm exec tsx tools/migrate_domain.ts          # 默认 dry-run，无持久化写入
pnpm exec tsx tools/migrate_domain.ts --apply  # 明确提交迁移
```

JSON 报告列出 `eligible`、`already_current`、`blocked` 和 `migrated`。
仅当前 `content_version`、结构版本 `1`、领域版本 `1` 的农场进入迁移；
匹配当前内容的领域版本 `2` 农场列为已完成。未知领域版本、其他结构版本或任意内容不匹配
会给出农场 ID、实际版本和拒绝原因，并阻止**整批 apply**，不会只迁移其中一部分。
拒绝时进程退出码为 `2`，执行或连接异常为 `1`；成功预览/提交为 `0`。

发布顺序：先备份并停止旧版本的写入实例，用待发布版本的同一份内容执行预览，
核对目标农场与零 `blocked` 后显式 apply，成功后再启动领域版本 `2` 的服务。
不要在旧写入实例仍会继续建场的情况下完成切换。内容不匹配应调查发布内容和存档来源，
不能直接改写 `content_version` 来绕过门禁。

apply 在一个事务内先取得 `farms` 的 EXCLUSIVE 写入屏障，再按 ID 排序取得行锁。
普通 SELECT 仍可读取；新建农场、命令更新和其他迁移在写入窗口内等待。
已开始的写事务先提交后才被检查，避免漏掉并发插入或覆盖刚提交的状态。
锁等待超过 5 秒会失败并回滚，排查旧写事务后可重试。

迁移只更新 `farms.domain_version`，保留 `state`、乐观版本计数、时间戳、钱包、库存、
身份、选址、建场记录、访客快照以及历史 `commands` 的结果和旧版本字段。
不会根据旧库存、收获记录或已做过的对话推断新的 D0 次批播种证据或选择回顾记录；
缺少明确事实时由新领域逻辑保守处理。重复执行幂等，事务失败整批回滚。
领域版本 `2` 已接受新命令后，不可只把版本列改回 `1`；应使用经过审查的前向修复，
或按发布前备份执行完整恢复。

迁移真库回归位于 `test/db/domain_migration.test.ts`。只使用新建的独立
`TEST_DATABASE_URL`，数据库名须包含独立的 `test` 或 `migration` 段；
该套件会清理测试表，不能传入运行中的服务数据库。

## 居民委托（SGODOT-114，领域版本 18）

沿用 `journey.opportunities` 三个槽和原六个变体顺序，每份定义补充稳定 `id`、
`resident_id`、需求原因 `description` 与完成回应 `reply`。新增蔬菜汤、铜矿石和铜箍木箱需求。
原 `wood/produce/dishes` 字段保持兼容，增加 `materials/props`，内部规范化为物品 ID 与数量；
永久装备与不可制作的摆件不能作为交付物。多份委托可以贡献同一种现有街边成果。

每槽保存 `accepted`，独立于唯一的 `tracked_opportunity`：

| 命令，均需 `slot/sequence` | 行为 |
| --- | --- |
| `accept_opportunity` | 接取并追踪；不推进序号，不收费；重复接取拒绝 |
| `track_journey_opportunity` | `tracking:true` 兼容接取并追踪；`false` 只取消地图追踪，保留已接委托 |
| `abandon_opportunity` | 清除接取与本次追踪，序号加一，保留同一变体，不扣物或金币 |
| `decline_opportunity` | 换至下一份已解锁需求，清接取与本次追踪，序号加一 |
| `fulfill_opportunity` | 必须已接取；完整扣料并发金币、推进街边成果，清本次接取与追踪，序号加一 |

所有操作共用可用条件；小馆始终需要首次共同用餐 `shared_meal`。
`decline_opportunity` 可选 `timber_only:true` 仅用于修缮师，直接换成已有纯木料工作，
使缺钱恢复不依赖矿坑或作物。已是纯木料时拒绝且保留接取，错误类型或其他人物的定向换单拒绝。
正常委托交付不增加友情点，不消耗 113 料理效果次数；手作品交付推进工作台序号。
最近完成结果保存在槽内 `last_completed:{offer_id,resident_id,sequence,consumed,coins,effect,contribution}`，
其中 `contribution` 是该成果完成后的阶段总数，封顶后仍按配方支付金币。
成功事件 `opportunity_completed` 包含同一结果及 `slot`；GET 可恢复结果，历史请求重放不重新结算。

显式迁移接受领域 `1..17` 到 `18`，只更新领域/内容版本列。
有效旧追踪在投影时成为已接委托；旧序号不能被当作完成数、关系奖励或成果证据。
17 版背包、装备、料理效果、矿坑与历史响应保持原样。
测试入口 `node tools/test_requests_isolated.mjs` 固定使用
`sensen_farm_journey_requests_test_20260914`。
模拟器夹具 `FARM_ID=<uuid> pnpm exec tsx tools/prepare_requests_qa.ts materials|shortage`
只访问 `sensen_farm_journey_requests_emulator_20260914`，先备份完整农场行，再递增版本。
夹具中的原料、解锁和指定需求均为人工开发条件，不是自然玩家成果。

## 人物属性与装备（SGODOT-113，领域版本 17）

共享规则位于 `assets/farm/data/character.json`，装备与料理仍来自统一 `items.json`。
基础属性为农具范围 `1`、采集加成 `0`、采矿加成 `0`、制作节省 `0`，整畦工具保留范围 `3`。
`bag.equipped` 增加 `accessory` 位，装备和料理属性相加，属性总值不写入存档。
铜镐在工具位使每块矿石多得一份石料，采集手套在配件位增加一份采集主材料，工匠围裙
在配件位节省一份工作台基础材料。三件装备在工作台修好后以材料制作，每种最多拥有一件，
制作后进入背包，不自动换装，不可丢弃。成本、加成和料理次数以共享配置为准。

沙拉、矿盐蔬菜汤、花草茶分别增强随后三次有效采集、采矿和工作台制作。`state.character`
保存 `{version:1,buffs:[{id,source_item_id,remaining_uses}]}`；同种效果未结束时拒绝重复食用，
不同效果可以并存。采集主材料按数量最大选择，同数按木料、石料、芦苇顺序；只作用于
`collect_resource`，不作用于设施、发现点或农田收获。矿坑只增加石料，矿物抽签保持原哈希。
工作台节省先应用装备、再应用茶，按木料、石料、芦苇逐份减少，每项最低保留一份，
铜矿石和岩盐不打折；茶只有额外贡献时才扣一次。首次花箱、重复手作与装备制作都适用，
料理和工程建设不适用。所有效果次数与成本、产物、世界状态在同一事务里成功或回滚。

新增主人命令 `use_bag_item {stack_id,sequence}` 和 `craft_equipment {item_id,sequence}`。
`unequip_bag_item` 新增可选 `slot:tool/accessory`，缺省仍卸下工具。
成功命令返回顶层 `events`，制作事件包含 `actual_saved` 材料数量，普通 GET 不重发事件；
幂等重放返回该次历史状态和事件，不能再次扣料或扣效果次数。新增错误为
`EFFECT_ACTIVE`、`EQUIPMENT_OWNED`，沿用满包、序号与材料错误。

显式迁移接受领域 `1..16` 到 `17`，只更新领域/内容版本列，旧命令与存档原文保留。
旧背包缺少配件位时补空位，旧人物状态补空效果，不发放新装备、不导入过期汇总。
本轮隔离回归使用 `node tools/test_character_isolated.mjs`，固定数据库
`sensen_farm_journey_character_test_20260914`，不会操作运行中的试玩数据库。

## 统一背包（SGODOT-112，领域版本 16）

`assets/farm/data/items.json` 为双方共用的物品目录。背包初始 24 格，种子、作物、材料与矿物
每堆最多 99，料理与摆件每堆最多 20；工具是数量为 1 的独立实例。基础工具和整行工具
共用一个装备位，装备位不占格。首次购买整行工具自动装备，旧工具进入背包；之后可显式换装。

`state.bag` 是库存权威，包含 `version`、`sequence`、`capacity`、`next_id`、`slots`、
`overflow` 和 `equipped.tool`。每堆具有稳定 `id`、`item_id`、`quantity`、`quality`，
种子保留 `seed_lot`，工具保留 `instance_id`。品质、种子来源或实例属性不同不会合堆。
旧的 `inventory`、`journey.wood/materials/workshop.stock`、`tools.row_tool` 是兼容汇总；
其中 `row_tool` 表示拥有，不表示当前装备。工程预留是已有产物的标签，不另计一份物品。

所有普通获取、消费与制作在 reducer 中先整笔扣料再尝试装入产出。满包返回 `BAG_FULL`，
不会消耗成本、破坏矿石、收获作物或提前领取奖励。纯消费仍可在满包时进行，优先消耗暂存物品。
旧存档与自动章节奖励超出容量时进入 `overflow`，保留全部数量；可整理、消费或领取回空格。

背包命令通过已有主人命令端点提交，并要求当前 `sequence`：

| 命令 | 其他字段 |
| --- | --- |
| `split_bag_stack` | `stack_id`, `quantity` |
| `merge_bag_stacks` | `source_id`, `target_id`，目标填满后保留来源余量 |
| `sort_bag` | `mode: category/name` |
| `discard_bag_stack` | `stack_id`, `quantity`，保护工具和工程预留产物 |
| `equip_bag_item` | `stack_id` |
| `unequip_bag_item` | 无，背包满时拒绝 |
| `claim_bag_overflow` | `stack_id`，只领取可装下的部分 |

背包改变后序号增加，过期操作返回 `BAG_CHANGED`；HTTP 幂等重放仍返回原结果。
旅程模式的首次花箱进入背包，庭院 `save_decorations` 新增扣物、移除返物，移动旋转不扣物。
旧旅程的免费庭院道具按解锁权限转换为一次持有权：已摆放者留在场景，未摆放者进入背包，
原工作台库存额外完整保留。非旅程模式沿用历史免费庭院规则，开始旅程时再转换。

显式迁移接受领域 `1..15` 到 `16`，只更新领域/内容版本列，保留结构版本 `1` 与历史命令。
缺少背包的状态在主人投影中确定性转换，首次成功命令持久保存；已有背包不会再导入旧汇总。
部署时先记录旧内容哈希，再按下节命令传 `--previous-content-version` 预览并应用。
本地隔离验证可运行 `node tools/test_inventory_isolated.mjs`，仅使用固定的背包测试数据库。

## 新手矿坑（领域版本 15）

普通新农场直接开放五层矿坑，每层六块矿石。共享配置为
`assets/farm/data/mining.json`；每块固定获得一份石料，并按配置权重额外获得铜矿石、
岩盐或无额外材料。掉落由服务端农场 ID、探矿轮次、楼层和矿石 ID 确定，重试、
改变挖掘顺序、离开重进不会重新抽取。没有战斗、体力或现实时间刷新要求。

主人首次 `enter_mine {run: 0}` 才建立可选的 `state.mine`，不会在读取旧存档时写入。
`floor: 0` 表示农场，`1..5` 表示矿层；`broken` 按楼层字符串保存已挖矿石，
`cleared_floors` 保存本轮完成楼层。`mine_rock {run, floor, node_id}` 必须在当前楼层，
`descend_mine {run, floor}` 要求挖完本层全部矿石，`ascend_mine {run, floor}` 可返回上一层。
`leave_mine {run, floor}` 回农场并保留进度；再次进入从第一层开始。

第五层全部挖完后永久开放电梯，`use_mine_elevator {run, floor}` 仅在第一层和第五层互通。
完成第五层且已回农场后，`restart_mine {run}` 才能显式开始下一轮；保留全部库存与电梯，
增加 `run` 并清空矿石和本轮楼层完成记录。所有命令还需现有的 `base_version`、
`idempotency_key`，过期轮次、重复矿石与非法楼层被拒绝。矿坑进度和掉落不出现在访客快照中。
客户端在全部五层已完成后的下一次访问，自动顺序调用 `restart_mine` 和 `enter_mine`。
部分完成时仍进入原轮；只完成第五层时可从第一层的明确按钮主动重开。
这是客户端流程衔接，未改变读取接口、命令载荷或存档格式。

铜矿石和岩盐保存在可选的 `journey.materials.copper_ore/rock_salt`，旧存档缺失值按零读取。
铜箍木箱复用工作台制作、库存及设施陈列：消耗 2 木料、3 铜矿石和 1 石料。
岩盐蔬菜汤复用厨房与摊位：消耗 1 萝卜、1 生菜和 1 岩盐，售价 16 金币。
扣料与产出原子结算，不改旧配方、存量物品或历史命令结果。

该次版本的显式迁移接受领域版本 `1..14` 到 `15`；当前目标版本见“统一背包”。保持结构版本 `1`，只更新农场的领域版本和
内容版本。先记录旧服务 `/v1/healthz` 的 `content_version`，用新内容运行预览：

```bash
# 在 server/ 下运行，MIGRATION_DATABASE_URL 指向明确要升级的数据库。
pnpm exec tsx tools/migrate_domain.ts --previous-content-version "$PREVIOUS_CONTENT_VERSION"
pnpm exec tsx tools/migrate_domain.ts --previous-content-version "$PREVIOUS_CONTENT_VERSION" --apply
```

预览有 `blocked` 时先解决版本来源，不改写状态绕过检查。普通服务启动不会自动执行规则迁移。
旧幂等键仍可返回历史结果；未迁移农场的新命令继续返回 `VERSION_MISMATCH`。
验证入口为 `test/domain/mining.test.ts`、`test/db/store_conformance.test.ts` 与
`test/db/domain_migration.test.ts`，数据库套件须使用独立测试库。

## 庭院摆件存档（SGODOT-45）

`save_decorations` 通过既有命令端点原子替换整份庭院布置。仅完成工具或扩地购买后开放，
历史非旅程模式的六件摆件免费，每种最多一件；旅程模式现在使用统一背包扣返，见上文。
空列表表示全部收起。命令仍受版本、幂等和主人身份校验保护。

```json
{
  "type": "save_decorations",
  "payload": {
    "props": [{ "anchor_id": "courtyard", "prop_id": "bench", "offset_q": [-4, 3] }]
  }
}
```

封套还需提供 `idempotency_key` 和 `base_version`。六个 `prop_id` 为
`bench / planter / lantern / fountain / sign / crate`，不接收旋转或额外私有字段。
`offset_q` 是庭院独立实例的 `[x, z]` 整数坐标，每单位 0.5 米，不能当作农田 `cell_id`。
共享内容表 `assets/farm/data/decorations.json` 定义合法区域、中央通道、固定布景避让和默认位置。
当前可用区域为 `x = -6..-3 或 3..6`、`z = 3..5`，排除 `abs(x) >= 5 且 z <= 3`，
任意两件中心间距至少 2 个量化单位。任一摆件非法时返回 422，原布置与版本不变。

主人状态使用可选 `state.decorations`；早期领域版本 2 存档缺少此字段时按空列表读取，
首次保存才写入，不在 GET 中补写数据库。新农场初始化为空列表。本变更不升级
`DOMAIN_VERSION` 或 `STATE_SCHEMA_VERSION`，不修改自动或显式迁移工具。
新增内容表参与 `content_version`；旧内容版本存档仍受现有门禁限制，不会自动改写版本。

访客快照复用已有 `props` 白名单，只包含 `anchor_id / prop_id / offset_q`，
按既有 15 分钟快照槽更新，不包含钱包、成长购买、库存或居民状态。
保存、重载、幂等、失败不覆盖和访客隔离回归在 `test/db/decorations_conformance.test.ts`，
同时覆盖内存 Store 与配置了独立 `TEST_DATABASE_URL` 的 PostgreSQL。

## 首周结局（SGODOT-43 / SGODOT-46）

`state.week_summary` 在 D6 章节完成且 `life_choices[6]` 已明确记录后生成。
共同场景先完成但第六次用途尚未选择时不生成，也不会默认把缺失选择当作出售。
不增加金币、物品、经验或关系；摘要记录首次满足条件时的真实状态，后续耕作与交易不改写它。

摘要包含 `id: first_week`、服务器时间 `completed_at`、玩家日 `completed_day`、
`wallet / xp / level`、已购买的 `growth_choice`、苗圃状态和三名居民的真实点数与阶段。
`choices` 只含已确认的 D1-D6 用途，`life_choice_count` 是其中 `gift` 或 `keep` 的数量。
达到内容表阈值 4 时 `life_priority=true`：`photo_variant=personalized`、
`journal_pages=[shared_harvest,familiar_faces]`、`next_week_clue=resident_seed_exchange`；
否则为合法出售结局：`photo_variant=standard`、空手写页列表、`next_week_clue=nursery_next_stage`。
手账仅追加一次 `kind=week_summary / key=first_week`，访客快照不包含摘要及其分支。

旧存档已满足条件时，GET 在克隆状态中按最后持久化动作时间确定性投影摘要，不写数据库；
下一条成功命令持久化同一摘要。失败命令、重复请求和跨日读取不能重复生成手账页。
摘要余额是完成时点的快照，可能与玩家之后交易后的当前钱包不同。

`test/db/chapter_conformance.test.ts` 覆盖工具/扩地 × 生活/出售四路线，
在上海及洛杉矶（含 DST）分别运行 MemoryStore 与 PostgreSQL HTTP 流程。
最终钱包分别为工具生活 305、扩地生活 145、工具出售 376、扩地出售 200。
最后一项沿用既有账本规则：D6 触及 100 金币摊位预算，2R 留在库存；
不能为了达到旧 PRD 的 216 数字超额结算。所有路线验证重登、幂等和摘要不提前锁定。

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

### Geographic farms and relocation (retired, SGODOT-304 / 342)

Map-generated farms (OSM + WorldCover terrain, domains 25–27) and the one-time relocation were retired with the Journey service (stopped 2026-10-16). `POST /v1/farms` with `generation_version` answers `410 FARM_GENERATION_RETIRED`; the relocation routes are gone. Farms start from a curated city's street candidate. The `farm_terrain` and `relocation_*` columns stay in `schema.sql` but are no longer read or written; `tools/migrate_domain.ts` refuses (`geographic_farm_retired`) to upgrade a map-generated farm. The design notes are in git history before this change and in `docs/qa/*geograph*`, `docs/qa/*relocation*`.
