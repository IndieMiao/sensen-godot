# SGODOT-424 · 渡轮与海鸥 v1

黄忠制作，独立交给马可波罗装配；本包不覆盖主体 `layout.json`、场景或导航。
对应原白模 #792 / b16c31982f34a64cdd4f9c6683064edbf20837a0。

渡轮 `ferry.glb`：25 m 长（X 轴）、船头 −X，原点沿用原渡轮 Y=0 的水线轴心，
船底到 Y=-1 m。白色两层客舱、蓝灰船身与烟囱、救生圈、开放栏杆、船舷护舷。
近档 5,144 三角面；`ferry_far.glb` 1,480 面（28.77%），55 m 切换，margin=0。
两档原点与长度一致；远档省去小护舷、窗口反光条、下横杆等细节。
每档一个网格 / 一个 surface，顶点色、哑光，不带粒子、点击区或碰撞，不投影。

`gull.glb`：一个网格 / 一个 surface、284 面；三个静态形态：
基础 stand，两个 blend shape `preen`（梳毛）、`spread`（原地张翅）。脚不位移，
无骨骼、AnimationPlayer、飞行或自动播放。所有姿势的实际包围见 manifest。
原点脚底，头朝 −Z（沿用旧件朝向），不改实例 yaw。

| 原实例 | 原坐标 (m) | 形态 |
|---|---|---|
| ferry_000 | (-7, 0, 19) | ferry / ferry_far |
| gull_000 | (-23.6, 2, 18.2) | stand |
| gull_001 | (10, 4.25, 8.7) | preen |
| gull_002 | (-24, 11, -7) | spread |

所有 yaw=0、scale=[1,1,1]。完整原始点位保存在 `ferry_gull_manifest.json`。

## 装配

1. 替换 `ferry.glb`、`gull.glb` 并保留本包 `.import`（沿用原 UID）；复制新
   `ferry_far.glb` / `.import`、`ferry_gull_material_import.gd` / `.gd.uid`。
2. 原 `ferry_000` placement 加 `lod_group: "ferry"`；把 manifest 的
   `ferry_lod_group` 加到主体 `lod_groups`，assets 表追加 ferry_far。坐标和朝向不变。
   原 `_add_asset` 已支持同名 `_far` 的 55 m 切档，无须另做缩放。
3. 原场景取出 GLB 的 mesh 使用，静态形态可直接在各 `MeshInstance3D` 上设置，
   不用复制 mesh，不要把两个形态同时开到 1：

```gdscript
func apply_gull_pose(instance: MeshInstance3D, pose: String) -> void:
    for i in instance.mesh.get_blend_shape_count():
        instance.set_blend_shape_value(i,
            1.0 if instance.mesh.get_blend_shape_name(i) == pose else 0.0)
```

`stand` 会把两项都设 0；按上表分别调用。此片段仅为交接文档，运行时接入归场景方。
导入脚本只启用线性顶点色、哑光并关闭投影，不做动作/染色逻辑。

## 源与审阅

可编辑命名源及确定性生成脚本在 `tools/art/source/alcatraz_ferry_424/`；
`gull.blend` 是命名构件，`gull_export_poses.blend` 另保留单网格的三种形态供直接检查。
每件 provenance 在该目录 `modules/`。所有 Blender / Godot 执行使用
`flock ~/gs66-render.lock`，独立工程在 `output/alcatraz-ferry-424/`。

验图基于原白模完整场景与机位，360×800、43° / yaw14.5° / 宽6.72 m；
只在隔离 fixture 增加渡轮 LOD 和海鸥姿势选择，宿主脚本、shader、点位保持原样。
码头开场是原取景；完整渡轮/近远档/海鸥三姿势图是补充审阅视角，不能当作开场截图。
审阅材料在 `docs/design/alcatraz-ferry-424-2026-11-06/`。
桌面 Vulkan Mobile 计数不代替最终整岛或 vivo 手机验收。
