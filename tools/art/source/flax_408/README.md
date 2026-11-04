# SGODOT-408 亚麻田源文件

作者：黄忠，Plane `5281cd25-6a49-4df8-9802-f3e534956e80`。

`flax_patch.blend` 保留土圈、16 根茎、叶片和 12 朵五瓣花的独立命名对象。
`build.py` 从这些构造参数重建源文件，再将临时副本烘成一个顶点色 mesh。
源文件与生成器同步；重复运行会覆盖源文件，不保留手工编辑。

参考为上官婉儿提供的 `~/incoming/408/flax.svg.png`（本目录 `reference_flax.png`），
只参考蓝色五瓣花、细灰绿茎和披针叶。尺寸来自派活规格，不按图标量尺寸。
`zz_spot_art_old.gd` 是派活附件原样存档，只供隔离审阅里的旧资源对比。

运行时模型：`assets/farm/art/flax_patch.glb`。单位米，Y 向上，+Z 朝前，原点底面中心。
完整实测数据追加到农场 `manifest.json` 的 `assets.flax_patch`；原条目保留。
材质与 `sign.glb` 一致；放进农场 / 鱼塘时沿用 `FarmArt.instance("flax_patch", at)`，
共享 `FarmArt.material()`，线性顶点色，roughness 0.9，不需要贴图或新材质脚本。

## 重建与验图

以下在仓库根目录执行，使用已验证工具链与黄忠私有 ADB 5097。渲染前检查 `nvidia-smi`。

```bash
source ~/.codex-huangzhong/env.sh
blender --background --factory-startup --threads 3 --python "$PWD/tools/art/source/flax_408/build.py"
python3 tools/art/source/flax_408/prepare_review.py
SENSEN_OFFLINE=1 godot --headless --path output/flax-408/project --editor --import
SENSEN_OFFLINE=1 godot --headless --path output/flax-408/project --script res://configure_imports.gd -- "$PWD"
P0_SCENE=pond:pond_san_francisco_01 SENSEN_OFFLINE=1 godot --path output/flax-408/project --rendering-method mobile --rendering-driver vulkan
output/art-setup/venv/bin/python tools/art/source/flax_408/verify.py
output/art-setup/venv/bin/python tools/art/source/flax_408/package_review.py
```

`prepare_review.py` 从固定 b1 `174bf1a1` 提取私有工程；只在输出副本的
`modules/ponds/pond_scenery.gd` 添加 F2 `(7.9, 0, -1.1)` 单位比例模型。
场景保持真实出生点、镜头、UI、灯光、水和人物；隔离账户、阻断传输的 fixture 提供 HUD 数据。
并排图在同一塘景草地上另放一排对比件，沿用原旧件材质，不把对比排法提交到运行时。
最终运行会自动退出。导入缓存、临时工程、原始截图与日志留在 `output/flax-408/`。

预览 UI 是 360×800 逻辑像素；正式图将完整截图等比放大 2 倍并在外围署名，
不重绘场景。并排图为 1600×700 的真实渲染。所有数字由 GLB / Godot 实际顶点量取。
