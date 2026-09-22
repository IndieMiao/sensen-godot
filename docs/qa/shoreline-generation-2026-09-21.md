# 湖岸选址生成失败：诊断、修复与发布验证

日期：2026-09-21。**服务端修复已上线，真机原来的失败选区已原地生成预览成功。** 发布标识 `shoreline-farm-20260921`，domain 27 / content `50c2dbdde04c9678` 保持。客户端 **0.16.9 / 2026092105** 已发布并在模拟器安装验证；为保留用户当前成功预览，V2509A 继续保持 **0.16.8**，本轮没有重启或覆盖安装手机，也没有确认真实用户搬迁。

证据根目录为 `output/farm-generation-error-2026-09-21/`。32 米农场的既有约定见[紧凑农场验证](compact-farm-2026-09-21.md)。

## 原页面与定位证据

用户在 V2509A 的 **0.16.8** 重新选址页面遇到地理生成失败，画面位于洛杉矶 Silver Lake Reservoir 西侧。为保留用户正在选择的位置，诊断期间没有重启、重装、返回或拖动原应用页面。原始画面及日志为 `current.png`、`current-game.log`。

通过只读 JDI 字段读取取得原生地图相机缓存：**34.09875, -118.26627，zoom 16、pitch 45**。工具记录为 `ReadMapCamera.java`。该缓存按 **5 位小数**格式化；客户端实际预览请求使用 6 位小数，因此这里是从现存相机恢复的重放中心，不能声称已经取回原请求的全部精度。下文名称含 `exact-west-reservoir` 的文件表示在这个恢复中心保存的精确重放数据，不表示找回了原始 6 位小数请求体。

只读查询原农场时，`has_draft=false`、`draft=null`，资格仍 `available=true`、`used=false`，见 `device/draft-before.json` 及其私有原始 CloudCommand 回执。失败预览不会写入手机的确认命令日志或覆盖 `FarmChoice`；原用户农场、资产及搬迁机会未因本轮诊断被迁移。修复后已在同一原页面仅点击一次“预览这个位置”，成功结果与完整精度的请求位置见本页发布章节；**没有代用户确认搬迁**。

## 实际失败原因

在恢复中心进行真实请求重放时，Overpass 返回 **HTTP 200**，约 5.2 秒取得 **5 个 OSM 对象**：4 条道路及 1 个水库外环。地理服务取数成功，但这一选区没有 OSM 土地用途多边形。

在 40×40 的源分类网格中，旧算法得到 **972 格未知地表、628 格水体、0 格已知可用陆地**，最大已知陆地连通分量为 0。道路能够参与道路外观，不能独自证明周边未知地表适合建农场。旧实现将这类完整取数但覆盖不足的情况也报成 `GEOGRAPHY_UNAVAILABLE`，于是用户看到类似地图服务暂不可用的提示。证据为 `geography/exact-west-reservoir.json`、`exact-west-reservoir-raw.json` 和 `exact-west-reservoir-geography.json`。这是该恢复中心的可重复结果；不冒充对原手机请求全部网络细节的捕获。

第二个问题是固定设施与湖岸不相容。只读相交分析显示，旧固定设施区域会与 **250 格已观测湖水**冲突，超过当时允许的 50 格上限。这个数字是生成前的冲突分析，**没有执行填湖或修改用户农场**。仅补上土地覆盖信息而保留固定设施位置，仍不能正确生成该湖岸农场。证据 `geography/exact-west-reservoir-facilities.json`。

## 使用真实土地覆盖并保留湖岸

补充数据来自 **ESA WorldCover 10m 2021 v200** 的真实瓦片 `N33W120`。开发采样记录为 **2 次 HTTP Range 请求、累计 131,072 字节**，得到 39 个覆盖地物；这只是本次样本的取数记录，不是长期吞吐或所有地点的性能保证。

记录中的分类像元如下。这是土地覆盖采样窗口的像元统计，不是农场的格子数量：

