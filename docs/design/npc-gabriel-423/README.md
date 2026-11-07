# SGODOT-423 · Gabriel 神父 / Father Gabriel · v1.1

**最新 v1.4 / SGODOT-444：**[NPC 专用深色鞋 shoes3_npc_gabriel、三张重烘头像](../npc-gabriel-444/dark-shoes-v1.4/README.md)。
衣服保留 [v1.2 前领片与前襟贴图](v1.2/README.md)；以下保留 v1.1 交付记录。

**部件压缩补正：**衣服、头发两份 `.import` 已按各自 donor 改为 `compress/mode=2`，
由 Godot 写回 `s3tc_bptc` / `etc2_astc`；原 UID、512² 上限、mipmaps 保留。
重建脚本也改为继承 donor 参数。两张 PNG 与 keeper 头像不变，keeper 仍为无损、无 mipmap。
[验证记录](vram-import-validation.json)：两张纹理及导入文件共四文件在独立空缓存冷导入后
哈希一致；实际加载为 512² 压缩纹理且含 mipmaps。已有审阅图和 Android 冒烟是压缩补正前的记录。

刘备，2026-11-07。本版替换已退回的短袖短裤方案；供 #863 审阅，程序接入只对话的 NPC。

```json
{"hairHat":"hairhat0_npc_gabriel","cloth":"cloth36_npc_gabriel","shoes":"shoes3_npc_gabriel","glass":"glass0"}
```

实拍比较了 cloth36、cloth1_1、cloth28：cloth1_1 仍是短袖短裤；cloth28 是卷袖制服，
带腰部器具；cloth36 是完整长袖外套、长裤，选它作为黑色神父服的底件。
保留现成西装外形，没有重建长袍或修改网格。原白衬衫、红领带、金纽扣统一改近黑，
领口留白色带，袖口与下摆用深灰。没有文字、十字或新增宗教符号。

短发采用 hairhat0 的暖白贴图变体，保留阴影层次；不加胡子。
glass0 是现成圆框透明眼镜，镜框和挂点不改；鞋现已改用 shoes3_npc_gabriel，见最新交付。

## 审阅图

- [v1 → v1.1 同机位](v1.1/before-after.png)。v1 仅作为已退回的对照。
- [正面 / 3/4 / 背面](v1.1/full-body-review.png)：每列 360×800，真实 Godot Vulkan Mobile，未缩放角色。
- [Kai / Gabriel / Mei](kai-gabriel-mei-lineup.png)：同骨架、scale 1、镜头 2.02 m。
- [教堂 360×800](church-360x800.png)：#861 C `4d9668c2` 艺术装配预览；镜头俯角 43° / 水平 45°、宽 6.72 m，焦点 (0,1.4,-1)。Gabriel 在 423 评论 `3b31f242` 指定的 (-1.3,.54,-1.2)、yaw 180。站位未变；本图不含正式玩法/UI 接入。
- [新头像 / 邮票 / 脸框](portrait-review.png)：居民头像烘焙流程开窗口重烘。

## 网格、材质、导入

衣服 3,192 三角形、1 surface、38 skin binds。顶点、法线、UV、索引、权重、包围盒及
所有 bind pose 与 `cloth36_npc_sigrid` 完全相同。头发网格、层级、transform、socket offset
与 hairhat0 一致。材质浮点参数沿用各自 donor，shader、采样次数、pass 均未改：

| 参数 | cloth36 | hairhat0 |
|---|---:|---:|
| rim_strength | 0 | 0 |
| ao_strength | 0.1 | 0.5 |
| diffuse_strength | 1 | 1 |
| emission_strength | 0.3 | 0.6 |
| smoothness | 0.1 | 0.1 |

贴图为原 UV 上的确定性改色：近黑 #2B2A2E，白领 #F4F1E8，收边 #39373D；
头发基色约 #E7E5DF。衣服和头发源图均 1024²，运行时上限 512²、mipmaps、显存压缩导入，
源图 alpha 不变；各自替换 donor 原采样。

