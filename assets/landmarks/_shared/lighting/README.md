# 通用室外光照预设 · SGODOT-437

【刘备】三个 `.tres` 同时携带一个原生 `Environment` 和一盏主光的颜色、角度、强度。`lighting_rig.tscn` 是可实例化的小场景片段；切换其 `preset` 即可切换光照。没有贴图、模型、天空辐照贴图或逐帧脚本。

## 挂接

新场景实例化 `lighting_rig.tscn`，在根节点的 `preset` 中选择 `warm_noon.tres`、`cool_morning.tres` 或 `golden_dusk.tres`。片段含一个 WorldEnvironment 和一个 DirectionalLight3D；保持根变换为单位变换，`top_level=true` 避免宿主旋转改变主光方向。场景中只保留这一套环境和主光。

已有环境 / 主光的宿主可以直接套预设，保留原有节点和全部阴影设置：

```gdscript
const LightingPreset = preload("res://assets/landmarks/_shared/lighting/cool_morning.tres")

func _ready() -> void:
    LightingPreset.apply_to($WorldEnvironment, $Sun)
```

`apply_to` 只替换 Environment 的独立副本和主光颜色 / 强度 / 局部欧拉角；不触碰阴影、投影分组、可见性或节点数量。宿主与多个实例不会共用可变的 Environment。自定义地标时复制一份 `.tres`，修改其 Environment 子资源及 sun 字段，无需改脚本。运行时切换片段的 `preset` 会立即应用；直接修改当前资源字段后调用片段的 `apply_preset()`，或重新载入场景。

## 参数表

颜色为 sRGB；X 为负俯角、Y 为 Godot 绕 Y 角度，单位度。灯光节点沿本地 −Z 照射。

| 参数 | 暖午 `warm_noon` | 清晨 `cool_morning` | 黄昏 `golden_dusk` |
|---|---|---|---|
| 背景模式 | BG_COLOR | BG_COLOR | BG_COLOR |
| 背景色 | `#D000D0`，原版诊断色，见下文 | `#D9E6EF` | `#EDCEB3` |
| 环境光源 | AMBIENT_SOURCE_COLOR | 同左 | 同左 |
| 环境光色 | `#D5E4EE` | `#B7CDDF` | `#B7B5CA` |
| 环境光强度 | 0.72 | 0.64 | 0.58 |
| `sun_color` | RGB (1, 0.965, 0.88)，约 `#FFF6E0` | `#D7E8FF` | `#FFC58A` |
| `sun_energy` | 0.98 | 0.84 | 1.10 |
| `sun_rotation_degrees` | (−56, −34, 0) | (−24, 65, 0) | (−18, −115, 0) |
| 平地影长 / 物高，几何近似 | 0.67 | 2.25 | 3.08 |
| 普通雾 / 体积雾 | 均关闭 | 均关闭 | 均关闭 |
| 雾色，关闭时不参与绘制 | Godot 原默认值 | `#B1CADB` | `#D9AE8F` |
| SSAO / SSR / SDFGI / Glow | 全部关闭 | 全部关闭 | 全部关闭 |

暖午严格等于分支基线 `4e2c401ac` 的恶魔岛设置。该场景的 `background_color=#D000D0` 是用于检查海面漏底的诊断洋红，正常画面被背景水面完全遮住。示例同样有完整背景水面；没有背景覆盖的室外 POI 应在复制的 `.tres` 中指定正式背景色，例如格里菲斯现用的 `#E3EBE8`。这项差异没有偷偷写回暖午预设或原地标。

雾字段作为 Environment 参数保留，但三套交付预设均保持原场景的关雾状态，以维持原有着色成本。432 海面与 434 远景卡片是 `unshaded`，不会随主光自动换色；本套只改变受光物体，不修改这些已验收材质。

## 阴影与预算

场景片段沿用恶魔岛：一盏开启阴影的主光、`SHADOW_ORTHOGONAL` 单级、max_distance=120、opacity=0.48、bias=0.035、normal_bias=0.28；其余属性保持原默认。项目维持现用的 2048 方向光阴影贴图和 filter quality=2，本套不改 ProjectSettings。

格里菲斯与恶魔岛的阴影参数并不完全相同：它使用 max_distance=0、fade_start=1、pancake_size=4、blur=1.8。对已有格里菲斯式节点调用 `apply_to` 时，这些值逐项保留；三个 `.tres` 不携带或覆盖阴影参数。原两处地标文件均未改。

同一示例海岸比较原设置及三套预设：灯光、环境、绘制数量一致，无新 pass、采样或高开销效果，无 `_process` / `_physics_process`。预设切换时才复制 Environment。Deck / Vulkan Mobile 的交替采样及 Android 切换证据见审阅目录；这不是实体手机帧时间承诺。

原生 `.gd` / `.tres` / `.tscn` 无新 GLB 或贴图，`.import`、`nodes/root_script`、纹理压缩格式不适用。两个 `.gd.uid` 由 Godot 生成并保留。

[审阅与验证](../../../../docs/design/lighting-437/README.md) · [复现步骤](../../../../tools/art/source/lighting_437/README.md)
