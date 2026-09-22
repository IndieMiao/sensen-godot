# 水体细节第二轮验证 · 2026-09-19

本轮对应用户的 0.16.3 真机截图与设计稿对照反馈，范围包括农场池塘、街区柳影湖和芦苇河。目标包为 Journey 0.16.4 / 2026091905，保持 `com.sensen.journeypreview`、原签名及公共服务；首次交付时未向 Joey 发送消息。

## 验证

Godot 4.7.2 四组 **35 项测试全部通过**：钓鱼、农场美术、地块与街区互动。街区老用例按英文按钮查找，初次在中文环境出现四处数组下标错误，旧场景实现也复现；使用项目已有 `SENSEN_LANGUAGE=en` QA 配置后 35 项全部通过，未修改那些测试断言或居民行为。报告：`output/water-detail-2026-09-19/qa/godot-results.xml`。Headless 测试退出仍有 1 个 ObjectDB / DummyTexture 警告，原生 Mobile 场景退出和 Android 切换日志无对应错误；没有将它当作已证明的 Android 运行期泄漏。

Mobile / Compatibility 实际画面已检查；原生专用观察镜头位于 `native/`，仅用于材质对照，不代表普通玩家镜头。观察脚本使用存档快照，已关闭自动联网；不写游戏存档。

Android 模拟器通过普通触控完成：农场连接完成后走到岸边、抛竿、咬钩、按住/松开拉竿、失败结算、关闭返回；街区普通步行分别到湖泊/河流抛竿、关闭；另从池塘东岸走到南岸并拖动正常游戏相机观察水面。所有场景由 `tools/android/run_test.sh` 启动并在结束时停止，坐标来自只读场景树或实际相机投影。

模拟器静止池塘取样 10 次为 60 FPS；岸景反射捕获计数保持不变，确认没有在静止时不断重绘。移动/换景时会重建或刷新捕获，不宣称真机持续 60 FPS。测试过程中发现较大岸石遮住近岸浮漂，已收窄降低常用进场方向的岸石，后续截图中可见浮漂与鱼线。

用户随后重新连接并解锁 V2509A，本轮已完成实际手机验证：池塘抛竿、咬钩、按住/松开拉竿、结算和退出；街区湖泊/河流普通步行到岸边后抛竿；池塘南岸步行与相机拖动观察。池边 10 次取样为 83–90 FPS，中位 88，静止反射捕获计数保持 5。该取样不代表所有场景或长时间散热后的性能。

**正式 0.16.4 已安装到 V2509A。** 移除观察器后的公开 APK 已冷启动复查，`device/final-smoke.json` 全部通过。从手机拉回已安装 APK 的 SHA-256 与公开包一致。原安装身份、五份本地偏好/外观文件、装备、47 个作物格、187 金币及其余游戏字段保留；农场从 v262 到 v269 仅增加本轮真实钓鱼记录及自然时钟推进，无改存档或清理应用数据。最终冷启动按本轮备份的上海地图选择进入，保留其银湖区原农场身份。

## 保存和发布约束

服务端 domain 25 / content `50c2dbdde04c9678` 未变；未修改钓鱼数据、通行图或装备配置。模拟器每轮核对作物、库存、装备和金币，除实际 QA 钓鱼指令与自然时钟推进外没有额外游戏写入。

只提供一份原 Journey 更新包。发布包移除只读观察器；原签名为 `38771d94b8fbfa11651cc440e3746c9182114461a90cc0ab7188d7b708515673`。正式 APK 已在模拟器覆盖安装并冷启动进入原农场、走到岸边打开/关闭钓鱼；`emulator/final-smoke.json` 通过。安装后从模拟器拉回 APK 比较哈希一致，服务端农场身份和最后一次 QA 后的作物、库存、金币、装备及钓鱼记录逐项一致。

- 文件：`sensen-journey-water-detail-0.16.4.apk`，156355815 bytes。
- SHA-256：`f6d05bc633f45b315025e14f6e81cd0ec5ee81bf9c425ca08fd3bc1cc753148f`。
- 首次发布时手机尚未重连，公共不可变清单记载 `physical_validation: false`、`emulator_validation: true`；随后同一哈希的 APK 已在 V2509A 安装和验证。补充真机证据为 `device/final-smoke.json`，没有覆写原公共发布文件。


对比图：`output/water-detail-2026-09-19/comparison.jpg`，按来源标明设计稿、用户 0.16.3 真机图、0.16.4 V2509A 真机。只裁剪和等比缩放截图，未修改画面颜色。Android 证据包括 `emulator/pond-composition.png`、`pond-reel.png`、`street_lake-cast.png`、`street_river-cast.png` 与 `reflection-samples.json`。


## 下载

[DMIT 美国下载](https://download-us.sensenjoy.cn:8443/farm/releases/water-detail-20260919-f6d05bc633f4/sensen-journey-water-detail-0.16.4.apk) / [OSS 备用](https://oss.sensenjoy.cn/farm/releases/water-detail-20260919-f6d05bc633f4/sensen-journey-water-detail-0.16.4.apk)。
两个地址均通过 HTTPS 全量下载、SHA-256 对比与 Range 206 字节校验，见 `release/download/verification.json`。仅上传 APK、公共清单和校验文件，没有上传私有存档。首次交付时未向 Joey 或其他联系人发送链接。


真机补充证据：`device/pond-composition.png`、`pond-reel.png`、`street_lake-cast.png`、`street_river-cast.png`、`final-ready.png`、`final-bank.png`、`reflection-samples.json` 与 `final-smoke.json`。本轮开发和首次交付时没有发送 Joey 消息。


## 用户授权后的 Slack 交付

2026-09-19 16:15:49（北京时间），用户明确授权将本包通过 Slack 发给 Joey。已发送 0.16.4 美国下载、OSS 备用地址与简短更新说明，并回读确认。[Slack 消息](https://gensenapp.slack.com/archives/D0C1MHLA3GQ/p1789805749666689)。回执：`output/water-detail-2026-09-19/delivery/slack-receipt.json`。

本次授权只对应当前包；后续仍遵守用户“明确要求才发送给 Joey”的偏好。
