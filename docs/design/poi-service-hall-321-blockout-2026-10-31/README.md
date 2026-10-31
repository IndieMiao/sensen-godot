# SGODOT-321 N2 服务大厅：三版白模

黄忠，2026-10-31。当前只提交排法评审，等待上官婉儿和不知火舞选定后再做细模。依据 316 R3 主图批准 `d0559eeb`、评估 `92dbfb6a`、复核 `3f2b4c6c`，以及 321 补充 `45617721` 和随后关于窄件的确认。

| 方案 | 座位 | 沙发 / 椅宽 | 小桌 / 植物 | 环道最窄 | 入口净宽 | 白模面 / surface |
|---|---:|---|---|---:|---:|---|
| A1 原件 | 11 | 2.806 / 1.50m | 1 / 2 | 0.73m | 1.01m | 29,354 / 30 |
| A2 窄件 | 11 | 2.30 / 1.30m | 3 / 2 | 0.73m | 1.56m | 30,218 / 32 |
| B 推荐 | 8 | 2.806 / 1.50m | 3 / 4 | 1.04m | 1.46m | 26,782 / 31 |

推荐 B：左右各一组沙发加单椅，左墙候客排布、后墙展示区和蓝色十字走道都保留，展示墙前方更清楚。若 11 座优先，A2 比 A1 更从容，但需要在源文件里重新制作窄件比例。A1 去掉两张边桌、两盆植物；A2 去掉两盆植物；B 去掉三把扶手椅。小桌均为 Ø0.60m、高 0.75m 的白模。

## 真实依赖

- 公共壳：PR #594，固定 `3aa234665681f8fe9e9acc63784c3ef65bf93ff4`。真实 6.8×6.4m、floor Y=0.08，左墙两窗、后墙、边界碰撞全部直接实例化。壳的 GLB、布局、脚本和图集不改。
- 324 件包：PR #563，固定 `104446a2a995c8a0269d12d27308b3d547b29f6e`。直接读取 GLB 顶点：沙发 2.806×1.326×0.890m，扶手椅 1.500×1.326×0.890m，原圆边桌 Ø1.10m、高 1.134m。白模按总监补充改用小桌占位。
- 盆栽：共享库 `peace_lily`，整体约 0.854×1.240×0.727m。按源盆体 Ø0.49m、高 0.39m 加碰撞，叶片不设硬碰撞。
- 上述依赖只提取到忽略的 `output/poi-service-hall-321/dependencies/` 和隔离审阅工程；当前 PR 不复制或覆盖其他草稿 PR 的公共资产。`dependency_manifest.json` 与交付 validation 记录哈希并逐项回读检查。

坐面局部高度始终 0.715m，放在公共壳 0.08m 地面后，挂点世界 Y=0.795m。每个座位均有朝向、module 和独立可达接近点。A1/A2 有 11 个座位，B 有 8 个。参考人物站立高度 1.745m。

## 白模界限

中央底座为 Ø1.86m、高 0.40m；上方雕塑以 Ø1.09m、离地顶高 1.90m 的体积占位。展示龛、宣传架、饮水机、窗下花箱和墙面图板按派活尺寸占位，尚未造型或做最终皮肤。没有服务柜台、NPC、自助机、排队绳或墙端方柱。

蓝色十字与环形区域直接由审阅用地面材质表示，原地板几何不动，没有凸起地毯。墙体和家具使用中性白模材质覆盖；最终墙、石砖、座椅色与 hall 图集重映射在排法确认后制作。

A2 仅用于排布的节点 X 缩放已获总监允许，Y/Z、座高及靠背高度不变。最终三人沙发需要把底座、背板和三片坐垫重新调比例，坐垫合计约 2.10m、座位中心为 -0.70/0/0.70m；扶手椅最终保留 0.99m 坐垫和原背板/底座，只收上扶手外缘。不能把白模压缩后的圆角、卷边和钉扣直接当细模交付。逐部件原始尺寸见 `narrowing_assessment.json`。

## 验证与图

Shapely 用实际外框检查摆放、穿插、座位接近区、环道与入口净宽；Godot 4.7.2 Vulkan Mobile 用真实壳碰撞和标准半径 0.25m、高 1.745m 胶囊复核每个座位路径、16 个分散站位和出口。主环道与入口纵向通路另用半径 0.35m 检查；靠前沿固定挡边的出口端点按标准 0.25m 胶囊验。553 项渲染/物理/尺寸检查通过，另附实际白模预算检查。

[三版对照](SGODOT-321_N2_blockout_comparison.png)、[决策表](SGODOT-321_N2_blockout_decision.md)、[完整 validation](SGODOT-321_N2_blockout_validation.json)。各版均有默认 43° / 6.72m / 360px、缩远全景和标注胶囊扫掠的正俯视图。默认图保留游戏人物比例，全景单独标注缩远。

## 复现

在自己的私有 Godot/ADB 环境中运行；黄忠端口为 5097。先看 `nvidia-smi`，所有审阅进程自动退出。依赖 Python NumPy、Pillow、Shapely；没有在线账号、存档、模拟器或发布操作。

```bash
git fetch origin refs/pull/594/head:refs/remotes/origin/pr-594 refs/pull/563/head:refs/remotes/origin/pr-563
python tools/art/source/poi_service_hall/dependencies.py
python tools/art/source/poi_service_hall/plan.py
blender --background --factory-startup --python tools/art/source/poi_service_hall/build_source.py
blender --background --factory-startup --python tools/art/source/poi_service_hall/inspect_narrowing.py
python tools/art/source/poi_service_hall/prepare_review.py
godot --headless --path output/poi-service-hall-321/project --editor --import
godot --path output/poi-service-hall-321/project --rendering-method mobile --rendering-driver vulkan
godot --headless --path output/poi-service-hall-321/project -- --structure-only
python tools/art/source/poi_service_hall/package_review.py
```

可编辑 Blender 源 `tools/art/source/poi_service_hall/service_hall_blockouts.blend` 含 `N2_A1`、`N2_A2`、`N2_B` 三个场景。当前源和布局用于评审，草稿 PR 不合并；选中排法后再交最终 `poi_service_hall_art.tscn`、皮肤图集和细模。
