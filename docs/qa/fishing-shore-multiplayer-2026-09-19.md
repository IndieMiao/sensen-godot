# 沿岸自由钓鱼与多人验证（2026-09-19）

实现与规则见 [产品契约](../product/fishing-shore-multiplayer-2026-09-19.md)。本轮仅交付原包名 `com.sensen.journeypreview` 的 Journey 更新，已发布版本 0.16.0 / 2026091901。

已通过的验证：

- TypeScript 类型检查；真实独立 PostgreSQL 上 23 项钓鱼领域／HTTP／WebSocket 专项。多个连续岸边位置、无效／内陆／水中／障碍落点、房间与连接绑定、移动后返回不得恢复旧钓鱼、双人同时抛竿、访客鱼获独立、后来进入者收到当前动作、公共数据不泄露私有字段、离场清理和客户端不得伪造钓鱼。
- 93 项服务端迁移与联机回归，包括真实 PostgreSQL、历史版本迁移、组队／语音／矿洞／外观／导航。
- Godot 实际渲染运行：80 项网络回归；最终 20 项钓鱼与在线人物专项全部通过、无孤儿节点。自由选择多个岸边、连续站位不吸附、原动作与低遮挡 UI、远端动画不移动摄像机、人物离场与池复用清理。
- 线上数据库复制件迁移演练：72 份农场、303 株作物，状态 JSON 与历史／组队表精确保持，零搬迁。克隆服务通过实际 WebSocket 步行、非原固定站位抛竿、真实 HTTP 捕获／出售／重放、第二客户端看到抛竿与鱼获、重启后完整状态一致。

运行日志、APK、截图和发布回执保存在 `output/fishing-shore-2026-09-19/`。私有账户、服务端迁移备份及临时上传凭证未放入公开下载。

本轮 adb 暂只检测到 `emulator-5560`，未检测到 V2509A。不能把模拟器或上轮真机验证算作本轮真机通过。模拟器既有原生 Mapbox 库的 Android 16 KB 兼容提示仍存在，本轮不改变该原生库。

## 发布与 Android 结果

- 服务 `fishing-shore-20260919` 已于 2026-09-19 07:24:35–07:24:47（UTC+8）完成切换，领域 24、内容 `38e6db02b26b8b43`。停止旧单写者后备份，显式迁移并恢复路由；72 份原农场、303 株作物全部原样保留，语音配置有效。
- 公共 HTTPS 服务另经两名真实 HTTP/WebSocket 客户端验证：实际步行到不同于原固定点的岸边、抛竿、确认鱼获、出售、幂等重放，观察者看到抛竿与确认鱼获。临时验证账号已设为仅自己访问且不展示位置。首次从容器访问域名遇到 DNS `EAI_AGAIN`；改从本机走同一公共 HTTPS 地址完整验证成功。
- Android 在一个完整 runner 会话内验证：自动走到 `[13.125, -28.875]`（原固定点为 `[9.375, -27.375]`）、双人并排持竿、同步收线与捕获、退出后远端钓具清理、直接点击水面再次钓鱼、湖泊与河流自由选岸和捕获。62 次真实按压事件；河流最终捕获稀有鱼。旁路第二客户端使用正常 HTTP/WebSocket 步行与结算，未直接改数据库。场景选择使用 QA 入口，钓鱼操作使用实际 adb 触控。
- 初次 QA 脚本碰到 Android 系统兼容弹窗吞触摸，以及切场景尚未完成就发送场景测试指令；修正等待和弹窗处理后完整流程通过。一次河流鱼逃脱是合法高难度结果，验证也检查逃脱不会增加库存，没有把每次都钓到作为正确性要求。
- 唯一正式包覆盖安装到模拟器，三份既有身份／农场选择文件逐字节相同，原公网农场可读。安装包拉回哈希与发布文件一致；冷启动无脚本错误，包内没有 QA 账号或观察器。本轮未连接到 V2509A，未安装或声明真机通过。
- APK：`152079821` bytes；SHA-256 `7e12d830b60c78b6bec1a3531f4e20a5687aaaa23d8e2f1e14e0c5299297eed2`；签名 SHA-256 `38771d94b8fbfa11651cc440e3746c9182114461a90cc0ab7188d7b708515673`，与原 Journey 一致。
- [美国下载](https://download-us.sensenjoy.cn:8443/farm/releases/fishing-shore-20260919-7e12d830b60c/sensen-journey-fishing-0.16.0.apk) · [OSS 备用](https://oss.sensenjoy.cn/farm/releases/fishing-shore-20260919-7e12d830b60c/sensen-journey-fishing-0.16.0.apk)。两处均通过完整 HTTPS 下载、SHA-256 和 Range 206 字节校验。

证据：`android/result.json`、`android/together-playing.png`、`android/river-playing.png`、`release/final-smoke.json`、`release/download/verification.json`、`checks/`；SGODOT-129 保持 In Progress，保留自然玩家难度／经济观察与本轮真机复核边界。

交付：新版本 APK 已通过 [Slack 发给 Joey](https://gensenapp.slack.com/archives/D0C1MHLA3GQ/p1789774391052729)，并回读确认两条下载地址。SGODOT-129 已追加发布证据，评论 ID `770865da-5ae6-499b-8e40-105d76ce39a6`；回执见 `output/fishing-shore-2026-09-19/delivery/receipt.json`。

## 后续 V2509A 安装

用户重新连接并要求真机安装后，已将同一个公开 0.16.0 / 2026091901 APK 覆盖安装到 `10AFAF162200319` / V2509A，原版本为 0.15.1。安装前备份旧 APK、五份身份／外观文件及公网存档；保留 `com.sensen.journeypreview` 与原签名。

安装后拉回 APK，SHA-256 与已发布文件完全一致；`install_key.txt`、`farm_choice.json`、`region_choice.json`、`ui_state.json`、`avatar/outfit_local.json` 均逐字节不变。原公网农场仍为 v183，田地、库存、钱包、背包、钓鱼与矿洞数据保持一致。通过 Android runner 完成冷启动，未发现脚本错误，结束后正常关闭测试进程。

本次完成的是用户要求的正式包安装、启动与保存完整性核对，未把它扩大为全套新版本真机钓鱼验收。证据见 `output/fishing-shore-2026-09-19/device/installation.json`、`final-smoke.json`、`final-installed.png` 与 `smoke-run.log`；公开不可变下载清单保留发布时的验证状态，新增真机安装证据在此补记。
