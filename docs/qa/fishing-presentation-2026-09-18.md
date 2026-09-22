# 钓鱼动作与场景 UI：0.15.1

2026-09-18，对应用户标注图和 SGODOT-129。规格见 [场景内钓鱼与动作反馈](../product/fishing-presentation-2026-09-18.md)。

## 交付行为

- 移除大弹窗和全屏暗罩，使用落点旁的细竖条、底部单个圆形钓鱼按钮及退出按钮。
- 同一按钮完成抛竿、提竿和按住拉竿。钓鱼时收起任务、种子、农活、摊位和联机 HUD，退出后恢复原界面和相机。
- 朝向水面的双手持竿、前甩、扬竿和上身发力姿态；双臂求解到竿柄与卷线柄，鱼竿弯曲、鱼线张弛、浮漂抖动和水纹与状态联动。
- 在原长发装扮上复核后，将取景调整为更侧面的近景，并将握持位置前移，避免头发遮住手部。
- 服务端确认捕获后才播放提鱼出水；失败、取消、未确认命令和后台恢复沿用已有保护。
- 水面增加深浅色、细波纹法线、柔和反光、浅水光纹与浮漂涟漪，替换白色圆斑及亮色管状边圈。

本轮为客户端表现更新。公网仍使用 `fishing-20260918` / domain **23** / content **1b7a7871f9f19e49**，未修改鱼种、价格、捕获难度、导航或数据库。

## 验证

| 检查 | 结果 |
| --- | --- |
| Godot 相关回归 | 钓鱼、农场场景和街区交互 61 项通过，0 errors / failures / orphans，`reports/report_1184` |
| 最终钓鱼专项 | 手位、侧面镜头及卷线柄调整后 7 项通过，`reports/report_1187` |
| UI 与动作契约 | 无全屏 ColorRect；两个按钮中只有一个钓鱼操作按钮；竖条与按钮不重叠；抛竿事件不会被快速回包跳过；鱼线端点跟随竿尖/浮漂；退出恢复 HUD、镜头和待机 |
| Android 模拟器 | 实际触摸完成捕获、出售、街区钓鱼、失败与后台恢复。长按时手部位移约 0.158m、竿尖位移约 0.456m；随后在真机复测最终长发构图与手位 |
| V2509A 最终方案 | 8 项连续检查通过，40 次真实触摸转换；真实公网结算与背景恢复通过；无脚本或着色器错误 |

原生图片验证使用隔离工程与模拟状态，只用于构图/姿态；没有作为真实捕获或结算证据。Android 与真机测试分别使用隔离 QA 账号及用户原 Journey 账号，真机观察器只读控件矩形和状态，不注入账号、移动、操作输入或服务器结果。

最终真机长按采样：手部位移 **0.121m**，竿尖位移 **0.882m**，拉力表现系数约 **0.9999**；当时 FPS 为 117，仅是该采样点，不作为长期性能结论。已保存 20 秒、1080×2344 的真实屏幕录像，包含抛竿、咬钩和拉竿。

自动化脚本适配了已有鱼堆叠导致的背包详情返回层级，以及 Godot 对节点名冒号的下划线替换；没有修改游戏数据来绕过这两个脚本问题。最终完整场景从正常选城、地图、农场进入，走到池塘/湖泊/河流后操作。

## 原账号与最终安装

- vivo V2509A / `10AFAF162200319`，最终安装 **Journey 0.15.1-fishing-motion / 2026091803**，包名仍为 `com.sensen.journeypreview`。
- 原 `install_key`、农场选择、地区选择、UI 状态和装扮 5 份文件逐字节保持；原 47 条耕作记录及成熟时间、非鱼库存、装备、矿井、人物属性、旅程和装饰状态与测试前一致。
- 最后完整场景版本 145→158、金币 185→187，成功捕获并售卖鲫鱼，再钓得金锦鲤。包含前面检查在内，本轮实际测试累计金币 178→187、鲫鱼增加 1 条、金锦鲤增加 1 条；全部来自真实玩法结算。
- 最终无观察器包完成冷启动与服务端状态精确回读。直接使用公网 HTTPS，无本机服务或 adb reverse 依赖。
- APK **152074549 bytes**；SHA-256 `958db1810f934b95b9939b8b421b27c61bbff434bd98f7bd2fede0d0b5e1dc0a`。
- 沿用原签名 SHA-256 `38771d94b8fbfa11651cc440e3746c9182114461a90cc0ab7188d7b708515673`。最终包排除观察器、QA 场景及测试身份。手机安装回读与最终 APK 一致。
- 所有 Android 测试使用 `tools/android/run_test.sh`，退出时停止测试应用，保留安装、模拟器和存档。

## 证据

- [用户标注参考](../../output/fishing-presentation-2026-09-18/reference.png)
- [最终真机拉竿画面](../../output/fishing-presentation-2026-09-18/device/final-reel-frame.png)
- [20 秒真机视频](../../output/fishing-presentation-2026-09-18/device/fishing-motion.mp4)
- [真机结果](../../output/fishing-presentation-2026-09-18/device/result.json)
- [动作位移采样](../../output/fishing-presentation-2026-09-18/device/motion-metrics.json)
- [最终冷启动](../../output/fishing-presentation-2026-09-18/device/final-smoke.json)
- [安装与回读](../../output/fishing-presentation-2026-09-18/device/installation.json)
- [模拟器结果](../../output/fishing-presentation-2026-09-18/android/result.json)

Plane 继续保留更广的自然玩家学习难度、重复选择与经济平衡观察范围；本轮动作、UI、水面与真机更新已完成。

## 2026-09-19 Slack 交付 Joey

用户要求提交线上、打包并通过 Slack 发送 APK 地址。复核线上服务仍为 domain 23 / content `1b7a7871f9f19e49`，最新 0.15.1 最终包哈希一致，运行时代码没有晚于该包的改动；沿用已打包、上线及真机验收的同一版本。

重新检查 DMIT 与 OSS 的 HTTPS 地址，均返回 206，下载样本与最终 APK 相同。已发送至 Joey 的既有 Slack 私聊，包含两处下载地址、版本、主要更新和覆盖安装说明，并回读核对。

[Slack 消息](https://gensenapp.slack.com/archives/D0C1MHLA3GQ/p1789751716137789)；[发送回执](../../output/fishing-presentation-2026-09-18/delivery-2026-09-19/slack-delivery.json)。

## 同一最终包下载

- [DMIT 美国下载](https://download-us.sensenjoy.cn:8443/farm/releases/fishing-motion-20260918-958db1810f93/sensen-journey-fishing-0.15.1.apk)
- [OSS 备用](https://oss.sensenjoy.cn/farm/releases/fishing-motion-20260918-958db1810f93/sensen-journey-fishing-0.15.1.apk)

两处均完成全量 HTTPS 下载、SHA-256 和 Range 206 指定片段校验，与手机最终安装回读一致。只向新的不可变版本目录发布 APK、清单和校验文件；没有修改旧文件或服务端配置。见[发布清单](../../output/fishing-presentation-2026-09-18/release/release.json)与[下载验证](../../output/fishing-presentation-2026-09-18/release/download/verification.json)。
