# 通用室外光照预设 · SGODOT-437

【刘备】暖午、清晨、黄昏各一套 `.tres`，同时携带原生 Environment、一盏主光，以及配套海面 / 远景材质。实例化 `lighting_rig.tscn`，切换 `preset` 即可同步换色。无新模型、贴图、第二盏灯或逐帧脚本。

## 挂接

1. 实例化 `lighting_rig.tscn`。根节点 `top_level=true`，避免宿主旋转改变主光方向；场景只保留一套 WorldEnvironment 和主光。
2. 将宿主已有的海面 GeometryInstance3D 填入 `sea_targets`；城市、丘陵、桥分别填入 `city_targets`、`hill_targets`、`bridge_targets`。支持 MeshInstance3D 和 MultiMeshInstance3D，可填写多个实例。使用与 432 海面 / 434 卡片一致的模型和顶点通道。无该类背景时数组留空。
3. 指定 `warm_noon.tres`、`cool_morning.tres` 或 `golden_dusk.tres`。Inspector 保存的目标在 `_ready()` 应用；若代码在 `_ready()` 后填充目标，填完调用一次 `apply_preset()`。运行时重新赋值 `preset` 会同步切换光照及所有已绑定材质。

已有环境和主光的宿主也可直接调用，保留原有阴影设置：

```gdscript
const Morning = preload("res://assets/landmarks/_shared/lighting/cool_morning.tres")

func _ready() -> void:
    Morning.apply_to($WorldEnvironment, $Sun,
        [$Sea], [$City], [$Hills], [$Bridge])
```

不传后四个参数时只应用环境和主光。空数组不创建背景模型。每次切换复制一份 Environment 和每类材质，宿主修改不会污染预设；同一宿主、同角色的所有目标共享该材质副本。保留几何、变换、阴影、可见性与节点数量。切换后直接修改资源字段需调用 `apply_preset()`。

脚本显式 preload，不注册全局类，不依赖编辑器类缓存。`preset` 为 Resource，setter 检查绑定的 `lighting_preset.gd`；误选其他资源会警告并保留有效预设。清空字段保留最后应用的光照和材质，后续可重新指定预设。

## 光照参数

颜色为 sRGB，角度为 Godot 局部欧拉角。太阳能量是节点参数；低角度照在水平面的贡献较低，不能将 energy 比值当作画面亮度比。实际同区域亮度比较见审阅资料。

| 参数 | 暖午 | 清晨 | 黄昏 |
|---|---|---|---|
| 背景模式 | BG_COLOR | BG_COLOR | BG_COLOR |
| 背景色 | `#E3EBE8` | `#C4D6E5` | `#DCA7B5` |
| 环境光源 | AMBIENT_SOURCE_COLOR | 同左 | 同左 |
| 环境光色 / 强度 | `#D5E4EE` / 0.72 | RGB (0.788132, 0.837254, 0.789618) / 0.90 | RGB (0.83, 0.795, 0.984) / 0.62 |
| 主光色 | RGB (1, 0.965, 0.88) | `#E3EFFF` | RGB (1, 0.88, 0.26) |
| 主光强度 | 0.98 | 1.10 | 1.73 |
| 主光旋转 | (−56, −34, 0) | (−24, 65, 0) | (−18, −13, 0) |
| 平地影长 / 物高，几何近似 | 0.67 | 2.25 | 3.08 |
| 普通雾 / 体积雾 | 关闭 | 关闭 | 关闭 |
| SSAO / SSR / SDFGI / Glow | 全部关闭 | 全部关闭 | 全部关闭 |

v1.3 经奕星、上官婉儿授权，仅将黄昏水平角从 −115° 调至 −13°，保留 18° 低高度角及所有阴影参数；暖午、清晨的角度不变。固定机位下人物和长椅的平地投影朝右上，详见审阅图。清晨只调整环境光颜色，草地 HSL 饱和度为暖午同区的 70.9% / 73.7%。

暖午光照及配套材质保留已验收海岸画面；共享背景使用正式色 `#E3EBE8`。恶魔岛自己的场景保留查漏底的诊断洋红，共享预设不用。恶魔岛、格里菲斯原文件未改。

## 配套材质

每套预设引用本目录的 `<时段>_sea.tres` 与 `<时段>_far.tres`。后者是 `far_material_set.gd` 资源，包含 city / hills / bridge 三个 ShaderMaterial 子资源，保留三个角色各自的配色和远景深度排序。换地标时复制这些 `.tres` 后改参数即可；不需改脚本或原套件。

海面直接引用 432 的 `sea_backdrop.gdshader`，远景直接引用 434 的 `far_card.gdshader`。原 shader 和原 `.tres` 均不修改，无新增 shader。

| 海面参数 | 暖午 | 清晨 | 黄昏 |
|---|---|---|---|
| `shallow_color` | `#439BB0` | `#72B8BF` | `#66979F` |
| `deep_color` | `#31849F` | `#498C9E` | `#3E7C93` |
| `far_color` | `#67AFC2` | `#D4E4E7` | HDR RGB (1.30, 1.12, 0.30) |
| `far_fade_screen_y` | (0.12, 0.28) | (0.06, 0.33) | (0.08, 0.43) |
| `reveal_far_background` | false | true | true |
| `ripple_strength` | 0.018 | 0.035 | 0.026 |
| `render_priority` | −100 | −100 | −100 |

海面的现有远处颜色和透明渐隐在同一 pass 中形成背景到海面的过渡。清晨露出淡蓝灰背景与冷白波纹；黄昏露出桃粉背景，HDR 暖金远处颜色经原有渐隐形成一条柔和的横向反光带，再过渡到蓝绿海面。此处为参数控制的风格化色带，不是随太阳位置计算的物理反射。没有 Glow、额外面片或反射 pass；近岸距离分支保持关闭。此渐隐使用 SCREEN_UV，改变构图时在复制的海面 `.tres` 中调范围。

远景三个子材质的 `base_color` / `accent_color` / `shadow_color` / `fog_color` / `fog_amount` 可独立调节。清晨偏淡蓝紫，黄昏为压暗的紫色城市 / 丘陵和暖紫桥。深度保留 city=0.96、hills=0.98、bridge=0.94，优先级分别 −98 / −99 / −97；雾化只混色，不增加雾或透明层。

## 阴影与预算

片段沿用恶魔岛：单盏主光、`SHADOW_ORTHOGONAL`、max_distance=120、opacity=0.48、bias=0.035、normal_bias=0.28；其他阴影默认值不变。项目保持 2048 阴影贴图和 filter quality=2。已有格里菲斯的 max_distance=0、fade_start=1、pancake_size=4、blur=1.8 通过 `apply_to` 保留，预设不覆盖这些设置。

海面和远景复用已有 shader 及其绘制节点：不增采样、pass 或透明叠层；海面的可选近岸计算仍关闭。预设切换才分配资源副本，无 `_process` / `_physics_process`。帧时间和真实 Android 切换的验证范围见审阅记录，不作实体手机保证。

17 个原生运行文件，无新模型或贴图，`.import`、`nodes/root_script`、纹理压缩条目不适用；三个 `.gd.uid` 均由 Godot 生成。

[三套并排与验证](../../../../docs/design/lighting-437/v13/README.md) · [复现步骤](../../../../tools/art/source/lighting_437/README.md)
