# 鱼漂水波纹增强

2026-09-30，基于 `a0fa6a5`，按用户截图加强鱼漂附近水波纹。

仅调整池塘水材质中的交互波纹：默认强度乘数为 2；波长约从 0.22m 改为 0.29m；增强局部法线起伏，亮波峰搭配柔和暗波谷。波纹在 0.55–0.95m 范围淡出，并在近岸淡化。屏幕导数柔化小视图中的圆环边缘。表面弱法线、水色、焦散及一般高光参数沿用上一版。

`FishingPresentation` 未改动：等待仍传入 0.3，拉鱼为 0.7，停止为 0。离线预览新增鱼漂近景，以及等待／拉鱼／停用／强度关闭对照；拉鱼示例跳过入场水花，核对持续波纹。

- [同机位前后近景](../../output/pond-bobber-ripples-2026-09-30/before-after.png)
- [相位对照](../../output/pond-bobber-ripples-2026-09-30/state-review.png)、[扩散连续帧](../../output/pond-bobber-ripples-2026-09-30/motion-review.png)
- [30 秒完整池塘视频](../../output/pond-bobber-ripples-2026-09-30/Gensen-Pond-Bobber-Ripples-30s.mp4)、[抽帧复核](../../output/pond-bobber-ripples-2026-09-30/video-review.png)

现有 `tests/ponds` 12 项通过，0 errors / failures / orphans。Metal / Mobile 和 Android Vulkan / Mobile 核对全景、参考机位、鱼漂近景及 390×844 竖屏；Shader／纹理哈希、相机、波纹强度和交互状态一致。四组 RGB 平均差为 0.3462–0.6967 / 255，竖屏排除上下各 90px HUD／安全区，属于平台一致性数据。[测试日志](../../output/pond-bobber-ripples-2026-09-30/tests-ponds.log)、[画面对比](../../output/pond-bobber-ripples-2026-09-30/parity.json)。

模拟器最终预热后 24 次短采样均为 60 FPS。全景机位为 33 draw calls，与此前同一全景机位相同；不与较近参考机位的 32 次混为一谈。没有新增纹理采样或绘制几何，未测实体手机 GPU 毫秒增量。

QA 包 `com.sensen.pondart.calmcloud` 在 `emulator-5586` 完整回读一致；全部捕获 `network_booted=false`。录制在恢复横屏后的冷启动中进行，30 秒成片无遮挡。视频交付版保留 1280×800、30 FPS，约 5.5 MB。runner 已停止应用并保留模拟器；未更新实体手机、部署服务、修改存档或发送 APK。

最终 Shader SHA-256：`56820fb73d512eb00a4669f69e169d370309c3223597fd073fb6a410884d2569`。
QA APK SHA-256：`541a21699a0e8f3a5ed019a047d56673854284265f1d978466c9ae7c18c7f10e`。

对比图 `om_x100b64fe645ef8b4b2ee12150c1ab0e` 和更新后的 30 秒全景视频 `om_x100b64fe06cd00a8b1a9bebe03d0b01` 已发送至同一 Gensen 本人评审会话，并回读确认文件名、时长和封面。[视频消息](https://applink.feishu.cn/client/chat/open?openChatId=oc_b984c6fc14e05e62e6cfd5af2c95ffa6&position=165)。
