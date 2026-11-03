# SGODOT-355 浅坑 Quarry v1.1

按上官婉儿 355 `3900260a`，v1 背景、支架和地面梯度已通过，v1.1 仅调整运行时 `palette.json` 的 wall / backdrop_tint。GLB、Blender 源和 .import 与 v1 逐字节相同；ground、fog 四段全部保留。源生成器只同步调色常量，没有重建背景。

运行时 v1.1 增量 `cfd3436f`，已在共享分支推送前 pull --rebase。

| 层段 | ground（不变） | wall | backdrop_tint |
|---|---|---|---|
| 1–4 | #DCA26E | #B85E43 | #653425 |
| 5–10 | #CD925B | #A0563B | #582F20 |
| 11–20 | #BA824A | #884C35 | #4B2A1D |
| 21–30 | #A07146 | #70422E | #3E2419 |

第一段恢复线上原值，排除后续色相条件；后三段岩壁 HSL 色相约 16.04° / 16.63° / 18.18°，L=.429 / .371 / .310，S=.461 / .439 / .418；背景按相同红岩色系下降。地面仍为 28–30° 暖色，与红岩墙分开。

本次只交一张五列总表 `SGODOT-355_mine_quarry_v1.1_bands.jpg`（四段 + 守关）。25 项 GLB / 配色检查和 25 项 Godot 检查通过；空目录原 `uv2_check.gd` 实测 UV2.y min=max=0，5840 顶点，值为 1 的顶点数 0。几何未变，沿用 v1 全密度裁剪证据；保留性的哈希核对见 `validation-v1.1.json`。最新媒体清单 `media-manifest-v1.1.json`，草稿 PR #686 待复核和用户批准。

## v1 历史（墙色由 v1.1 替代）

赵云。按上官婉儿 355 `5ada1f3f` 调整暖色深度梯度、台阶边沿和木支架，交 v1 技术与画面复核。运行时仍只推 `art/monsters-355`；源与审阅分支 `wp-3d-scene-zhaoyun-quarry-355` 开草稿 PR 到 `wp-3d-scene`。未批准合并。

运行时 v1 增量 `942d78f8`，仅改 `assets/mine/types/quarry/backdrop.glb` 和 `palette.json`；推送前已 pull --rebase，保留共享分支同时到达的提交。

## v1 变化

配色按 **HSL** 校准（此处 L 是 HSL 明度，不是下面像素检查的 CIE L*）：

| 层段 | 地面 | H | S | L | 岩壁 | 背景套色 |
|---|---|---:|---:|---:|---|---|
| 1–4 | #DCA26E | 28.36° | .611 | .647 | #B97941 | #664324 |
| 5–10 | #CD925B | 28.95° | .533 | .580 | #A06C3B | #583B20 |
| 11–20 | #BA824A | 30.00° | .448 | .510 | #885E35 | #4B341D |
| 21–30 | #A07146 | 28.67° | .391 | .451 | #704E2E | #3E2B19 |

地面、岩壁、背景套色全部保持 28–30° 暖色，最低 S=.391，主要靠 L 逐段下降；第一段地面保留原色。岩壁改为同色系赭石，背景套色继续约为岩壁 RGB 的 55%。四段 fog 沿用 v0，不启用真实雾。

台阶窄边沿设为线性灰度 .95 / .94 / .92，相邻宽立面 .42 / .43 / .44，取代原先亮立面与暗细缝。木撑立柱 .13→.24 m、横梁 .16→.28 m、斜撑 .10→.20 m；侧面灰度 .58–.96、正面 .96。两组前侧支架向默认取景中间收，背侧保留一组，上下各能完整看见支架；侧边两组保留。内轮廓、浮雕基底几何、外缘渐隐函数和前移约定不变。

预算仍为 **2968 三角形 / 1 mesh / 1 surface / 0 textures**，45 个具名部件。`.import` 和 UID `uid://mfcdrjqauttn` 保持。空目录运行原 `uv2_check.gd`：**Godot UV2.y min=0、max=0，5840 个顶点，值为 1 的顶点数 0**。自验使用正式公式、显式 `vein_mask=1`。

最新媒体前缀 `SGODOT-355_mine_quarry_v1_`，包含四段、守关层、总表、全景，以及第 1/4 段 v0/v1 同镜头对比，全部 JPG。最新证据 `validation-v1.json`、`media-manifest-v1.json`。v0 图和验证保留为历史。

煤的辨识度检查新增整块矿石轮廓内颜色中位数：按实际煤网格投影生成遮罩，向内缩 2 px，排除地面和假影；保留旧 3×3 亮面采样作为补充，不把煤的小亮面当成整块煤的颜色。23 项 GLB 检查包含新的 HSL 条件；25 项 Godot 检查继续覆盖材质、遮罩和截图，完整深度扫描与主体开关差分随 v1 重跑。

