# SGODOT-355 Shroomling / 灰模

黄忠，virtual_user_id `5281cd25-6a49-4df8-9802-f3e534956e80`。依据用户已批的设定图 v1.1（355 `c368e7dd`）、上官婉儿派活和 11-02 修订的周瑜客户端接口制作。

本阶段交比例、骨骼、全部动作和实际导入验证。正式版计划 11-08，灰模不等于正式画面验收。运行时只推 `art/monsters-355`，不建 PR；源和审阅推 `wp-3d-scene-huangzhong-monsters-355`，正式版再开审阅 PR。

## 尺寸与材质

- **1,496 三角形 / 7 骨 / 1 surface**，米、Y 向上、正面 +Z，根节点在脚底中心，单位比例。
- 从实际顶点量得 bounds：`[-0.30, 0, -0.30]` 至 `[0.30, 0.70475, 0.30]`，含贴合帽面的白斑总高约 0.705 m，伞帽最大直径 0.60 m。
- 碰撞 `radius=0.32`；`hit_point=[0,0.28,0.04]`，`badge_point=[0,0.92,0]`，补充 `spore_point=[0,0.65,0]`。不在 GLB 中放玩法碰撞。
- 圆润奶白身体、粉珊瑚红伞帽、六块奶白斑点、两只黑眼与白高光、粉腮红。所有表面平滑法线、哑光、无贴图、无描边。
- COLOR_0 存线性底色，UV2.x=1 为身体、帽、手脚；眼睛、腮红、高光和奶白帽斑为 0。每顶点 100% 绑一根骨头，无混合权重。
- 骨骼：root、stem、cap、arm_l/r、foot_l/r；脸跟随 stem、斑点跟随 cap。

共用已获同意的 `assets/monsters/material_import.gd` 与稳定 `.gd.uid`，仅在导入时打开线性顶点色并关闭真实投影，不含运行时染色或闪白。每怪 `.glb.import` 的 `[params]` 中指定 `import_script/path="res://assets/monsters/material_import.gd"`，并保留生成 UID。接入说明也放在运行时分支的 `assets/monsters/README.md`。

## 动作接口

客户端读取 `hit_point`、`durations`、顶层 `hit_at=0.18` 与 `spore_at=0.35`。`anims` 留作美术补充记录，客户端不读取。动作时长已与导出 GLB 逐项核对。

| 动作 | 秒 | 循环 | 内容 |
|---|---:|---|---|
| idle | 1.20 | 是 | 身体呼吸，伞帽轻颤 |
| move | 0.60 | 是 | 原地左右步伐，摆手、晃帽 |
| windup | 0.55 | 否 | 后仰压缩蓄势 |
| attack | 0.40 | 否 | 前倾顶撞，hit_at=0.18 |
| recover | 0.45 | 否 | 收招回正 |
| hit | 0.25 | 否 | 后仰压缩 |
| die | 0.75 | 否 | 原地侧倒并缩小 |
| hide | 1.00 | 否 | 缩进帽下，结尾保持缩入；停留多久由程序定 |
| spore | 0.80 | 否 | 伞帽鼓起，spore_at=0.35 时到达鼓起峰值 |

所有动作无根运动。hide 采用 stem 压缩和 cap 尺寸补偿保留帽的体积，手脚收进帽下；没有真孢子、命中或无敌逻辑，这些由程序按事件时刻处理。循环片段首尾一致。

## 验证与复现

`verify.py mob_shroomling` 检查真实 GLB 三角形、bounds、刚性权重、遮罩、动作名、时长、循环首尾、静止 root 轨道及客户端顶层 JSON 键。Godot 隔离工程逐动作实播，检查蒙皮顶点变化、骨骼根静止、原始导入材质、真实投影关闭和导入 UID。

本次 313 项 GLB 检查和 149 项 Godot 检查通过，最终日志无脚本错误。实际 hide 收起后最高点约 0.465 m；spore 在 0.35 s 附近的帽外径约 0.689 m，随后回到静止尺寸。白斑用实际帽面射线测得贴合高度并检查三角形内部离面间隙，避免贴片穿插。交付图逐张目检，署名上传后下载 SHA-256 核验。

交三视图、九动作关键帧拼图、真实矿内默认 43° 尺度对照。矿层和史莱姆直接调用未修改的 farm-dev `mine_art.gd`、`mine_combat.gd`，史莱姆 radius=0.40 m，玩家实际 H=1.745 m；360×800、43°、yaw=14.5°、默认 zoom=.8、7.5 m 视宽。这里只做美术验证，没有玩家存档、战斗接线或手机性能结论。

复现与蝙蝠共用工具，将命令中的 ID 换为 `mob_shroomling`：

```bash
source ~/.codex-huangzhong/env.sh
blender --background --factory-startup --threads 2 --python-exit-code 1 --python tools/art/source/monsters/mob_shroomling/build.py
output/art-setup/venv/bin/python tools/art/source/monsters/prepare_review.py mob_shroomling
godot --headless --path output/monsters-355/mob_shroomling/project --editor --import
godot --headless --path output/monsters-355/mob_shroomling/project --script res://configure.gd -- "$PWD/output/monsters-355/runtime"
output/art-setup/venv/bin/python tools/art/source/monsters/verify.py mob_shroomling
godot --path output/monsters-355/mob_shroomling/project --rendering-method mobile --rendering-driver vulkan res://review.tscn
output/art-setup/venv/bin/python tools/art/source/monsters/package_review.py mob_shroomling
```

`output/monsters-355/runtime` 是已存在的独立运行时工作树。不能重置共享分支。使用私有 ADB 5097，渲染前核对 GPU，只停本人记录的 PID。
