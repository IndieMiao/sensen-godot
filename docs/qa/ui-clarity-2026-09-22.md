# Journey 高清 UI、离屏方向与鱼塘对齐 · 2026-09-22

**已发布：0.16.11 / 2026092201**。高清素材、人物预览、离屏头像方向及鱼塘岸线调整已完成原生与隔离 Android 验证；高清图已按用户要求发往其本人飞书私聊。正式无观察器 APK 已完成模拟器覆盖安装、包回读、冷启动与原存档核对；公开下载校验见下方发布结果。首发时 V2509A 未连接；随后用户重连并明确要求安装，真机补验结果见文末。

## 显示与行为

- SVG 以 4× 密度导入：实际 **96×96 像素**，显示尺寸保持 **24×24 逻辑单位**。PNG 从原始高清素材重新裁切，使用逻辑尺寸保持既有九宫格边角和控件布局；没有把旧低清图片放大冒充新素材。素材尺寸和哈希见 `output/ui-clarity-2026-09-21/asset-density.json`。
- 人物页使用独立 SubViewport，以实际屏幕密度渲染：112×196 逻辑预览在 3× 下为 **336×588 像素**，最多 4×、长边 1024。保留真实存档装扮和原相机，隐藏后停止渲染；主世界未增加统一超采样。
- 角色仍在真实相机视口内时隐藏定位头像；离屏后沿实际方向连续贴边，箭头朝向角色。安全区只影响按钮摆放，不约束自由相机或人物移动。点击平滑回中后头像消失，保留 56px 点击区域。
- 鱼塘岸线外观与既有水面范围对齐。前后水面 AABB、钓鱼盆地中心及半径一致，原存档状态不变；两角度原生图和几何比较在 `output/pond-alignment-2026-09-21/verification.json`。

## 验证

| 范围 | 结果与证据 |
| --- | --- |
| 原生头像、相机 | 21 项通过，0 errors / failures / orphans；`output/ui-clarity-2026-09-21/tests/farm/results.json` |
| 库存、装备、人物密度与生命周期 | 24 项通过，含 3× / 4×、1024 上限、逻辑尺寸、装扮与主相机不变、隐藏停渲染；`output/ui-redesign-2026-09-21/inventory-density-headless.log` |
| 人物预览实际渲染 | 原生 336×588 图已检查；`output/ui-redesign-2026-09-21/character-density/report.json` 与 `portrait-raster.png` |
| 鱼塘、紧凑农场、地理水体 | 21 项通过，0 errors / failures / orphans；`output/pond-alignment-2026-09-21/geometry-tests.log` |
| 最终隔离 Android 流程 | 24 次真实触控、八个离屏方向均通过；`output/ui-clarity-2026-09-21/android-flow-final.log` 与 `android/result.json` |

Android 覆盖角色屏内隐藏、八方向贴边、回中后隐藏、保存位置不变、96px 图标保持 24 逻辑单位、五列背包、下拉菜单选中标记、人物物理分辨率、鱼塘路线及服务器确认抛竿。库存、钱包与地块比较保持一致。修正最后两处图标后进行了最终流程重跑，结果为 `passed=true`；使用隔离账号，未向公共玩家存档写入验收数据。

原生展示截图实际尺寸为 **1080×2008 像素**，对应 **419×780 逻辑视口**，见 `output/ui-clarity-2026-09-21/native/captures.json`。这是 Godot 的实际运行截图，未标作 1080×2340，也未把桌面截图等同于真机验收。人物独立密度测试和 Android 触控证据分别记录。

## 模拟器安装空间

更新 QA 应用时出现 `INSTALL_FAILED_INSUFFICIENT_STORAGE`。此前 21 个旧 QA 录像已逐个归档、校验 SHA-256 并移走相同远端副本，记录在 `output/ui-redesign-2026-09-21/emulator-storage/archive-manifest.json`。本轮安装随后临时降低模拟器保留空间阈值，安装成功后在清理路径恢复两个设置；`sys_storage_threshold_percentage` 与 `sys_storage_threshold_max_bytes` 的原值和恢复值均为 `null`。

最新安装成功及恢复证据为 `output/ui-clarity-2026-09-21/emulator-storage-install.json`；`qa-install-final.log` 保留较早失败尝试，不作为最终安装结果。没有卸载已有应用或清空任何存档，模拟器继续运行。此次操作不涉及真机存储设置。

## 飞书高清图交付

用户明确要求通过飞书查看高清图。已向张邵杰本人既有「张邵杰的飞书 CLI」私聊发送 5 条消息：说明、清晰度对比图、高清农场图、高清背包图、原图 ZIP。全部消息经 `mget` 回读核对同一会话、类型和内容；未向其他联系人发送，也未附 APK。

