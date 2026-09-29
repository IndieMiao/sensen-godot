# 双层纹理阈值水面核对

2026-09-30。用户否定前一版长条高光并提供 80.lv 文章。本轮已读取原文、Josh 的原始 10 秒演示、材质节点图及 Jasper 视频 10:44 后的阈值方法，来源与适配说明见[设计记录](../design/pond-water-breakdown-2026-09-30/README.md)。

## 最终实现与视觉检查

使用独立滚动的两层自制纹理产生共同高度场；低阈值塑造反光表面层，高阈值产生会变形、生长和消退的闪光。法线来自同一高度场。保留 HDR 环境反射，风格化闪光经过实际灯光、阴影和视角响应，最终强度为 4。

[同机位前后图](../../output/pond-water-breakdown-2026-09-30/before-after.png)、[12／14／16 秒连续帧](../../output/pond-water-breakdown-2026-09-30/motion-frames.png)、[Android 录像](../../output/pond-water-breakdown-2026-09-30/review-android/water-motion-android.mp4)、[抽帧复核](../../output/pond-water-breakdown-2026-09-30/video-review.png)。

已对照原始演示复核闪光尺寸、边缘和生灭，确认长斜条纹已移除；没有把原作者或 Nintendo 的纹理放进游戏。这是该方法在现有 Godot 场景中的适配，池形、配色、光照环境和岸线仍不同，不能宣称完整复刻 UE5 参考或用户已通过视觉验收。

## 验证结果

- `tests/ponds`：最终 12 项通过，0 error / failure / orphan；未改变地点目录、导航和游戏数据。
- Metal / Mobile 实际捕获三种池塘、近景、390×844 竖屏，以及太阳镜面光关闭、环境关闭、波纹关闭和转向观察的控制画面。
- Android Vulkan / Mobile 完成同一场景序列及约 12 秒录像。5 组相同机位、时间、光照／环境／阈值参数的 3D RGB 平均差为 0.2605–0.3758 / 255；竖屏排除安全区 HUD。该数据仅表示平台一致性。
- 正确读取 Shader 默认值，所有最终画面 `shimmer_strength=4`。太阳镜面强度为 0 时闪光消失，环境关闭时反光层消失，波强度为 0 时高度场恒定、不再产生闪光。[控制参数](../../output/pond-water-breakdown-2026-09-30/lighting-response-final.json)
- 模拟器最终预热后 24 次短采样均为 60 FPS；这是共享 M4 宿主的模拟器结果，不是实体手机性能验收。
- 隔离 QA 包在 `emulator-5586` 完整回读相同，runner 已停止应用，模拟器保留。所有捕获 `network_booted=false`，未发布或更新用户手机。

桌面交互预览的另一组短采样中位数为 56 FPS（53–60），[原始记录](../../output/pond-water-breakdown-2026-09-30/live-preview/performance.json)单独保留，不与模拟器结果合并为性能保证。

[最终回归日志](../../output/pond-water-breakdown-2026-09-30/tests-ponds-final.log)、[Android 日志](../../output/pond-water-breakdown-2026-09-30/android-review.log)、[平台对比](../../output/pond-water-breakdown-2026-09-30/parity.json)、[APK 回读](../../output/pond-water-breakdown-2026-09-30/apk-validation.json)。

QA APK 86,772,900 字节；SHA-256：

```text
1455e8c516dff7d2e1cab08796c16525272ccdf4ba8cb927d7324d659baa55d2
```

## 预览隔离修复

第一次捕获序列发现，输出目录中的备份 `fishing_water.gd` 被父工程扫描，覆盖了 `FishingWater` 全局类路径；首张图缺失，该序列不计为最终通过。已添加 `output/.gdignore`，预览 launcher 和准备脚本会确保标记存在。重新导入后核对父工程与隔离工程的 class cache 均不含 `res://output/`，`FishingWater` 和 `FishingPondScene` 均指向正式源码。

随后顺序导出再捕获，最终捕获不仅检查进程退出码，还检查 `POND_ART_READY`、无 `ERROR:` 和真实 PNG 文件。全部最终图片位于 `review-native`／`review-android`，未复用失败序列的结果。

## Gensen 飞书交付

同一本人评审会话已收到本轮前后对比 `om_x100b648b990efca4b11b5ee80099395` 和 12 秒视频 `om_x100b648ba45bf8a8b266579470b85fd`，消息、图片资源、视频文件名／时长／封面已回读核对。[证据](../../output/pond-water-breakdown-2026-09-30/feishu-delivery/messages-readback.json)。只发送本项目的对比图和渲染视频，没有转发原作者完整视频、APK 或发给其他收件人。
