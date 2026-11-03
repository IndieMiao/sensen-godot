# SGODOT-322 N4 Classroom 白模 v0（历史交付）

以下记录对应 `377d4be3`；复现白模请使用该提交。当前细模见本目录 README.md。

赵云，2026-11-03。用户已恢复 POI 制作；本轮按上官婉儿派活先交白模，等待上官婉儿技术检查和不知火舞空间验收，再开始细模与图集配色。设计依据是 SGODOT-317 R3 主图、俯视图、模块清单，原始资料副本在源目录 `reference/`；不沿用卡面旧的 10 月排期。

## 交付范围

分支 `wp-3d-scene-zhaoyun-poi-classroom`，从 `origin/wp-3d-scene @ 4dbd3e98` 开出，草稿 PR 目标 `wp-3d-scene`。

- 复用原 `assets/rooms/_shared/shell_hall/` 和 `scenes/shell_hall/`，没有改壳文件、几何、窗口、图集或碰撞。6.8×6.4 m，墙高 3.7 m，地面顶 Y=.08。
- 本件目录 `assets/rooms/poi_classroom/`：5 个自有 `blockout_*.glb` 及带 UID 的导入文件、`layout.json`、`asset_stats.json`。灰盒是占位，不冒充已完成的复用细模。
- 装配场景 `scenes/poi_classroom/poi_classroom_art.tscn/.gd`：复用共享壳，读取摆位、生成简单碰撞和全部挂点。中性材质只在本件实例上覆盖；玻璃材质保持。场景不自带环境、太阳或相机。
- 可编辑 `tools/art/source/poi_classroom/classroom_blockout.blend` 和生成/检查/拍摄脚本，带 `.gdignore`。五个导出网格名均为 `<件名>_mobile`。
- 现场实测 **16,958 三角形 / 45 surface**，含公共壳，排除审阅玩家。白模使用共享壳原图集和无贴图中性灰材料；教室最终单张 2048² 图集在白模批准后制作，细模预算重新核查。

## 座位与通道

按 R3 两列、三排摆 6 张课桌和 6 个独立圆凳。课桌面 **1.02×0.58 m**，离地高 **1.13425 m（0.65H，H=1.745 m）**；圆凳直径 .48 m，座面离地 **.715 m**，所以 `seat_desk_1..6` 世界/布局 Y 为 **.795 m**。六座朝向后墙（P0 挂点 yaw=0）；软垫没有座位挂点。

| 部位 | 净宽 |
|---|---:|
| 中央纵向通道 | 1.13 m |
| 左侧书柜旁纵向通道 | 1.61 m |
| 阅读软垫旁局部收窄 | **0.74 m** |
| 右侧纵向通道 | 1.23 m |
| 讲台前横通道 | 0.7785 m |
| 前沿横通道 | 0.82 m |

桌凳之间是就座区，接近点从中央通道分支进入；不把桌凳间小间隙当成穿行通道。检查使用完整家具轮廓，0.25 m 半径 / 1.745 m 高胶囊验证 spawn→中央/两侧→六座接近点→出口；0.35 m 半径检查 0.70 m 主通道。离出口最近的边界点按实际 .25 m 玩家检查，.35 m 主通道检查到距边界 .40 m 的出口接近点。网格额外留 3 mm 数值余量。

16 个可同时容纳 .25 m 胶囊、互距至少 .55 m 的建议站位记录在验证数据中。实际装配后 **49 项导航/胶囊检查通过**，包含原 `P0RoomNav` 的目标落点；不是只看平面上的箭头。球/盒占位的桌面物件也检查支撑高度与桌面包含关系。

六个审阅玩家使用原游戏 `sit_idle` 与 `P0Outpost.SIT_ROOT_BELOW_SEAT=.34`，根节点在座面下 .34 m，未制作或改动画；六座全景供目视复核。玩家实测站立高约 1.7398 m，落在 Basic Room 基线范围。这里验证挂点、姿势和通行，不包含多人占座或点击 UI 接入。

## 默认镜头

使用隔离工程中的原 `P0Room.use_art("poi_classroom")`、`frame_all()` 与 P0Ui 镜头区域，**43° / 偏航 45° / 6.72 m**，先按 360×800 算取景，再按相同投影拍 720×1600。

