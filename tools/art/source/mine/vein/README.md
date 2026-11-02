# SGODOT-355 矿脉 vein v1.1

黄忠，2026-11-03。按上官婉儿 355 / 5b186df5 仅调整白脉顶点色，供画面复验。
v1 的技术、形状和位置已通过；v1.1 保留其几何、锈红、UV、UID 和配色表。源/审阅 PR #687 保持草稿，目标 wp-3d-scene。

## 文件与原点

运行时目录 `assets/mine/types/vein/`：`backdrop.glb`、`backdrop.glb.import`、`palette.json`。
源码目录本文件所在位置：原资产副本 `base_reference.blend`、命名部件源 `vein.blend`、生成与验证脚本、provenance。
原副本来自 `assets/mine/backdrop/source/mine_backdrop.blend`，SHA-256 见 `reuse_provenance.json`。

- 3,595 三角形，1 mesh / 1 surface / 0 贴图，线性顶点色，不透明，无碰撞。
- 根节点 identity，米制，Y up；网格保留俯角 43°、偏航 14.5° 的原朝向。沿视线前移 1 m 仍由 `MineBackdrop` 做。
- 保留连续主体岩层与内保护区；沿同一条折线，从上方岩体斜穿到下方，矿层中间保持空洞，不增加几何。
- 白脉以 sRGB `#B4B3BA` 到 `#C8C6CE` 的淡紫灰为主体，凹面降至 `#A9A5B5`，按实际面法线分配明暗；转换一次到线性顶点色。实测 sRGB 加权亮度 .65492–.78040，差 .12548；暗凹面略低于 .70，以保留约 .12 的明暗跨度。锈红夹层颜色保持。
- 所有新增矿脉几何距原内轮廓退开 0.08 m。三档像素栅格轮廓完全一致；Godot 4×MSAA 对照保护区和内边缘均为零变化。
- 原主岩层的全部顶点在相机平面的投影保持。8 个外缘顶点只沿视线收进不足 3 mm，以满足深度硬界；不改变投影轮廓。
- 实测 `dot(P,N)` 为约 -6.967996 至 -5.669998 m，N=(.183116,.681998,.708058)。
- `.import` 沿用原 backdrop 设置、独立 Godot UID，`import_script/path=""`；不挂 monsters 导入脚本。关闭投影与 GI 由背景接入代码执行，自验已检查。

## 顶点格式

`COLOR_0.a=1`。暗岩 RGB 三分量相等，保留约 .42–.96 的灰度权重；矿脉写线性石英白与锈红色。
UV2.x 是原有外缘渐隐。**UV2.y 以 Godot 读出的值为准**：暗岩 0、矿脉 1。
Blender 的 `Fade_UV2` 中，暗岩 v=1、矿脉 v=0；导出 glTF 时翻 V，Godot 不再翻。

每次交付前在空工程用指定的 GLTFDocument 方法直接读文件，不执行 `--import` 或 `--editor`。
本次独立读入结果：

| 项 | 原背景 | vein v1.1 |
| --- | ---: | ---: |
| UV2.y 最小 | 1.0 | -0.0000152587890625 |
| UV2.y 最大 | 1.0 | 1.0 |
| 归零顶点 | 0 | 6,120 |
| 归一顶点 | 7,204 | 1,359 |
| 其他值 | 0 | 0 |

归零按 0.0001 容差统计，微小负值来自 Godot ArrayMesh 的 UV 压缩；GLB 内是精确 0/1。
6,120 个归零顶点全部为灰度，1,359 个矿脉顶点使用 mask 1。独立脚本还检查了旧背景原样导出确实全为 1。

正式接入的公式由周瑜负责，本次只在隔离工程里应用并将 `vein_mask` 设为 1：

```glsl
ALBEDO = mix(mix(COLOR.rgb * floor_tint, COLOR.rgb, UV2.y * vein_mask), void_tint, UV2.x);
```

`floor_tint` 取 `backdrop_tint`，`void_tint` 与 `Environment.background_color` 都取 `fog`。
`fog` 是虚空色，不启用真正的雾。旧背景默认 `vein_mask=0` 的接入兼容逻辑不由本资产改动。

## 四段配色

| 层段 | ground | wall | backdrop_tint | fog |
| --- | --- | --- | --- | --- |
| 1–10 | #B8A2A0 | #94768D | #4D3D49 | #242125 |
| 11–20 | #A29C9E | #7E7189 | #423B47 | #242126 |
| 21–30 | #909598 | #6C7180 | #383B43 | #222126 |
| 31–40 | #7F8A90 | #5D6877 | #30363E | #201F24 |

首段保留原紫灰岩壁 #94768D，地面由 #C69B80 向冷灰调整，减少与铜矿、甲虫橙边的近色。
后三段逐渐冷却压暗；最深地面仍明显亮于近黑煤矿。色表对比度只作辅助，最终以矿内识别度验收。
守关、精英层包含在所在段，连续覆盖 1–40。

## 自验

