# SGODOT-355 守关头饰 v1

当前返修见 [v1.1](v1.1/README.md)。本页保留 v1 历史审阅。

黄忠，2026-11-02。三件供技术和画面验收，尚未合入主线。

| 文件 | 三角形 | surface | 宽 × 高 × 深（m） |
| --- | ---: | ---: | --- |
| crown.glb | 728 | 1 | 0.614 × 0.428 × 0.663 |
| ironback_plates.glb | 672 | 1 | 0.460 × 0.651 × 1.225 |
| quartz_cluster.glb | 368 | 1 | 0.483 × 0.547 × 0.392 |

按半径 r=1.0 m 的实际代码史莱姆制作。单位米，Y 向上，脸朝 +Z，背朝 -Z。
GLB 原点是头顶接触中心，装配位置 `(0, 1.43*r, 0)`，头饰跟随王统一缩放 r。
本地负 Y 是包覆圆顶和后背的几何，不是脚底原点。不要按包围盒底面重新落地。
金冠五个圆头尖角，金色主色 E9B34E，正前方圆宝石；铁背五片圆角甲和八颗铆钉；石英四根圆头晶柱。
全部为平滑法线、单材质、单 surface、线性顶点色、无贴图、不透明，不带骨骼、动作或碰撞。

运行时交付在 `art/monsters-355` 的 `assets/monsters/slime_king/`；
源与审阅在美术分支，Blender 源及生成器为 `tools/art/source/monsters/slime_king/`。
每件保存命名独立部件，导出合并为 `Body` 节点及 `<件名>_mobile` mesh。
共用现有 `assets/monsters/material_import.gd`，只在导入时打开线性顶点色和关闭投影，不改运行时染色逻辑。
各 `.glb.import` 的 `import_script/path` 指向该脚本，保留 Godot 生成 UID，
`animation/import=false`、`animation/remove_immutable_tracks=false`、`gltf/texture_map_mode=1`，空 `_subresources`。

三视图和挂载图来自 Godot 4.7.2 Vulkan Mobile / RTX 2060 的 512×512 SubViewport，未缩放原图。
挂载替身调用未修改的 `mine_combat.gd::_slime({radius:1.0},false)`；只隐藏血条并设置审阅用身体颜色。
身体颜色是提案，不是新增客户端规则。铁背另附后方 43°，可见背甲延伸。
接触验证直接对 `_slime_body(1.0)` 的三角形构建临时射线代理；仅封住代码顶部半径 0.04 m 的小开口。
每片导出三角形均取七行重心采样，累计 49,495 个有效射线点，无超过 1 mm 的穿插。
最小间隙：金冠约 3.35 mm、铁背约 0.65 mm、石英约 0.94 mm。此为采样检查，不是所有连续表面的数学证明。
代理碰撞仅存在于审阅场景，不进入运行时 GLB。
实渲 GLB 和交付文件的 SHA-256 一致；本轮没有手机性能测量。

复现（主工作树，先准备 `output/monsters-355/runtime` 指向运行时资产工作树）：

```sh
blender --background --factory-startup --threads 2 --python-exit-code 1 --python tools/art/source/monsters/slime_king/build.py
output/art-setup/venv/bin/python tools/art/source/mine_kit_355/prepare_review.py headgear
source ~/.codex-huangzhong/env.sh
godot --headless --path output/mine-kit-355/headgear/project --editor --import > output/mine-kit-355/headgear/import.log 2>&1
godot --path output/mine-kit-355/headgear/project --rendering-method mobile --rendering-driver vulkan > output/mine-kit-355/headgear/render.log 2>&1
output/art-setup/venv/bin/python tools/art/source/mine_kit_355/verify.py headgear
output/art-setup/venv/bin/python tools/art/source/mine_kit_355/package_headgear.py
```

生成器会覆盖本批 Blender 源；人工改源前先保留改动。审阅与验证脚本不改玩法代码。
全部原始依据来自上官婉儿 `dispatch-huangzhong-2.txt` 和运行时史莱姆轮廓，未另生成设计参考图。
