# SGODOT-419 源与复现

使用已配置的 Godot 4.7.2、私有 ADB 5097；不需要 Blender 或导入新 GLB。
汤面和圆泡采用可编辑的 Godot 原生资源，动画关键帧保存在运行时场景内。

```bash
source ~/.codex-huangzhong/env.sh
python3 tools/art/source/cooking_pot_wait_419/prepare.py
SENSEN_OFFLINE=1 godot --headless --path output/cookpot-419/project --script build.gd
SENSEN_OFFLINE=1 godot --headless --path output/cookpot-419/project --script verify.gd
```

生成在隔离工程的 `assets/props/cooking_pot_wait/`。复核后将该目录的新原生资源复制回仓库，
不复制任何 b1 运行时代码。`prepare.py` 固定 b1 提交，验证原锅 GLB 的 SHA-256 与美术分支一致。

渲染前查看 `nvidia-smi`，与其他美工错开。白底预览入口 `review.gd`；
v1.1 叠层预览入口 `review_overlay.gd`，临时更换隔离工程 `review.tscn` 的脚本路径。
两者使用桌面 Mobile/Vulkan、固定 30 fps，每帧由 Godot 渲染后保存；ffmpeg 按 30 fps 编码。
v1.1 使用独立透明 200×180 SubViewport 和宿主左上暖光，显示在 360×800 画布的 `(80,150)`；圆环只是半径 60 px 的细线占位。
不带倒计时或进度条。旧 `review_phone.gd` 是 v1 取景记录，已经被叠层方案取代。
v1.2 仅修蒸汽，使用 `review_steam.gd` 拍三帧；同一夹具另外拍 35° / 43° 下的 Steam 开关对照，
确认盖沿以下 RGB 无变化、盖沿上方仍有可见白气。正式相机由哪吒提供。
不运行账号、后端或料理交互，也不修改 b1 源文件。

`verify.gd` 核对原锅实例、隐藏小锅、面数、尺寸、两个动画、首尾、根节点不动、
任意翻滚阶段切 idle 的恢复、蒸汽位置和预算。`review_phone.gd` 从实际顶点投影量取像素尺寸与位移。
