# 旧农场一次重新选址：发布与验证

日期：2026-09-21。对应[产品约定](../product/farm-relocation-2026-09-21.md)。**Journey 0.16.6 / 2026092102、domain 27 已上线**，content 保持 `50c2dbdde04c9678`。最终原签名、无观察器更新包已在模拟器安装并核对哈希。首次发布时 V2509A 未连接；用户随后连接手机并要求“真机更新”，**同一公开 APK 已覆盖安装，冷启动及原账号登录通过**。搬迁流程由模拟器验证，真机未消耗用户机会。未向 Joey 或其他联系人发送消息。

本页相对证据路径均位于 `output/farm-relocation-2026-09-21/`。

## 已发布行为

- 升级时仍使用旧基础地形的已有农场，获得一次免费、主动重新选址资格。新建地理农场不领取这项旧农场迁移资格。
- 入口为“我的农场”右上角“重新选址”，在原城市选择位置、预览地形与需要移动的地块/摆放数量，再“确认搬迁”。城市与时区保留。
- 服务端冻结预览结果 30 分钟；取消、无效选址或明确拒绝的确认不消耗资格。确认结果不明时持久化恢复同一结果，恢复前不能当作安全取消。
- 原子提交新地形、位置、冲突内容的新坐标、农场版本及已用资格。农场和账号身份、作物内容与成熟时间、装饰旋转、背包、装备、钱包、矿井、任务和历史保持；不能容纳全部资产时拒绝搬迁。
- 全水体、全沙漠、缺失数据及可用土地不足仍拒绝生成。钓鱼、矿井与未结算操作有搬迁保护。
- 搬迁后旧房间代次与旧票据失效；主人、访客和其他设备获取新几何再进入。已搬迁农场的加入请求及六种空间命令绑定 `terrain_checksum`，客户端在排入操作时冻结该值，旧坐标不能套用到新地形。历史命令仍先重放原收据。

## 自动化与地理服务

完整隔离 PostgreSQL/服务端套件 **786/786**，67 个文件全部通过，无跳过；TypeScript 检查通过。最终日志 `server-tests-osm-final.log`。此前完整套件及专项是开发过程中的验证，不重复累加。

Godot 通过：地图套件 137 项、本地化 9 项、网络完整套件 103 项；之后包含校验和重启恢复的迁居会话专项 11 项、路由 5 项、旧场景刷新 4 项、首个地图点击回归 3 项。部分专项和完整套件重叠，不作为去重总数。日志位于 `/tmp/relocation-*.log`，Godot 报告包括 `reports/report_1236`。

真实 OSM 演练曾遇到 Overpass 503，修复为默认 DE 端点失败后尝试 Kumi，整个请求共享 30 秒时限。显式配置的端点保持单端点。只缓存成功的真实结果（精确坐标/范围，5 分钟、8 个 LRU 条目），合并相同在途请求，向调用方返回独立副本。不缓存失败，不使用过期或虚构地形兜底。服务端最终全量回归包含该修复。

## Android 验证

按 `tools/android/run_test.sh` 管理测试会话，模拟器为 `emulator-5560`。

隔离账号通过本机 `127.0.0.1:3192` MemoryStore 服务使用记录下来的真实上海 OSM 数据，完成预览、取消、无效选址、明确确认、迁后种田、钓鱼与矿井往返。取消保留原场景与相机、资格不消耗；确认移动 **3 个地块和 1 个装饰**，同一农场的资产与作物成熟时间保持，资格只消耗一次。证据 `android/result.json` 及相邻截图/日志。内存服务不作为数据库持久化证据，持久化由 PostgreSQL 回归与生产主机演练覆盖。

最初 QA 操作按钮进入正常居民目标，脚本随后沿用同一隔离存档改为直接地块操作并继续完成场景；结果标记 `continued_after_harness_navigation: true`。这些证据不代表一次未中断的自然玩家会话。过程中修复了实际 UI 问题：旧的隐藏邻居选中状态会吞掉重新选址地图的第一次点击；迁居模式已跳过该旧分支，并保留原地图 UI 状态。

正式服务上的模拟器使用原 Journey 账号，仅验证新入口、打开地图、取消返回，**没有发出预览或确认搬迁请求**。证据 `emulator/entry-result.json`。最终公开、无观察器 APK 覆盖安装后从设备拉回，哈希与发布物一致；四份身份/偏好文件逐字节不变，见 `emulator/installation.json`。最后冷启动、打开选址及取消通过，见 `emulator/final-smoke.json`、`final-installed.png`、`final-picker.png`、`final-return.png`、`final-game.log`，画面已检查。