| ESA 类别 | 含义 | 像元数 |
| --- | --- | ---: |
| 10 | 树木覆盖 | 69 |
| 50 | 建成区 | 161 |
| 60 | 裸地或稀疏植被 | 30 |
| 80 | 常年水体 | 136 |

数据保存于 `geography/exact-west-reservoir-land-cover.json`，是 **2021 年**的土地覆盖产品，不是实时卫星影像。OSM 的精确水库多边形继续决定已观测湖岸，补充覆盖信息不把水体改判为陆地，也不把未知地表直接视为可用草地。全水、全沙漠、未知覆盖不足与必要设施不可达仍有明确拒绝规则。

设施改为在可用陆地中适配位置，真实主水库 **628 格全部保留**。这个记录的最终农场仍为 **32×32 米、40×40 格、800 毫米/格**，地理选区 160 米；可行走 **730 格**、可耕种 **397 格**。房屋锚点为 `[22,33]`，出生点 `[22,30]`，矿井 `[19,31]`；独立钓鱼塘中心保持在相应地形椭圆 `[8,33]`，其默认抛竿验证通过。结果见 `geography/exact-west-reservoir-fixed-report.json`、`exact-west-reservoir-fixed-terrain.json`。

来源与许可随地形持久化：OSM 为 © OpenStreetMap contributors、ODbL 1.0；ESA 为 **CC BY 4.0**，署名 **ESA WorldCover 2021 v200 (Zanaga et al., 2022; DOI:10.5281/zenodo.7254221)**。`source.land_cover` 记录数据集、年份、分辨率、瓦片、分类及来源校验和。已有农场不重新生成；访客仍不获得主人的位置与来源元数据。

真实记录的固定回归样本为 `tests/fixtures/generated_shoreline_farm_terrain.json`，与上述结果文件逐字节相同，共 40,601 字节，文件 SHA-256 为 `b042089a84ded2df21bfaa9c56b981ba12273bbc63ae84c3a3be94084cd48e2d`，地形 checksum 为 `60c376d6bd1207be96537ea361a5975b37c81ef5378c3fabbaa9693a88586513`。对应 OSM 与 ESA 输入、来源说明见 `tests/fixtures/shore_osm_geography.json`、`shore_land_cover.json`、`shoreline-geography.md`；这些是实际记录，不是演示蓝图或兜底地图。

## 客户端反馈与边界美术

客户端区分三种情况：

- `GEOGRAPHY_INCOMPLETE`：已取到地图信息，但真实地表覆盖不足；提示拖动地图重新选址。
- `GEOGRAPHY_UNAVAILABLE`：服务暂不可用、超时或取数/解析失败；提示稍后重试。
- `INVALID_FARM_TERRAIN`：成功响应的地形未通过客户端校验；提示重试载入。该代码是客户端本地错误，不再混同上游不可用。

没有放宽地形 checksum、网格、设施锚点和缓存一致性检查。错误和重试保留正在选择的位置、原农场缓存及资格；确认结果不明时仍保留原请求并核实，不能当作未提交而取消。没有增加包含认证或选址坐标的客户端日志。

生成农场的外围石块、灌木现在避开边界水体，并检查相邻一格的覆盖范围，避免在真实湖面上形成悬空围墙。干岸保持原排列，旧农场的完整边界不变，内部岩地摆景仍按真实地面类型筛选。鱼塘的水面、岸景、地表遮罩、寻路、点击和钓鱼继续使用当前农场自己的几何；访客不会使用自己家里的鱼塘位置。

## 自动化及原生画面验证

最终冻结源码的完整隔离 PostgreSQL／服务端回归 **836/836，75 个测试文件全部通过，无跳过**，TypeScript 通过。见 `server-tests-final.log`、`server-typecheck-final.log`。此前 833 项及各专项不重复相加。