原图 ZIP 包含人物、农场、背包、离屏方向示例及透明 UI 素材，大小 **6,962,752 字节**。从刚发送的飞书消息重新下载后，字节数及 SHA-256 与本地一致：

`78dc2b2416a04c6d1c23c590a4d1d7b11b9b87ed04f64eeffaaf54a474242f8b`

交付回执、5 个消息 ID、文件哈希和下载校验见 `output/ui-clarity-2026-09-21/feishu/delivery.json`。发送时说明鱼塘与模拟器验收仍在进行；此后的最终测试结果以上述日志为准。

## 正式发布

| 项目 | 状态 |
| --- | --- |
| Journey 版本 | `0.16.11 / 2026092201` |
| 正式包名 | `com.sensen.journeypreview`，沿用原签名及身份 |
| APK | `sensen-journey-ui-clarity-0.16.11.apk`，`159124765` 字节 |
| SHA256 | `e786708b6dd944be2dccd2791e0970aaf272870503494ed4ef24c7169ae1ab74` |
| 原证书 SHA256 | `38771d94b8fbfa11651cc440e3746c9182114461a90cc0ab7188d7b708515673` |
| 公开下载 | [DMIT](https://download-us.sensenjoy.cn:8443/farm/releases/ui-clarity-20260922-e786708b6dd9/sensen-journey-ui-clarity-0.16.11.apk) · [OSS](https://oss.sensenjoy.cn/farm/releases/ui-clarity-20260922-e786708b6dd9/sensen-journey-ui-clarity-0.16.11.apk)；完整 HTTPS 字节、SHA256、Range 206、manifest/checksum 均通过 |
| 最终普通包模拟器安装与冷启动 | 已通过；从实际安装包回读核验完整哈希、证书、版本和无观察器；冷登录原账号，五文件逐字节相同、地形/定位/资产/迁居状态保持 |
| V2509A 安装 | 用户重连后已覆盖安装同一公开 APK，版本/原证书/完整哈希、冷登录与当前存档核对通过 |

最终产物与普通包证据位于 `output/ui-clarity-2026-09-21/release/apk.json`、`emulator/installation.json`、`emulator/final-smoke.json`。完整 24 次触控在隔离 QA 包执行；最终普通包补验范围是城市页、原账号冷登录与保存状态，不冒称真机或完整玩法重跑。

钓鱼短提示最后改用同风格的紧凑九宫格，避免两端32px切片在44px高度上相交；8次背包/人物/水边/抛竿专项重跑通过，`android/pond-result.json` 与 `android-pond-final.log` 记录最终状态。

服务器仍为 `shoreline-farm-20260921`、domain 27、content `50c2dbdde04c9678`。本轮没有后端部署、领域迁移、真实农场重新生成或玩家存档写入。

公开发布证据：`output/ui-clarity-2026-09-21/release/release.json`、`release/download/verification.json` 与 `release/publication.log`。正式包通过普通 `adb install -r` 安装到模拟器，没有使用存储阈值辅助；临时设置仅用于此前 QA 包更新并已经恢复。


## 2026-09-22 用户重连后的真机安装

用户明确要求“安装到真机”后，V2509A (`10AFAF162200319`) 从 0.16.10 覆盖更新到同一公开的 **0.16.11 / 2026092201**。没有重新构建、添加观察器、卸载、清数据或恢复历史快照。安装包 SHA256 仍为 `e786708b6dd944be2dccd2791e0970aaf272870503494ed4ef24c7169ae1ab74`，从已安装 base.apk 回读核对相同字节数、哈希和原签名。

安装前重新捕获手机自身的五份身份/外观文件和公共 owner farm，未使用此前47地块快照覆盖玩家新进度。更新后五文件逐字节一致；农场身份、version、真实地形、定位、迁居状态及全部非 clock 状态保持一致。当前 **49 个已开垦地块、10 个背包堆叠**保留，迁居仍为 `available=false / used=true`。

最终普通包通过 `run_test.sh` 冷启动，确认本次新生成的日志中原账号登录成功且已有农场，中文城市页截图已目视检查。首次辅助脚本过早读到旧文件日志而要求 PID logcat，不能作为成功证据；随后只移除了已归档的运行日志，先确认应用已停止且日志不存在，再启动得到新日志并完成核对。未修改任何身份或存档文件。

本次验收范围为安装、冷登录、城市页和当前存档保留，**没有重跑完整八方向或池塘真机玩法**。首次发布的不可变 manifest 中 `physical_validation=false` 保持其发布时事实，不改写公开文件；后续补验证据单独存于 `output/ui-clarity-2026-09-21/device/installation.json`、`final-smoke.json`、`fresh-log-baseline.json`、`final-city.png`、`final-runner.log` 与 `runner-cleanup.json`。
