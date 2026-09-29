# 弱法线水面与焦散范围

2026-09-30。按用户要求，先原样保存双层纹理水面，再制作弱法线对照版。

## 保留版本

- 原版本提交：`e89107af81c42e4f168fe90048b131beddaa83cb`。
- 本地 annotated tag：`pond-water-layered-v1-20260930`，在任何本轮材质修改之前创建，未推送远端。
- 标签包含此前完整的池塘材质、环境、石头、荷叶、树、原始纹理、工具和验证文档。
- 标签内水面 Shader SHA-256：`12733edc6a6ebac5333d4a057fe071a1e8a0744c6be2166efc887bdd694c6734`，与上轮最终渲染记录相同。[保存核对](../../output/pond-water-soft-normal-2026-09-30/preservation.json)

## 本轮变化

| 项目 | 保留版 | 弱法线版 |
| --- | --- | --- |
| 基础法线斜率幅度 | 100% | 独立参数 `normal_strength=0.30` |
| 低阈值反光层明暗反差 | 100% | `film_contrast=0.30` |
| 反光层阈值边界 | 屏幕导数抗锯齿 | 额外保留 0.045 的柔化半宽 |
| 焦散随深度衰减 | `exp(-depth * 2.1)` | `exp(-depth * 1.35)` |

单独减弱法线的首张试渲染仍有明显反射分块，因此最终同时减轻反光层反差、柔化边界。高光所用高度场、阈值、运动速度与强度 4 保持原设定，光照与视角仍决定最终亮度。环境反射、三段水色、水底纹理、鱼和浮漂交互继续使用现有实现。

焦散范围通过较慢的深度衰减向池塘中部延伸，没有放大纹理单元或整体水色。光程深度为 1 时，衰减权重约从 0.122 增至 0.259；岸边零深度的增益不变。此数值描述 Shader 衰减，不是屏幕覆盖面积比例。

[同机位前后对比及深水放大](../../output/pond-water-soft-normal-2026-09-30/before-after.png)、[多池形与连续帧](../../output/pond-water-soft-normal-2026-09-30/native-review.png)、[Android 12 秒录像](../../output/pond-water-soft-normal-2026-09-30/android/water-motion-android.mp4)、[录像抽帧](../../output/pond-water-soft-normal-2026-09-30/video-review.png)。

## 验证

- 现有 `tests/ponds`：12 项通过，0 errors / failures / orphans。[日志](../../output/pond-water-soft-normal-2026-09-30/tests-ponds.log)
- Metal / Mobile：三种池形、近景、390×844 竖屏，以及 12／14／16 秒固定帧。每张检查正常退出、`POND_ART_READY`、无 `ERROR:`、实际 PNG 和参数／Shader 哈希。
- Android Vulkan / Mobile：隔离的 `emulator-5586` / `com.sensen.pondart.calmcloud` 完成同一序列与 12.008 秒录屏。五组同机位画面的 RGB 平均差为 0.2903–0.4659 / 255；竖屏排除顶部和底部各 90px 的 HUD／安全区差异。仅表示平台一致性，不代表参考图还原评分。[参数与平台比对](../../output/pond-water-soft-normal-2026-09-30/parity.json)
- 模拟器预热后的 24 次短采样为 60–61 FPS，中位数 60；不是实体手机性能验收。
- 全部捕获 `network_booted=false`。QA APK 完整回读一致，测试进程已停止，模拟器尺寸已恢复并保留运行。[APK 核对](../../output/pond-water-soft-normal-2026-09-30/apk-validation.json)
- 保留 `output/.gdignore`；父工程和预览工程 class cache 不含 `res://output/`。导入／导出与原生捕获顺序执行。

最终 Shader SHA-256：`23a96f6612a3a4d2120af35e744010937a73119372f94b989a977277e08adb9e`。
QA APK SHA-256：`883d27fa49e310c82422c591c1ca7aa4be0f650321e4cea63463d5fb912bd8af`，86,772,900 字节。

本轮是本地美术对照版；未部署服务、操作玩家数据或更新实体手机，视觉取舍仍交由用户评审。

## Gensen 飞书交付

沿用本轮已指定的本人评审会话，发送并回读确认：

- 对比图：`om_x100b64f40de360a0b0467106a524d1c`。
- 12 秒录像：`om_x100b64f405c9e4a8b10ba0d506c68a1`，文件名 `Gensen-soft-normal-water.mp4`；时长、封面和会话一致。
- [打开视频消息](https://applink.feishu.cn/client/chat/open?openChatId=oc_b984c6fc14e05e62e6cfd5af2c95ffa6&position=157)；[回读记录](../../output/pond-water-soft-normal-2026-09-30/feishu-delivery/messages-readback.json)。

只交付本轮美术对比与录像，未发送 APK。