设施适配先按已确认干地的连通分量剪枝，地理水体只栅格化一次；上限为 4,096 个候选、96 次设施栅格化。断开岛屿和狭长半岛拒绝案例有计数回归，最坏样例约 240–300ms，仅为受控测试测量；实际湖岸样本只用 1 个候选和 1 次设施栅格化，布局与校验和保持不变。

本轮相关客户端原生回归合计 **544 项通过**，均为零错误、零失败、零孤立节点：

| 套件 | 数量 | 证据日志 |
| --- | ---: | --- |
| 农场 | 245 | `native/farm-tests.log` |
| 钓鱼 | 19 | `native/fishing-tests.log` |
| 地图 | 142 | `native/map-tests.log` |
| 网络 | 109 | `native/net-tests.log` |
| 本地化 | 9 | `native/localization-tests.log` |
| 摆放面板 | 20 | `native/decoration-tests.log` |

农场套件已包含 3 项真实岸线检查和 4 项水岸边界检查；网络、地图套件包含错误区分、重试保留位置与机会的检查，不能再次累加这些专项。此前 0.16.8 的 562 项是另一批验证，本页不将两批相加。农场套件退出仍有既有的 5 个 ObjectDB 引用提示，套件没有孤立节点或运行错误；不据此推断 Android 长时间性能。

真实样本在 Godot 中通过未修改的地形 checksum 校验，628 格主水库逐格保持为水体且不可通行；出生点至矿井、塘岸、站位、摊位及出口均可达，默认抛竿有效。主人元数据读写保持，去掉来源的访客快照也能载入相同几何；旧农场缓存、全局旧鱼塘配置及资产未改写。

`native/recorded-shore-owner.png`、`native/recorded-shore-visitor.png` 已完成画面检查：真实湖岸保留，水边没有外围浮石围墙。两张图使用**测试专用俯视相机**检查整片岸线，不表示默认游戏镜头改为远景。

## 隔离 Android 全流程

模拟器隔离包 `com.sensen.journeyshorelinefarmqa` 使用独立账号与记录下来的真实 OSM、ESA 数据，通过 `tools/android/run_test.sh` 管理会话。最终 `android/result.json` 为 `passed=true`，共 **21 次触控**，`continued_after_harness_navigation=false`。

流程完成旧农场进入、选址与预览、取消、不可用位置、重新预览及明确确认、32 米农场进入、种田、矿井往返、钓鱼及收线。确认迁移 **3 个地块、1 个摆放**；取消和错误不消耗资格，成功确认仅消耗一次，资产及作物成熟时间保留。该流程的确认仅作用于隔离账号，**没有消耗真实用户的搬迁机会**。

会话日志为 `qa/android-session.log`。`android/03-preview.png`、`06-confirmation.png`、`07-new-farm.png`、`08-mine.png`、`09-farming.png`、`10-pond.png`、`11-reel.png`、`12-ready.png` 等画面已产出；默认近景农场、种田及收线关键截图已由主任务复核，房屋和必要设施位于陆地，湖水与岸边保留。流程断言通过不等同于已完成自然用户旅程或长期性能验收，隔离内存服务也不替代数据库持久化与正式服务演练。

## 生产演练与正式切换

生产主机克隆库使用正常实时 OSM 和 ESA 请求验证原失败区域，生成与预览成功，628 格原始水库全部保留。把克隆库中的真实 47 格存档复制给新建隔离 QA 主人，再确认搬迁：作物内容、成熟时间、实例、数量和资产均保持，原来源农场行不变；实际岸边移动、钓鱼收获、矿井、预览冻结后重启确认及幂等重放均通过。旧发布 v1/v2 地形和旧 v2 冻结预览按原数据读取、确认，不重新生成。

演练后恢复全部九张表，74 座农场、77 个玩家、1,429 条历史命令、10 个房间等指纹完全一致，6 个测试账号全部移除，演练容器停止。见 `release/rehearsal-http.json`、`rehearsal-restored.json`、`rehearsal-reset.json`、`rehearsal-preservation.json`、`rehearsal-startup-preserved.json`。

