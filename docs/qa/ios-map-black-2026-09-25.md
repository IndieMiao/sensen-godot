# iPhone 选城后地图黑屏 · 2026-09-25

后续自动化参考：[iOS / TestFlight 已验证流程与故障处理](ios-testflight-automation.md)，含 `No Accounts` 判断、Organizer 回退、分阶段验收和真机数据保留规则。

## 当前结果

**修复版 `0.16.37 (3)` 已成功上传，并从 TestFlight 原位安装到 iPhone 14 Pro。** 该 TestFlight 安装包的冷启动、前后台切换、洛杉矶地图、拖动和缩放检查全部通过，截图已复核。原应用 `app.gensen.maps` 保留当前身份和城市选择；临时 QA 包和 runner 已清理。受控真机旧版失败/新版恢复对照及同一 Release 二进制的隔离回归均已完成。

首次问题发生于 TestFlight build 1；原始进程首次初始化失败的具体底层错误未被捕获。受控端口冲突证明了 listener 缺少恢复机制的代码缺口及修复效果，不能将该受控触发条件认定为用户首次黑屏的确切原因。

命令行分发仍报 `No Accounts`，但用户截图显示 Xcode 中 `shaojie@gensen.app` 已登录并拥有 Gensen 管理员权限。改用该 Xcode 进程的 Organizer 后，成功使用 Gensen 云管理的 Apple Distribution 签名并上传同一份 build 3 归档。不能再将本次发布描述为等待用户登录。

## 安装来源与数据基线

- `app.gensen.maps` / Journey / iPhone 14 Pro / iOS 26.3。
- 直接读取手机 TestFlight 详情：Gensen、`0.16.37 / Build 1`、“打开”、“可在此 iPhone 上使用”、有效期 90 天。安装目录较之前开发直装版本已变化，当前进程拒绝调试器附加。
- CoreDevice 仍返回 `builtByDeveloper=true`。**该字段不能单独用来区分开发直装和 TestFlight 安装**；此前仅凭它判断来源不充分，本次以 TestFlight 实际页面补充核实。
- 以本次任务开始时的现有 Documents 为基线，仅有 `install_key.txt`、`region_choice.json` 两个身份/选择文件，另有引擎缓存目录。已保存私有备份并回读比较；二者在排查后逐字节不变，没有恢复任何历史身份或农场。
- 原应用仅选择用户已经选定的洛杉矶并浏览地图；上海和故障注入使用独立 QA 包。没有确认农场生成、搬迁或资产操作。

[设备初查](../../output/ios-map-black-20260925/initial-device-check.json) · [TestFlight 详情证据](../../output/ios-map-black-20260925/testflight-installed-source-attachments/testflight-installed.png) · [当前身份文件哈希](../../output/ios-map-black-20260925/identity-baseline-hashes.json)

## 复现与定位边界

1. 最初手机停在选城页。选择洛杉矶后，角色、选址框和 HUD 正常，但底图全黑，标题一直显示“正在加载地图”；等待和拖动/缩放后仍未显示地图。
2. 黑屏阶段的可访问性树没有原生 Mapbox 的 Compass / About this map 控件。恢复后的树中存在这些控件；问题发生在原生地图创建/就绪链路，而非整个 Godot 画面停止绘制。
3. 对当前已安装版本做一次冷启动，再选择同一城市，日志出现 `MapView created` → `style loaded` → `READY|3.0`，截图确认地图恢复。
4. 随后分别立即选城与等待 4 秒后选城，两次均能显示地图。现有证据不能把固定 2 秒启动延迟认定为原始根因。
5. 原始失败进程的启动日志不可追溯；旧桥只在开始调用 `NWListener.start` 后打印“started”，没有记录后续异步 listener 失败，也不重建失败的 listener。因而单次初始化失败会缺少恢复路径。此代码缺口已确认，但最初具体触发错误仍未知。

