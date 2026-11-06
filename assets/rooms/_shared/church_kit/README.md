# 教堂共享套件 v1.1（准备件）

黄忠。来源为已上线 Grace Cathedral；原 `assets/rooms/poi_church/` 的全部71个文件保持原字节。
本目录包含独立GLB、材质、彩窗色板和导入文件，依赖 poi_church 的图集；没有新地点、布局或游戏场景。
用户后续是否添加、添加哪些教堂仍待定，本次只交可复用件和审阅示例。

## 模数与坐标

单位米，Y向上。墙/玻璃的+Z是室内正面，墙底Y=0。结构沿X以2m模数拼接。

| 模块 | 接口与安装 |
|---|---|
| wall_door_2m | 宽2、高4.8、主体厚0.26；门洞1.40×2.60，双木门扇与墙合为1surface；底部中心原点，+Z朝室内 |
| wall_straight_2m | 宽2、高4.8，主体厚0.26；底部中心原点，端点(-1,0,0)/(1,0,0) |
| wall_pointed_2m | 同一直墙接口；真尖拱孔洞和石框已合成一个surface |
| wall_rose_2m | 同一直墙接口；圆孔中心(0,3.25,0)，半径0.828 |
| wall_corner_2m | 原点在转角弯点、墙底；两臂各1m，沿+X/+Z，端点(1,0,0)/(0,0,1) |
| roof_band_2m | 2m宽、2.4m高，底部中心；放在墙顶Y=4.8，组合总高7.2m |
| beam_2m | 2m长、0.18m方截面，原点在梁中心线；端点X=±1 |
| floor_tile_2m | 2×2m、厚0.12m；原点在底面，放Y=-0.12使完成面为0 |
| steps_2m | 宽2、深1.5、三阶各高0.18，总高0.54；顶平台2×0.9m，中心(0,.54,-.30) |
| pointed_glass | 单独玻璃，原点与窗墙底中心相同；与wall_pointed_2m用相同变换即可 |
| rose_frame / rose_glass | 原点是窗心安装面，不是底面；一起放在wall_rose_2m的(0,3.25,0) |

直墙中心间距2m；两侧转角各占1m，因此一条8m边可用 `1 + 2 + 2 + 2 + 1` 组合。
转角按90°旋转，连接端点先对齐再摆直段；不要按带饰条的AABB宽度累计，否则会产生偏移。
墙厚0.26是主体厚，含窗台/檐口的实际深度更大，完整包围见 `kit_manifest.json`。
玫瑰窗由原件等比缩放0.92，石框外径约1.887m，适合2m窗墙；玻璃/石框同轴。
入口用wall_door_2m替换一个2m墙段。Map门钮建议挂在木门局部(0.35,1.65,0.20)，随模块变换；实际接入时选默认镜头可见的门面。门扇为静态布景，未带碰撞或交互节点。屋顶带是可选上层件；需要较矮的空间可以只用4.8m墙段。

## 原件复用与挂装

wood_pew、altar_table、sanctuary_steps、iron_chandelier、pipe_organ、flower_pedestal、
grass_surround保留原GLB的全部几何、UV、顶点色和BIN数据，仅把JSON内的贴图URI改为
`../../poi_church/room_albedo_ao.png`，避免原始GLB导入查找已删的本地副本。
依赖 poi_church 的图集：`opaque_atlas.tres`直接引用
`res://assets/rooms/poi_church/room_albedo_ao.png`（2048²）；套件不再包含重复PNG或它的.import。
各自新增Godot UID，不复用原教堂的资源UID。

- wood_pew：原尺寸约2.69m长；坐面0.715m，靠背在局部+Z，座位朝-Z。
- altar_table：原地面轴心，桌面1.12m；放在台阶顶面Y=0.54时原点也加0.54。
- sanctuary_steps：原宽约4.8m的大台阶，供更宽祭坛使用；小空间可用steps_2m。
- iron_chandelier：原点在环体中心高度；顶部吊点在局部(0,1.8,0)，用“吊点世界高度-1.8”放根。
- pipe_organ：底部原点，键盘朝+Z；花架保留原花/底座比例，不新增符号。
- grass_surround：辅助衬底27m见方，顶部局部Y=-0.67；示例根放Y=0.55，使草面为-0.12。

