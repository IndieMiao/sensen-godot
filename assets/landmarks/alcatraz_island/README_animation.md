# SGODOT-424 海鸥 / 渡轮原地动作 v1

黄忠。基于已验收 #815 / 996528d3；此包增加场景动画，场景不自动播放、根节点不移动。
主体布局 / 导航 / 摄像机 / 远景不改，三只海鸥仍在原来的三个点，渡轮仍在 (-7,0,19)。

## 运行时入口

- `gull.tscn`：一个独立 Node3D，引用 `gull.glb`，一个 AnimationPlayer。
  `idle` 8.5 s循环，67.2%的时间完全静止；约1.25–2.05s转头、3.5–4.82s理毛、
  6.32–7.02s轻扑两下，之后静止。仅写 preen / spread / turn_head 的形变权重。
  不飞、脚不移动、不可点；不放骨骼或灯光、相机、碰撞。
- `ferry.tscn`：根节点 Ferry 保持原摆位；只动 BodyRig 子节点。
  `idle` 4 s循环，Y=0.02*sin(TAU*t/4)，实测±0.020 m；X/Z和旋转不动。
  BodyRig 内含原 ferry / ferry_far 两档，55 m切换；两档和旗帜一起起伏，不会两套相位。
  船尾外侧小旗挂在局部 (11.2,1.48,2.5)，旗杆1.65m、旗面0.80×0.45m；
  珊瑚赭/奶油顶点色，flutter 周期2s、前后幅度≤0.035m。不扩大原渡轮静态外包围。

全部 AnimationPlayer 命名固定为 `AnimationPlayer`，只有 `idle` 和编辑器 `RESET`；无 autoplay。
动画资源外链 gull_animations.tres / ferry_animations.tres，有Godot原生UID；场景只引用GLB，
不嵌一份重复网格。`gull.glb`仍284面/1 surface，原几何/法线/颜色/索引及preen、spread
形变值不变，新增turn_head；`ferry.glb`、`ferry_far.glb`和两份.import逐字节不变。
旗帜52面/1 surface，因此渡轮近档+旗=5196面，远档+旗=1532面。

## 交给马可波罗 / 接入程序

这两种类型用 PackedScene 实例化，不再只从GLB提取Mesh；三只海鸥各独立实例，不用MultiMesh。
渡轮整个实例只摆一次，ferry.tscn自己带远档，外部不要再额外加一份ferry_far。
点位、rotation和scale照原layout，每只海鸥/渡轮根节点始终保留这个变换。

```gdscript
var bird := preload("res://assets/landmarks/alcatraz_island/gull.tscn").instantiate()
zone.add_child(bird)
bird.transform = placement_transform
var player: AnimationPlayer = bird.get_node("AnimationPlayer")
player.play("idle")
player.seek(rng.randf_range(0.0, 8.5), true)
```

三只的起始偏移只在创建时各取一次；建议在0–8.5s的三个区间内分别随机，避免恰好很接近：
`offset = (index + rng.randf_range(0.1,0.9)) * 8.5 / 3.0`。不在每帧重新随机。
渡轮同样由程序调用 `play("idle")`，可从0或随机0–4s开始；停止时可播RESET归位。
不要在实例化后再写旧的静态 preen/spread 权重覆盖动画。

每个GLB的.import保留UID和nodes/root_script=null；新ferry_flag的UID由Godot导入生成。
材质继续用原ferry_gull_material_import.gd（线性顶点色、哑光、不投影），不添加运行时脚本。

## 审阅与源

`tools/art/source/alcatraz_anim_424/`：旗帜源、生成场景/动画库、验证/录制/打包脚本。
海鸥源仍在 `alcatraz_ferry_424/gull_export_poses.blend`，包含四个shape key；原构件源同目录。
审阅在 `docs/design/alcatraz-anim-424-2026-11-06/`：6s码头原开场、6s全部动作补充视角、姿势拼图。
原开场只见码头那只海鸥和船头；另外两只原点位远离开场，补充视频按原地近景同步展示，
没有把它们挪进开场。第三只近景从侧面拍，避免灯塔挡住。真正客户端接入由程序负责。
