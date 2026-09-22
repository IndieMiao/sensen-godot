# SGODOT-126 队伍语音：阿里云自建与 Android 阶段

日期：2026-09-16。状态：**In Progress**。用户采纳海外为主、2–8 人、未来 iOS；本次明确要求复用阿里云部署，不需要用户创建 LiveKit Cloud 项目。

## 已部署与实现

- 香港现有 ECS 上独立 LiveKit 1.13.7 开发/生产容器，可信 TLS 域名 `voice-dev.sensenjoy.cn` / `voice.sensenjoy.cn`；独立密钥与命名空间。开源许可免费，现有公网按流量计费；未购买云主机或 Cloud 套餐。
- 正式游戏后端 `voice-20260916` 已上线。domain 20、内容指纹 `31b34f03eb712fea` 保持。数据库副本演练、线上切换前后完整存档/队伍指纹一致，60 个既有农场投影检查通过；只保留一个正式 realtime writer。切换窗口 09:08:15–09:08:29 UTC。
- 游戏后端校验队伍，签发仅麦克风与收听权限的短期 token；20 秒租约、5 秒续期；每队 8、正式全局 32 语音席位。游戏 300 人容量保持。
- 自建模式下成员移除/租约失效轮换房间并关闭旧房间，缓存 token 无法访问剩余成员的新房间。服务异常不撤销已经提交的游戏队伍动作，新语音凭证失败关闭。
- Android 官方 SDK 2.28.2 + 跟随全局会话的 GodotVoice。队伍面板加入/退出、麦克风、收听、讲话状态；加入默认静音、自动重连保留用户音频选择。后台/账号替换断开并重置静音。场景切换保留同一原生通话。
- 单个 Journey 预览包：0.11.0 / 2026091607，`com.sensen.journeypreview`，原有签名。APK 内未发现服务密钥或 QA 账号资源。原生 WebRTC 库已打包。

## 验证结果

| 检查 | 结果与证据（output/voice-126-2026-09-16 下） |
| --- | --- |
| 开发/生产 API 与密钥隔离 | 通过；`endpoint-check.json` |
| 开发双向音频、强制 TURN | 通过；`audio-check.json`，各方向解码数百帧、有音频能量 |
| 生产双向音频、强制 TURN UDP 443 | 通过；`audio-production-check.json`，各方向 430–447 帧 |
| 正式游戏 API 签发凭证后实际双向音频 | 通过；`public-voice-check.json`，239/254 解码帧；被踢拒绝再次加入，房间代际变化 |
| Android 2/4/8 人原生 SDK | 通过；`android/result.json`、`eight-connected.png`。模拟器 + Node 音频参与者；不是 8 台真实手机 |
| Android 开麦、独立收听、跨场景、被踢退出 | 通过；远端收到 Android 麦克风轨，Android 解码远端合成音频；农场到街区原生 session 不变 |
| 后台关闭，回前台不自动开麦/重连 | 通过；`android/background.json` |
| 后端语音用例 | 15/15；`server-tests.log`，含 8 席并发、权限、旧 token 房间隔离、延迟请求、总量限制、管理地址校验 |
| 后端实时功能回归 | 53 通过，5 项 PG 用例因本地环境跳过；真实 PG 数据保留由远端副本和正式指纹补验；`server-realtime-tests.log` |
| Godot 会话/在线/滚动/中文 | 38 通过、0 孤儿节点；`godot-tests.log`。需有窗口模式以测试系统剪贴板；最初 headless 的剪贴板失败经正确环境重跑通过 |
| TypeScript | 通过；`server-typecheck.log` |
| 正式 APK 资源、签名与敏感文件扫描 | 通过；`release/packages.json`、`apk-secrets-check.log` |
| 正式 APK 覆盖更新 | 模拟器旧应用账号与农场恢复、无脚本错误；`release/emulator-smoke.json` |
| Apple 桥接编译 | macOS 与 arm64 iOS Simulator 通过；`apple-build.log`、`apple-simulator-build.log`；后者 Mach-O 平台核实 IOSSIMULATOR / iOS 15 |

音频测试使用合成波形与解码计数，不保存或上传麦克风 PCM/录音。截图检查修复了动态语音按钮图标与文字重叠，以及窄屏语音状态按钮右侧越界。

## 配置与运维

见 `server/deploy/voice/README.md` 与三个 `.env.voice.*example`。本机私有 `server/.env.voice.local` 已连远端开发；正式私有环境在 ECS `/opt/sensen-voice/private/voice-production.env`。密钥不写文档或 APK。

正式游戏使用 `http://172.18.0.1:7880` 调 SFU 管理 API，手机连接 `wss://voice.sensenjoy.cn`。演练初次只连接隔离数据库网络，导致语音管理请求 503；接入与正式容器一致的 `farm_default` 后，dev 演练签发与正式 API 音频均通过。

## 尚待验收

- 两台 Android 真机的听感、回声、蓝牙/有线耳机、蜂窝与 Wi-Fi 切换、来电中断；本轮未连接物理手机，不能把模拟器解码当成真实通话体验完成。
- 海外实际同区域/跨洲延迟、长时间通话、32 人并发和同机游戏负载。香港单节点不是全球优化网络。
- 仅 TCP 443 放行的网络：目前未部署 TURN/TLS，不能保证可用。
- iOS 已有官方 Swift SDK 控制桥接及编译证据；Godot iOS 适配、导出打包、授权与 Android↔iPhone / iPhone↔iPhone 真实音频未验收。保持未来 iOS 支持范围，不将其标记已交付。
- 旧 token 可能重新创建旧房间，但访问不了新代际队伍通话；全局发证限额不是恶意媒体层资源配额。扩量前补充流量监控与服务端硬限额评估。

QA 进程与测试音频房间在验证后关闭；保留模拟器、已安装应用与存档。发布文件与飞书发送结果见同目录 `release/release.json`、`download-verification.json`、`delivery.json`（各阶段完成后生成）。

## 单包交付

已通过飞书 cli bot 发送唯一 Journey 更新包链接，并读回核对消息与下载地址。

- 消息：`om_x100b6591ac2054b4deb548878779290`。
- [Journey 0.11.0 下载](https://oss.sensenjoy.cn/farm/releases/party-voice-20260916-c0f5a2122d93/sensen-party-voice-online-2026-09-16.apk)；151,976,003 bytes，SHA-256 `c0f5a2122d9347707ac0724c7160066b524f005d254a697f30c5acc2a940a402`。
- 当前只有 Android 模拟器连接，未执行物理手机安装。
