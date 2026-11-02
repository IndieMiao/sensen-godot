# 四矿石顶点色 v1.1

黄忠，2026-11-02。按不知火舞 355 / dc6d4110，只改铁、铜和石英的顶点色。
四件仍各 114 三角形、单 surface、半径不超过 .47 m、高 .63 m，形状、法线、材质设置和全部导入 UID 保持。
煤、已通过的电梯站及守关场地 GLB 均与 v1 逐字节一致。

- 铁：岩底冷灰 606D75，矿脉深锈红棕 703C3E / 8B4840，局部银灰金属亮面 B4BFC3，不再用亮橙。
- 铜：岩底暖铜色 9D6852，矿脉亮铜橙 EB994D / F2B46A；十个矿脉面板仅一个下部面板使用 6EAB94 绿锈，作为点缀。
- 石英：白色 FAF8F1 配淡紫 C6ADE6，统一淡紫水晶图标及头饰白底淡紫尖的颜色方向。
- 煤：黑亮配色不改。

一张两矿并排图，各栏保持 900×500 原始 43° 取景，顺序都是铁 / 石英 / 煤 / 铜，附实测 H=1.745 m 玩家。
使用实际红岩 F1 和紫灰岩 F3 环境及游戏光照，Godot 4.7.2 Vulkan Mobile / RTX 2060。
独立验证按导出三角形比较位置与法线的完整集合、材质 JSON 和 UID，确认本轮只有颜色变化；颜色和交付 SHA-256 记在附件验证中。
169 项独立检查和两种矿的 Godot Mobile 实渲检查通过，最终日志无错误。
源文件同步更新，未做玩法接入、合并或发布。

复现：保存 v1 的四个 GLB 为 `output/mine-kit-355/{iron-v1,quartz-rock-v1,coal-v1,copper-v1}.glb`
（运行时提交 `bd93076f`），随后运行：

```sh
blender --background --factory-startup --threads 2 --python-exit-code 1 --python tools/art/source/mine_kit_355/build_mine_props.py -- --ores-only
output/art-setup/venv/bin/python tools/art/source/mine_kit_355/prepare_review.py mine_props
source ~/.codex-huangzhong/env.sh
godot --headless --path output/mine-kit-355/mine_props/project --editor --import > output/mine-kit-355/mine_props/import.log 2>&1
godot --path output/mine-kit-355/mine_props/project --rendering-method mobile --rendering-driver vulkan -- --ores-v11 > output/mine-kit-355/mine_props/render.log 2>&1
output/art-setup/venv/bin/python tools/art/source/mine_kit_355/verify.py mine_props --compare-ores output/mine-kit-355
output/art-setup/venv/bin/python tools/art/source/mine_kit_355/package_ores_v11.py
```
