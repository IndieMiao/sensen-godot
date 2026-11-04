# SGODOT-402 鱼笼浮标 A 款

【黄忠】依据上官婉儿设定 b82ebef9、不知火舞定 A 的 0331ee23 及 11-04 派活制作。
参考图和图标原样保存在 `reference/`，红色取 i-trap SVG 的 #E07A5F。

`fish_trap_marker.blend` 保留水面原点和命名部件：笼顶暗底、十二根经向编条、两圈横向编条、
水线边圈、短杆、红白浮球、顶钮、两圈绑绳和短绳尾。可分别编辑；导出合成一个 `fish_trap_marker_mobile` mesh / surface。
水上高 0.38 m、水下 0.05 m、笼顶宽 0.45 m；不加水面或波纹，浮动交程序。

## 复现

```bash
source ~/.codex-huangzhong/env.sh
blender --background --python tools/art/source/fish_trap_marker_402/build.py
output/art-setup/venv/bin/python tools/art/source/fish_trap_marker_402/prepare_review.py
godot --headless --path output/trap-402/project --editor --import
godot --headless --path output/trap-402/project --script res://configure_imports.gd -- "$PWD"
output/art-setup/venv/bin/python tools/art/source/fish_trap_marker_402/verify.py
blender --background --python tools/art/source/fish_trap_marker_402/verify_source.py
nvidia-smi
godot --path output/trap-402/project --rendering-method mobile --rendering-driver vulkan
output/art-setup/venv/bin/python tools/art/source/fish_trap_marker_402/package_review.py
```

私有 ADB 5097，不使用手机或模拟器，Godot 出图后自行退出。
`prepare_review.py` 从固定 b1 `6cf0bcb2` 只读导出到 output，使用独立用户目录、本机空网络端点及空会话传输。
未改 b1 的塘、水、浮漂、UI 源文件。仅审阅子类覆写浮标工厂，并跳过联机和到达提示；不提交客户端接入。
旧头像编辑源在私有工程用 .gdignore 排除，运行时仍使用原导出部件。

审阅使用真实 P0 Pond、FishingWater、FishingPresentation 的抛竿浮漂/鱼线/人物及 P0Ui.name_bar。
对比浮漂按原 1.6 倍绘制，鱼笼浮标按单位比例绘制。43° 镜头只为同框平移，正交宽度仍为原生 6.72 m。
近景单独用 25°/25°，便于看短杆与绳结。头顶 UI 在实际 360×800 逻辑视口核对，报告保留原始像素尺寸。

## 提示条交接

原生 0.6 m 提示锚点在 360 逻辑宽度时覆盖浮球上部，保留该真实截图。
另拍同机位、仅将 UI 锚点临时设为 0.9 m 的对照；这不是已批准的接入改动。
两者使用相同原生 `Fish Trap · 0/3` 图标/名字条。无关 HUD 在审阅截图隐藏，原生 UI 组件和算法保持。