真实用户存档只读核对通过：同一农场 ID 与版本、原始状态/资产与旧地形保持，**47 个地块保留，`relocation.available = true`、`relocation.used = false`**。证据 `release/original-user-opportunity.json`。私有认证及原始快照保留在私有目录，不进入公开发布物。

## 生产演练与正式迁移

在生产主机克隆数据库进行真实 HTTP/WebSocket 与实时 OSM 演练：创建地理农场、预览与确认、通过正常命令种植的作物及制作/摆放的花盆迁移、资格与幂等性、旧命令/票据/加入校验、访客刷新与隐私、钓鱼、矿井、重启重放全部通过。测试后恢复演练库并核对各表指纹，演练容器已停止。证据 `release/rehearsal-http.json`、`rehearsal-restored.json`、`rehearsal-reset.json`。第一次演练的临时上游失败由上述缓存/备用端点修复，最终 R2 镜像演练通过后才切换正式服务。

正式切换北京时间 **2026-09-21 14:28:20–14:28:37**。停止唯一 writer 后重新备份，显式执行 domain **26→27**，保留原数据库身份、令牌 pepper、语音配置及双网络。迁移保留 **74 座农场、288 个已种作物、1,429 条历史命令**，旧 state/terrain 文本、其余农场数据、所有权、账号/令牌、队伍与房间保持。九张表按预期新增领域版本与资格后归一化的指纹相同。**74 座旧农场授予一次资格，0 次消耗，没有自动搬迁**。

服务入口 `https://farm.sensenjoy.cn/preview/journey/v1`；发布标识 `farm-relocation-20260921`，目录 `/opt/farm/journey-preview/releases/farm-relocation-20260921`。健康检查返回 domain `27`、content `50c2dbdde04c9678`。迁居能力通过主人 DTO 的 `relocation` 字段与 domain 27 表达；`/regions` 没有 `farm_relocation_version` 字段。证据 `release/live-migration.json`、`public-health.json`、`public-capabilities.json`、`publish-server.sh.result.json`。

## 唯一公开更新包

包名 `com.sensen.journeypreview`，版本 **0.16.6 / 2026092102**；原证书 SHA-256 `38771d94b8fbfa11651cc440e3746c9182114461a90cc0ab7188d7b708515673`。不含观察器、QA 探针或测试账号。

APK `sensen-journey-farm-relocation-0.16.6.apk`，**156,409,751 bytes**，SHA-256 `d3dc5e2037fcb79700926746911a92ae403fe6d15877842b303087b429b099df`。

- [DMIT 美国下载](https://download-us.sensenjoy.cn:8443/farm/releases/farm-relocation-20260921-d3dc5e2037fc/sensen-journey-farm-relocation-0.16.6.apk)
- [OSS 备用](https://oss.sensenjoy.cn/farm/releases/farm-relocation-20260921-d3dc5e2037fc/sensen-journey-farm-relocation-0.16.6.apk)

两站 HTTPS 全量下载、长度、SHA-256、Range 206 字节内容、清单与校验文件均通过，证据 `release/download/verification.json`、`release/release.json`、`release/apk.json`。不可变公开清单保留首次发布时“模拟器通过、真机尚未安装/验证”的状态，随后真机安装证据见下节；真实用户的机会继续保留给本人使用。

## 用户后续要求的真机更新

用户明确要求“真机更新”后，V2509A（`10AFAF162200319`）已重新连接。先停止原 Journey，备份五份身份/外观/偏好文件并只读保存服务端农场状态，再以 `adb install -r` 覆盖安装公开 0.16.6 APK；没有卸载应用或清空数据。Vivo 安装提示按当前 UI 树核对应用名、版本及按钮后确认。

安装后的 `versionCode=2026092102`、`versionName=0.16.6` 已核对。从手机拉回 `base.apk`，SHA-256 与公开包一致，签名证书与原 Journey 一致。`install_key.txt`、`farm_choice.json`、`region_choice.json`、`ui_state.json`、`avatar/outfit_local.json` 在安装后和启动后均逐字节不变，证据 `device/installation.json`、`device/before-files.json`。

使用 `tools/android/run_test.sh --serial 10AFAF162200319` 完成一次冷启动会话。启动返回成功，原账号及已有农场加载成功，已检查城市选择首屏画面；日志未见脚本、解析或编译错误。该验证没有进入搬迁流程，没有发送预览或确认请求，不作为真机搬迁全流程验收。

启动后只读核对同一农场 ID、版本、旧地形、位置和除正常时钟推进外的完整状态保持，47 个地块与资产保留，资格仍为 `available=true`、`used=false`。证据 `device/final-smoke.json`、`device/final-session.log`、`device/final-game.log`、`device/final-installed.png`。测试结束按 runner 约定停止应用，用户可自行打开新版并选择是否搬迁。