[原包黑屏](../../output/ios-map-black-20260925/before-city-map-attachments/04-city-map-entry.png) · [原包冷启动恢复](../../output/ios-map-black-20260925/console-city-map-attachments/04-city-map-entry.png) · [启动回调日志](../../output/ios-map-black-20260925/installed-cold-launch-console.log)

原地图 XCTest 方法的自动断言只检查应用仍在前台，地图是否正确依赖截图人工复核，因此旧方法在本次黑屏时也返回通过。本轮已补充原生地图控件存在性断言，并人工复核瓦片实际显示。

## 已验证的 build 3 修复

[MapUnderlay.swift](../../tools/ios/MapUnderlay.swift) 修改包含：

- 处理 listener 的 ready / waiting / failed / cancelled 状态，失败后以 1–4 秒有界间隔重建；进入后台时不持续启动重试，恢复前台时重新检查。
- 监听地址限于 `127.0.0.1`，与现有本机 UDP 桥用途一致。
- 重建 listener 时关闭旧 peer；接收出现错误时取消连接并退出接收循环，防止对失败连接无限重复接收。
- 优先使用前台 UIWindowScene 的正常窗口，并保留旧 Godot app-delegate 模板的窗口兼容路径；恢复前台和显示地图时重新应用透明合成设置。
- 仅在样式实际加载后返回 READY，记录地图加载错误类型，避免输出 CREATE 中携带的 token。
- 包含之前 ITMS-90683 的定位用途说明修复；没有实现新的 iOS 定位能力。

Swift 编译和原应用身份的 Release 归档均通过。归档为 `app.gensen.maps / 0.16.37 (3)`，PCK SHA-256 与已经测试的 build 1 相同：`84cd47e37b1845062ff11e931afcef8c11e9730fc5dd9cebae20317a6dd6c7d7`。

[build 3 归档记录](../../output/ios-map-black-20260925/release-archive-result.json) · [归档日志](../../output/ios-map-black-20260925/release-archive.log)

## 受控真机对照与 Release 验证

独立 `app.gensen.maps.mapqa` 使用现有 Gensen 开发证书和包含本机的通配开发描述文件；本地无签名编译后使用有效开发身份签名并严格验证。对照阶段没有覆盖原 TestFlight 应用。

QA 包在首次启动前已写入自己的 `Documents/server.txt`，指向 `http://127.0.0.1:9/v1`；测试不连接生产游戏服务。

用户解锁后，XCTest 临时占用本机 UDP 46464，使桥初始化失败，然后释放端口，检查无需重启应用是否恢复原生地图：

- **旧代码失败**：在预期的 `Map did not recover after the transient listener failure` 断言失败，释放端口后截图仍为黑屏；退出码 65。
- **修复代码通过**：释放端口后在同一进程中自动显示地图；退出码 0，截图已复核。
- **实际 Release 二进制通过**：直接复制 build 3 归档应用，仅更改 QA 包身份并重新开发签名。归档与 QA 可执行文件 UUID 相同：`63C05C9F-6E83-3C03-B864-CEBFD565EA00`。2 项测试、0 失败，覆盖故障恢复、返回选城、上海地图、前后台切换、拖动及缩放；截图已复核。

[旧版结果](../../output/ios-map-black-20260925/listener-recovery-before-result.json) · [新版结果](../../output/ios-map-black-20260925/listener-recovery-after-result.json) · [Release 结果](../../output/ios-map-black-20260925/release-qa-suite-result.json) · [Release 上海截图](../../output/ios-map-black-20260925/release-qa-suite-attachments/qa-shanghai-map.png) · [测试源文件](../../tests/ios/JourneyDeviceUITests.swift)

## 开发直装阶段的原位更新

完成隔离回归后移除 QA 包和 runner。随后为使用户能直接测试修复版，以归档中的正式 `app.gensen.maps` 开发签名 Release 包原位升级，不卸载原应用。

