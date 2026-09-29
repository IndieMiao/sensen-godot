# 较大、连续流动的水面高光

**后续已被替换：** 用户指出此版像漂浮物、没有真实光照关系。最新实现改用 HDR 环境图和引擎 GGX 镜面光，见[反射核对](pond-reflection-2026-09-29.md)。下文仅记录被否定方案的历史实现与检查。

2026-09-29，用户认可当前水色层次，要求适量增加水面高光、避免细碎，并看见高光流动。本轮仅修改系统池塘 shader 的高光生成，保持已认可的水色、光学深度、石床、鱼影与焦散。

## 实现与实际画面

高光由较宽的柔光片组成，主轴约 10–17 厘米，随波缓慢伸缩、旋转和变形。图案沿水面以约 9 厘米／秒平流，再由波形扰动轨迹；这是图案速度，不是实际水流模拟。每像素检查四个相邻网格，避免光片越过生成单元边界时突然截断。保留慢速明暗变化和柔光晕，靠岸平滑淡出。

- [同机位前后对比](../../output/pond-highlights-2026-09-29/before-after.png)
- [最终 Android 12 秒动态录像](../../output/pond-highlights-2026-09-29/android/water-motion-android.mp4)
- [12／14／16 秒实际帧](../../output/pond-highlights-2026-09-29/motion-frames.png)
- [相同水面位置的移动近景](../../output/pond-highlights-2026-09-29/motion-detail.png)
- [390×844 竖屏](../../output/pond-highlights-2026-09-29/native/gourd-portrait.png)

连续帧和录像抽帧已检查：光片有持续位移，同时改变长短、方向和亮度。形状保持完整，手机竖屏中仍可辨认；不依赖高频法线阈值产生碎白点。这里是实现与渲染核对，最终高光强度和节奏仍由用户视觉评审。

## 保留水色

固定机位和 shader 时间 12 秒，排除白色高光后，五个原有水面样本的 RGB 中位数与已确认版本完全一致：

```text
[18,134,185]  [18,140,189]  [31,184,212]  [91,235,233]  [118,234,228]
```

[原始对比数据](../../output/pond-highlights-2026-09-29/colour-preservation.json)。这说明这些基准色阶被保留，不表示所有被高光覆盖的像素颜色不变。

## 验证

- 三种池塘、近景与竖屏完成 Godot 4.7.2 / Mobile 实际渲染，无 shader／脚本错误。
- 五组 Metal 与 Android Vulkan 同机位、同时间捕获，元数据一致，RGB 平均差 0.0333–0.0520 / 255；竖屏排除安全区 HUD。该数据表示平台一致性，不是设计图还原分数。
- 独立 `emulator-5586` / ADB `5053` 完成场景捕获和 12 秒录像，预热后 24 次短采样均为 60 FPS。这是 M4 模拟器结果，未做实体手机或 iOS 性能验收。
- 离线 QA 包 `com.sensen.pondart.calmcloud` 完整 APK 回读相同，runner 已停止应用，模拟器保留；捕获均 `network_booted=false`。
- 本轮为单个 shader 的高光调整，未修改玩法、几何、存档或生产服务；未重复计入此前游戏逻辑回归数量。

[会话日志](../../output/pond-highlights-2026-09-29/android-qa.log)、[跨平台数据](../../output/pond-highlights-2026-09-29/parity.json)、[APK 回读](../../output/pond-highlights-2026-09-29/apk-validation.json)、[录像抽帧](../../output/pond-highlights-2026-09-29/video-review.png)。

最终 QA APK：84,404,730 字节，SHA-256：

```text
96f5f801d9b289429a170fb8af14f3f4dffbf5fa1194525c12eada221e83ceb5
```

`tools/dev/open_pond_art.command` 打开当前动态效果。前两轮素材保持原路径，本轮材料位于 `output/pond-highlights-2026-09-29`。
