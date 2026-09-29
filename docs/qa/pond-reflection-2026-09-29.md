# 池塘 HDR 环境反射与 GGX 高光核对

2026-09-29 开始，09-30 完成。目标、实现边界与参考链接情况见[设计记录](../design/pond-reflection-2026-09-29/README.md)。本轮替换用户否定的漂浮白斑方案，没有把它当作已获视觉验收的实现。

## 灯光关系

使用真实运行场景固定 shader 时间 12 秒，依次改变单个条件。所有参数及截图由同一个 `pond_pitch.gd` 记录。材质未覆盖的参数从 RenderingServer 读取 shader 默认值，避免把 `null` 当作实际强度。

| 检查 | 操作与结果 |
| --- | --- |
| 太阳高光 | 仅将真实太阳节点 `light_specular` 置 0，直接太阳亮部消失，环境反光仍在 |
| 环境反射 | 将 `reflected_light_source` 改为 Disabled，天空反光层消失，太阳镜面光仍在 |
| 法线关系 | `wave_strength=0` 后，反光收敛为平面水面效果，波峰亮边消失 |
| 环境方向 | 环境图旋转 90°，反射区域改变；场景布局、时间和太阳不变 |
| 光源方向 | 太阳方向旋转 60°，镜面响应随实际光源改变 |
| 观察方向 | 摄像机绕水面旋转 30°，反射随观察方向变化；这是视觉核对，不用整图像素差来证明模型准确率 |

[控制截图](../../output/pond-reflection-2026-09-29/lighting-controls-final.png)、[原始参数／差异记录](../../output/pond-reflection-2026-09-29/lighting-response-final.json)。上述开关检查证明反光与灯光、环境、法线关联，不代表水体已达到参考图的完整视觉还原。

## 渲染与回归

- `tests/ponds` 12 项通过，0 error / failure / orphan，覆盖现有池塘几何、浮漂、导航、相机、动作与 UI。
- Godot 4.7.2 / Mobile，桌面 Metal 与独立模拟器 Vulkan 完成三种池塘、近景、竖屏和动态验证，最终导出／渲染日志无 shader 或脚本错误。
- 六组相同机位、时间、太阳强度／角尺寸、环境方向／能量、辐射图尺寸、波强度／粗糙度的画面，平均 RGB 差为 0.2311–0.4862 / 255。竖屏只比较避开安全区 HUD 的中间区域。这是平台一致性数据，不是参考图相似度。
- 最终约 12 秒 Android 实录已复核首、中、后帧：波面改变反射形状，天空反光与波峰亮边同时存在，没有独立发光白斑层。预热后 24 次短采样均为 60 FPS，仅为 M4 模拟器会话结果。
- QA 包仅安装在 `emulator-5586`，使用 ADB 5053；全 APK 回读相同，runner 已停止该应用，模拟器保留。没有更新用户手机、发布 Journey、修改生产服务或存档。

所有捕获为 session=null、`network_booted=false`。地图目录 SHA-256 仍为 `2c6e2a2f5f6efa3742912257fa8a0b4844cbf89277e5867ac88157784770a187`。

交付时另开的桌面预览短采样中位数 52 FPS（51–79），32 draw calls、约 104 万三角形／帧，见[独立记录](../../output/pond-reflection-2026-09-29/live-preview/performance.json)。模拟器的 60 FPS 不推广为桌面或实体手机的性能保证。

## 证据

- [回归日志](../../output/pond-reflection-2026-09-29/tests-ponds.log)、[Android 会话](../../output/pond-reflection-2026-09-29/android-qa-final.log)
- [跨平台数据](../../output/pond-reflection-2026-09-29/parity.json)、[APK 回读](../../output/pond-reflection-2026-09-29/apk-validation.json)
- [最终视频](../../output/pond-reflection-2026-09-29/android-final/water-motion-android.mp4)、[录像抽帧](../../output/pond-reflection-2026-09-29/video-review.png)

最终 QA APK 86,506,434 字节，SHA-256：

```text
883404805718b024d551f17cd4b0b1e2f2a8577abd9069097cd880266e93db53
```

HDR 文件 SHA-256：`758dcecde7066d3411a700d7d26793fb2dacd7cf4eec1a2e427d3036b64ea110`。

## Gensen 飞书评审素材

延续用户指定的同一 Gensen 飞书本人评审会话，前后对比图、光照控制图和 12 秒视频已发送并回读核对。三条消息分别为 `om_x100b648a7d9f84a4b32ba7153225e1c`、`om_x100b648a0f3e60a0b2a682fcd94babd`、`om_x100b648a03254ca4b25d66c913d66cd`。[回读证据](../../output/pond-reflection-2026-09-29/feishu-delivery/messages-readback.json)。本次仅发图片与视频，没有发送 APK 或发给其他收件人。

复现单个控制画面（把 `sun-off` 换为 `env-off`、`flat`、`env-rotate`、`sun-rotate`、`view-turn`）：

```sh
POND_ADB_PORT=5054 tools/dev/pond_art_godot.sh \
  --path output/pond-reference-2026-09-29/project --resolution 1280x800 \
  -- --capture --shot=reference --probe=sun-off \
  --out=res://../../pond-reflection-2026-09-29/review
```
