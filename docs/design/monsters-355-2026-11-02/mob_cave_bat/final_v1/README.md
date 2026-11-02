# Cave Bat / 正式版 v1 候选

黄忠，Plane virtual_user_id `5281cd25-6a49-4df8-9802-f3e534956e80`。本版按灰模技术检查后的放大意见，以及不知火舞 355 `6a4c6bba` 的死亡动作意见制作。等待技术和画面验收，不代表已获用户批准合并。

## 本轮变化

- 实际身体宽 **0.50 m**、静止翼展 **1.30 m**，radius **0.35 m**。局部网格和骨骼静止关节同步调整，节点比例仍为 1。身体悬停中心保持 `[0,1.0,0]`，原点仍在地面。
- 模型维持 **1,376 三角形 / 10 骨 / 单 surface**。静止最高点 1.387020 m，随放大更新 JSON bounds/height。脸、内耳、脚随身体协调放大，配色和染色遮罩保留。
- `die` 保持 **0.70 s**：约 0.22 s 收拢双翼，随后 body 骨下降 0.62 m，约 0.58 s 到达落下姿势。全程保持身体体积，根骨不动；模型不自行缩成点，消失由程序配淡出。另附三帧时序图。
- 全部 **8 个动作名、时长、命中时刻** 与接口修订后的灰模 `75768edb` 相同。`hit_point=[0,1.0,0.05]`、`hit_at=0.2`、`durations` 保留；`fly_high` 不加高度位移。

## 导入与验证

沿用共享 `material_import.gd` 和 `.gd.uid`，只负责线性顶点色与关闭真实投影。GLB 原 UID `uid://btbkmxg5skb7` 保留。`.glb.import` 继续使用 `animation/remove_immutable_tracks=false`、`nodes/use_name_suffixes=true`，没有在高级导入中保存或展开 `_subresources`。

验证直接读取 GLB 的位置、权重、UV2、所有骨骼轨道和时长，另核对死亡动作的 body scale 恒为 1、下落量为 0.62 m。Godot 逐动作实播，并直接从每个动作切回 idle，不手动重置骨骼，验证没有姿势残留。

最终 **418 项 GLB 检查 / 148 项 Godot 检查通过**，八种动作切回 idle 的最大顶点误差均为 0，日志无错误或警告。交付 GLB 与截图使用的文件 SHA-256 一致；重建时导出器可能重排索引，已核对其有向三角形、顶点属性和全部动画数据等价。来源记录见同源目录的 `reuse_provenance.json`。

两张矿内默认 43° 分别调用现有 `mine_art.gd` 的红岩 F1（墙 `B85E43`）和紫灰岩 F3（墙 `94768D`），均放现有史莱姆 r=0.40 m 与玩家 H=1.745 m 作参照。使用真实游戏材质、几何和光照，360×800、yaw=14.5°、zoom=.8、视宽 7.5 m；没有重画矿洞或替换背景。另交三视图、全动作关键帧、死亡时序和验证记录。

源：`tools/art/source/monsters/mob_cave_bat/mob_cave_bat.blend` 与 `build.py`，默认生成正式版；历史灰模用 `--stage blockout`。运行时仍走 `art/monsters-355`，源与材料开草稿审阅 PR 进 `wp-3d-scene`，不合并、不发包。

```bash
source ~/.codex-huangzhong/env.sh
blender --background --factory-startup --threads 2 --python-exit-code 1 --python tools/art/source/monsters/mob_cave_bat/build.py -- --stage final_v1
output/art-setup/venv/bin/python tools/art/source/monsters/prepare_review.py mob_cave_bat
godot --headless --path output/monsters-355/mob_cave_bat/project --editor --import
godot --headless --path output/monsters-355/mob_cave_bat/project --script res://configure.gd -- "$PWD/output/monsters-355/runtime"
output/art-setup/venv/bin/python tools/art/source/monsters/verify.py mob_cave_bat
godot --path output/monsters-355/mob_cave_bat/project --rendering-method mobile --rendering-driver vulkan res://review.tscn
output/art-setup/venv/bin/python tools/art/source/monsters/package_review.py mob_cave_bat --stage final_v1
```

渲染前核对显卡，ADB 5097，不连接设备。审阅仅为桌面 Vulkan Mobile，不声称手机性能或正式游戏接入已验收。
