# 农场大格、首屏构图、对称镜头与自然边缘

2026-09-18。对应用户的五项手机体验反馈与 Plane SGODOT-128。

## 本次行为

- 种田格边长从 **0.5m → 0.75m（1.5 倍）**；64×64 网格的总范围变为 48m。角色缩放仍为 1，沿用上一版近景镜头宽度，未通过缩小角色扩大田格。
- 重排出生点附近的房屋、矿井、水井、储物箱和摊位。矿井、水井与储物箱在默认竖屏第一屏内可见；实时导航同步新锚点，出生点为 `[21.375, -26.625]`。
- 镜头围绕人物身体中心，在整个 view 中保持上下、左右对称。中央缓冲区内可以走动，超出后以 0.16s 阻尼跟随；手动拖动共用对称边界，保留人物身体和 HUD 间距，放手后保持构图。修复大幅拖动投影失败及松手回弹。
- 边缘以弯曲岩带、错落灌木、树木和草花衔接；水塘增加柔和岸线、芦苇与岸石。
- 道路采用连续曲线和柔化边缘，移除大块矩形门前铺地。种植、通行与碰撞仍由共享网格判定；视觉不再呈现逐格直角路面。
- 保留默认行走、单按钮切换种地、显式批量劳作、种子横向滚动、访客只读及已有在线玩法。

## 存档与布局契约

- `farm_plot.json` 的 homestead_a revision 2；客户端和服务端共用 rect / ellipse / Catmull-Rom path 栅格规则。
- 地块 checksum：`13e324021b1024a6cb496d8a5ecd2807318c3206f881be8974001549632e8911`。3003 个可开垦格、3086 个可放置格。
- 地面纹理由 `tools/art/bake_farm_ground.py` 按布局生成；`--check` 检查资源新鲜度。道路、石地、水面蒙版与耕作状态纹理各自处理。
- domain **21 → 22**；content **`a19e895011110070`**。不重置账号或存档。新的道路/建筑占到旧耕作位置时，确定性地移至最近的空闲可耕作格；保留作物内容、播种状态与成熟期限。
- 原庭院格式的装饰转换为当前 cell 格式；放置冲突时移到最近可用占地，不丢失物品，不覆盖作物。库存、金币、矿井、队伍、历史命令与快照保持。
- 已有地理蓝图和街区导航不变；本次只调整农场内部布局及对应的农场实时导航。

## 验证结果与边界

- Godot 农场全套 **204 项通过**（`reports/report_1174`）；最终拖动修正后镜头 **9 项通过**（`report_1175`）。TypeScript 检查通过。
- 服务端最终全量 **687 项通过 / 49 个套件**，包含独立 PostgreSQL。修正了测试清库与异步 token 查询的死锁重试，仅作用于测试清库入口。
- 真 HTTP + PostgreSQL 完整闭环：买种扣款、开垦、播种扣种、浇水生成服务端期限、未熟拒收、成熟收获、重放不重复产出、重启与重新登录精确恢复。仅隔离 QA 工具推进成熟时间，正式作物时间未加速。
- Android 模拟器真实手势通过：瓦片投影 1.5 倍、人物比例不变、首屏四个地标可见、上下左右拖动达对称边界，拖动未产生劳作请求。独立 QA 场景使用假传输只验证视觉/输入；真实种植结论来自上面的 HTTP/数据库验证。
- 720×1560 Android 视口的身体焦点边界：上/下 y=410.598 / 1149.402，左/右 x=134.598 / 585.402，分别关于视口中心对称。
- 最终原生画面复核：390×844、360×640、1280×720。沿用现有低模模型和已认可的色彩方向；不声称与概念图逐像素一致。
- 最终交付 APK 在 `emulator-5560` 覆盖原 Journey 0.11.0，正常入口冷启动、连接公网、恢复已有农场通过；三个账号/选择文件逐字节保持，APK 安装回读哈希与公开下载相同，无临时 observer/probe。
- 发布时手机未连接；随后用户连接 V2509A 并要求安装测试，下方真机补充已完成。本轮完成不代表原卡道具放置、木本作物等全部原始范围均已验收。

