# SGODOT-355 岩甲虫灰模 G0

赵云，2026-11-02。按上官婉儿派活和已批准的 `beetle_v3.png` 制作，交灰模技术检查与程序接口试接。正式版仍按 11-09 交付，本次不代表正式画面验收；不开运行时或美术 PR，不改 355 卡状态。

## 交付

- 运行时共享分支：`art/monsters-355`，从 farm-dev `0beeca15` 开工，只增加 `assets/monsters/mob_rock_beetle/`。
- 运行时三个文件：`mob_rock_beetle.glb`、同名 JSON、GLB 的 `.import`。
- 基础软陶材质实测 roughness=0.78、Godot specular=0.5，复用黄忠在共享分支 `b3a4f713` 提供的 `assets/monsters/material_import.gd` 启用顶点色和关闭真实投影，不改该共享脚本。没有额外贴图、材质文件或 surface。
- 美术源分支：`wp-3d-scene-zhaoyun-monsters-355`。Blender、生成/验证/拍摄脚本及实际参考图在 `tools/art/source/monsters/mob_rock_beetle/`；正式版再开审阅 PR。
- 参考和规格：`~/incoming/monsters-355/dispatch-zhaoyun.txt`、`dispatch-common.md`、3D 计划第 6 节；Plane 355 `c368e7dd` 和 `bb7ad32e`。本目录图片均为 Godot 实渲。

## 模型接口

1474 三角形，1 个 mesh、1 个 surface、11 根骨骼。米制、Y 向上、+Z 正面，根骨头 `root` 在脚底中心。实际含脚外包围盒约 **1.041 × 0.704 × 0.433 m**（宽×深×高），横向为普通史莱姆直径 0.8 m 的 **1.30 倍**；碰撞半径 0.45 m，脚端少量超出壳体碰撞范围。JSON 的 height=0.4334 与顶点测量一致。

骨骼为 root、body、head、ant_l/r、leg_l_1..3、leg_r_1..3。独角随 head，六条腿各整块绑一根骨头，网格本身带膝部弯折；每个顶点严格只有一个 1.0 权重。六腿按交替三足步态摆动。

顶点色提供棕壳、橙边、黑眼、高光和粉色腮红；UV2.x 为 1 的壳/躯体/腿可染，脸、眼、腮红、独角及橙边为 0。变体由程序材质按 UV2.x 处理，QA 已用仅改材质参数的覆盖 shader 验证身体换色、眼睛不变。模型的真实投影在 .import 节点配置里关闭，矿层比较沿用程序的 BlobShadow 假影。

## 动作

| 名称 | 秒 | 循环 | 用途 |
|---|---:|---|---|
| idle | 1.60 | 是 | 身体轻晃、触角微动 |
| move | 0.80 | 是 | 交替三足摆动 |
| windup | 0.60 | 否 | 降低身体、前腿刨地蓄力 |
| attack | 0.40 | 否 | 原地冲撞姿势，hit_at=0.18 |
| recover | 0.50 | 否 | 从压低姿势恢复 |
| hit | 0.25 | 否 | 身体与头部顿挫 |
| die | 0.80 | 否 | 翻倒，结束姿势保持 |
| stunned | 1.00 | 是 | 身体下沉、触角耷拉、头左右晃 |

全部原地，不带根运动。冲撞位移、击退、受击闪白和硬直总时长归程序；stunned 循环由程序持续 2 秒。动作名称、骨架和这些时长作为正式版接口保持。按 11-02 最新接口，受击点用 `hit_point=[0,0.27,0.05]`，顶层 `durations` 给出全部 8 个动作秒数，顶层 `hit_at=0.18`；旧 `hurt_point` 已移除。`anims` 仅保留作审阅说明，客户端循环按动作名决定。

## 验证与审阅

- 独立 GLB 检查 36 项通过：面数、surface、11 骨、单位权重、UV2、法线、无位图、脚底及尺寸、客户端字段及 8 动作时长、root 静止、循环首尾一致。
- Godot Mobile / Vulkan / RTX 2060 实渲检查 76 项通过：实际 Skeleton3D 与 AnimationPlayer、逐动作骨骼变化、根不动、循环、UID、共享导入修正、客户端字段、关闭投影及图片输出。
- 换色与 stunned 四相位的实际像素检查见 `validation-graybox.json`，不是仅检查动画名称存在。
- 图片为三视图、8 动作关键帧及 stunned 四相位拼图、360×800 与 720×1600 矿层比大小图；前缀 `SGODOT-355_mob_rock_beetle_graybox_`。
- 矿层图使用未改动的 farm-dev MineArt 第 3 层、MineCombat 普通史莱姆及实际 Avatar，43°、6.72 m；是静态艺术比较工位，不是战斗 AI 接入或玩家实操证明。
- 完整工程复制到 output 隔离工位，使用独立用户目录和 localhost:9 网络地址。正式运行时工位只写岩甲虫目录；未动生产账号/存档、未做 Android/手机性能或上线验收。

灰模先交比例和接口，正式版继续处理设定轮廓、腿与关节的玩具感、面部及矿层颜色细化；保持骨架和动作接口。

## 复现

工具：Blender 5.2.2、Godot 4.7.2；Python NumPy / Pillow。每次开 Godot 先加载私有 ADB 5099 环境，渲染前查看 nvidia-smi，完成后只关自己的 PID。

```bash
source ~/.codex-zhaoyun/env.sh
BEETLE_RUNTIME=/absolute/path/to/private/farm-dev-checkout
BEETLE_SOURCE="$PWD/tools/art/source/monsters/mob_rock_beetle"
blender --background --factory-startup --threads 2 --python "$BEETLE_SOURCE/build.py" -- --runtime "$BEETLE_RUNTIME"
python3 "$BEETLE_SOURCE/prepare.py" --runtime "$BEETLE_RUNTIME"
godot --headless --path output/rock-beetle-355/project --editor --import
godot --headless --path output/rock-beetle-355/project --script res://configure.gd
godot --headless --path output/rock-beetle-355/project --editor --import
nvidia-smi
godot --path output/rock-beetle-355/project --display-driver wayland --rendering-method mobile --rendering-driver vulkan --max-fps 30
cp output/rock-beetle-355/project/assets/monsters/mob_rock_beetle/*.import "$BEETLE_RUNTIME/assets/monsters/mob_rock_beetle/"
output/art-setup/venv/bin/python "$BEETLE_SOURCE/verify.py" --runtime "$BEETLE_RUNTIME"
output/art-setup/venv/bin/python "$BEETLE_SOURCE/package.py" --runtime "$BEETLE_RUNTIME"
```

生成器保留具名施工部件和单 mesh 导出副本；在 Blender 中取消隐藏施工部件可分别编辑。手工编辑需同步生成脚本，避免重建覆盖。共享运行时分支推送前 fetch，保留黄忠目录，只做可快进推送。
