# SGODOT-401 家园徽章 Homestead Badge · C63 A · v1

制作：赵云（`8ea32e40-c0ba-4a31-864f-374a6bcbc554`）。按用户 2026-11-04 14:41 选定的 A 立柱圆章制作；参考 `concept_A.png`、HOME-2 横幅圆章，以及不知火舞 401 `a6abb6a7` / `ae5a3a42`。旧升级木牌 #746 保持 `2761ba4c` 草稿原样。本交付为独立草稿，待技术检查、画面验收和报批。

## 交付与预算

| 项目 | 实测 / 口径 |
| --- | --- |
| 运行时模型 | `assets/farm/art/homestead_badge.glb` |
| Godot UID | `uid://b56qpo5b7x0fp`（实际 --import 生成） |
| 四档文件总三角面 | **896**：公共底座 144 + 四档各 188 |
| 显示一档 | **332 三角面、2 个可见 surface**：底座 + 当前圆章 |
| 文件内存储 | **5 个 mesh / 5 个 surface、1 个材质**；三个档位隐藏，不把隐藏成本从总面数中扣掉 |
| 材质 | 农场线性顶点色；roughness 0.9 / metallic 0 / specular 0.18；无纹理、无骨骼 |
| 圆章 | Ø0.80 m；空白面 Ø0.65 m；中心 Y=1.00 m；X=-25° |
| 底座与木桩 | 五块低面石头组成约 Ø0.50 m 的脚座，木桩高 0.60 m；原点为石座底部中心 |
| 全模型 AABB | X -0.400～0.400；Y 0～1.379005；Z -0.236869～0.211527 m |
| 导入 | `texture_map_mode=1`、`light_baking=1`；禁用 LOD / shadow mesh；独立导入钩子转换挂点并设置默认木档 |
| manifest | 只在末尾追加 `homestead_badge`，已有条目及顺序不变 |

`≤2 surface` 按指定的“运行时只显示一个档位”统计；GLB 内四档备用数据有 5 个存储 surface，已在 manifest 和验证报告显式分别记录。数字及 Lv 的 Label3D 由程序创建，不计入模型的 mesh 预算。

木桩沿用 #746 单柱的建造方式并改尺寸；#746 实际没有石座，本次石座按 A 图新做。生成器、可编辑命名部件 `.blend`、逐节点 provenance / 色板在 `tools/art/source/homestead_badge_401/`。四档空白圆章在 `.blend` 中并排便于编辑，导出时恢复到同一挂载原点。

## 程序接入契约

请实例化整个 PackedScene，保留层级；`FarmArt.instance()` 只抽取 mesh 的路径不适用。在 `BadgeFace` 下的 `Tier_wood` / `Tier_bronze` / `Tier_silver` / `Tier_gold` 四选一，默认导入后仅 wood 显示。等级区间为 2–4 / 5–9 / 10–14 / 15–17；低于 2 的显隐由现有家园逻辑处理。

| 档位 | 外圈 sRGB | 空白面 sRGB |
| --- | --- | --- |
| wood | `#AA713D` | `#F6E6CB` |
| bronze | `#D68A47` | `#F9E8CC` |
| silver | `#ABB3BC` | `#F9F8F3` |
| gold | `#D9AC36` | `#F0D45A` |

`BadgeNumber` 和 `BadgeLv` 是真正的 Marker3D，均位于 `BadgeFace` 下，随其后仰 25°。局部位置分别为 `(0,0,0.055)` 与 `(0,0.238,0.055)`；空白面在局部 Z=0.052，两挂点均向外 3 mm。`BadgeNumber` 位于面底中心。根节点保持 Y 上、+Z 正面；放在农场 `_plaque` / `PLAQUE_CELL (7,14)` 时，根节点 Y 转 14.5°。

实拍文字参数：`res://assets/ui/fonts/nunito_w800.tres`（Nunito ExtraBold）、`pixel_size=.002`、数字字号 223（cap 目标约 0.315 m）、Lv 字号 57、颜色 `#3B2F25`、`outline_size=0`、`shaded=false`、`double_sided=false`、不 billboard。实际墨迹在面内；Label3D AABB 含整行行距，不能用 AABB 高度代替数字 cap。

## 实渲与验证

基于 **b1 `dfe937a1`** 的隔离副本；原 P0Farm、灯光、HUD、角色、原生开场与跟随镜头。只在 `output/badge-401/project/` 临时替换占位。用独立 QA 用户目录和本地 fixture，未提交 b1 接入、碰撞、存档或场景修改。

47 项 GLB / 导入 / manifest 检查、38 项 Godot 实渲检查通过。Godot 4.7.2、Mobile / Vulkan、RTX 2060；本轮是桌面游戏实渲，不是手机性能测试。原生输入调用与 `wait:6,walk:0:-1:1.2,wait:3` 相同，走动后实测 `zoom=1`、`size=6.72 m`、俯角 43°。

- 四张 `follow_Lv3/7/10/17`：左侧完整 360×800 逻辑像素原图，右侧明确标注 ×5 的局部放大；圆章 **42.9 px**，数字实际墨迹 **16–17 px**（最终逐档值见图及 `validation-v1.json`）。字高由匹配的“隐藏数字”控制图做差测得，不把整行空白、Lv 或阴影算进去。
- `four_tiers_close`：四档并排，沿用同一个农场 World3D 与原灯光，另用 43° 近景相机；仅此道具近景隐藏玩家，避免截断的腿进入比较画面。所有远景中玩家照常显示。
- `opening_tier_comparison`：一张图并排四个完整原生开场画面，保持同一个 Lv3 fixture 和镜头，仅换徽章档位作颜色比较。开场自动放宽至约 10.927 m，字高只在跟随镜头验收。

六图不调色、不重绘资产。署名、测量标注和说明均在审阅排版层。完整资产数字、图像 SHA-256、GPU / 相机 / 挂点证据见 `validation-v1.json`，上传清单见 `media-manifest-v1.json`。

复现命令见 [源文件说明](../../../tools/art/source/homestead_badge_401/README.md)。
