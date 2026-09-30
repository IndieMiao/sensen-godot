# 焦散动态修正验证

2026-09-30，基于 `2d3797d`。用户反馈上版仍像平移；本轮重新核对原网页动图，移除占主导的固定光纹，使用宽光带的完整双层交集与三组独立波动形变。[设计与原因](../design/pond-caustics-motion-2026-09-30.md)

## 动态证据

- [12 秒同步对比视频](../../output/pond-caustics-motion-2026-09-30/motion-comparison-final.mp4)：前 6 秒为上版／新版，后 6 秒为新版／关闭纹理平移。均为 Godot Metal/Mobile 实际渲染，640×400 每侧，24 FPS，Shader 时间从 12 秒开始，以相同步长捕获。历史 Shader 和历史焦散纹理从保存副本临时载入，没有用新版纹理冒充旧版。
- [静态对比](../../output/pond-caustics-motion-2026-09-30/before-after.png)用于确认水色与场景；不能单独证明动画形变。
- [灰度控制画面](../../output/pond-caustics-motion-2026-09-30/motion-proof.png)只显示焦散并固定诊断深度，排除高光、鱼、水底颜色和折射的干扰。关闭平移时，选定水域两秒间 RGB 平均差为 79.317 / 255，90.8% 像素变化超过 5；同时冻结形变后，该区域差异为 0。这是动作来源验证，不是参考还原评分。[原始指标与区域](../../output/pond-caustics-motion-2026-09-30/motion-proof.json)

## 回归与 Android

- 现有 `tests/ponds` 12 项通过，0 errors / failures / orphans。[日志](../../output/pond-caustics-motion-2026-09-30/tests-ponds.log)
- 三种池形、近景和 390×844 竖屏均完成 Metal 与 Vulkan / Mobile 捕获。五组相同相机、Shader 时间、参数、Shader 及解码纹理哈希的 RGB 平均差为 0.2873–0.4541 / 255；竖屏排除上下各 90px 的 HUD／安全区偏移。[详情](../../output/pond-caustics-motion-2026-09-30/parity.json)
- [Android 最终 12 秒实录](../../output/pond-caustics-motion-2026-09-30/android/water-motion-android.mp4)及[抽帧](../../output/pond-caustics-motion-2026-09-30/android-video-review.png)已复核，没有系统提示遮挡。最终 24 次预热后短采样均为 60 FPS，draw calls 为 32、primitives 为 1,044,584；未测实体手机 GPU 耗时。[性能](../../output/pond-caustics-motion-2026-09-30/performance-summary.json)
- 焦散保留两次采样和原有绘制 pass，新增三次正弦计算。没有新增投影几何或场景深度读取；原法线、反射和表面高光参数保留。
- 隔离 QA 包为 `com.sensen.pondart.calmcloud`，设备 `emulator-5586`，ADB 5053。APK 完整回读和导入纹理字节检查通过，全部捕获 `network_booted=false`。runner 停止应用，模拟器保持运行，尺寸恢复为 1280×800。[APK 证据](../../output/pond-caustics-motion-2026-09-30/apk-validation.json)

首轮 Android 录像再次出现尺寸切换后的系统教育遮罩，默认 UI 树并未暴露该窗口。此序列归档为 `android-obscured`，不作为最终录像／性能证据。录制流程现在在尺寸测试结束、恢复横屏后，冷启动同一个隔离预览包再测量和录像；没有清除数据或触碰其他应用。修改后重跑完整序列，最终日志含 `RECORDING_COLD_START`，成片已复核。

最终 Shader SHA-256：`59fb9544d3ee25424342f4c369c8469b94f49a04742d30f3fea6998cb93fd028`。
QA APK SHA-256：`03b01002aa73a4a71aa94f4489672a578688906008e3a15c235bf780efb7c9d8`，86,912,164 字节。

## 飞书交付

Gensen 本人评审会话中，对比图 `om_x100b64fde89eb088b16fa509240e58b` 和同步对比视频 `om_x100b64fde34e68a0b3b4c4c53aadcca` 已发送并回读确认。文件名 `Gensen-caustic-motion-comparison.mp4`，时长 12 秒、封面一致。[视频消息](https://applink.feishu.cn/client/chat/open?openChatId=oc_b984c6fc14e05e62e6cfd5af2c95ffa6&position=162)、[回读证据](../../output/pond-caustics-motion-2026-09-30/feishu-delivery/messages-readback.json)。

没有发送 APK、更新实体手机、部署服务或操作玩家数据。旧版标签和历史提交保持可用，视觉取舍仍由用户评审。
