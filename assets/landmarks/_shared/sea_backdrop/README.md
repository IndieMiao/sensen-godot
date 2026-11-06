# 通用海面 / 湖面背景材质 · SGODOT-432

刘备。从恶魔岛已验收的海面算法提取；原恶魔岛目录不变。`bay.tres` 是蓝色海湾，`lake.tres` 是波纹更宽、更慢、近岸青绿向外湖蓝的湖面（v1.1）。复制预设到新地标，只改 `.tres` 参数即可。此目录没有运行脚本、模型、导航或 layout。

## 套用

1. 使用单 surface、朝上的 XZ 平面，Y 朝上、单位米。覆盖镜头可见范围；审阅用 512 × 512 m 的 `PlaneMesh`。
2. 将预设分配到平面的 `material_override`，关闭平面投影。模型 UV 不参与着色，波纹取世界 XZ，调整模型缩放不会改变波长。
3. 海面与 426 岸石的水位对齐；430 浪花仍为独立单层。审阅水位 Y=0.20 m、浪花 Y=0.218 m，材质优先级分别为 0 / 1；新地标按自己的水位同步平移。不要在已有水面上再叠一个本材质平面。
4. 426 岸石的湿带仍在岸石本身上着色。本材质不读取场景岸线、不产生湿带，也不需要额外透明层。湖面通过 `.tres` 中的三段简化岸线控制浅水色。
5. 按新镜头调整 `far_fade_screen_y`。海湾预设向 `far_color` 渐隐，湖面 v1.1 关闭远色覆盖；两者均 alpha=1，无需另放远海底板。若宿主已有独立远景，可选 `reveal_far_background=true`；复现原恶魔岛模式时另设 `far_color_amount=0`、渐隐范围 `(0.12, 0.24)`。

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
| `shallow_color` | `#439BB0` | `#54D5CD` | 浅色档 |
| `deep_color` | `#31849F` | `#147DA1` | 深色档 |
| `far_color` | `#67AFC2` | `#147DA1` | 屏幕远处渐隐色 |
| `ripple_wavelength_m` | 3.64 | 5.8 | 主波纹近似波长，米；> 0 |
| `color_patch_scale` | 1.0 | 1.4 | 大片底色尺寸相对原版的倍率；> 0 |
| `color_mix_range` | (0.35, 0.75) | (0.12, 0.27) | 深→浅混合权重下限 / 上限，0–1 |
| `pattern_origin` | (0, 0) | (0, 0) | 世界 XZ 图案原点，米；相邻水片保持相同值 |
| `motion_speed` | 1.0 | 0.55 | 原算法时间倍率；0 为静止 |
| `ripple_strength` | 0.018 | 0.012 | 细波亮脊增益，0–0.06 |
| `ripple_threshold` | (0.96, 1.0) | (0.95, 1.0) | 波峰软阈值，x < y；降低 x 会使亮脊变宽 |
| `far_fade_screen_y` | (0.12, 0.28) | (0.00, 0.08) | 屏幕顶部为 0、底部为 1；x 以上全远色，y 以下全水色 |
| `far_color_amount` | 1 | 0 | 远色混合强度，0–1 |
| `reveal_far_background` | false | false | true 则顶部 alpha 淡出，需宿主有完整远景 |

| `shore_shallows_strength` | 0（默认） | 0.9 | 简化岸线附近向浅色混合的强度；0 时跳过整段距离运算 |
| `shore_depth_range_m` | (0.25, 4.0)（未启用） | (0.25, 4.0) | 离岸 0.25 m 内最浅，至 4 m 完成过渡；按距离平方平滑插值 |
| `shore_segment_a/b/c` | 未启用 | 见 `lake.tres` | 每个 vec4 为 `(起点世界 X, Z, 终点世界 X, Z)`，米；重复段可退化成一条直岸 |

### 湖面 v1.1 近岸渐变

三个线段是美术填写的岸线近似，不是场景深度探测。当前值对应审阅夹具：局部点 `(-3.2,4.5) → (0.5,4.5) → (0.5,0.5) → (5.2,0.5)`，绕 Y 转 65° 后写入 `.tres` 世界 XZ。换地标只需改三个线段端点及过渡距离；无需改 shader、模型或 UV。若海岸更复杂，应选能覆盖主要镜头的简化岸线，或将强度设为 0 保留原大色块模式。`pattern_origin` 仅移动波纹，不移动岸线；岸线和水体移位时按世界位置更新端点。

湖面浅色 `#54D5CD`，深色 `#147DA1`；深浅混合范围 `(0.12,0.27)`，近岸强度 `0.9`。`far_color_amount=0` 去掉原顶部灰绿雾带；`far_color` 同深水色，`far_fade_screen_y=(0,0.08)` 作为未启用的预留值。波纹尺度、速度、强度均不变。海湾 `.tres` 字节不变，新增功能默认关闭，两个时间点完整画面对照差为 0。

浅 / 深色为风格化浅水观感，不是真实水深或透视水底。该材质适合原项目的俯视背景镜头，不包含折射、倒影、浮漂、碰撞或岸线探测；渐隐随屏幕位置走，新镜头需调整范围。

## 开销与导入

- 与原海面相同：**0 次纹理采样、1 pass、5 次 sin**。保留原 unshaded / blend_mix / depth_draw_opaque / cull_back；v1.1 湖面增加三段解析距离的点积 / clamp / 平滑插值，使用平方距离避免开方；海湾通过统一参数分支跳过。未新增噪声函数、深度 / 屏幕采样或额外几何。此处保证采样 / pass / 层数预算，不声称 ALU 或实体手机 GPU 耗时完全相同。
- 保持一个海面背景层，不增加 430 浪花层数；材质没有 `next_pass`。
- 本件只有 Godot 原生 `.gdshader` / `.tres` 和 Godot 生成的 `.gdshader.uid`，没有新贴图或 GLB。因此没有 `.import`、`imported_formats` 或 `nodes/root_script` 条目需要配置。审阅借用的 426 / 430 导入设置不改。
- 冷导入、Vulkan Mobile、Android 模拟器与文件保全证据见 [审阅说明](../../../../docs/design/sea-backdrop-432/README.md)。这不是物理手机 GPU 性能结论。
