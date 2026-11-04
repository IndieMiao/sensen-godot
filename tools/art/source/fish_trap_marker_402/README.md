# SGODOT-402 鱼笼浮标 A 款 v1.1

【黄忠】依据上官婉儿设定 b82ebef9、不知火舞定 A 的 0331ee23 及 11-04 派活制作。
参考图和图标原样保存在 `reference/`，红色取 i-trap SVG 的 #E07A5F。

`fish_trap_marker.blend` 保留水面原点和命名部件：笼顶暗底、十二根经向编条、两圈横向编条、
水线边圈、短杆、红白浮球、顶钮、两圈绑绳和短绳尾。可分别编辑；导出合成一个 `fish_trap_marker_mobile` mesh / surface。
C64 要求整体放大 1.35 倍，`MODEL_SCALE` 直接乘到源顶点和导出顶点，节点仍是单位比例。
水上高 0.513 m、水下 0.0675 m、笼顶宽 0.6075 m；样式、颜色和 500 面不变，浮动交程序。

## 复现

```bash
source ~/.codex-huangzhong/env.sh
blender --background --python "$PWD/tools/art/source/fish_trap_marker_402/build.py"
output/art-setup/venv/bin/python tools/art/source/fish_trap_marker_402/prepare_review.py
SENSEN_OFFLINE=1 godot --headless --path output/trap-402-v11/project --editor --import
SENSEN_OFFLINE=1 godot --headless --path output/trap-402-v11/project --script res://configure_imports.gd -- "$PWD"
output/art-setup/venv/bin/python tools/art/source/fish_trap_marker_402/verify.py
blender --background --python "$PWD/tools/art/source/fish_trap_marker_402/verify_source.py"
nvidia-smi
SENSEN_OFFLINE=1 godot --path output/trap-402-v11/project --rendering-method mobile --rendering-driver vulkan
output/art-setup/venv/bin/python tools/art/source/fish_trap_marker_402/package_review.py
```

私有 ADB 5097，不使用手机或模拟器，Godot 出图后自行退出。
`prepare_review.py` 从固定 b1 `174bf1a1` 导出到 `output/trap-402-v11/`，使用独立用户目录、本机空网络端点及空会话传输。
只在私有副本把 `p0_pond.gd:606` 的名字条偏移从 0.6 改成 1.15 m；其余塘、水、浮漂、UI 源文件哈希不变。
审阅子类覆写浮标工厂，并跳过联机和到达提示；不提交客户端接入。
旧头像编辑源在私有工程用 .gdignore 排除，运行时仍使用原导出部件。

审阅使用真实 P0 Pond、FishingWater、FishingPresentation 的抛竿浮漂/鱼线/人物及 P0Ui.name_bar。
对比浮漂按原 1.6 倍绘制，鱼笼浮标按单位比例绘制。43° 镜头只为同框平移，正交宽度仍为原生 6.72 m。
本轮只拍一张同框图。头顶 UI 在实际 360×800 逻辑视口核对，完整截图放大 2 倍展示。

## 提示条交接

**本轮定稿为 1.15 m**，替代原来定的 1.0 m（以及 v1 审阅时的 0.9 m 提案）。
程序接入时将 `p0_pond.gd:606` 的 `Vector3(0, 0.6, 0)` 改成 `Vector3(0, 1.15, 0)`。
审阅由原生 `_trap_frame` 使用这处临时改动生成 `Fish Trap · 0/3` 名字条；无关 HUD 隐藏。
生成器重建的是放大后的源和 GLB，接入不用再乘 1.35；旧鱼笼工厂的 1.6 根缩放应去掉。
