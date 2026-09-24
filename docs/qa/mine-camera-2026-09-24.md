# 矿坑近景视口验证 · 2026-09-24

对应用户“视角放大，矿坑出屏幕也可以，操控类似农场”的反馈。

## 原生

98 项检查全部通过，0 错误、0 失败、0 孤立节点：矿坑布局、互动与战斗，新的近景相机检查，农场相机、通用拖动缩放与头像组件。

新增覆盖默认人物投影大小、矿室出屏、拖动释放后保持、采矿与同层快照保持视口、双指缩放锚点且不触发点击、离屏头像回中、手势中断回中、背包隐藏提示、挂起恢复与换层重新取景。旧拾取用例改为先平移到对应模型，符合近景允许目标出屏的规则。

检查中修正了两类测试夹具问题：场景重建用例需等待旧节点的 `queue_free` 完成再检查孤立节点；头像单独测试在主世界相机退出后需显式驱动真实渲染帧，才能完成 SubViewport 的一次性画像。没有为此更改头像的生产行为。

原生 Mobile/Metal 截图包含五层 × 三种逻辑视口（360×640、390×844、960×720），另有平移至电梯、离屏头像、回中后的三个状态。`after/chamber-*.png` 仍是美术核对用全室构图，不代表新的游戏默认相机。

## Android

`emulator-5560`，独立 `com.sensen.journeymineartqa / 0.16.32-cameraqa / 2026092402`；36 次真实系统触摸、24 张原始截图通过。使用 `tools/android/run_test.sh` 管理同一次完整会话。

三个请求尺寸：720×1280、780×1688、960×720（最后一个由应用竖屏约束旋转为实际 720×960）。逐尺寸验证：

- 默认近景、可见矿石点击/走近/开采，开采后的镜头中心不变。
- 持续拖动到角色出屏，松手保持，头像提示出现并可点击回中；角色位置与缩放不变。
- 通过既有 `JourneyTouch` 注入 Android OS 双指事件，放大与缩小均生效，且没有增加采矿命令。
- 背包开关保留视角；切换五层的隔离样本恢复入场视角和默认缩放。

触摸位置来自实时 Godot 控件与模型树；系统弹窗来自 UIAutomator。采矿使用隔离本地命令夹具，换层按钮仅用于展示固定样本；本轮没有真实服务器结算或自然玩家难度验证。已有原生矿坑套件覆盖楼梯、电梯和命令恢复。

最终日志无 Godot 脚本、资源加载错误或崩溃。退出后 QA 进程停止，模拟器恢复 720×1560。未操作连接的 V2509A、正式 Journey 或生产数据。

原始证据：`output/mine-camera-2026-09-24/verification/`、`android/report.json`、`android/runtime.log`。原生图片在 `after/`，Android 图片在 `android/`。

通过验证的 QA APK：70,568,479 bytes，SHA-256 `74938c4ff9f41d578a7049e140f2892e9ed41aa7c1f3c97771e6046dd94707f3`。

复现 Android：

```sh
python3 tools/dev/prepare_mine_art_preview.py --android --camera-qa --output output/mine-camera-2026-09-24
godot --headless --path output/mine-camera-2026-09-24/android-project --editor --import --quit
godot --headless --path output/mine-camera-2026-09-24/android-project --export-debug 'Android Mine Art QA'
adb -s emulator-5560 install -r output/mine-camera-2026-09-24/mine-art-qa.apk
tools/android/run_test.sh --serial emulator-5560 com.sensen.journeymineartqa -- node tools/dev/mine_camera_android_qa.mjs
```

双指用例使用模拟器已有 `/data/local/tmp/journey-touch.dex`（源码 `tools/dev/JourneyTouch.java`）。

沿用用户本次矿坑截图检查的明确授权，已将四张 PNG（第一/四层近景对照、离屏头像、电梯平移细节）补充到同一已验证的 Slack 自聊线程。[更新消息](https://gensenapp.slack.com/archives/D0C0V4YULKT/p1790228821391249?thread_ts=1790226637.901109&cid=D0C0V4YULKT)。四份上传 HTTP 200，分享成功并经线程回读核对文件 ID；回执与哈希在 `output/mine-camera-2026-09-24/delivery/`。没有发送 APK 或投递给其他人。
