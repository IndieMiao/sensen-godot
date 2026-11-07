# Gabriel NPC 专用深色鞋 · SGODOT-444 · v1.4

刘备，2026-11-07。新部件 `shoes3_npc_gabriel` 使用 shoes3 的原网格，把浅蓝色区域涂成鞋面同色的深灰黑。
共用 shoes3 的 FBX、PNG、`.import`、运行时部件均未修改，其他 NPC 保留原鞋。

```json
{"hairHat":"hairhat0_npc_gabriel","cloth":"cloth36_npc_gabriel","shoes":"shoes3_npc_gabriel","glass":"glass0"}
```

## 审阅图

- [45° 鞋部近景前后对照](shoe-closeup-comparison.png)、[新鞋近景原图](shoes3_npc_gabriel-feet.png)。
- [360×800 全身](shoes3_npc_gabriel-full.png)。
- [重烘卡图、132×132 头像及 44×44 显示预览](portraits-review.png)、[44×44 原图](head-44.png)。

Vulkan Mobile / Deck RADV，居民头像原光照，scale 1、idle 第 0 帧，同机位比较。
**浅蓝色已去掉；原模型的小星星有凸起几何，近景仍有深色轮廓阴影。**本次只改贴图，未去掉这部分几何。

## 新部件与材质

来源为 farm-dev `594a953b87cc42a6cd1a99a3034b6fd14a5c5aef` 的 shoes3，与本分支 donor 逐字节一致。
FBX 完整照抄，SHA-256 `fc8ea72a89c6f0d9b53842c066963af64fd0a3c617c3ed43f5c282ca596c5310`。
提取后的鞋为 1,202 三角形、1 surface、6 skin binds；顶点、法线、UV、索引、权重、包围盒和 bind pose 均与原鞋一致。

新目录 `assets/avatar/source/shoes3_npc_gabriel/` 只有 FBX、新 PNG 和各自 `.import`，没有额外贴图或别名。
原 PNG 为 512²，浅蓝色及抗锯齿边缘实测占 10.8624%，改为 RGB (58–60, 57–59, 57–59)。
区域以外的像素与全部 alpha 逐值不变，见 [贴图验证](texture-validation.json)。
新纹理沿用 shoes3 的全部 `[params]`：`compress/mode=2`、512² 上限、mipmaps，Godot 生成 s3tc_bptc / etc2_astc。
FBX 导入参数也与 donor 相同，有独立合法 UID 和 `nodes/root_script=null`。

材质继续用原 shader，rim=0、AO=0.54、diffuse=1、emission=0.45、smoothness=0.1；只绑定新 albedo，不加采样或 pass。
`parts/shoes3_npc_gabriel.res`、实渲缩略图和导入文件已齐，recipes_gabriel / parts_manifest / npc_only 各追加一条。
NPC 目录可加载，玩家鞋柜池排除新鞋，原 shoes3 仍可正常使用。

## 头像和接入

用新 slots 开窗口运行现有居民头像 baker，在隔离项目 `assets/p0/art/residents/` 下重烘，再同步：

- `keepers/gabriel_card.jpg`：300×660，与 residents 卡字节相同。
- `keepers/gabriel_head.jpg`：132×132，从新卡 `[70,51,165,165]` 裁切，LANCZOS、JPEG quality 95，无色度抽样。
- `residents/gabriel_card.jpg`：300×660。

三张头像 `.import` 的原 UID、mode=0、无 mipmaps 均保留。新烘焙的 stamp/face 框与原 crop 表完全一致，不改 crop 表。
衣服、头发保持已通过的贴图和 mode=2 导入。首次接入需追加 Gabriel 衣服、头发、鞋三条注册，
保留运行时现有其他 NPC；已有衣服/头发时只追加新鞋，覆盖三张头像并更新 Gabriel 的 shoes slot。

## 冷导入与已知来源报文

[验证记录](validation.json)、[结构检查](structure-validation.json)、[冷导入报文原文](cold-import-source-warnings.txt)。
独立空缓存冷导入前后，18 个交付文件哈希一致、0 个被跟踪文件被导入改写；17 项鞋部件检查全部通过，
三张头像实际加载尺寸和无 mipmaps 通过。

按上官婉儿本轮明确要求：FBX 逐字节照抄，不修贴图路径、不加贴图别名。原 FBX 引用的四张不用的全身材质图
`T_skin02_eyes_D.png`、`T_skin02_body_D.png`、`T_skin03_cloth_D.png`、`T_skin03_hair_D.png` 缺失，冷导入仍有 4 条 FBX WARNING。
引擎同时为每张输出 2 条 ResourceLoader / FileAccess ERROR，共 8 条；原文全部保留，不称为“零错误导入”。
这些来源材质不进入提取后的运行时鞋，运行时 albedo 由 recipe 明确绑定，冷缓存加载与实渲已验证。
本轮没有新增 Android 或实体手机性能结论。

## 复现

```sh
python tools/art/recolor_gabriel_shoes_444.py
python tools/art/source/gabriel_423/stage_review.py
# 在输出的隔离项目中，Godot 持有 ~/gs66-render.lock：
godot --headless --path . --editor --import
godot --headless --path . --script res://tools/art/extract_gabriel_423.gd -- --only=shoes3_npc_gabriel
```

复制本目录 `verify_shoes.gd` / `review_shoes.gd` 到隔离项目的 tools/art 后运行；review 必须开窗口，并生成实渲缩略图。
再用 `tools/art/bake_resident_portraits.gd` 和 staging 输出的 `output/gabriel-looks.json` 重烘。
临时 baker 仍仅沿用 v1.1 记录的 P0Logic 延迟加载适配，正式 baker、灯光和构图算法不改。
