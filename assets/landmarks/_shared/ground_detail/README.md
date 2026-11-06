# 通用地表细节材质 · SGODOT-428 · 刘备

从已审 #827 v1.1 整理，独立于恶魔岛。五种哑光地表：三色草坡、浅色铺石、木纹、干沙、湿沙／潮线。运行资源只依赖本目录，模型无需 UV；单位为米，Y 朝上。颜色、识别键、尺度和投影全部通过 ShaderMaterial `.tres` 调整。

## 套到新地标

1. 复制本目录的一份 `.tres` 到新地标自己的目录，保留共享 shader 和两张贴图引用。不要修改共享预设来改变单个地标。
2. 单一地面用 `ground_grass / paving / wood / sand / wet_sand.tres`，`finish_kind=1…5` 强制类型，不要求顶点色键。混合地形用 `ground_palette_example.tres`，`finish_kind=0` 按 COLOR_0 识别；未识别的顶点色直接保留。示例潮线在 Z=6.7m，实际项目要改。
3. 用 `MeshInstance3D.material_override` 或对应 surface override 套材质，不改模型和 UV。默认只覆盖接近朝上的面。山坡需要时把 `top_normal_range` 改为如 `(0.55,0.85)`；竖直石壁仍可保留原色。
4. 导入 glTF 的 COLOR_0 为线性 RGB。Inspector 的 `*_key` 色值按原作者 **sRGB 色板**填，`source_color` 自动转线性；不要把新显示色填进识别键。程序创建网格时，COLOR 要用 `Color(hex).srgb_to_linear()`。相邻类别请用分开的面顶点，避免插值产生模糊分类带。
5. 输出配色用 `*_color`；识别容差 `palette_tolerance` 是线性 RGB 欧氏距离，不是百分比。键应互相隔开超过两倍容差；若相撞，优先级为草→石→木→沙→湿沙。
6. 世界投影适合连续地形；物体投影适合移动或旋转的码头模块。木纹预设默认物体投影。物体坐标的尺度受节点缩放影响，建议应用缩放或在 `.tres` 补偿。投影先减 `mapping_origin_m`，再旋转；所有 repeat 和潮线在这个 XZ 平面中计算。
7. 湿沙 `tide_enabled=false` 得到整片湿沙；开启时沿 `tide_direction` 从干过渡到湿，并带低对比沉积线。方向必须非零。该材质只画地面，不生成水面或浪花，不依赖任何水材质。弯曲海岸可由分段地表的独立 `.tres` 配置方向／位置；没有沿任意岸线自动投影的功能。
8. 若只要某个局部高度的顶面，开启 `height_filter_enabled` 并设置 `local_height_range_m`。普通地形不要照搬旧码头的 Y≈0 筛选。检查默认镜头、暖光和目标设备实渲后再套用。

## 预算与贴图

| 贴图（1024² RGB，线性数据） | R | G | B |
|---|---|---|---|
| `ground_fields.png` | 周期大色块＋碎边 | 短叶细纹 | 沙粒／矿物细纹 |
| `ground_surfaces.png` | 石板缝 | 石板明暗 | 木纹 |

两张图与 #827 的原图逐字节相同；新增沙材质启用原先预留的 B 通道。草3次采样，铺石1次，木1次，干沙／湿沙各2次，不匹配0次；最大仍3次，2个 sampler，单不透明pass，无额外法线、屏幕、深度、TIME 或水贴图采样。材质切换分支按面保持一致。次级宏观场与细节频率错开，减弱明显平铺。

PNG 导入由 Godot 4.7.2 生成 UID，mipmap + 高质量 VRAM 压缩（桌面BPTC / Android ASTC）。完整 mip 链两张压缩图约2.67MiB纹理块数据；源PNG大小不代表显存。Godot实际格式以目标设备为准。`.gdshader.uid` 同样由编辑器生成。

本交付没有 GLB、FBX 或 Blender 场景导入。`nodes/root_script=null` 是场景导入参数，PNG 的 texture importer 不适用，也不伪加这一字段。测试地形由隔离 QA 脚本构造，不进入游戏／layout。冷导入记录见审阅资料。

## 参数表

下表默认值来自共享 shader；各 `.tres` 可以覆盖任意一项。颜色均为 sRGB HEX（仅容差与运行时 COLOR 运算在线性空间）。参数不能置为反序范围：`*_transition.x < .y`；尺寸和宽度取正值，比例混合限制0…1。