v1 结果：四段主体开/关差分最大 RGB 差均为 0；地面比煤主体中位数高 47.99 / 42.43 / 36.09 / 28.90 L*，最深段旧亮面采样差为 8.02 L*，两种统计均保留。1,451,883 个全密度机位复测通过，最小 far 余量 0.357079 m，2 测试、0 错误/失败/跳过/孤儿。灯光、默认镜头与 v0 保持一致。

## v0 历史记录

赵云，2026-11-02。按上官婉儿 `dispatch-mine-layers.md`（含周瑜确认的 ★ 段）交背景粗模、配色初稿和逐段矿内截图。v0 待技术与画面复核，正式版目标仍为 11-10；不是最终验收、程序接入或合并批准。

## 文件与范围

运行时共享分支 `art/monsters-355`，本次只新增：

- `assets/mine/types/quarry/backdrop.glb`
- `assets/mine/types/quarry/backdrop.glb.import`
- `assets/mine/types/quarry/palette.json`

运行时 v0 提交 `d29e177d`；推送前已执行 `git pull --rebase origin art/monsters-355`。

源与审阅分支 `wp-3d-scene-zhaoyun-quarry-355`，从 `origin/wp-3d-scene @ 4dbd3e98` 开出；v0 先推分支，正式版再开草稿 PR。Blender 源和脚本在 `tools/art/source/mine/quarry/`，带 `.gdignore`。不改黄忠的 vein、矿石、怪物或共享运行代码。

## 背景

从运行时原 `assets/mine/backdrop/source/mine_backdrop.blend` 复制后修改，保留内轮廓和外缘投影；减少外侧零碎岩体，强化连续台阶，增加五组木支架与斜撑。45 个具名可编辑部件，导出为 **2968 三角形 / 1 mesh / 1 surface / 0 textures**，不带碰撞，运行时沿用 `MineBackdrop` 关闭投影和 GI。

- **224 个内缘顶点保持原位置**，导出最大坐标误差小于 2 微米；逐三角形对原保护多边形求交，面积为 **0**。
- 原点、米制、Y-up、43° 俯角 / 14.5° 偏航对齐约定不变。网格中没有加入向相机的 1 m 位移，仍由 `MineBackdrop.FORWARD_M` 完成。
- 沿 N 的深度范围 **-6.970811 至 -5.602000 m**。最小值来自逐顶点保留的原内缘，沿用原 README 的精确值（派活中的 -6.97 是两位小数）；没有比原背景更深。
- `COLOR_0.rgb` 为相等的线性灰度，范围约 **0.4223–0.9569**，alpha 恒为 1。木撑也只用灰度，靠形状和明暗分层。
- `UV2.x` 保留外缘虚空渐隐；**导出 GLB 和 Godot 导入后的 `UV2.y` 都为 0**。Blender 的 UV V 会在 glTF 导出时翻转，因此源中写 V=1，实际输出遮罩为 0。按新增 ★★ 段，在空工程直接运行原 `uv2_check.gd`（无 `--import` / `--editor`），实测 **UV2.y min=0、max=0，5840 个顶点，值为 1 的顶点数 0**；原背景对照读到 min=max=1。日志保留在验证 JSON；原小脚本未释放临时场景，退出有资源泄漏提示，两个文件的读取 err 均为 0。
- `.import` 由 Godot 生成新 UID **uid://mfcdrjqauttn**，参数复制旧背景模板，`texture_map_mode=1`，无 monsters 的 `material_import.gd`。

## 配色初稿

| 层段 | ground | wall | backdrop_tint | fog |
|---|---|---|---|---|
| 1–4 | #DCA26E | #B85E43 | #653425 | #242125 |
| 5–10 | #C39B76 | #9E6650 | #57382C | #242225 |
| 11–20 | #AC927C | #88685B | #4B3932 | #222125 |
| 21–30 | #958474 | #736157 | #3F3530 | #201F23 |

连续覆盖 1–30 层，守关和精英层属于所在层段。ground、wall、backdrop_tint 的线性亮度逐段降低；下层地面适度去饱和，保留煤与橙色矿物的辨识度。第一段严格沿用红岩矿指定起点。

`fog` 仅作 Environment 背景色和 shader 的 `void_tint`，不启用实际雾。临时审阅 shader 按周瑜公式：

```glsl
ALBEDO = mix(mix(COLOR.rgb * floor_tint, COLOR.rgb, UV2.y * vein_mask), void_tint, UV2.x);
```

uniform 名保持 `floor_tint` / `void_tint`；审阅时显式设 **vein_mask=1**，已按该公式重拍全部图。浅坑的 UV2.y=0，仍为灰度乘楼层套色。正式程序接入归周瑜。

## 验证与画面

21 项独立 GLB 验证、25 项 Godot 实渲检查通过。使用 Godot 4.7.2、RTX 2060、Mobile/Vulkan、4× MSAA；沿用 P0Mine 灯光、太阳、相机和深度设置。工位隔离用户目录、localhost:9，不连接生产账号或存档；没有 Android/真机性能结论。