新结构件用opaque_vertex.tres，复用件用opaque_atlas.tres。每个GLB均1mesh/1surface，
套件19件合计30,552独立三角面；单件实测尺寸、面数、源路径、provenance在kit_manifest.json。
重复地板/墙段适合在未来接入时按材料批处理；本准备包不引入场景装配逻辑。

## 彩窗换色

pointed_glass、rose_glass通过UV.x存六类色块索引，玻璃材质只有一个 `palette_texture` 参数。
两款现成材质：`glass_palette_classic.tres`（原蓝金）、`glass_palette_meadow.tres`（灰绿淡紫）。
换材质或替换它引用的8×1色板即可，不改模型、UV或石框；铅条在两款里都保留深褐。

| 色板列（从0开始） | 分组 |
|---|---|
| 0 | 主色 blue |
| 1 | 暗色 blue_dark |
| 2 | 点缀 coral |
| 3 | 金色 glass_gold |
| 4 | 浅色 glass_cream |
| 5 | 铅条 iron |
| 6、7 | 预留，不被当前玻璃采样 |

色板用sRGB PNG、最近邻采样、不压缩、不生成mipmap；shader按source_color转线性光照。
默认glow_strength=0.12，玻璃是彩色实体面，不依赖实时彩光投影。
同一房间可以共用一个预设材质；需要修改预设参数时先duplicate，避免影响其他房间。

```gdscript
var palette_material := load("res://assets/rooms/_shared/church_kit/glass_palette_meadow.tres")
for mesh in glass_instance.find_children("*", "MeshInstance3D", true, false):
    mesh.material_override = palette_material
```

导入由church_kit_import.gd按manifest绑定材质。所有GLB `.import` 的UID由Godot生成，
带root_script=null、texture_map_mode=1、light_baking=1；shader和导入脚本的.uid一起保留。

## 审阅示例

只在隔离审阅脚本用套件拼约8×8m乡村小教堂：4张长椅、中央通道约1.21m、三级祭台、
可见木门、玫瑰窗/尖拱窗、风琴、花架、吊灯；没有迷宫。54个网格实例，68,504面/54surface。
默认图为360×800、43°、6.72m屏宽，参照人实测1.745m；另有全景、件表和换色对照。

示例脚本在 `tools/art/source/church_kit/`（.gdignore），只用于重现审阅图；
新套件不包含layout.json、spawn/exit/座位挂点或完整运行时场景，也没有注册新教堂。
审阅图和验证：`docs/design/church-kit-427-v11-2026-11-06/`。

新教堂要么把 cam_default 往房间中心收，要么在衬底草地上加花草和小路（照野外 v1.3）。
本次只为门的可见性将审阅镜头焦点移到(-0.70,1.30,-0.30)，未增加草地布景。

## 手机纹理导入与冷导入

隔离工程与主项目一致启用 `textures/vram_compression/import_etc2_astc=true`，
所有导入均让Godot实际写回。两张8×1色板刻意使用无损`compress/mode=0`、无mipmap、
`vram_texture=false`，Godot不会为它们写`imported_formats`；同一ctex可跨平台读取，
无需为满足字段而把八个色值转成有损块压缩。

`cold_import.py`清除隔离工程的.godot后导入两次：套件全部文件相对交付源无变化，
第二遍整个隔离工程（不含缓存）无变化。原分支poi_church图集的.import仍只有s3tc_bptc，
第一遍会在隔离副本补出etc2_astc；本次按要求不改已上线poi_church的文件。
该原目录后续如需统一导入元数据，应另行处理；本套件没有复制或覆盖它。
