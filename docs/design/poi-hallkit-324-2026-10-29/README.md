# SGODOT-324 公共大厅复用件包 v1

黄忠制作，2026-10-29。按上官婉儿本次派活，只交设计稿无关的 8 类复用件。上官婉儿技术检查；半成品随 N2 一起画面验收，进主线前须用户批准。本 PR 目标仅 `wp-3d-scene`。

命名增量（上官婉儿 `cfd38d5c`）：14 个导出 mesh 统一为 `<件名>_mobile`，玻璃与画心分别加 `_glass`、`_artwork`；节点 `Body / Glass / Artwork` 保留。此次 verify 的 212 项检查通过，GLB 二进制块和除 mesh 名外的 JSON 均与 `b56e9952` 一致，沿用原审阅图。见 [命名验证](SGODOT-324_HALLKIT_v1_mesh_naming_validation.json)。圆岛方形玻璃罩留待 N3 判断。

## 内容与状态

- `assets/rooms/_shared/shell_hall/`：8 类 / 10 个 GLB 变体，共 10,740 三角形、14 surface。画框有竖/横两款，展柜有长柜/圆岛两款，其余各一款。
- `tools/art/source/hallkit_324/hallkit_324.blend`：各 KIT 集合、逐个命名结构件、打包的临时色板。源文件里横向展开便于编辑；导出 GLB 均回到各自局部轴心。
- `tools/art/build_hallkit_324.py`：从原件具名 Blender 几何重建；修改前逐件核对原 GLB 实际顶点尺寸和三角形数。基线 `fadcaa195f5bb34229fba3995b27c5808ff34089`。
- 每件的来源记录在 `shell_hall/provenance/<件名>/reuse_provenance.json`，包括源 GLB / blend 哈希、源件尺寸、部件名称、改动、UV 色块归属。
- 单张 2048² `hallkit_palette.png`，颜色逐字取 Basic Room `PALETTE`；未带任何原房间图集。当前蓝/米白/鼠尾草色与抽象画心均为临时色块，不代表 Stark 新稿定色，也不属于 325 第二款皮肤。

台灯、拱窗、多格窗、课桌、搁架、公共大厅壳和工程接入不在本包。没有修改玩法、房间服务、地图入口、正式挂点、原件或其他人的分支。

## 比例与复用

尺寸以 GLB 解码顶点测量，单位米，Y 向上、+Z 向前。详细前后表见 [实测尺寸表](SGODOT-324_HALLKIT_v1_dimensions.md)，CSV 和署名 PNG 同名交付。

三人沙发在 Deluxe 原型上把两块坐垫改成三块；单人扶手椅截取一个座位并缩短基座/靠背，扶手厚度保留。沙发、扶手椅、长凳、圆凳实际座面均通过向下射线验证为 0.715 m（1 mm 容差）。长凳原缝线浮起一并压回座面下。桌面为 0.65H = 1.13425 m，展柜承台为 0.66H = 1.1517 m，H = 1.745 m。

圆桌比较了三件实测候选，选 `coffee_shop_0.round_table`：直径 1.10 m、240 面；另两件为 Bakery 1.30 m / 556 面、Tavern 1.58 m / 556 面。完整候选测量在 `table_candidates.json`。未从格宽或设计图推算。

两个画框保留框条和背板，移除旧立体画面，以单独 `Artwork` 节点的两三角面替代，画心 UV 占专用矩形色块。两个展柜复用 Bakery 曲面玻璃，罩高 0.60 m；补两端、背面与半径 9 mm 的细边框，圆岛版玻璃横向缩到 50%。罩内不含糕点或展品。

## 取用约定

1. 独立 GLB 可直接预览，均引用同目录的同一外部 PNG。所有 `.glb.import` 设置 `gltf/texture_map_mode=1`；图集启用 VRAM 压缩和 mipmaps。
2. 装配时将普通 `MeshInstance3D.material_override` 绑定 `hall_opaque.tres`；名为 `Glass` 的节点绑定 `hall_glass.tres` 并关闭投影。这是同一图集的透明例外，不是携带另一房间图集。审阅项目实际使用这两个共享材质。
3. 两个画框的 `Body` 与 `Artwork` 都用同一不透明材质；换画时只替换 `Artwork` 或重映射其 UV，不改框。`palette.json` 记录 glTF 坐标色块范围，留 32 px 边距。
4. 地面件最低顶点为 Y=0；挂墙件背面 Z=0、挂点中心 Y=0。`asset_stats.json` 的局部座位/灯位只作装配参考，正式 `seat_<组>_<n>` 等挂点由消费场景按规范命名。
5. 壁灯只带原件几何；房间局部灯由场景安排。图中暖光和灰白挂墙背板是审阅夹具，不计入包。正式 N2/N3 应按灯光预算接入。
6. 临时色板没有房间接触 AO。319 定大厅图集后需重新映射和对色；家具摆进正式房间后再处理接触 AO。本轮未把旧房间的阴影带过来。

## 验证与图片

`SGODOT-324_HALLKIT_v1_validation.json` 汇总 198 项独立 GLB 检查和 46 项实际 Godot 检查。内容包括：源哈希、面数、法线/绕序、退化面、实际尺寸、落地/挂墙轴心、UV 完整三角形落在同一色块、座面射线、长凳针脚贴面、可换画心、玻璃五向闭合、导入尺寸/节点及实际 Mobile 渲染器。

一字排列图含全部 8 类 / 10 变体和完整人物。人物使用 Basic Room 默认装扮，从当前姿态的实际顶点测得原高 1.718339 m，等比乘 1.015516 至 1.745 m，并按脚底落地。排列图正交俯角 20°、偏航 0°，用于同时比较物件；近景各自取景，保留同一人物比例。这些是复用件审阅图，不冒充正式房间 43° 游戏构图。

渲染为 Godot 4.7.2 / Vulkan Mobile / RTX 2060。首轮默认启动实际落在 Forward+，带条纹阴影，已弃用；最终命令显式指定 `--rendering-method mobile`，校验实际返回值。最终图使用交付的图集导入配置和共享材质。没有 Android 输入、实体手机性能、完整房间通行或正式画面验收结论。

媒体均以 `SGODOT-324_HALLKIT_v1_` 命名并署黄忠；`media-manifest.json` 记录 PNG/CSV/Markdown/JSON 的 SHA-256。Plane 324 评论和附件均使用黄忠虚拟身份。

## 复现

在仓库根目录，Blender 5.2.2、Godot 4.7.2，Python 需 NumPy / Pillow。每次渲染前检查共享 GPU；以下命令依次执行。所有 Godot 进程使用 5097，脚本结束自动退出；不连接模拟器或真机。

```bash
source ~/.codex-huangzhong/env.sh
blender --background --factory-startup --threads 2 --python "$PWD/tools/art/build_hallkit_324.py"
python3 tools/art/prepare_hallkit_324.py
godot --headless --path output/hallkit-324/project --editor --import --rendering-method mobile
output/art-setup/venv/bin/python tools/art/verify_hallkit_324.py
nvidia-smi
godot --path output/hallkit-324/project --rendering-method mobile --rendering-driver vulkan --max-fps 30
output/art-setup/venv/bin/python tools/art/package_hallkit_324.py
```

`output/` 与 `tools/art/source/` 保持 `.gdignore`。生成脚本会覆盖本任务的生成源和资产；手工修改源后须同步脚本再重建。不会打开原游戏或读取玩家存档。