v1.1 直接修改已通过 v1 GLB 的 501 个白脉顶点 RGB（167 个三角面，共 3,003 字节），不重新导出几何。
颜色审计逐字节核对其他数据：JSON、材质、索引、位置、法线、两个 UV、alpha、锈红及灰岩颜色全部保持。
本轮重跑 39 项资产检查、Godot 导入、独立 UV 检查和五个实际视图；几何、轮廓及深度证据继承 v1，报告用 baseline SHA 和颜色审计关联，不冒充本轮重跑。

独立 GLB 检查预算、线性颜色、0/1 矿脉遮罩、深度界、palette schema、连续层段及明度递减。
内轮廓用实际 GLB 三角形投影比较；仅对 Float32 带来的微米级接缝做 0.01 mm 焊接和 0.05 mm 毛刺清理。
另直接逐点核对原主体岩层投影，避免依赖轮廓算法自证。
v1 增加严格栅格检查：40 / 100 / 160 像素每米下，新旧投影完全相同；实际 Godot Mobile 的 2400×2000、4×MSAA 轮廓图中，909,763 个保护区像素无新增覆盖，内边缘变化为 0 像素。
五个视图均有背景开/关对照：原矿层、人物、敌人、矿石等主体像素保持不变。

完整深度测试使用现有 `tests/p0/test_p0_mine_backdrop_depth.gd`，`P0_BACKDROP_DEPTH_FULL=1`；
原测试只加入进度打印，断言、密度、相机和 near/far 逻辑不变，GLB 通过隔离的 MineBackdrop.SCENE 指向本件。
覆盖 5 种视口 × 2 个楼层，含缩放回弹和所有允许平移；数值报告随审阅 JSON 交付。
v1 重新扫描 1,451,883 个机位，最小 far 余量 0.357143 m、near 余量 12.639031 m；原测试两项通过，零错误、失败或孤儿节点。

真实 Godot 4.7.2 Vulkan Mobile / RTX 2060，每段原始 720×1600（360×800 的 2 倍），43°、zoom=.8。
每段放实际玩家 H=1.745 m、青绿史莱姆、紫蝙蝠、红帽菇菇怪、岩甲虫和四种正式矿石；另附 F40 守关场地。
展示使用原紫灰矿的几何，只临时改颜色；没有提交 MineArt、MineBackdrop、着色器或测试代码的运行时改动。
v1.1 按要求只交四段和守关层总表及验证 JSON；v1 的五张独立 720×1600 JPG 保留为历史材料。
本轮是桌面美术审阅，不是手机性能测量，也未合并或发布。

## 复现

先准备本机独立 `output/monsters-355/runtime` 工作树和 `output/art-setup/venv`（NumPy、Pillow、Shapely）。
生成器会覆盖 `vein.blend`，人工修改前先保留源。

本次只改色的复现路径：从运行时 v1 提交 `827ef079491be0e06054c2fecbe33fbfbe6b6f63` 取出
`assets/mine/types/vein/backdrop.glb` 保存为 `output/mine-vein-355/vein-v1.glb`（SHA-256 `f3ce040a4a9b29fe557b487abf1ebda9071cb77e200caad8d4354f4045db5253`）。
运行时目标文件须为 v1 或仅改过白脉色的版本；补丁会拒绝其他字节变化。

```sh
output/art-setup/venv/bin/python tools/art/source/mine/vein/apply_quartz_colour.py --baseline output/mine-vein-355/vein-v1.glb
blender --background --factory-startup --threads 2 --python-exit-code 1 --python tools/art/source/mine/vein/recolour_source.py
```

完整重建才运行 `build.py`；本次交付使用上面的颜色补丁保持已通过的几何字节。完整重建及出图命令：

```sh
blender --background --factory-startup --threads 2 --python-exit-code 1 --python tools/art/source/mine/vein/build.py
output/art-setup/venv/bin/python tools/art/source/mine/vein/prepare_review.py
source ~/.codex-huangzhong/env.sh
godot --headless --path output/mine-vein-355/project --editor --import > output/mine-vein-355/import.log 2>&1
godot --path output/mine-vein-355/project --rendering-method mobile --rendering-driver vulkan > output/mine-vein-355/render.log 2>&1
output/art-setup/venv/bin/python tools/art/source/mine/vein/verify.py
```

深度检查设置 `P0_BACKDROP_DEPTH_FULL=1` 和 `P0_BACKDROP_DEPTH_JSON`，用该隔离工程的 GdUnit4 跑原测试。
独立 UV 检查目录只放最小 project.godot、`uv2_check.gd`、原背景 `orig.glb` 和新件 `backdrop.glb`，在目录内运行：

```sh
godot --headless --path . -s res://uv2_check.gd
```

本脚本沿用上官婉儿的 GLTFDocument 检查方式，追加 0/1 计数、灰度检查和节点清理。
最后用 `package_review.py --stage v1.1` 打包原分辨率 JPG 总表与验证 JSON；脚本验证本轮 UV、主体像素与颜色审计，并关联已通过 v1 的几何证据。
完整重建几何后需要重新运行 `outline_review.gd`、`verify_outline.py` 及全密度深度测试；v1 的原深度报告为 `depth-validation-v1.json`。
