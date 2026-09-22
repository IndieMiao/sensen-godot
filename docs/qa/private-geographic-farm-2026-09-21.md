# 街区与农場合并：本地实现与验证

日期：2026-09-21。对应[产品约定](../product/private-geographic-farm-2026-09-21.md)。本轮最初完成本地及模拟器验证；用户随后明确要求真机安装与线上更新。**Journey 0.16.5 / 2026092101、配套 Domain 26 已上线，原签名更新包已安装 V2509A。** 下文先保留本地验证记录，随后补充正式发布证据。未向 Joey 发送消息。

## 已实现

- 正常入口统一进入按玩家隔离的私有农场。地图选择任意城市内选区，服务端生成地形，不再选择固定街区卡片。
- 新农场为 64×64 格、0.75m/格（48m），真实地理采样范围为 240m。保存 OSM 来源、抓取时间、来源摘要、生成版本、地形及 checksum；两端种田、摆放、导航与地面同源。
- 原街区的居民、资源选择、聚会与设施入口接入农场。任务、领取与物品 ID 延续；室内苗圃/厨房/庭院空间保留。资源领取仍由服务器确认。
- 保留可达鱼塘和初级矿井。原始选区全水、全沙漠、连续可用土地不足、必要设施会覆盖过多真实水体时拒绝生成；取不到地理数据时提示重试/重选，不代填蓝图。
- 使用现有农场模型、近景相机及水面；新增布局采用连续地表纹理、柔化草边、泥土颗粒与路边植被。钓鱼侧视重新计算相机裁剪范围，退出时恢复。
- 组队与旧街区协议均遵守农场访问权限。访客只收到需要的几何，隐藏原位置、来源引用和 OSM 元素 ID，保留已保存的美术风格。
- 用户明确选择保留旧农场：旧地形、作物、摆放和资产不重新生成。Domain 26 的 25→26 迁移保留原 state JSON，新增可空地形列；旧农场读取继续使用原布局。

## 自动化与真实地图来源

完整隔离 PostgreSQL 服务端检查：739 项通过，日志 `output/private-geographic-farm-2026-09-21/server-tests.log`。后续复核修复另外通过来源隐私、缓存完整性、多外环岛洞、生成美术风格专项及 TypeScript 检查；这些专项不重复累加为完整套件数量。

Godot 检查覆盖选址/失败恢复、同一农场实例复用、居民与采集命令、旧农场、访客、服务端几何 checksum、两片水体的独立岛洞、接近格边界的双精度多边形/道路、相机与钓鱼恢复。本轮报告位于 `output/unified-farm-2026-09-21/client/`、`output/private-geographic-farm-2026-09-21/qa/` 及 `reports/report_1217`。后者 15 项地形测试通过；生成数据与会话契约的最终 73 项检查通过；12 项农场集成检查通过。

扩展的原生 Godot 回归另有 251 项、28 个套件全部通过，覆盖地图、场景路由、实际画面读回、街区历史交互和矿井；报告 `output/unified-farm-2026-09-21/client/map-scenes-mining-native.xml`。旧农场场景单独回归 46 项通过（`qa/legacy-scenes/report_1/results.xml`）；原来要求标题为街区名的断言更新为“我的农场”，服务端布局优先级与保存身份断言继续保留。

两份实际 OSM 数据为上海人民公园（31.2341,121.4704）和洛杉矶 MacArthur Park 北侧（34.0596,-118.278）。原始响应、查询、规范化地物、生成地形及哈希清单位于 `output/private-geographic-farm-2026-09-21/geo/`。正常数据不是测试夹具。`tests/fixtures/generated_farm_terrain.json` 等固定样例明确用于合成边界测试。

早期 MacArthur Park 湖心样例因必要设施将覆盖过多原水面，被后续检查拒绝；`*-rejected-pre-guard-terrain.json` 及 `native/home.png / geographic_water.png / overview.png` 仅为排错历史，不是最终验收结果。

## Android 与画面

设备：Android 模拟器 `emulator-5560`。隔离包 `com.sensen.journeygeofarmqa`，标识 `0.16.5-geographic-farm-qa`。通过 `tools/android/run_test.sh` 启动和结束每次场景验证，原 Journey 应用与存档保持原状。

选址与农场验证使用记录下来的真实 OSM 数据，以及本机隔离 MemoryStore HTTP/WebSocket 服务 `127.0.0.1:3191`。真实来源只覆盖指定小范围，超出范围明确返回数据不可用。数据库重启与迁移由上述 PostgreSQL 测试覆盖，不把内存服务当作持久化证据。

普通触控已验证：在地图上重新选择区域、无数据时建场失败且没有农场、重新选择有效位置并生成、进入私有在线农场、开垦/播种/浇水产生服务端成熟时间、点击矿井模型进入及返回、步行至鱼塘岸边、抛竿、咬钩提竿、按住/松开拉竿、收竿返回。生成结果在重新启动隔离客户端后不变，已种作物继续保留。

开发期间修正了 QA 脚本的按钮源文案匹配、相机跟随后田地移到 HUD 下、场景栈模拟及咬钩阶段名；已有隔离存档连续复用，没有为通过测试反复重置农场。选址/建场与种田证据来自前序会话，最终 10 次触控复核沿同一存档完成矿井和钓鱼往返。`android/result.json` 汇总的是这些分段证据，不代表一次未中断的新玩家会话。

最终 Android 画面已检查：`android/03-farm.png`、`04-farming.png`、`05-mine.png`、`06-pond.png`、`08-reeling.png`、`09-ready.png`；客户端日志无脚本或 shader 编译错误。取样为 60 FPS，仅代表本机模拟器的这些场景，不推断真机或长时间性能。

