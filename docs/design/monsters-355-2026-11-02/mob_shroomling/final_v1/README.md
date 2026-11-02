# Shroomling / 正式版 v1 候选

黄忠，Plane virtual_user_id `5281cd25-6a49-4df8-9802-f3e534956e80`。按不知火舞 355 `6a4c6bba` 的矿内配色意见制作；等待技术和画面验收，尚未合并或发布。

## 配色修改

| 部位 | 灰模 | 正式版 v1 |
|---|---|---|
| 伞盖 | D9857D | **E45D68** |
| 白斑 | F7E5C4 | **FFFDF6** |
| 奶白身体 | EEE0BD | 保持 |

伞盖改为更红、更饱和的色相，减少与矿内棕色地面斑块混同；白斑提白。修改仅落在顶点底色，白斑仍为 UV2.x=0，不受运行时变体染色影响。没有增加贴图、材质或描边。

保持灰模的 **1,496 三角形 / 7 骨 / 单 surface**、帽 Ø0.60 m、总高 0.70475 m、radius .32、hit_point `[0,.28,.04]`。九个动作、时长和全部几何均保留；顶层 `hit_at=.18`、`spore_at=.35` 及 `durations` 不变。hide 的 1 秒结束姿势供程序保持；spore 仍在 .35 s 鼓帽峰值放孢子。

## 验证与交付

验证直接读取最终 GLB 并核对原几何、刚性权重、UV2 遮罩、九个动作和顶层接口；Godot 逐个实播，并检查从每个动作直接切回 idle 无骨骼姿势残留。

最终 **324 项 GLB 检查 / 160 项 Godot 检查通过**，九种动作切回 idle 的最大顶点误差均为 0，日志无错误或警告。与灰模 `035ee7c1` 对照：位置、法线、UV2、权重、动画采样和客户端数值保留，仅顶点配色改变。交付 GLB 与实渲文件 SHA-256 一致；重复导出只可能改变有向三角形的索引排列。来源记录见同源目录的 `reuse_provenance.json`。

沿用共享 `material_import.gd` 和稳定 `.gd.uid`，只启用线性顶点色、关真实投影；每怪 `.glb.import` 挂接该脚本。GLB UID `uid://ygsce1gitlls` 保留，`animation/remove_immutable_tracks=false`，未从高级导入存盘，`_subresources` 仍为空。

交付三视图、九动作关键帧，以及红岩矿 F1 / 紫灰岩矿 F3 各一张默认 43°。两图均调用未修改的游戏矿层与史莱姆，放入 H=1.745 m 玩家、r=.40 m 史莱姆；360×800、yaw=14.5°、默认 zoom=.8、7.5 m 视宽。是桌面 Mobile 实渲，不是概念图或手机性能结果。

源：`tools/art/source/monsters/mob_shroomling/mob_shroomling.blend` 和 `build.py`。默认生成正式版；历史灰模用 `--stage blockout`。完整复现与蝙蝠正式版相同，ID 换成 `mob_shroomling`，生成与打包均指定 `--stage final_v1`。

运行时只推 `art/monsters-355`；源和审阅走草稿 PR 进 `wp-3d-scene`，合并须用户批准。显卡与赵云错开，使用 ADB 5097，仅关闭本人渲染 PID。