| 参数 | 默认值 | 用途 |
|---|---|---|
| `fields` | `绑定对应PNG` | 共享宏观／叶／沙粒数据贴图 |
| `surfaces` | `绑定对应PNG` | 共享铺石／木纹数据贴图 |
| `finish_kind` | `0` | 0识别顶点色；1草、2铺石、3木、4沙、5湿沙 |
| `strength` | `1.0` | 效果权重；0精确恢复原顶点颜色 |
| `palette_tolerance` | `0.012` | 识别键的线性RGB距离容差 |
| `grass_key` | `#86A84F` | 原模型识别色（与输出色独立） |
| `grass_dark_key` | `#759448` | 原模型识别色（与输出色独立） |
| `grass_light_key` | `#9AB55D` | 原模型识别色（与输出色独立） |
| `paving_key` | `#DFCBA7` | 原模型识别色（与输出色独立） |
| `wood_key` | `#BB8B52` | 原模型识别色（与输出色独立） |
| `wood_light_key` | `#D0A56C` | 原模型识别色（与输出色独立） |
| `wood_dark_key` | `#9A7046` | 原模型识别色（与输出色独立） |
| `sand_key` | `#D4C096` | 原模型识别色（与输出色独立） |
| `wet_sand_key` | `#9B8F70` | 原模型识别色（与输出色独立） |
| `coordinate_space` | `0` | 0世界XZ；1物体XZ |
| `mapping_origin_m` | `vec2(0.0)` | 投影原点（XZ米） |
| `mapping_rotation_degrees` | `0.0` | 投影旋转角度 |
| `top_normal_range` | `vec2(0.80, 0.98)` | 朝上程度由无覆盖到全覆盖的阈值 |
| `height_filter_enabled` | `false` | 是否启用物体局部Y筛选 |
| `local_height_range_m` | `vec2(-0.015, 0.015)` | 保留细节的物体局部Y范围，米 |
| `grass_deep_color` | `#527E35` | 地表输出色 |
| `grass_base_color` | `#78A044` | 地表输出色 |
| `grass_sun_color` | `#A2B95D` | 地表输出色 |
| `grass_patch_repeat_m` | `24.0` | 宏观场重复长度；默认形成数米大块 |
| `grass_secondary_ratio` | `1.618` | 第二宏观场相对长度 |
| `grass_secondary_offset_m` | `vec2(11.7, -4.3)` | 第二场交换XZ后的偏移（米） |
| `grass_secondary_mix` | `0.20` | 第二宏观场混合权重 |
| `grass_deep_transition` | `vec2(0.41, 0.46)` | 深→普通的场值区间 |
| `grass_sun_transition` | `vec2(0.54, 0.60)` | 普通→日晒的场值区间 |
| `grass_detail_repeat_m` | `2.0` | 短叶纹重复长度（米） |
| `grass_detail_strength` | `0.13` | 短叶纹明暗幅度 |
| `paving_color` | `#DFCBA7` | 地表输出色 |
| `paving_repeat_m` | `vec2(4.0, 4.0)` | 整张石纹XZ重复长度，4×4米时每块1×0.5米 |
| `paving_joint_strength` | `0.16` | 石板缝减暗幅度，沿用#827 |
| `paving_tone_strength` | `0.10` | 板间明暗幅度，沿用#827 |
| `wood_color` | `#BB8B52` | 地表输出色 |
| `wood_light_color` | `#D0A56C` | 地表输出色 |
| `wood_dark_color` | `#9A7046` | 地表输出色 |
| `wood_repeat_m` | `vec2(3.0, 1.0)` | 木纹XZ重复长度，沿投影X方向延伸 |
| `wood_grain_strength` | `0.32` | 木纹明暗幅度，沿用#827 |
| `sand_color` | `#D4C096` | 地表输出色 |
| `wet_sand_color` | `#9B8F70` | 地表输出色 |
| `tide_color` | `#817C63` | 地表输出色 |
| `sand_macro_repeat_m` | `12.0` | 沙地缓慢起伏的色场重复长度（米） |
| `sand_detail_repeat_m` | `1.5` | 沙粒纹重复长度（米） |
| `sand_macro_strength` | `0.10` | 沙地大范围明暗幅度 |
| `sand_grain_strength` | `0.10` | 沙粒细纹幅度 |
| `tide_enabled` | `true` | false整片湿沙；true位置控制干湿过渡 |
| `tide_direction` | `vec2(0.0, 1.0)` | 投影平面中干→湿方向，运行时归一化 |
| `tide_position_m` | `0.0` | 潮线沿该方向离投影原点的有符号距离（米） |
| `tide_transition_m` | `0.45` | 干湿柔边总宽度（米） |
| `tide_breakup_m` | `0.35` | 用现有宏观采样打碎潮线的偏移幅度（米） |
| `tide_band_offset_m` | `0.35` | 沉积细带向湿侧偏移（米） |
| `tide_band_width_m` | `0.14` | 细带半宽（米） |
| `tide_band_strength` | `0.28` | 沉积色混入幅度 |
| `surface_roughness` | `0.94` | 干地面粗糙度 |
| `wet_roughness` | `0.86` | 完全湿沙粗糙度；维持哑光 |
| `surface_specular` | `0.15` | 高光权重 |

## 重建与审阅

源：`tools/art/source/ground_detail_428/`（NumPy / SciPy / Pillow）。`generate.py` 仅重建本目录两张PNG，确定性种子保留。`prepare.py` 把本目录和QA脚本放到 `output/ground-detail-428/project`；后者独立于主游戏。暖光与#827相同；默认相机宽6.72m、俯角43°、偏航14.5°。详见 `docs/design/ground-detail-428/README.md` 的原始截图、测量与冷导入证据。
