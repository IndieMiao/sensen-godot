# 双层焦散整合验证

2026-09-30，基于弱法线版本 `7abcbc4`。旧 layered 版本的本地标签 `pond-water-layered-v1-20260930` 保留。

## 结果与实现

焦散在原水材质中使用两次单色采样。独立运动的两层光纹通过预烘焙低频场发生形变，交叠区域随时间变亮／变淡；保留连续主光纹，避免严格取 `min` 造成碎点。Mip 选择结合屏幕导数与水深，柔化和亮度分别控制。

波纹贴图的原 RGB 与基线逐像素一致，新 Alpha 保存平滑扰动。保留 30% 法线、30% 反光层反差、原高光、水色和焦散深度衰减 1.35。[整合记录](../design/pond-caustics-mobile-2026-09-30.md)、[资源与成本核对](../../output/pond-caustics-mobile-2026-09-30/integration-manifest.json)。

[同机位前后对比](../../output/pond-caustics-mobile-2026-09-30/before-after.png)、[多池形／连续帧](../../output/pond-caustics-mobile-2026-09-30/native-review.png)、[焦散开关与参数对照](../../output/pond-caustics-mobile-2026-09-30/controls-review.png)、[Android 最终录像](../../output/pond-caustics-mobile-2026-09-30/android/water-motion-android.mp4)、[最终录像抽帧](../../output/pond-caustics-mobile-2026-09-30/video-review.png)。

## 验证范围

- `tests/ponds`：12 项通过，0 errors / failures / orphans。[日志](../../output/pond-caustics-mobile-2026-09-30/tests-ponds.log)
- Metal / Mobile 捕获三种池形、近景、390×844 竖屏、12／14／16 秒固定帧；另检查关闭焦散、关闭形变、单层主光纹和增加 Mip 柔化四种对照。
- 捕获验证正常退出、`POND_ART_READY`、无 Shader／脚本错误、实际 PNG、参数和 Shader 哈希。最终五组跨平台画面还校验解码后纹理像素数据哈希，避免依赖 APK 中不存在的原始 PNG 文件。
- Android Vulkan / Mobile 使用 `emulator-5586`、ADB 5053、`com.sensen.pondart.calmcloud`。五组同机位、同时间及参数的 Metal/Vulkan RGB 平均差为 0.2904–0.4666 / 255；竖屏排除上下各 90px 的 HUD／安全区偏移。该值只衡量平台一致性。[详情](../../output/pond-caustics-mobile-2026-09-30/parity.json)
- 最终录制前的 24 次预热后短采样均为 60 FPS；相对弱法线版本，draw calls 同为 32、primitives 同为 1,044,584。没有增加投影 pass。这不是实体手机 GPU 毫秒增量或性能验收。[性能记录](../../output/pond-caustics-mobile-2026-09-30/performance-summary.json)
- 全部捕获 `network_booted=false`。QA APK 完整回读一致，打包后的两张导入纹理与已测桌面资源字节一致；runner 已停止应用，模拟器保留运行，尺寸恢复为 1280×800。[APK 核对](../../output/pond-caustics-mobile-2026-09-30/apk-validation.json)

首轮录像被延迟出现的 Android 系统教育提示遮挡，已归档至 `recording-obscured`，不作为最终录像或性能记录。QA runner 增加录制前的第二次 UI 树检查，使用实时控件边界处理系统提示；最终重新录制并抽帧复核。

最终 Shader SHA-256：`7d93fd856912eaaf2069ef7730c7290ed560528551c12d0df0b25e250f0922c8`。
QA APK SHA-256：`ddb0b6445b49828697f7c48cf819dd0047bbf00c703fa1c879a2d7b916805a75`，86,838,436 字节。

本轮只在隔离预览和模拟器中验证；未发布客户端、部署后端、更新用户手机或操作玩家数据。

## Gensen 飞书交付

同一本人评审会话已发送并回读确认：对比图 `om_x100b64f2bd7340b8b100d54e9f534b0`、最终 12 秒视频 `om_x100b64f3596dc8a4b0354c1f5fe18bf`。视频文件名为 `Gensen-dual-layer-caustics.mp4`，时长和封面一致。

[打开视频消息](https://applink.feishu.cn/client/chat/open?openChatId=oc_b984c6fc14e05e62e6cfd5af2c95ffa6&position=160)、[回读证据](../../output/pond-caustics-mobile-2026-09-30/feishu-delivery/messages-readback.json)。没有交付 APK。
