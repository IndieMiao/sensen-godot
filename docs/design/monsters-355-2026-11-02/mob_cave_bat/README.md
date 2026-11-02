# SGODOT-355 Cave Bat / 灰模试点

黄忠，virtual_user_id `5281cd25-6a49-4df8-9802-f3e534956e80`。
依据用户 11-02 批准的设定图 v1.1（Plane 355 `c368e7dd`）、上官婉儿派活及共同接口约定制作。此阶段交比例、骨骼与最终动作接口，正式美术仍需技术和画面复验；正式版计划 11-06。

运行时文件在基于 `origin/farm-dev 0beeca15` 的 `art/monsters-355` 分支，只推送、不建 PR：

- `assets/monsters/mob_cave_bat/mob_cave_bat.glb`
- `assets/monsters/mob_cave_bat/mob_cave_bat.json`
- `assets/monsters/mob_cave_bat/mob_cave_bat.glb.import`
- 共用 `assets/monsters/material_import.gd` 和 `material_import.gd.uid`

源文件、脚本和审阅材料在 `wp-3d-scene-huangzhong-monsters-355`，正式版时再开目标为 `wp-3d-scene` 的审阅 PR；不混入运行时交付分支。

## 几何与接口

1,376 三角形、单 mesh/surface、10 根骨骼。身体 Ø0.40 m，静止翼展 1.00 m；静止 bounds 为 X=-0.50..0.50、Y=0.745..1.309616、Z=-0.165..0.1705 m。JSON 的 height=1.309616 是地面到最高点，包含悬停空隙。身体中心在静止姿势 Y=1.0 m，根节点位于地面中心，米、Y 向上、正面 +Z，单位比例。

碰撞 radius=0.30 m，hurt_point=[0,1.0,0.05]，badge_point=[0,1.55,0]。模型不自带碰撞体或游戏逻辑；程序按 JSON 接入。全部部件使用平滑法线，每顶点仅一个权重为 1 的骨骼影响。root → body → 双耳、双段翅膀、双脚，左右每边两段翼骨可折叠、扇动。

底色为线性 COLOR_0，无贴图。UV2.x=1 是身体、翅膀和脚的可染色区，0 是眼睛、高光、腮红、嘴和内耳；精英、闪白和后续变体由运行时材质负责。

| 动作 | 秒 | 循环 | 事件与含义 |
|---|---:|---|---|
| idle | 1.00 | 是 | 扇翅、轻微上下浮动 |
| move | 0.60 | 是 | 快速扇翅，身体略前倾 |
| windup | 0.55 | 否 | 缩翅、前倾蓄势 |
| attack | 0.45 | 否 | 原地俯冲扑咬姿势，hit_at=0.20 |
| recover | 0.50 | 否 | 恢复飞行姿势 |
| hit | 0.25 | 否 | 受击后仰压缩 |
| die | 0.70 | 否 | 原地翻倒下降并缩小 |
| fly_high | 0.40 | 是 | 更快扇翅、身体后仰；不包含升高位移 |

所有动作不带根运动。移动、绕圈、俯冲轨迹和 fly_high 的升高均由程序控制；die 仅动 body 骨，不移动根节点。程序按照 JSON 设置循环模式和命中时刻，动作名与时长在正式版保持。

## 导入脚本

`material_import.gd` 仅在 EditorScenePostImport 中打开 `vertex_color_use_as_albedo=true`、设 `vertex_color_is_srgb=false`，并关闭 MeshInstance3D 的真实投影。它不做染色、闪白、动画或其他运行时逻辑。Godot 4.7.2 导入 glTF 时会保留 COLOR_0，但本环境默认材质未开启其底色开关；此处沿用 N1 已验证的做法，避免直接实例化后显示默认白材质。

每只怪的 `.glb.import` 在 `[params]` 中包含：

```ini
import_script/path="res://assets/monsters/material_import.gd"
gltf/texture_map_mode=1
```

共享脚本的 `.gd.uid` 与每只 GLB 的生成 UID 一起交付并保持稳定。运行时仍使用现有 `BlobShadow`，审阅也调用同一个假影实现。

## 验证与复现

`verify.py` 直接检查导出 GLB 的三角形、刚性权重、法线、bounds、双区 UV2.x、所有动作名与时长、循环首尾和恒定 root 轨道。隔离 Godot Mobile 工程逐个播放全部动作，实测蒙皮顶点变化与骨骼根位置；原件直接实例化后具有顶点色和关闭真实投影的属性。

本次 393 项 GLB 检查、136 项 Godot 检查通过。三视图、8 动作关键帧和矿内尺度图已逐张目检；审阅附件用黄忠 ID 上传并下载核对 SHA-256。矿内夹具依赖补齐后单独重跑对照段，最终对照日志没有脚本错误；动作验证沿用同一 GLB 的已通过实播结果。

审阅包含三视图、每个动作的关键帧拼图，以及未修改 farm-dev `mine_art.gd` 第 1 层中的默认 43° 对照。矿内史莱姆直接由 `mine_combat.gd` 的现有模型生成，radius=0.40；玩家用现有装配器、实际身高校准为 1.745 m。相机遵循该版本矿洞的 43°、yaw=14.5°、默认 zoom=.8，360×800 时视宽 7.5 m。这是美术隔离夹具，没有真实战斗接入或手机性能结论。

```bash
source ~/.codex-huangzhong/env.sh
blender --background --factory-startup --threads 2 --python-exit-code 1 --python tools/art/source/monsters/mob_cave_bat/build.py
output/art-setup/venv/bin/python tools/art/source/monsters/prepare_review.py mob_cave_bat
godot --headless --path output/monsters-355/mob_cave_bat/project --editor --import
godot --headless --path output/monsters-355/mob_cave_bat/project --script res://configure.gd -- "$PWD/output/monsters-355/runtime"
output/art-setup/venv/bin/python tools/art/source/monsters/verify.py mob_cave_bat
godot --path output/monsters-355/mob_cave_bat/project --rendering-method mobile --rendering-driver vulkan res://review.tscn
output/art-setup/venv/bin/python tools/art/source/monsters/package_review.py mob_cave_bat
```

先准备 `output/monsters-355/runtime` 的独立工作树；不得重置已有的共享交付分支。显卡共用，实渲前检查 nvidia-smi。私有 ADB 端口 5097，不连接设备，完成后仅停止本人记录 PID 的进程。