中央前沿 spawn 的初稿会把讲台裁掉，故白模调整为前沿右侧 **spawn=[2.90,.08,2.50]**，`cam_default` 同位；出口仍在中线 **[.50,.08,2.88]**，前沿通道保持畅通。原游戏网格实际落点约 [2.975,.08,2.525]，偏移 .079 m。不是另换镜头或缩小玩家。

六张课桌、黑板、讲台及招牌全部位于默认画面宽度内，纵向避开顶部 100 px / 底部 90 px。**67 项实渲检查通过**。房间左右端部分布景在默认视宽外，完整布局由俯视标尺图和六座全景补充，保留 6.8×6.4 m 壳尺寸。

## 与黄忠的接口

黄忠 7 件已通过技术检查：`350bd1f1`，草稿 PR #689，路径 `assets/rooms/poi_classroom/props/`。本轮只读其 `prop_manifest.json`，**没有取入或修改这些文件**。灰盒已按其实测尺寸调整：

- 讲台体量 1.30×.723 m，桌面高 1.13425 m；最终 GLB 上方额外 .05 m 的书不计入简单桌体灰盒。
- 地球仪按讲台局部 `globe_mount=[-.32,1.13425,-.0015]` 预留。
- 书本笔筒占位 **.545×.255×.27 m**，两套都包含在学生桌面内。
- 石膏像和几何体组合 .6775×.505×.2382 m，沿左柜转 90°，落在第一段低柜上。
- 黑板按 1.90×1.10×.16 m；两软垫直径 .60 m，只作装饰。
- 招牌按 1.45×.38 m，`sign_door` 可写区 **1.30×.28 m**。

Basic Room 没有现成课桌/圆凳：只有 `dining_table.glb`、`chair.glb`、`bench.glb`。白模批准后由赵云用这些源件改制课桌与无靠背圆凳，搁板类以 `wall_shelf.glb` 改制；共享灯、植物在细模阶段替换占位。黄忠的 `props/` 文件保持归他维护，赵云维护布局、场景和复用家具。

## 审阅材料

前缀 `SGODOT-322_POI_CLASSROOM_WHITE_v0_`，4 张署名 PNG：默认 43° HUD 安全区图、同镜头干净图、俯视标尺图、六个原生坐姿的整间全景。数据见 `validation-white-v0.json` 和 `media-manifest-white-v0.json`。

Godot 4.7.2、桌面 RTX 2060、Mobile/Vulkan；私有 ADB 5099。隔离工位使用独立用户目录、localhost:9，未改 farm-dev 工位、POI 模板表、服务端、其他房间或黄忠资产。没有 Android/真机性能结论。

## 复现

```bash
source ~/.codex-zhaoyun/env.sh
CLASSROOM_SOURCE="$PWD/tools/art/source/poi_classroom"
CLASSROOM_RUNTIME=/absolute/path/to/private/farm-dev-based-checkout
python3 "$CLASSROOM_SOURCE/plan.py"
output/art-setup/venv/bin/python "$CLASSROOM_SOURCE/check_plan.py"
blender --background --factory-startup --threads 2 --python-exit-code 1 --python "$CLASSROOM_SOURCE/build_blockout.py"
python3 "$CLASSROOM_SOURCE/prepare.py" --runtime "$CLASSROOM_RUNTIME"
godot --headless --path output/classroom-322/project --editor --import
godot --headless --path output/classroom-322/project --script res://configure.gd
godot --headless --path output/classroom-322/project --editor --import
python3 "$CLASSROOM_SOURCE/prepare.py" --runtime "$CLASSROOM_RUNTIME" --sync-import
godot --headless --path output/classroom-322/project --script res://check_navigation.gd > output/classroom-322/navigation.log 2>&1
nvidia-smi
godot --path output/classroom-322/project --display-driver wayland --rendering-method mobile --rendering-driver vulkan --max-fps 30 > output/classroom-322/render.log 2>&1
output/art-setup/venv/bin/python "$CLASSROOM_SOURCE/package.py"
```

生成脚本只导出五个 `blockout_` 文件，不清空整个房间目录。后续细模必须在白模获批后进行，并重新核座位、支撑、碰撞和预算。