- 四段使用同一个原矿室壳，便于比较配色；隔离工程临时覆盖 `MineArt` 颜色和 `MineBackdrop` 资源/套色，临时 shader 支持 UV2.y。运行时不提交这些代码改动，程序尚未正式读取 palette。
- 按真实 `P0Mine._update_camera()`，玩家站在 `Layout.SPAWN`，使用 P0Ui 的默认镜头区域。先以 360×800 算取景，再按相同投影拍 720×1600；俯角 43°、偏航 14.5°、视宽 6.72 m、zoom=1。UI 只在拍图时隐藏，没有单独放大角色。
- 每段都有真实玩家、普通史莱姆、已通过的岩甲虫 v1.1、蝙蝠、菇菇怪和四种矿石。守关图在第 4 段上放原 `guard_arena.glb`，附 22 m 全景显示完整浅坑外围，明确区别于默认镜头。
- 背景开/关像素对照：四段矿层主体（含边缘）最大 RGB 差 **0**；原始 PNG 留在 `output/quarry-355/captures/`，交付 JPG 不用于无损差分。
- 指定煤亮面与相邻地面 3×3 像素中位数比较，地面比煤高 **27.11 / 22.67 / 18.17 / 11.97 L***。这是采样点证据，是否整体易辨仍交美术看图。
- `P0_BACKDROP_DEPTH_FULL=1`，原深度测试覆盖两种矿室形状、五种屏幕尺寸、缩放回弹范围、0.01 缩放步长及 0.05 m 横向焦点步长；总共 **1,451,883 个机位**。最小 far 余量 **0.357079 m**，最小 near 余量 **12.571118 m**；2 个测试通过，0 errors / failures / skipped / orphans。
- 全密度测试的隔离副本只增加三角形包围盒缓存以提前排除屏幕外三角形、逐案例日志和更长超时；原三角形裁剪、扫描密度、断言及 0.05 m 门槛不变。原运行时测试文件不改。最初未加缓存的长跑主动停止，不计作通过。

审阅共 7 张 JPG：四段各一张、守关层、五列总表、全景；前缀 `SGODOT-355_mine_quarry_v0_`。总表 `SGODOT-355_mine_quarry_v0_bands.jpg` 约 1.09 MB，署名赵云；每份文件小于 3 MB。最新证据 `validation-v0.json`、`media-manifest-v0.json`。

## 复现

Python 依赖 NumPy、Pillow、Shapely；Blender 5.2.2、Godot 4.7.2。每次 Godot 先加载私有 ADB 5099 环境，渲染前检查共享 GPU，只停止自己记录的 PID。

```bash
source ~/.codex-zhaoyun/env.sh
QUARRY_RUNTIME=/absolute/path/to/monsters-runtime-checkout
QUARRY_SOURCE="$PWD/tools/art/source/mine/quarry"
blender --background --factory-startup --threads 2 --python "$QUARRY_SOURCE/build.py" -- --runtime "$QUARRY_RUNTIME"
output/art-setup/venv/bin/python "$QUARRY_SOURCE/verify.py" --runtime "$QUARRY_RUNTIME"
python3 "$QUARRY_SOURCE/prepare.py" --runtime "$QUARRY_RUNTIME"
godot --headless --path output/quarry-355/project --editor --import
godot --headless --path output/quarry-355/project --script res://configure.gd
godot --headless --path output/quarry-355/project --editor --import
python3 "$QUARRY_SOURCE/prepare.py" --runtime "$QUARRY_RUNTIME" --sync-import
P0_BACKDROP_DEPTH_FULL=1 P0_BACKDROP_DEPTH_JSON="$PWD/output/quarry-355/depth-full-v1.json" SENSEN_LANGUAGE=en godot --headless --path output/quarry-355/project --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/p0/test_p0_mine_backdrop_depth.gd
nvidia-smi
godot --path output/quarry-355/project --display-driver wayland --rendering-method mobile --rendering-driver vulkan --max-fps 30
output/art-setup/venv/bin/python "$QUARRY_SOURCE/package.py" --runtime "$QUARRY_RUNTIME"
```

打包前还需按派活执行空工程检查：将原检查脚本、旧背景 `orig.glb` 和本件 `backdrop.glb` 放入仅有 `project.godot` 的空工位，加载私有环境后在该目录运行 `godot --headless --path . -s res://uv2_check.gd`；输出记录为 `output/quarry-355/uv2-godot-v1.1.txt`（按交付版本命名）。不在该工位运行导入或编辑器。当前打包默认 v1.1，可用 `--revision v1` 重现上一版媒体格式。

生成器从原已验收 backdrop.blend 复制开始。当前 quarry.blend 内嵌 `EXPORT_RUNTIME.py` 可导出手工编辑后的具名部件；默认使用源中记录的运行时工位，也可通过环境变量 `QUARRY_RUNTIME` 指定另一工位。旧的 257 制作脚本和 contour 数据保留为来源记录，不用旧脚本覆盖当前 quarry 编辑。
