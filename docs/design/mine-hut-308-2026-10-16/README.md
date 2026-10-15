# SGODOT-308 · Ivo 的矿口小屋

刘备制作；上官婉儿技术检查、不知火舞画面验收，用户批准后合并。目标分支 `wp-3d-scene`。本包依据 Stark 原图、不知火舞标注和《SGODOT-218 3D 制作清单 v1.1》的 308 节与共同要求制作。

## 交付

- 新套件：`assets/rooms/mine_hut/`；地台 6.8 × 6.4 m，地面顶面 Y=0.082 m；Y 向上、+Z 向前，真实米制，导入 scale 1。
- 65,722 三角面、43 个 GLB / 43 个 surface，单张 2048² `room_albedo_ao.png`；每件一个合并 mesh、一个 surface。43 个材质槽共用同一图集；发光提灯和炉炭由场景覆盖材质。面数不含审阅角色及阴影重复绘制。
- 编辑源：`tools/art/source/mine_hut/mine_hut.blend`，分 KIT 集合、命名部件；`reuse_provenance.json` 列出复用来源、缩放、移除的旧内容和依赖版本。
- 独立艺术场景：`scenes/mine_hut/mine_hut_art.tscn`，只装配房间、碰撞和局部灯。没有账号、存档或网络依赖。
- 新墙体、木板地面、岩石矿口、交叉木撑、铁轨与载石矿车；两条盐烤鱼的金属炉；四盏提灯；分拣台、铜锈绿石、石英、料箱；镐加短斧、线条坑道图、盘绳、平底锅、蒜和干草；毛皮毯、麻袋、石阶和无字交叉镐招牌。

## 复用与取舍

- 复用 blacksmith_shop 的 `back_tool_bench`、`metal_ingot_crate`、`left_floor_crate`、`quench_barrel`、`forge_stool`、`stump`、`forge_lantern`、`lantern_glow`、`right_wall_shelf` 的具名 Blender 部件；换色后统一烘入新图集。新做的 `room_shell` 不来自旧套件。
- 木桶原件 5,528 面，煤桶原件 7,400 面，因此选择木桶，去掉水面后装石块；原石锭箱移除旧内容。工作台横向放大 1.16 倍、深度 1.07 倍以容纳三格料盒；仍保留原件各命名部件。
- 墙挂安全帽直接使用 farm-dev `ef70f8052cf547407eaa09fd881839bf2df929e3` 的 `hairhat_npc_ivo_scene.tscn` 网格及贴图，只移到挂墙轴心，另加小挂钩。验证包含原网格全部顶点的对应检查，不能用相似帽替代。
- 保留参考稿橘棕木色、暖米色墙；矿石采用矿口参考中的灰绿，增加不知火舞指定的铜锈绿。四盏灯和烤台局部光为暖橘，环境和主光降低暖色强度。代表色块的实测色相差见 `colour-validation.json`；亮度、饱和度与完整画面仍交美术验收。
- 可读性与真实尺寸优先：360×800、43° / yaw 45°、6.72 m 的游戏取景保持比例，边缘会裁切。另交 12.4 m 全景（360 宽和 1200×1000），不以缩小模型冒充完整游戏取景。

## 接入建议

仅 `npc_ivo` 和出口可点；矿口和炉子为布景。矿口有独立实体阻挡，不能进入。下列世界坐标已写入 `layout.json.suggested_anchors`，场景提供 `suggested_*` Marker3D。正式 `mine_hut.anchors.json` 仍由程序编写。

| 建议挂点 | 世界坐标 X, Y, Z（米） | 朝向 |
|---|---|---|
| npc_ivo | 1.40, 0.082, −0.84 | yaw 45°，面向镜头 |
| stand_ivo | 0.80, 0.082, 0.05 | 0° |
| spawn | 0, 0.082, 2.55 | 0° |
| exit | 0, 0.082, 3.08 | 0° |
| badge_exit | 0, 0.70, 3.08 | 0° |

Ivo 审阅造型：`hairhat_npc_ivo + mask16_npc_ivo + cloth1_npc_ivo + shoes3`。名字条预留盒中心 `(1.40, 2.18, −0.84)`，尺寸 `1.0 × 0.55 × 0.65 m`，已检查不被房间网格占据。

## 验证与图

`validation.json` 汇总实际 GLB、Godot 导入、物理碰撞及色块结果；`media-manifest.json` 记录交付图尺寸和 SHA-256。

- 实际导入面数、surface、尺寸、UV 范围和 2048² 图集；每个 GLB 的 `.import` 都为 `gltf/texture_map_mode=1`。
- 全部道具两两实际三角面交叠检查，含主动制造穿插的阳性对照。墙柱与地基、岩石与墙洞、小挂钩等装配接触逐项记录；道具无未说明的穿插。提灯、凳子和料盒用实际网格向下射线量支撑间隙，≤1 mm 且不贯入。
- 每个 UV 顶点和三角形中心不采到空黑图集。补色只扩展原先空黑 texel；已烘焙像素不改。
- Godot 使用半径 0.25 m、总高 1.745 m 的胶囊体实际扫掠，矿口先撞到独立阻挡；出生点至中央、Ivo 接近区和出口接近区通过。
- Vulkan Mobile / AMD Custom GPU 0405（RADV VANGOGH）窗口渲染。当前没有连接的 Android 测试目标；此包不声称 Android 输入、实体手机性能或整合后的完整游戏验收。

审阅图均带 `SGODOT-308 / LIU BEI` 署名，前缀 `SGODOT-308_MINEHUT_v1_`：游戏默认取景、完整全景、矿道口、分拣台、Ivo 站位；另附 360 宽全景、Ivo 低视角、烤炉近景、俯视和参考对照。

## 复现

仓库依赖须包含上述 farm-dev 提交；工具版本 Blender 5.2.2 LTS、Godot 4.7.2。`output/` 与 Blender 源目录保持 `.gdignore`。顺序执行：

```bash
python tools/art/prepare_mine_hut_308.py --helmet
blender -b --factory-startup --python tools/art/build_mine_hut_308.py
python tools/art/prepare_mine_hut_308.py
blender -b --factory-startup --python tools/art/verify_mine_hut_308.py
godot --headless --path output/minehut-308/project --editor --import
godot --path output/minehut-308/project
python tools/art/package_mine_hut_308.py
```

最后两步需要真实窗口环境、Pillow / NumPy。审阅脚本通过 SubViewport 生成准确分辨率，导入与碰撞验证保存在独立的 `output/minehut-308/`；不使用生产存档。
