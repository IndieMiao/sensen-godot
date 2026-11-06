# 通用湾区远景卡片 · SGODOT-434

刘备整理，轮廓来源为黄忠的恶魔岛远景。用于旧金山湾区地标的远处城市、丘陵和桥；不包含可走结构、碰撞、导航、示例 layout 或游戏接入。恶魔岛原文件不变。

## 件表与坐标

| 文件 | 三角面 | 宽 × 高，m | 内容 |
|---|---:|---:|---|
| `far_city_high.glb` | 208 | 4.8 × 0.91 | 原高密城市轮廓，保留圆顶高楼和尖塔 |
| `far_city_medium.glb` | 184 | 4.8 × 0.541 | 去掉两座地标高楼，中等高度的密集街区 |
| `far_city_low.glb` | 34 | 4.8 × 0.243 | 17 栋低矮建筑，成组留空，低密水岸 |
| `far_hills_a.glb` | 120 | 8 × 0.52 | 原三层柔和丘陵 |
| `far_hills_b.glb` | 120 | 8 × 0.52 | 反向并调整起伏的另一段丘陵 |
| `far_bridge.glb` | 498 | 2 × 0.9 | 原双塔悬索桥，三档颜色可换 |

每件一个 mesh / surface / 静态 LOD，无贴图。六件共 1,164 三角面；实际场景选择所需的段，不把所有变体叠在一起。两种审阅组合分别使用桥＋高密城市＋丘陵 A（826 面），或中密城市＋低密城市＋丘陵 B（338 面），均 3 个 surface，不超过原三卡 826 面 / 3 surface。

单位米、Y 朝上，所有顶点位于局部 **XY 面 / Z=0**，底边中心为原点、正面 +Z。尺寸是风景卡片的构图单位，不是建筑真实高度。保留原来的镜头朝向投影：shader 忽略卡片旋转，使用世界原点在 view 中的 XY 与节点正向 X/Y 缩放，投到相机远裁面以内。用正缩放；负缩放不会镜像，丘陵 B 已在几何中做了不同走势。

## 材质参数

三个 `.tres` 共用 `far_card.gdshader`。颜色填 sRGB，颜色 alpha 不参与计算。

| 参数 | city.tres | hills.tres | bridge.tres | 含义 |
|---|---|---|---|---|
| `base_color` | `#E8DACA` | `#9DAE9B` | `#C97454` | 主色 |
| `accent_color` | `#AABDC6` | `#B2BA9B` | `#DE8A62` | 蓝灰楼面 / 浅山层 / 桥的亮部 |
| `shadow_color` | `#9FB1BD` | `#839D9A` | `#AD604A` | 暗部 |
| `fog_color` | `#67AFC2` | 同左 | 同左 | 与 432 海湾远色一致 |
| `fog_amount` | 0.18 | 0.28 | 0.10 | 0 原色，1 完全混到雾色；只混颜色，不增加透明层 |
| `depth_fraction` | 0.96 | 0.98 | 0.94 | 相机远裁面距离的比例；保留原卡片深度顺序 |
| `render_priority` | -98 | -99 | -97 | hills → city → bridge，三类间固定排序 |

桥换色时同时改三档颜色。例如冷蓝灰：主色 `#779BA7`、亮部 `#9EBBC1`、暗部 `#557C8D`，不需改模型或 shader。提高雾化可设 `fog_amount=0.75`；审阅中验证了这两种变化。

新 GLB 的 `COLOR.rgb` 是三个调色槽的**线性混合权重**（和为 1），不是最终顶点色；`COLOR.a=1`。不要覆盖成普通顶点色材质或将权重按 sRGB 转换。`far_card_import.gd` 将正确 `.tres` 绑定到 Mesh surface，抽取 Mesh 复用时也保留材质。实例需要不同配色时复制 `.tres`，或 `duplicate()` 材质后再调整参数，避免改到共享实例。

## 和 432 海面组合

432 海湾预设默认远处不透明，因此组合时把背景海面材质复制一份，**只将 `render_priority` 设为 -100**；保持其颜色、波纹和 shader 参数。这样先画海面，再画远景卡片，最后画 430 浪花（优先级 1）。否则默认优先级 0 的不透明远海会盖住负优先级卡片。

```gdscript
var bay := preload("res://assets/landmarks/_shared/sea_backdrop/bay.tres").duplicate()
bay.render_priority = -100
sea.material_override = bay
var card := preload("res://assets/landmarks/_shared/far_backdrop/far_bridge.glb").instantiate()
add_child(card)
# position / scale are the host's visual placement, not geographic bridge coordinates.
```

shader 仍进行深度测试，投到远处的卡片被正常不透明前景遮挡，不写深度，不投影、不参与 GI。导入节点沿用原宿主的 `extra_cull_margin=100`，避免 CPU 按未投影的薄片包围盒误剔除。若自行提取 Mesh 创建节点，需同时设置这些节点选项。多个同类城市段可沿共同底线相邻放置；不保证任意段的屋顶高度在边界一致，也不应按卡片尺寸解释为可走地形。

固定原点随宿主镜头平移投影；需要锁在屏幕上缘时由宿主设置卡片原点。本包不自动跟随玩家或改相机。审阅采用与 432 相同的 360×800、宽 6.72 m、俯角 43°镜头，上缘布置仅在隔离 QA 脚本中。

## 开销与导入

与原实际未启用贴图的远景相同：每卡 **0 次采样、1 个透明队列 pass**，不写深度、不加阴影 pass。颜色权重和雾色在 vertex 阶段计算；fragment 只输出颜色和 alpha=1，剪影空隙由几何保留。原 shader 的可选贴图分支在本件移除。最多使用推荐的三张卡片，避免额外全屏层或重复同位叠卡；新增库存变体本身不是每帧开销。

六份 `.glb.import` 均由 Godot 生成独立 UID，含 `nodes/root_script=null`，绑定本目录导入脚本；禁自动 LOD、shadow mesh、切线与动画导入。shader / 导入脚本 `.uid` 一并保留。没有新贴图，`imported_formats` 不适用。空缓存冷导入后资源文件保持原字节。

[审阅与验证](../../../../docs/design/far-backdrop-434/README.md) · [六份可编辑 Blender 源与重现步骤](../../../../tools/art/source/far_backdrop_434/README.md)。
