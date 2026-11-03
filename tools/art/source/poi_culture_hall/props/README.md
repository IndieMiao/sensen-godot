# SGODOT-323 N3 新做件

【黄忠】按 318 R3 主图和上官婉儿的实尺寸规格制作。17 个独立 GLB、18 次摆放。
只交 `assets/rooms/poi_culture_hall/props/`，不改整间 layout 或赵云的场景。

`culture_props.blend` 保留 17 个 KIT 集合，每组一个局部根及命名部件。
玻璃罩五片玻璃保持可编辑，导出合为单一玻璃 surface；原点为底面中心，挂墙画框/招牌为背面中心。
单位米，Godot Y 向上，+Z 朝前；mesh 名统一 `<件名>_mobile`。
全部原创几何与色块，参考归档在 `reference/`，每件 provenance 在 `modules/`。
不含真实作品、文字或宗教物件。

## 组装交接

- `display_cabinet.glb` 摆两次：实例 ID `glass_case_1`、`glass_case_2`；占地 0.95 × 1.80 m，总高 1.50 m。
- 柜内**实际陈列面 y=1.00 m**，不是白模的 1.04 m。三个展品 local z 为 -0.55 / 0 / 0.55，左右均居中。
- `exhibit_plinth.glb` 的陈列面 **y=1.10 m**，不是白模的 1.15 m。菊石 `plinth_exhibit` 放在台面中心。
- `prop_manifest.json` 的 `display_assignment` 列明每件展品的容器、槽位、原白模实例名及容器局部坐标。容器的整间坐标/朝向由赵云按已批白模保留。
- 六画每幅 0.70 × 0.55 m，`gallery_offset` 给两排三列的组内坐标，整组宽 2.40 m、高 1.25 m。
- `floor_mosaic` 直径 1.94 m、厚 0.008 m，不带碰撞，导入时关投影。
- `name_sign` 可写区 1.24 × 0.28 m，空节点 `sign_door` 位于正面中心，metadata 带 size/module；画面留空运行时写字。
- 新件不新增 seat、NPC 或交互挂点。后墙前 2 m 净空和整间碰撞/导航由场景执行人验证。

玻璃独立 surface，alpha=0.16，双面、低反光；其余是粗糙度 0.9 的哑光顶点色，无贴图。
全部 `.glb.import` 有独立 UID、`gltf/texture_map_mode=1`，挂同目录 `material_import.gd`（含 UID），启用线性顶点色并保留独立玻璃材质。

## 复现与检查

```bash
source ~/.codex-huangzhong/env.sh
blender --background --python tools/art/source/poi_culture_hall/props/build_props.py
blender --background --python tools/art/source/poi_culture_hall/props/verify_source.py
output/art-setup/venv/bin/python tools/art/source/poi_culture_hall/props/prepare_review.py
godot --headless --path output/culture-props-323/project --editor --import
godot --headless --path output/culture-props-323/project --script res://configure_imports.gd -- "$PWD"
output/art-setup/venv/bin/python tools/art/source/poi_culture_hall/props/verify.py
nvidia-smi
godot --path output/culture-props-323/project --rendering-method mobile --rendering-driver vulkan
output/art-setup/venv/bin/python tools/art/source/poi_culture_hall/props/package_review.py
```

只导入隔离工程，私有 ADB 5097，审阅完成自动退出。`verify.py` 独立读取 GLB 顶点和索引，
检查面数、尺寸、原点、单位变换、画面法线、玻璃 surface、展品落地与不穿插、画墙宽度及 UID。
`review.gd` 再量 Godot 实际导入网格并用真实玩家 H=1.745 m 出图。
白底比例摆件台仅作尺度审阅，不是已组装的 N3 整间。
