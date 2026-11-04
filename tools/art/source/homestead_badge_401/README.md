# Homestead Badge 401 / C63 A

赵云。`homestead_badge.blend` 保留命名木桩、五块石头、四个可编辑空白圆章；`spec.json` 保存尺寸、色板、预算、挂点和复用来源。生成器会重建此文件，手工修改请同步生成器或另存。

从仓库根目录运行（Python 需要 NumPy / Pillow；不需要联网或实际账号）：

```bash
source ~/.codex-zhaoyun/env.sh
blender --background --python "$PWD/tools/art/build_homestead_badge.py"
python3 tools/art/source/homestead_badge_401/prepare.py --runtime-ref dfe937a1
node --experimental-transform-types --loader ./tools/art/source/homestead_badge_401/ts_resolve.mjs ./tools/art/source/homestead_badge_401/make_view.ts
godot --headless --path "$PWD/output/badge-401/project" --import > output/badge-401/import.log 2>&1
godot --headless --path "$PWD/output/badge-401/project" --script configure.gd
godot --headless --path "$PWD/output/badge-401/project" --import > output/badge-401/reimport.log 2>&1
python3 tools/art/source/homestead_badge_401/prepare.py --sync-import
python3 tools/art/source/homestead_badge_401/verify.py
nvidia-smi
godot --path "$PWD/output/badge-401/project" --rendering-method mobile --rendering-driver vulkan --display-driver x11 --disable-vsync --max-fps 60 --resolution 360x800 --quit-after 1800 res://review.tscn > output/badge-401/render.log 2>&1
python3 tools/art/source/homestead_badge_401/package.py
```

每次 import / editor / 渲染均使用 `env.sh` 的私有 ADB 5099。`package.py` 会读取 `reimport.log`，请保存最后一次导入日志至 `output/badge-401/reimport.log`。隔离项目显式运行 `res://review.tscn`，使用独立 QA 用户目录、无生产网络的 fixture；先等待 6 s，再调用与 P0_SHOT_STEPS 一致的 `p0_joystick(0,-1)` 1.2 s、松开并等 3 s。保留开场/跟随各档原始图，以及隐藏数字的控制图；脚本拍完自行退出。

`verify.py` 读实际 GLB 二进制、顶点色和节点变换；检查全文件面数、几何范围、法线、空白面、挂点与 manifest 只追加。`review.gd` 另在游戏渲染中检查导入、档位隐藏、材质、真实相机和数字布局。`package.py` 对数字开关图做差测墨迹 cap，整理六张带署名的图。不要用文件中 5 个存储 surface 冒充 2 个；2 是运行时“共用底座 + 一个档位”的可见值，896 面包括所有档位。

游戏集成需加载整个 PackedScene。`homestead_badge_import.gd` 是交付的一部分，负责让 BadgeNumber / BadgeLv 成为 Marker3D，以及默认只显示 Tier_wood。Label3D 示例仅在审阅脚本内，模型面底没有文字。
