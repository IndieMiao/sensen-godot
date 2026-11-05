# SGODOT-424 · Alcatraz Island · v2 实尺白模

作者：马可波罗。按用户 2026-11-05 22:22 确定的 B 恶魔岛和上官婉儿 v2 尺寸制作。只提交白模／布局；细节、植被和正式配色等白模双审通过后继续，最终交付约 11-10。

最新审阅材料：[`docs/design/alcatraz-blockout-424-2026-11-05/v2/`](../../../../docs/design/alcatraz-blockout-424-2026-11-05/v2/README.md)。v1 小场景已经被 v2 尺寸取代，历史源可从 `d93763c3` 恢复。

## 参考与尺寸

实际参考为 `reference/landmark_alcatraz_v2.jpg`、`c_alc2.png` 和随附 `alc2_phone.png`，哈希见 `reference/provenance.json`。生图只提供构图关系，文字实尺优先。

| 对象 | 制作尺寸 |
| --- | --- |
| 岛体加码头外接范围 | 60 m 东西 ×40 m 南北，渡轮另在岸外 |
| 主楼／游客中心 | 40 m 长、10 m 深、两层共 9 m 高，门框略凸出立面 |
| 灯塔／水塔 | 地面至最高点 15 m／12 m |
| 渡轮 | 长 25 m，停在码头侧；无交互 |
| 四段台阶 | 每段 15 级，每级 0.15 m，踏步深 0.30 m，宽 3 m |
| 长椅 | 长 1.5 m，源模型座面高 0.45 m |
| 步道栏杆／路灯 | 源模型栏杆高 1.0 m／路灯总高 3.5 m |
| 角色 | 沿用农场 Avatar、scale=1；名义 1.75 m，默认服装网格包围盒实测约 1.740 m |
| 近景镜头 | 任务指定宽 6.72 m；复用 FarmCamera 的 43°／14.5° 投影方向 |

从码头 +1 m，经 +3.25、+5.5、+7.75 m 台地，到 +10 m 主楼前。导航实际行走约 119 m；路径中心线是制作布局线，不能代替 NavigationServer 实测距离。铺装比花园明亮，花园不可走，四段台阶边缘设栏杆。

## 可编辑源与区块

- `alcatraz_blockout.blend` 保留命名构件、模块 collection 和按区块组织的实际实例；`build.py` 确定性重建并导出，完整重跑会覆盖源文件。
- Godot 米制、Y 向上、北为 -Z；Blender 坐标 `(x, -z, y)`。建筑与家具以本地地面中心为原点；地形、道路、台阶、栏杆使用公共岛体原点。
- `DockZone`、`TerraceZone`、`SummitZone` 各是一个独立 Node3D，拥有本区模型、碰撞和 NavigationRegion3D；三者连接同一私有导航地图，供后续分批加载接入。当前一次加载全岛。
- `DistantScenery` 是另一个 World3D／SubViewport：橙红金门大桥和城市天际线按假透视布置。近景海面的顶部过渡显露远景，岛上实体仍按正常深度遮挡；桥不是岛旁的缩小实体。俯视与全岛尺度审阅关闭此远景层，避免把它解释成岛体坐标。
- `spawn`、`exit`、`cam0` 在 `layout.json`；对应 Marker3D 在 DockZone。Map 门图标与名字条靠码头左侧，避开出生角色。渡轮及海鸟无碰撞交互。

近景保持角色与镜头比例，只为开场取景向前偏移 2.8 m，使角色处于下方并看见广场／第一段台阶。拖动自由查看，下一次走路或 Follow 恢复跟随，保留缩放。所有调整仅限这个新场景，未改共享玩法、农场镜头或地图入口注册。

大岛导航超过 Godot 默认每次 4096 个多边形的搜索上限。`find_path()` 使用本岛导航多边形数加少量余量作为上限，检查实际到达目标，防止把提前截断的路径当成成功。导航格边缘收缩 0.25 m，连续坡面跨越 0.15 m 的视觉台阶；铺装、台阶及木板下连续底板有实际碰撞。

## 重建与检查

```sh
flock ~/gs66-render.lock blender --background --factory-startup --threads 3 --python-exit-code 1 --python "$PWD/tools/art/source/alcatraz_island/build.py"
bash tools/art/source/alcatraz_island/review.sh
python3 tools/art/source/alcatraz_island/package_review.py
```

先等待 Blender 完成，再运行检查。实渲使用当前合法的 `DISPLAY`／`XAUTHORITY`，不要复用过期会话路径。所有 Blender／Godot 操作使用同一共享锁并自动退出。源目录 `.gdignore` 避免 Blender 源和参考图被游戏自动导入。

`prepare.py` 建立 `output/alcatraz-424/project` 最小隔离项目，仅 Avatar autoload、独立用户目录，无 Net 自动登录。新 `.import`／UID 由 Godot 生成并回收；只清理本套件已退役的导出件。v2 日志与原始截图保存在 `output/alcatraz-424/v2/`。

`review.gd` 运行真实 Vulkan Mobile 场景，走到半山及主楼，测量完整路径、角色高度、所有导航格地面碰撞、三个加载区块、镜头／手势、Map 请求、远景桥像素以及含角色／远景的面数与 surface。它是桌面程序化回归，不是 Android 实际输入或真机性能验证。`package_review.py` 核对实尺与被测文件字节，保留原始近景图，仅给俯视图添加明确标识的路径／尺寸注释。
