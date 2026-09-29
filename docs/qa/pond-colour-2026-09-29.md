# 池塘水色复核

2026-09-29，接续用户对首轮水色的反馈。详细差异、采样方法和最终色号见[水色复核与修正](../design/pond-reference-2026-09-29/colour-correction.md)。

本轮改动为 `pond_water.gdshader` 的水色合成／岸边倒影滤波，以及 `bake_pond_bed.py` 的光学深度。三种池塘水底图 RGB 与首轮逐像素相同，只有 alpha 深度变化；目录 SHA-256 仍为 `2c6e2a2f5f6efa3742912257fa8a0b4844cbf89277e5867ac88157784770a187`。

## 最终验证

- Godot 4.7.2 / Mobile：Metal 桌面与独立 Android Vulkan 模拟器均完成三种池塘、近景与竖屏渲染。导出和实际渲染日志没有 shader／脚本错误。
- 6 组固定机位、尺寸、shader 时间、MSAA、阴影和资源哈希相同的捕获，RGB 平均差为 0.0079–0.0520 / 255。竖屏只比较避开安全区 HUD 的中间 3D 区域。该数据表示平台一致性，与设计稿还原分数无关。
- Android 最终会话捕获 8 张固定画面及一组动态画面，录制约 12 秒 MP4；首、中、后帧确认新色阶、鱼影、焦散变形与光斑闪烁。预热后 24 次短采样均为 60 FPS，仅代表 M4 模拟器会话。
- 最终隔离 QA APK 安装到 `emulator-5586`，完整回读与本地逐字节相同。runner 已停止该 QA 进程，模拟器保留。
- 所有捕获报告 `network_booted=false`。本轮没有生产发布、用户手机安装、存档或服务器操作；未新增飞书发送。

交付时桌面动态预览另一次短采样中位数为 52 FPS（51–75），32 draw calls、约 104 万三角形／帧，[原始数据](../../output/pond-colour-2026-09-29/live-preview/performance.json)单独保留。未把模拟器的 60 FPS 当作桌面或实体手机的性能结论。

首轮 33 项游戏逻辑／几何回归仍保留在[首轮 QA 记录](pond-reference-2026-09-29.md)。本轮未修改这些逻辑，也未把已有测试重复计为新的验证数量。

## 证据

- [颜色对照图](../../output/pond-colour-2026-09-29/colour-comparison.png)、[采样原始数据](../../output/pond-colour-2026-09-29/colour-samples.json)
- [跨平台数据](../../output/pond-colour-2026-09-29/parity.json)、[最终 Android 会话](../../output/pond-colour-2026-09-29/android-qa-final.log)
- [动态视频](../../output/pond-colour-2026-09-29/android-final/water-motion-android.mp4)、[视频抽帧](../../output/pond-colour-2026-09-29/motion-review.png)
- [APK 回读](../../output/pond-colour-2026-09-29/apk-validation.json)

QA 包保留 `com.sensen.pondart.calmcloud`；84,404,730 字节；SHA-256：

```text
198065f303ad0eca1761f3818410f18eff0168dadd46d6a3f767d0b2d835c943
```

`tools/dev/open_pond_art.command` 会打开当前修正版。重新生成三栏颜色图：

```sh
python3 tools/dev/compare_pond_colour.py \
  --render output/pond-colour-2026-09-29/native-final/gourd-reference.png
```

参考 PNG 没有嵌入 ICC，按 sRGB 解释；Godot PNG 标记为 sRGB。取样点是对应视觉区域，池形和局部光照没有像素配准。最近岸样本仍略偏暖，不能根据几个色块宣称完全还原。

## 后续 Gensen 飞书交付

用户追问最新素材是否已发到飞书后，已向本人张邵杰的既有 Gensen 私聊补发：修正版三栏颜色对比图 `om_x100b6488d97588a0b306ebf51c86693`，以及最终 12 秒 MP4 `om_x100b6488ea7300a4b3bc3699937aa59`。显式使用 profile=`gensen`、bot 身份、本人 open_id；两条消息、图片资源及视频文件名／时长／封面均已回读核对。[回读证据](../../output/pond-colour-2026-09-29/feishu-delivery/messages-readback.json)。
