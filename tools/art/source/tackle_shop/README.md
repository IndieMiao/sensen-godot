# SGODOT-214 渔具铺可编辑源文件

赵云 · 2026-10-16。

依据是上官婉儿提供的 Stark `2681:135486` 原图、不知火舞标注、
SGODOT-218 清单 v1.1 的共同要求/214，以及已通过的鱼竿架 v1 规格。
完整提供件保存在 [reference](reference/)。本次通过本地原图制作，未宣称重新访问 Figma。

`tackle_shop.blend` 的当前 v1.1 保留 38 个命名 `KIT_*` 集合、936 个网格零件，模型使用
Godot 米制 Y-up、前向 +Z，Blender 坐标为 `(x,-z,y)`。柜台、渔情板、
鱼竿架、浮漂桶、鱼缸、渔网、舷窗等均可分别编辑。人物不属于资产；空节点
只记录建议位置。唯一复用实例是第二只浮漂桶。

```sh
source ~/.codex-zhaoyun/env.sh
blender --background --factory-startup --threads 6 --python-exit-code 1 \
  --python "$PWD/tools/art/build_tackle_shop.py"
```

脚本会重新生成并覆盖此 blend、运行时 GLB、layout、统计和 2048² 图集。
仅检查模型可在末尾加 `-- --geometry-only`。手工修改应先同步到生成脚本再重建。

房间复用现有 `scene_room_pipeline.py` 的 AO 烘焙和局部 pivot 导出流程，
未改动公共工具。地毯编织、白环和锚是原创数学绘制，保留为 blend 内的源图，
烘入房间图集；没有木纹照片、直接光烘焙或描边材质。

`finalize_tackle_atlas.py`（系统 Python 3 + Pillow）把烘焙区域留在图集上方
2048×1920 内，下方用带 32 px 保护边的 64 px 色块供细网绳、竿身、植物等采样。
颜色由命名源零件逐顶点传递，保留同一张 2048² 图集；避免细长 UV 岛产生黑边。

植物网格取自共享植物库的 `pothos` / `peace_lily` 可编辑源文件，按本房间尺度、
原图绿色和陶盆色适配并烘入同一图集。绿萝下垂枝沿货架前沿展开，避免穿过层板。
共享库文件未修改；所有这些小植物关闭运行时投影。

运行时通过 `scenes/tackle_shop/tackle_shop_art.tscn` 按 layout 装配模型、全部碰撞体和
三盏局部灯。每个 GLB surface 自带不透明 / 玻璃材质及同一外部图集引用，场景不覆盖它们；
`material_import.gd` 只校准每个 surface 的 specular=0.28。原始 GLB 不重复嵌入贴图。
所有 GLB 的 `.import` 包含 `gltf/texture_map_mode=1`。
最新审阅与验证记录见 [v1.1 交付目录](../../../../docs/design/tackle-shop-214-v1.1-2026-10-16/README.md)。

2026-10-16 灯光补正：运行时壁灯、吊灯改用朝墙面 / 台面的软边 SpotLight3D，
台上提灯仍用 OmniLight3D。参数在生成脚本的 `local_lights` 与导出的 layout 中；
这些运行时灯由 Godot 装配创建，不属于 Blender 源几何，也未烘进图集。
本轮 blend、GLB 和图集均与已通过 v1.1 字节一致，复现开关图见
[灯光补正交付](../../../../docs/design/tackle-shop-214-lighting-2026-10-16/README.md)。