所有修复后的最终 QA APK 已覆盖安装并冷启动检查，`android/final-smoke-result.json` 通过：同一隔离账户、同一生成农场、作物 ID/成熟时间保持，私有房间重新加入成功，日志无脚本或 shader 错误。测试会话已结束，模拟器保持运行。

原生 Mobile 画面已检查：`native/shanghai_home.png`、`shanghai_pond.png`、`shanghai_overview.png`、`shanghai_road_detail.png`，以及最终合格洛杉矶北侧布局 `native/la_north_home.png`、`la_north_water_edge.png`、`la_north_overview.png`。后者可见不同道路网和南侧真实湖面，住宅与矿口保持干燥。真实上海布局的本机地形注册约 63ms、512px 地面纹理约 72ms；纹理使用原生 SVG 光栅化，缓存有上限。Headless 个别套件退出仍有 ObjectDB/DummyTexture 提示，与原生/Android 运行期错误分开记录。

最终缓存完整性回归 16 项通过（`reports/report_1221`）：已有缓存也核对完整地形内容，不能用未改变的声明 checksum 绕过几何/锚点变化检查；清理来源 ID 后的私有访客几何正常接入。生成元数据损坏时保留原身份和存档，停止写入并要求有效刷新。

## 当前边界

沿用目前可选择的上海和洛杉矶城市范围。OSM 标注不足的土地或未标注海面可能返回“地理数据暂不可用”，不能保证城市内每一点都可生成。新位置必须通过原始地表与可达性检查；现有农场不因此失效。

本轮没有提供旧农场主动搬迁。旧农场继续使用原地形，新建农场采用真实地理生成。用户的自然体验反馈仍待后续验证。

## 用户授权后的真机与线上更新

用户明确要求“安装真机进行测试”，随后要求“更新到线上，我真机验证下”。最终包仅为原 `com.sensen.journeypreview`，证书 SHA-256 `38771d94b8fbfa11651cc440e3746c9182114461a90cc0ab7188d7b708515673`；不含测试观察器。临时新农场 QA 应用因转入线上发布而未进行真机流程验证，已从本轮新增的手机用户空间移除，原有应用保留。

V2509A 在原账号、正式服务上完成农场进入、矿井往返、到池塘岸边、抛竿、提竿、按住/松开收线、取消并恢复相机、地图返回及重新进入。取样 83–89 FPS，不代表长时间性能或所有场景。原五份身份/外观/偏好文件逐字节不变；47 个地块、装备实例、库存、187 金币及其他状态保留，仅有正常时钟推进和本轮已确认的钓鱼取消序列。见 `device/original-flow.json`、`device/installation.json`、`device/private/tested-farm.json`。

真机阶段还修复了两个兼容问题：旧服务的街区传送票据不再错误用于农场场景，而是提示更新服务并保留当前连接；生成地形缓存以完整浮点精度写盘，防止严格校验拒绝同一份缓存。30 项原生 Mobile 专项通过，见 `device/compatibility-tests.xml`。

发布目录 `/opt/farm/journey-preview/releases/private-geographic-farm-20260921`。先从正式库备份、恢复独立数据库，验证迁移，再在生产主机通过实时 OSM 分别创建上海和洛杉矶农场，完成真实 HTTP/WebSocket 农作、幂等重放、私有访问、钓鱼及旁观广播、矿井和重启恢复。演练最初因仅连接数据库内网导致外部 DNS 失败，补接原生产已有的外网后通过；没有改动生产网络配置。测试账号及对象已从演练库恢复清理，演练服务停止。

正式切换于北京时间 **2026-09-21 12:37:10–12:37:26** 进行。维护窗口内停止唯一 writer、重新备份，再增加可空地形列并迁移 **25→26**；内容指纹仍为 `50c2dbdde04c9678`。迁移前后逐行比较九张表，**74 座农场、288 个当时已种作物、1,422 条历史命令、账号/令牌、队伍及房间均保留**；`state::text` 完全一致，旧农场的地形列均为空。数据库、签名身份服务、LiveKit 配置和原双网络保持不变。服务发布标识 `private-geographic-farm-20260921`，镜像 `sha256:34709947b949b8adcc67c7fc4341dd6e8bdf735b45ac25251133df11dea0dcac`。

证据：`release/live-migration.json`、`release/rehearsal-http.json`、`release/rehearsal-restored.json`、`release/rehearsal-reset.json`、`release/public-health.json`、`release/public-capabilities.json`。私有数据库备份、认证和原始存档留在私有目录，不在公开下载中。

正式 APK：`sensen-journey-geographic-farm-0.16.5.apk`，156,390,062 bytes，SHA-256 `79f86aaf9465ed5b90bf0548bd398d655ca5907a855dc0e32b4363c83ab8f0d4`。从真机拉回的 APK 哈希与最终包一致。

服务切换后，无观察器的最终包在 V2509A 冷启动并进入“我的农场”，已检查实际完成加载的画面；`device/final-smoke.json`、`device/final-installed.png` 通过，原五份文件仍逐字节相同，农场版本与最后一次已确认测试结果一致。真机测试会话已结束，用户可自行打开 Journey 验证。

- [DMIT 美国下载](https://download-us.sensenjoy.cn:8443/farm/releases/private-geographic-farm-20260921-79f86aaf9465/sensen-journey-geographic-farm-0.16.5.apk)
- [OSS 备用](https://oss.sensenjoy.cn/farm/releases/private-geographic-farm-20260921-79f86aaf9465/sensen-journey-geographic-farm-0.16.5.apk)

两个地址均已通过 HTTPS 完整下载、哈希、Range 206、范围内容及清单/校验文件检查；见 `release/download/verification.json`。没有向 Joey 或其他联系人发送消息。
