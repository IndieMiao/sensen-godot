# SGODOT-319 公共大厅壳 v1

赵云 · 2026-10-31。当前交付是 **公共壳先行检查稿**，供 315 / 316 / 317 / 318 四间室内共用。上官婉儿检查壳后再继续 N1 酒店家具包；本轮不代表 N1 完成或用户批准合并。

## 依据与范围

- 315 R3 主图：`reference/SGODOT-315_Hotel_Lobby_Main_2026-10-31.png`；用户批准记录 `315 9704634d`，不知火舞复核 `3a4547e9`，上官婉儿拆分 `d231c310`。
- 两面墙、无前墙和门、无墙端方柱；暖米色墙、深木护墙板与顶线、厚踢脚、两扇三列四行方格窗、蜂蜜色人字地面。窗洞真实贯通，窗框、窗格单独导出。
- 保留 `mine_hut.blend / KIT_room_shell / Honey timber foundation` 的可编辑地台和圆角，降低基底顶面；重新制作地面和墙体。墙体构造沿用 Basic Room 的米制与具名部件工具。逐件来源与改动见 `shell_reuse_provenance.json`。
- 参考配套的旧地面色 `#482D1E` 已被 315 复核意见否定。本壳以主图蜂蜜木方向 `#CB8655` 为基础，护墙板用 `#652E18`，深木保留色块 `#551B0A`；不是对旧色板深棕地面的复现。

## 尺寸与待核高度

H=1.745 m；原图未写明的高度按主图比例暂定，**以下窗、护墙板与顶线高度是建模取值，尚不是 Stark 补交的测量值**。所有坐标为 Godot 米制，Y 向上，+Z 为开放前沿。地面中心为原点。

| 项目 | 本版取值 |
|---|---|
| 地台 | 6.8 x 6.4 m；底面 -0.28，顶面 0.08 |
| 墙高 / 厚度 | 从地面起 3.70 m，顶面 Y=3.78；厚 0.20 m |
| 左墙 / 后墙轴心 | (-3.30, 0.08, 0)，yaw 90° / (0.10, 0.08, -3.10)，yaw 0° |
| 护墙板顶 | Y=1.1525，即离地约 1.073 m（约 0.615H） |
| 踢脚主条 | 从地面起 0.19 m，向内厚 0.105 m，另有 0.035 m 上缘条 |
| 顶线 | Y=3.4625 至 3.746，含主板、上阶与下沿 |
| 共用窗洞 | 宽 1.24 x 高 2.04 m；窗台 Y=1.20，即离地 1.12 m |
| 两窗中心 | 左墙 Z=-1.78、+1.78，洞口中心 Y=2.22 |
| 窗框与窗格 | 同洞口的独立件，三列四行；两窗共用一个透明玻璃 surface |
| 人字拼单块 | 0.64 x 0.16 m；原创程序化色纹，缝宽约 5 mm，无木纹照片 |
| spawn / exit | (0, 0.08, 2.50) / (0, 0.08, 2.88) |

前沿与右沿只有不可见碰撞边界。出口放在前沿挡边以内，0.25 m 半径、1.745 m 高胶囊可抵达；后续程序按出口挂点触发离开。没有 `use_*` 或 `npc_*`。酒店专用 `sign_name`、8 个座位及家具在壳检查后制作。

## 图集与 324 交接

`assets/rooms/_shared/shell_hall/hall_albedo_ao.png` 为唯一 2048² 图集，6 个壳烘焙区 + 32 个固定复用色块。`hall_palette.json` 给出色号、PNG 像素区、glTF 与 Blender UV 区、安全边、全部 16 个 324 旧语义色的目标映射；人读表在 `atlas-regions.md`。32 色 PNG 中心像素均与 JSON RGB8 逐项相等。

glTF / PNG 以左上为原点，Blender V 轴反向，表内同时给出两种坐标。色块至少保留 16 px 安全边。细件可用色块中心 UV；需保留局部纹理的件映射到安全区内。四间可沿用同一 UV 区替换颜色，并保留 AO 明暗调制。两块画心色块留给替换图案。

壳只烘自身接缝 AO，没有家具压痕或直射光；N1 摆件后的接触阴影应随家具包验证。324 的旧文件与临时图集不在本次改动内，未宣称已完成其重映射。采用 `hall_palette.json`、`shell_asset_stats.json` 等独立文件名以避免覆盖 #563 的数据。

## 预算与验证

- 6 个 GLB、8 个摆放 surface，摆放后 **12,966 三角形**，其中玻璃为单独 1 个 surface；两种材质共用一个图集。为 N1 的 150k / 50 surface 目标留出余量。
- GLB 独立检查：真实尺寸、朝向、有限 UV、逐三角形不跨色区、16 px 边界、无退化面、图集引用、每件来源、模块间交叠、窗洞射线与实体墙阳性对照。正常的墙角线脚搭接、窗框安装接触单列；无未分类穿插。
- Godot 4.7.2 / Vulkan Mobile / RTX 2060 实渲：导入面数与 surface 核对、透明材质保留、地面/墙/边界共 5 个碰撞体、floor Y=.08、出生至中央/窗边/后墙/出口胶囊扫掠，以及四边阻挡对照。完整结果在 `validation.json`。
- 每个 GLB 的 `.import` 为 `gltf/texture_map_mode=1`，PNG 开启 mipmaps 与 VRAM 压缩。可编辑 Blender 源保留 100 余个具名施工部件、局部根轴心及人字纹源图。
- 审阅只有一盏带单级阴影的太阳与暖环境光。两处窗格光斑来自真实洞口与窗格遮挡，未烘进图集。审阅正交相机 near=.1 / far=40 m；过大的远裁面会降低单级阴影精度。复用场景不携带太阳或环境光。
- 当前仅桌面资产与物理检查，无 Android 输入、真机性能、16 人并发或 P2 接入结论。按派活不做工程接入与发包。

## 审阅图

所有图片署名 `SGODOT-319 / ZHAOYUN / 赵云`，前缀 `SGODOT-319_N1_v1_`。包含空壳 43° 全景、四面正交一张、正俯视、窗框近景、图集色块表、Stark 主图与空壳阶段对照、日光开关对照。N1 的进门默认 6.72 m 取景及家具近景待壳检查后交，不把这张 11 m 空壳全景当作游戏默认镜头。

## 复现

Blender 5.2.2 LTS、Godot 4.7.2；打包脚本需要 Pillow 和 NumPy。渲染前检查共用显卡占用，Godot 使用私有 ADB 5099。`output/.gdignore` 与 Blender 源目录的 `.gdignore` 保留。

```bash
source ~/.codex-zhaoyun/env.sh
blender --background --factory-startup --python "$PWD/tools/art/build_shell_hall_319.py"
blender --background --factory-startup --python "$PWD/tools/art/verify_shell_hall_319.py"
python3 tools/art/prepare_shell_hall_319.py
godot --headless --path output/poi-hall-319/project --editor --import
nvidia-smi
godot --path output/poi-hall-319/project --display-driver wayland --rendering-method mobile --rendering-driver vulkan
output/art-setup/venv/bin/python tools/art/package_shell_hall_319.py
```

验证工程隔离在 `output/poi-hall-319/project`，不读取生产账号或存档。审阅脚本完成后自行退出；如需中止，只停止本次记录的 PID。