## 线上发布与唯一安装包

- Journey API：`https://farm.sensenjoy.cn/preview/journey/v1`。
- release：`farm-composition-20260918`；镜像 `sha256:b3507148107080f512e93715b9837c5146c8371aa4f0721241772b81b627dcc1`。
- 先对线上副本迁移、真实写入与重启恢复；正式切换时维护路由、停止旧 writer、备份、事务迁移及全表比较、启动新 writer、恢复路由，保留回退资料。
- 切换窗口 UTC **00:35:24–00:35:38**（北京时间 08:35:24–08:35:38）。69 个既有农场、294 株作物保留；119 条受新地形影响的耕作记录就近迁移（包含未种植的已开垦记录）。历史与队伍数据核对一致。
- 公网新建一个私有 QA 农场，实际买种、开垦、播种、浇水、重新登录精确恢复通过；正式农场总数因此为 70。未重启正式服务来做恢复测试，重启测试在副本完成。
- 服务 healthy、重启计数 0，正式 LiveKit 配置保留；副本服务已停止，私有临时 OSS 部署包已删除。
- 唯一交付：**Sensen Journey Preview**，`com.sensen.journeypreview`，**0.14.0-farm-view / 2026091801**，沿用原签名与 Journey 账号。
- [下载 Journey 0.14.0 APK](https://oss.sensenjoy.cn/farm/releases/farm-view-20260918-fdd12c5eb11e/sensen-journey-farm-view-0.14.0.apk)。152014256 bytes；完整下载校验通过。
- SHA-256：`fdd12c5eb11eb800ad095006a40383ceff3bcd1fc49a08309fe013af1ff4affe`。
- 签名 SHA-256：`38771d94b8fbfa11651cc440e3746c9182114461a90cc0ab7188d7b708515673`。

## 证据

- [最终竖屏画面](../../output/farm-composition-2026-09-18/native-390/default.png)、[水岸](../../output/farm-composition-2026-09-18/native-390/pond.png)、[边缘](../../output/farm-composition-2026-09-18/native-390/boundary.png)。
- [Android 手势结果](../../output/farm-composition-2026-09-18/android/result.json)、[完整种植闭环](../../output/farm-composition-2026-09-18/http-loop.json)。
- [正式迁移回执](../../output/farm-composition-2026-09-18/release/live-migration.json)、[公网健康](../../output/farm-composition-2026-09-18/release/public-health.json)、[公网实际种植](../../output/farm-composition-2026-09-18/release/public-http.json)。
- [安装与账号保留](../../output/farm-composition-2026-09-18/release/installation.json)、[APK 下载校验](../../output/farm-composition-2026-09-18/release/release.json)。
- [Plane SGODOT-128](https://plane.sensenjoy.cn/zili/projects/47d11337-c390-4b42-8b05-ef60fa2633f7/issues/fbf1a5ef-1c6b-47f4-baca-9c20cae0d04a)。

Plane 描述与发布评论已更新并回读确认；旧的“重置全部存档”决策已改为保留 Journey 账号与存档。本轮真机完成结果已补充，卡片的更广原始范围仍保持 In Progress。

## V2509A 真机安装与真实种植补充

用户随后明确要求安装真机测试。设备 `10AFAF162200319` / vivo V2509A，从原 Journey **0.13.2 / 2026091712** 覆盖到 **0.14.0 / 2026091801**。保留原包名、签名、账号、装扮、农场和选择文件。安全锁屏导致首次安装被系统取消，用户解锁后成功安装。

使用临时只读场景观察器获取 Godot UI 控件矩形和相机投影，用真实 adb 手势操作正常游戏、正常公网服务；观察器未替换传输、注入存档或推进作物时间。测试结束后已覆盖为公开发布的无观察器 APK，安装回读 SHA-256 与公开下载完全一致。

- 10 项专项通过。进入原农场时，版本 61 的 20 条耕作记录、库存、钱包和 farm_id 与服务端备份一致。
- 0.75m 格投影为旧 0.5m 的 1.5 倍；角色缩放仍为 1，身体投影高度约 184.38px，与同一手机上一版测量一致。首屏能看到房屋、矿井、水井和储物箱。
- 1080×2344 view 实际四向拖动后，身体中心上/下 y=724.206 / 1619.794，左/右 x=201.897 / 878.103，分别关于屏幕中心对称；放手稳定，无劳作写入。
- 普通空地点按移动，默认行走不误开垦；单按钮切换种地正常。买 1 颗萝卜种子花费 4 金币，在 `27,34` 真实开垦→播种→浇水，种子只扣一次，服务端保存自然成熟时间。
- 切回行走后穿过新作物不改变种植状态。显式批量收获 2 株原有、已自然成熟的萝卜，萝卜库存从 2→4；新种的一株继续按 4 小时自然生长，不作为同一株即时完整收割验收。
- 测试正常玩法造成版本 **61→67**、金币 **180→176**；其他原存档保留。后台/返回、最终 APK 冷启动后恢复、重新登录后的服务端状态精确核对均通过；4 份身份/选择文件逐字节保持。
- 最终包直接使用公网 HTTPS，无 adb reverse，不依赖电脑服务，无脚本/着色器错误。整个操作通过 `tools/android/run_test.sh`，退出时停止应用，保留安装与存档。

证据：[真机 10 项结果](../../output/farm-composition-2026-09-18/device/result.json)、[最终安装回读](../../output/farm-composition-2026-09-18/device/installation.json)、[冷启动与服务端恢复](../../output/farm-composition-2026-09-18/device/final-smoke.json)、[最终真机画面](../../output/farm-composition-2026-09-18/device/final-installed.png)。截图右侧可见手机原有的系统悬浮视频窗口，未改变该窗口或其他应用。

服务器备份与演练证据位于 `/opt/farm/journey-preview/releases/farm-composition-20260918/`。本地和服务器 `private/` 包含账号及备份，不对外分享。

## DMIT 美国下载与飞书交付补充

2026-09-18 用户反馈美国访问 OSS 慢，要求同步线上并发送 APK。重新检查正式服务仍为 `farm-composition-20260918` / domain 22 / content `a19e895011110070`，与刚完成真机测试的安装包一致，因此没有重复迁移或重启游戏服务。

- 新增 [DMIT 洛杉矶 APK 下载](https://download-us.sensenjoy.cn:8443/farm/releases/farm-view-20260918-fdd12c5eb11e/sensen-journey-farm-view-0.14.0.apk)，原 OSS 链接作为备用。
- APK 实体文件已上传到 DMIT，直接提供下载；没有通过 DMIT 转发 OSS 请求。独立 HTTPS 8443，自动证书续期，支持 Range 断点续传；原 443/18443/1194 服务及防火墙规则保持。
- 公网 HTTPS 完整下载 152014256 字节并核对 SHA-256，与真机最终包完全一致；Range 206 和指定 1 MiB 片段的字节校验通过。这是下载可用性验证，不声称已测量美国用户的实际线路速度。
- 已通过飞书 CLI bot 将 DMIT 下载及 OSS 备用链接发给用户本人，并回读确认。消息 `om_x100b65feee7130acb15345198e94214`；收件会话与此前 Journey APK 交付一致。
- [部署与维护](../../server/deploy/downloads/README.md)、[下载验证](../../output/farm-composition-2026-09-18/dmit/verification.json)、[飞书交付回执](../../output/farm-composition-2026-09-18/dmit/delivery.json)。
