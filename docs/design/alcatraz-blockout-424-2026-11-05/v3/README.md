# SGODOT-424 · v3 可走接入白模

马可波罗，2026-11-06。v2 画面已获不知火舞通过；本次补齐上官婉儿及亚瑟的缩放、逐屏看点、预算和模块接口。正式件硬线为 **11-09 08:00**；11-08 20:00 再确认替换后的可走文件、分支头与实测预算。当前仍有明确标注的协作占位件，不代表正式件全部完成。

## 看图

[开场](01-opening.png) · [半山](02-mid-hill.png) · [主楼前](03-visitor-center.png) · [俯视布局](04-top-layout.png) · [全岛补图](05-whole-island.png) · [最远斜向取景](06-summit-zoom-out.png)

[20 屏路线总览](07-route-contact-sheet.png)；[全部沿路原图](route/) 每张 360×800。按真实 NavigationServer 路线每约 6.5 m 停一屏，末端补主楼前；每屏都有长椅、灯、花坛、树、牌、海鸟、废墟或主体建筑看点。原图保留，联系表只是缩小排版。当前灰色树冠、家具和塔为约定尺寸占位，供同组替换。

默认镜头宽 6.72 m、zoom=1，保留农场角色 scale=1（名义 1.75 m）。`+ / −` 使用格里菲斯预览的 1.15 倍步进，最远严格限制为 **20.16 m（3 倍）**。上官已确认最远端转为 60° 斜向，默认 43°／14.5° 不变；主楼前的最远图容纳主楼大半正面与灯塔占位。除投影范围检查，还通过隐藏灯塔前后 **16,787 个变化像素**确认塔确实被画出。近远档 margin 设为 0，修复了中间距离两档都不显示的问题。

桥、城市、山丘是 FarZone 的贴片占位。海上安装基准位于码头向 +Z 岛外 20 m，假透视的抬高和深度补偿写在数据／shader，开场左上有橙红桥。它们没有交互碰撞，不是岛上可走模型。

## 实测预算

Godot 4.7.2、Vulkan Mobile、gs66 RTX 2060。每个取景采 12 次渲染计数，表内取峰值；draw call 包含本场景可见绘制、阴影和现有预览 UI。

| 位置 | 可见三角数 | 场景总 draw call | 整个审阅窗口 draw call |
| --- | ---: | ---: | ---: |
| 开场 | 28,429 | 36 | 37 |
| 半山 | 29,209 | 43 | 44 |
| 主楼前 | 28,033 | 39 | 40 |
| 主楼前最远斜向 | 29,213 | 48 | 49 |

20 张沿路图的峰值为 **31,261 可见三角／44 场景 draw call**。另外对 20 个路线点位扫过中档／三倍缩放，40 组全部通过，整窗峰值 57；见 [wide-sweep.json](wide-sweep.json)。所有已检查的可玩取景均低于 80,000 三角和 60 draw call；整窗多出的 1 次是审阅工具显示 SubViewport 贴图的呈现绘制，原始计数没有隐去，见 [view-budgets.csv](view-budgets.csv) 和 [verification.json](verification.json)。俯视／全岛是仅供美术审阅的 74／78 m 相机，不是玩家可访问的缩放档，原始计数也完整记录。

全场驻留（含角色、海面、近远档和 MultiMesh）为 **37,716 三角／50 surface**。共有 29 个单 mesh／单 surface GLB；29 是含近远档及协作占位的原型数，不是最终完成件数量。[asset-validation.json](asset-validation.json) 含文件哈希、尺寸、实例、LOD 与所有截图。

石沿、路灯、垃圾桶、指示牌、栏杆小转角、低花坛、渡轮和海鸟不投影；地形、建筑、树、长椅、直段栏杆仍投影。未改阴影距离，亚瑟接入时决定距离和最终阈值。地形、步道和四段台阶按可走区块合成三个静态地面网格，减少可见与阴影绘制，重复小件仍由 MultiMesh 引用独立原型。工具采用固定模拟帧步与加速走位，以上是实际渲染计数，**不是 FPS／GPU 耗时或 vivo 性能结论**。替换正式件后必须重测，不能沿用占位预算；vivo 低于 30 FPS 不上线。

## 文件和协作

- 场景：`scenes/landmark/alcatraz_island.tscn`，已直接声明 DockZone、TerraceZone、SummitZone、FarZone 四个节点；地形／步道／台阶按三个可走区块离线合批，重复小件仍独立。
- `assets/landmarks/alcatraz_island/layout.json`：camera（position／target／size）、spawn、anchors、boundaries 按茶馆结构；另有 walk_bounds、分区导航、LOD 和资产表。
- [placement_points.json](../../../../assets/landmarks/alcatraz_island/placement_points.json)：**442 个重复件实例**，单原型 GLB＋位置／旋转／缩放；斜栏杆附原生 Transform3D basis，立柱保持竖直。预览已经按区块／类型使用 MultiMesh，没有把栏杆和家具焊成大块。
- 六组近／远档接口：主楼、灯塔、水塔、桥、城市、对岸山丘。文件名和 visibility_range 建议在 `lod_groups`。
- [完整交接约定](../../../../tools/art/source/alcatraz_island/HANDOFF.md)：坐标、枢轴、组件尺寸、矩阵、分工、交件硬线与接入注意事项。

马可波罗负责地形、路线／台阶、码头／渡轮、主楼近档及整岛合成。赵云负责 alc_bench、alc_lamp、alc_rail_straight、alc_rail_corner、alc_curb、alc_tree_a／_b、alc_flowerbed、alc_bin、alc_sign；黄忠负责 alc_far_*、alc_lighthouse(_far)、alc_watertower(_far) 以及主楼远档。除马可波罗范围外，目前导出件均标明 placeholder／owner，按同名、同尺寸、同原点替换。

## 验证范围

201 项主检查及 40 组额外缩放预算检查通过：三个可走分区与 FarZone、约 **119.31 m** 完整路线、**6,657 个导航格**地面碰撞、四段台阶、默认角色／镜头比例、20 屏看点、各屏预算、+／− 及双指缩放、最远构图与灯塔实际像素、Map 出口、装饰无交互、导入 UID 与被测副本字节一致。最远按钮值为 zoom=1/3、20.16 m，放大端为 1.4；全景按钮已从玩家 UI 移除。

源文件另经 Blender 重新打开核对，29 个模块保留可编辑对象、60 个台阶踏步仍独立命名，四区块实例数与布局一致，见 [source-validation.json](source-validation.json)。

所有 Blender／Godot 调用使用 `flock ~/gs66-render.lock` 并在完成后退出。独立用户目录，仅 Avatar autoload，无 Net 自动登录。共享玩法、农场／Avatar、地图入口及正式发布配置未改；没有手机安装或合并动作。
