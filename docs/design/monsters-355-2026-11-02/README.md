# SGODOT-355 Monster Art / 黄忠

本目录记录黄忠负责的洞穴蝙蝠和菇菇怪。运行时资产在 `art/monsters-355`；本审阅分支仅含具名 Blender 源、复现与验证脚本、参考和审阅材料，PR 目标 `wp-3d-scene`，保持草稿，等待技术、画面验收及用户批准合并。

| 资产 | 当前正式候选 | 历史灰模 |
|---|---|---|
| mob_cave_bat | [正式版 v1](mob_cave_bat/final_v1/README.md) | [灰模](mob_cave_bat/README.md) |
| mob_shroomling | [正式版 v1](mob_shroomling/final_v1/README.md) | [灰模](mob_shroomling/README.md) |

客户端接口采用 11-02 修订：`radius`、`hit_point`、`durations`、顶层 `hit_at`，菇菇怪另有 `spore_at`。共享导入脚本只打开线性顶点色和关闭真实投影；每个 `.glb.import` 保留 `animation/remove_immutable_tracks=false` 和空 `_subresources`。程序负责染色、闪白、根位移、淡出和圆形假影。

正式候选每只均含红岩 F1、紫灰岩 F3 默认 43° 实渲、三视图、动作关键帧、实测验证；蝙蝠另含死亡时序图。所有审阅附件以黄忠 virtual_user_id `5281cd25-6a49-4df8-9802-f3e534956e80` 上传 Plane 355 并回读校验。不包含游戏接入、真实设备验收、主线合并或发布。