`cloth36` 源 FBX 在美术基底缺失，因此此 PR 带其副本。仅修复其中 17 条源贴图路径，
解决 donor FBX 的失效外链；没有改 mesh/UV/蒙皮/骨架数据。原文件及交付哈希、路径差异见
[FBX provenance](../../../tools/art/source/gabriel_423/fbx-provenance.json)。未使用的 donor
body/eyes/shoes 子网格不会提取，实际 cloth 材质由配方绑定。场景 `.import` 有合法 UID、
`nodes/root_script=null`；两件缩略图由现有 PartThumbnailer 实渲。

- [29 项结构检查](cloth-import-validation.json)：全部通过；包含两件 NPC-only 排除和旧短装 ID 移除。
- [桌面实渲 / idle、walk](render-validation.json)：Vulkan Mobile / Deck RADV；两种动作骨骼变化通过。
- [冷导入](cold-import.json)：空 `.godot`，15 个交付文件字节稳定、0 错误、6 个合法唯一 UID。包括新 cloth36 FBX、运行时 .res/.tscn、贴图、缩略图、头像；排除其他历史 authoring FBX。
- [Android smoke](android-smoke.json)、[正面](android-front.png)：独立 API 37 / GFXStream SwiftShader 夹具，完整显示、3 次真实点按、walk 时间推进、APK 与部件/贴图回读。既有皮肤、眼镜和鞋仍有模拟器偏亮色差；该次黑衣/白发使用补正前的无损导入设置。模拟器检查不代表实体手机性能或整游戏验收。

## 程序交接

旧 `cloth1_npc_gabriel` 已从本 PR 删除。请同步更新 outpost NPC 的四个 slots（含 glass），
向运行时现有 manifest / npc_only **追加这两件**，保留所有其他 NPC，不能整文件覆盖。
美术基底保留原 29 条 manifest；运行时夹具使用 farm-dev `8493a5c4`，原 22 件 NPC-only
保留，加入两件后为 24。注册表只更新 Gabriel；outpost_npcs、导航、任务及对话代码不在本 PR。

配方 `assets/avatar/source/recipes_gabriel.json` 沿用 recipes_284 的 schema。
`tools/art/extract_gabriel_423.gd` 安全替换 Gabriel 两条，保留其他 ID。不要直接使用美术基底
旧提取器覆盖全表，它不支持 `--append`。

## 头像与复现

`assets/p0/art/residents/gabriel_card.jpg` 在该规定路径下开窗口生成，300×660；
`portrait_crops.json` 的 Gabriel 数值本次未变：stamp `[68,47,170,213]`、face `[70,51,165,165]`。
保留其他 11 条及整个裁切文件原字节；头像像素已换为长袖、白发、眼镜。

临时 baker 仅把 `P0Logic.content()` 延迟 load，适配 autoload 编译顺序；正式 baker、
镜头、光照、姿态、裁切算法未改。见 [provenance](portrait-script-provenance.json) 和
[portrait-validation](portrait-validation.json)。

```sh
python tools/art/source/gabriel_423/repath_fbx.py
blender --background --python tools/art/inspect_gabriel_423.py
python tools/art/recolor_gabriel_423.py
python tools/art/source/gabriel_423/stage_review.py
# 在输出的隔离项目，Godot 工作持有 ~/gs66-render.lock：
godot --headless --path . --editor --import
godot --headless --path . --script res://tools/art/extract_gabriel_423.gd
godot --headless --path . --script res://tools/art/verify_gabriel_423.gd
godot --path . --script res://tools/art/review_gabriel_423.gd
godot --path . --script res://tools/art/bake_resident_portraits.gd -- --looks=output/gabriel-looks.json --ids=gabriel --out=assets/p0/art/residents
```

重烘脚本会覆盖临时裁切表，只把 Gabriel 单条合回正式表。源掩码 R=白领、G=收边；
`texture-validation.json` 记录色值、alpha 与交付 FBX 哈希。