正式切换北京时间 **2026-09-21 17:51:56–17:52:08**，维护约 12 秒。镜像 `sha256:9de4d962de28910879680c1ee0ad7d4fe0e78525533ac3c14b24431462c4498b`。不迁移领域版本、不改内容指纹；切换前后 schema、九张表及原始 state/terrain/冻结预览文本一致，74 个机会仍可用、0 个已使用。数据库身份、令牌 pepper、语音配置及原两张网络保持。公开 HTTPS 健康与 v1/v2 能力读回通过，见 `release/public-health.json`、`public-regions.json`、`live-preservation.json`、`live-startup-preserved.json`、`publish-server.sh.result.json`。

## 真机原页面重试与存档保护

服务切换后，保持 V2509A 原 **0.16.8** 进程及其选址页面，只点了一次“预览这个位置”。按钮坐标来自同机同版本实际 Godot 控件树的底部固定操作行，操作前已查看当前失败页面；没有点击“确认搬迁”。这次是在用户已打开的原页面上检查，不是重启一个测试场景。

`device/after-retry.png` 显示 **32×32 米预览成功**，若主人随后确认，需要移动 **45 个种植地块、0 件摆放**。这只是预览计划，尚未执行搬迁。生成成功后服务端的冻结预览首次提供了完整原选区请求坐标 **34.098751, -118.266274**，与先前只读相机取得的五位小数一致；不要把此前五位小数的离线诊断误标为原请求的全部精度。

只读核对原农场版本仍为 284，同一农场身份、原地形、47 个地块及除正常时钟推进外的原资产状态保持，`available=true`、`used=false`。证据 `device/preview-result.json`、`preview-tap.json`、`preview-game.log`、`before-retry.png`、`after-retry.png`，原始状态及认证仅留在私有目录。

为保留用户正在查看的这份预览，本轮没有重启或更新手机。此结果证明**旧 0.16.8 客户端可以使用已修复的线上生成服务**，不代表手机已安装 0.16.9，也不代表已完成真实用户的搬迁确认。

## 0.16.9 客户端发布

新客户端改进错误区分和水边景观；包名 `com.sensen.journeypreview`，版本 **0.16.9 / 2026092105**。APK `sensen-journey-shoreline-farm-0.16.9.apk`，**156,414,135 bytes**，SHA-256 `9d30d59440c78917d0d93ae3b45598b2d29934136c8e61642cd969b0c5ad1735`。原证书 SHA-256 `38771d94b8fbfa11651cc440e3746c9182114461a90cc0ab7188d7b708515673`。最终包不含观察器、QA 探针或隔离账号。

最终公开 APK 已在模拟器覆盖安装，从设备拉回后哈希完全一致；四份既有身份/偏好文件逐字节相同，正式服务切换后的冷启动与原账号登录通过。见 `emulator/installation.json`、`final-smoke.json`、`final-session.log`、`final-installed.png`。真机安装状态明确为未安装 0.16.9；当前原地预览成功与该 APK 的验证分别记录。

- [DMIT 美国下载](https://download-us.sensenjoy.cn:8443/farm/releases/shoreline-farm-20260921-9d30d59440c7/sensen-journey-shoreline-farm-0.16.9.apk)
- [OSS 备用](https://oss.sensenjoy.cn/farm/releases/shoreline-farm-20260921-9d30d59440c7/sensen-journey-shoreline-farm-0.16.9.apk)

两站完整 HTTPS 下载、长度、SHA-256、Range 206 的 1–2 MiB 字节以及公开清单/校验文件均验证通过。见 `release/download/verification.json`、`release/release.json`；清单标记新 APK 真机未安装，同时单独记录 0.16.8 真机的线上预览成功、未发送确认。

本地 3194 隔离服务和测试会话已停止，模拟器保持运行；临时私有 OSS 部署包已清理，远端回滚备份保留。原手机成功预览继续留给用户。本轮没有向 Joey 或其他联系人发送消息。