- 安装成功并回读为 `Journey / app.gensen.maps / 0.16.37 (3)`。
- 安装前重新备份当前非缓存 Documents；安装后、首次启动前以及地图测试后均核对两个文件 SHA-256 不变。`install_key.txt`：`0d336002dbe22eee3f805320168fc7df453fb9bd40e3f7898dedaa2bc3725727`；`region_choice.json`：`966d983d4ffafab0b25b010ec1259d327c5d707d82607a934fa465fbd6ef31f5`。
- 原应用冷启动、选择洛杉矶、显示地图/角色、拖动及缩放 16→17：1 项 XCTest 通过，截图实际显示街道瓦片。
- 此阶段测试 runner 移除并保留原应用。后续已完成下述 TestFlight 渠道替换；开发直装验证是中间步骤。

[安装结果](../../output/ios-map-black-20260925/fixed-phone-install.json) · [版本回读](../../output/ios-map-black-20260925/fixed-phone-readback.json) · [安装后地图测试](../../output/ios-map-black-20260925/fixed-phone-map-result.json) · [地图截图](../../output/ios-map-black-20260925/fixed-phone-map-attachments/04-city-map-entry.png) · [缩放截图](../../output/ios-map-black-20260925/fixed-phone-map-attachments/06-map-after-pinch.png) · [最终身份比较](../../output/ios-map-black-20260925/phone-post-test-preservation.json)

## 最终 TestFlight 交付和手机复验

- Organizer 上传于北京时间 **2026-09-25 12:38:46** 返回 `Upload succeeded` / `Uploaded package is processing`。12:41 手机 TestFlight 显示 build 3、“安装”及兼容状态，证明处理和本机测试访问已就绪。
- 实际上传 IPA 为 87,815,746 字节，SHA-256 `4d57334dba9bd5c2b09caa67d7b7038dffeb311dcae1907d3b3d77941a92d73c`。严格签名验证、Gensen 分发身份、`get-task-allow=false`、`beta-reports-active=true`、定位用途说明、PCK 和 native UUID 核对全部通过。没有设备 UDID 限制。
- 已在手机 TestFlight 对明确显示的 build 3 点击安装，确认原位替换，等待“打开”出现；版本回读仍为 `app.gensen.maps / 0.16.37 (3)`。此步骤使用本次即时备份，不卸载应用、不恢复历史身份。
- TestFlight 安装后、首次启动前及最终地图测试后，两个现有身份/城市文件均与更新前逐字节一致；没有执行任何恢复写入。
- 最终 TestFlight 包的 **2 项 XCTest、0 失败**：冷启动/前后台恢复，以及洛杉矶地图/3D 角色/拖动/双指缩放 16→17。截图已复核，底图街道瓦片正常显示。
- 临时 runner 已移除；手机保留 **TestFlight build 3** 并返回 Journey 前台。没有新增其他聊天、邮箱或测试员邀请发送操作。
- 两项 Mapbox 缺失 dSYM 警告仍在，不阻止本次上传；CLI 与 GUI 账号列表不一致尚未修复，但通过已登录 GUI 完成了本次交付。

[上传结果](../../output/ios-map-black-20260925/testflight-upload-result.json) · [实际分发 IPA 验证](../../output/ios-map-black-20260925/app-store-package-validation.json) · [TestFlight 安装完成截图](../../output/ios-map-black-20260925/testflight-build3-confirm-install-attachments/testflight-build3-installed.png) · [最终地图](../../output/ios-map-black-20260925/testflight-build3-map-attachments/04-city-map-entry.png) · [最终缩放](../../output/ios-map-black-20260925/testflight-build3-map-attachments/06-map-after-pinch.png) · [TestFlight 地图测试](../../output/ios-map-black-20260925/testflight-build3-map-result.json) · [最终身份比较](../../output/ios-map-black-20260925/final-testflight-identity-check.json)

本轮没有修改游戏资源包、部署后端、迁移数据或进行真实账号资产操作。完整农场、钓鱼、矿坑、iOS 定位/语音及长期性能不在此次黑屏修复验收范围内。

[总状态记录](../../output/ios-map-black-20260925/validation.json)
