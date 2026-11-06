# 通用海面 / 湖面背景材质 · SGODOT-432

刘备。从恶魔岛已验收的海面算法提取；原恶魔岛目录不变。`bay.tres` 是蓝色海湾，`lake.tres` 是波纹更宽、更慢的蓝绿色湖面。复制预设到新地标，只改 `.tres` 参数即可。此目录没有运行脚本、模型、导航或 layout。

## 套用

1. 使用单 surface、朝上的 XZ 平面，Y 朝上、单位米。覆盖镜头可见范围；审阅用 512 × 512 m 的 `PlaneMesh`。
2. 将预设分配到平面的 `material_override`，关闭平面投影。模型 UV 不参与着色，波纹取世界 XZ，调整模型缩放不会改变波长。
3. 海面与 426 岸石的水位对齐；430 浪花仍为独立单层。审阅水位 Y=0.20 m、浪花 Y=0.218 m，材质优先级分别为 0 / 1；新地标按自己的水位同步平移。不要在已有水面上再叠一个本材质平面。
4. 426 岸石的湿带仍在岸石本身上着色。本材质不读岸线、不产生湿带，也不需要额外透明层。
5. 按新镜头调整 `far_fade_screen_y`。默认预设向 `far_color` 渐隐且 alpha=1，无需另放远海底板。若宿主已有独立远景，可选 `reveal_far_background=true`；复现原恶魔岛模式时另设 `far_color_amount=0`、渐隐范围 `(0.12, 0.24)`。

```gdscript
var water := MeshInstance3D.new()
var plane := PlaneMesh.new()
plane.size = Vector2(512, 512)
water.mesh = plane
water.material_override = preload("res://assets/landmarks/_shared/sea_backdrop/bay.tres")
water.position.y = 0.20
water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
add_child(water)
```

## 参数

颜色填 sRGB；表中为 RGB hex，颜色 alpha 不参与计算。比例与阈值建议保持下列范围。

| 参数 | 海湾 | 湖面 | 作用 / 单位 |
|---|---|---|---|
| `shallow_color` | `#439BB0` | `#6FA8A1` | 浅色档 |
| `deep_color` | `#31849F` | `#487A80` | 深色档 |
| `far_color` | `#67AFC2` | `#A7C2B6` | 屏幕远处渐隐色 |
| `ripple_wavelength_m` | 3.64 | 5.8 | 主波纹近似波长，米；> 0 |
| `color_patch_scale` | 1.0 | 1.4 | 大片底色尺寸相对原版的倍率；> 0 |
| `color_mix_range` | (0.35, 0.75) | (0.25, 0.80) | 深→浅混合权重下限 / 上限，0–1 |
| `pattern_origin` | (0, 0) | (0, 0) | 世界 XZ 图案原点，米；相邻水片保持相同值 |
| `motion_speed` | 1.0 | 0.55 | 原算法时间倍率；0 为静止 |
| `ripple_strength` | 0.018 | 0.012 | 细波亮脊增益，0–0.06 |
| `ripple_threshold` | (0.96, 1.0) | (0.95, 1.0) | 波峰软阈值，x < y；降低 x 会使亮脊变宽 |
| `far_fade_screen_y` | (0.12, 0.28) | (0.12, 0.30) | 屏幕顶部为 0、底部为 1；x 以上全远色，y 以下全水色 |
| `far_color_amount` | 1 | 1 | 远色混合强度，0–1 |
| `reveal_far_background` | false | false | true 则顶部 alpha 淡出，需宿主有完整远景 |

浅 / 深色来自风格化大色块，不是实际水深。该材质适合原项目的俯视背景镜头，不包含折射、倒影、浮漂、碰撞或岸线探测；渐隐随屏幕位置走，新镜头需调整范围。

## 开销与导入

- 与原海面相同：**0 次纹理采样、1 pass、5 次 sin**。保留原 unshaded / blend_mix / depth_draw_opaque / cull_back；只增加参数缩放与颜色插值，未新增噪声函数、深度 / 屏幕采样或额外几何。
- 保持一个海面背景层，不增加 430 浪花层数；材质没有 `next_pass`。
- 本件只有 Godot 原生 `.gdshader` / `.tres` 和 Godot 生成的 `.gdshader.uid`，没有新贴图或 GLB。因此没有 `.import`、`imported_formats` 或 `nodes/root_script` 条目需要配置。审阅借用的 426 / 430 导入设置不改。
- 冷导入、Vulkan Mobile、Android 模拟器与文件保全证据见 [审阅说明](../../../../docs/design/sea-backdrop-432/README.md)。这不是物理手机 GPU 性能结论。
