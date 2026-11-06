# SGODOT-426 · 海岸套件 v1.1

【赵云】按上官婉儿 `a11fd3a9` 与不知火舞 `2c540f46` 的五项意见完成。运行时修改收在 `assets/landmarks/_shared/coast_kit/`，同步本套件的源、导入 / 验证脚本和审阅材料。恶魔岛所有文件未改，示例不交 layout、不进入游戏。

| 项目 | v1.1 结果 |
|---|---|
| 木板 | 每段 11 块，实宽 0.172–0.177 m；1 cm 板缝有内收深色垫板，板缝不穿透到水面。低饱和暖木褐，小幅深浅变化 |
| 木桩 | 每段四角各一根 0.16 m 细方桩；桩位在段内，拼接不重复叠桩 |
| 护岸墙 | 中段 0.84 m 宽出挑压顶；Y=0.3 / 0.6 / 0.9 m 三道凹缝；两端原截面及顶高 1.2 m 保留 |
| 岸石色板 | 暖沙 / 冷灰褐，通过一个 `rock_palette` 参数切换；九件岩石共用原网格，无复制 GLB、无贴图、无新增 pass |
| 水线 | 岸石、散石、护岸墙和码头按世界水位形成向上渐淡 0.25 m 的湿带；已与 #824 原浪花叠用验证 |

冷灰褐基准为 #801 v3 的 `#777A75 / #93958B / #515B59`，默认图采用此套。九件岩石的 POSITION / NORMAL / 索引保持 v1，浮标、下水台阶 GLB 保持原字节。所有旧端口契约保持不变。

15 件共 **2,652 面**，每件 **96–384 面 / 1 surface**。护岸墙 156 面；码头直段 / 尽头 / 系缆桩段分别 240 / 340 / 384 面。其余面数不变。

## 审阅图

- [catalog](SGODOT-426_COAST_v1.1_catalog.png)：九种岩石每种均展示暖沙 / 冷灰褐，均为同一个 GLB；六种其他件各一格。主件 43°、相同尺度和 1.75 m 人物；下方补护岸墙与木桩的 25° 近景，示意水位 Y=0。
- [default_360x800](SGODOT-426_COAST_v1.1_default_360x800.png)：原默认 43° / yaw 14.5° / 6.72 m 镜头、原 360×800 尺寸，冷灰岸石、木褐窄板、湿带以及 #824 浪花叠用。水面 Y=0.15，浪花 Y=0.168。

PNG 只有拼版和署名，未调色、未缩放模型，长边均 ≤1600。目录中的报告包含其他内部检查帧；本轮交两张上述审阅图。

## 材质接入

完整拼法和参数见[套件 README](../../../../assets/landmarks/_shared/coast_kit/README.md)。新增两份 ShaderMaterial 预设及一个共享 shader；`rock_palette=0` 暖沙，`1` 冷灰褐。`water_level` 按世界水面 Y 设置，`wet_height=0.25`，`wet_strength=0.38`。

13 个需要换色 / 湿带的 GLB 由本包 EditorScenePostImport 脚本绑定材质到 Mesh surface，提取 Mesh 用于 MultiMesh 时仍保留。接入方保留导入材质，或使用本包材质覆写；顶点 RGB 是线性画色，COLOR.a 作为不透明面类型标签。shader 不写 ALPHA，不读纹理，没有 next_pass。

#824 的浪花仅在隔离审阅工程中引用原件 / 原透明材质，关闭投影；本包没有复制或修改这些浪花、水面材质或贴图。现有透明层可以叠在本包不透明湿带之上。来源文件 SHA 见 [foam-reference.json](foam-reference.json)。

## 验证

- [几何 / 接口](asset-validation.json)：340 项通过。实际网格验证 11 块窄板、1 cm 缝、四角桩、三道墙缝、原端口、九件岩石几何不变与浮标 / 台阶字节不变。43 组 out→in 配对的实际导出端点最大错位为 0；另核对两种码头与台阶走面接边。
- 木板顶面平均 HSV 饱和度由 v1 的 **0.5393 → 0.3577**，约降低 34%。
- [材质 GPU 探针](material-validation.json)：13 项通过。同一 mesh / material 只改参数完成换色；冷灰基准与原生 StandardMaterial 的 #777A75 参考在该控制视口误差 **0/255**。水位升高 20 cm，湿带移动 20 px（探针 1 cm/px）；平移模型和 MultiMesh 实例仍对齐世界水位。换色 / 湿带 / MultiMesh 均为 1 draw、2 个控制三角形，没有额外 pass。
- [实渲检查](render-validation.json)：131 项通过。15 件面数 / UID / 导入材质、两套色板相同 mesh、无额外 draw、#824 材质与两批叠用、示例端口和默认镜头均核对。GPU 为 Godot 4.7.2 Vulkan Mobile / RTX 2060。

本包没有新纹理，所以没有新增纹理压缩格式问题。15 个 GLB UID 保留、`nodes/root_script=null` 齐全，shader / 导入脚本 UID 由 Godot 生成。提交后清缓存冷导入再同步，确认工作区干净；具体新头和检查结果写在 #831 交付评论。

这些是桌面渲染与资产证据，不代表物理手机 FPS。所有 Blender / Godot（含导入和探针）均使用 `flock ~/gs66-render.lock`，私有 ADB 5099，完成即退出。

## 复现

源：[coast_kit.blend](../../../../tools/art/source/coast_kit/coast_kit.blend)、[生成器](../../../../tools/art/build_coast_kit.py)、[导入工具](../../../../tools/art/source/coast_kit/imports.py)、[几何检查](../../../../tools/art/source/coast_kit/verify.py)、[GPU 材质探针](../../../../tools/art/source/coast_kit/material_probe.gd)。

```bash
source ~/.codex-zhaoyun/env.sh
nvidia-smi
flock ~/gs66-render.lock blender --background --python tools/art/build_coast_kit.py
python3 tools/art/source/coast_kit/imports.py stage
python3 tools/art/source/coast_kit/imports.py configure
python3 tools/art/source/coast_kit/imports.py cold
flock ~/gs66-render.lock godot --headless --path output/coast-kit/import-project --import
python3 tools/art/source/coast_kit/imports.py sync
python3 tools/art/source/coast_kit/verify.py
flock ~/gs66-render.lock godot --path output/coast-kit/import-project --script res://material_probe.gd --rendering-method mobile --rendering-driver vulkan --disable-vsync --max-fps 60 --quit-after 1200
```

提交后再次 `stage → cold → Godot --import → sync → git status --short`。示例装配仍只在本机 output 中，用于出图，不在本次运行时交付里。
