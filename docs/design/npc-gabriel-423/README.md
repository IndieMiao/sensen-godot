# SGODOT-423 · Father Gabriel / Gabriel 神父

刘备，2026-11-07。只交 NPC 外观；对话、站位、名字条由哪吒接入。

```json
{"hairHat":"hairhat0","cloth":"cloth1_npc_gabriel","shoes":"shoes3"}
```

使用现成灰白短发 `hairhat0` 和黑靴 `shoes3`。Ivo 的头件含矿工帽，未选用。
衣服直接引用 cloth1 的原始 FBX，只复制并改色贴图，在原 UV 上改成近黑 `#2B2A2E`、白领
`#F4F1E8`、深灰袖口与下摆 `#39373D`。没有新增文字、十字或宗教符号。
**遵守不改网格：仍是 cloth1 原有短袖和短裤，不是新增长袍。**

衣服 1,629 三角形、一个 surface、59 个 skin binds；顶点、法线、UV、索引、权重、
原点与骨架均与 cloth1 相同，原始 FBX 未改、也未另存副本。材质参数照底件：rim 0、AO .3、diffuse 1、
emission .3、smoothness .1。原始贴图 1024²，导入上限 512²，保留 mipmaps。
新贴图用无损导入：SwiftShader 对 ETC2 采样把黑衣显著抬灰，无损对照恢复了近黑色。
不改 shader、不加采样或 pass；RGBA8 含 mip 的最坏预算约 1.33 MiB。

## 审阅图与检查

- [全身正面](gabriel-front.png)、[3/4](gabriel-three-quarter.png)、[背面](gabriel-back.png)，各 360×800。
- [Kai / Gabriel / Mei 并排](kai-gabriel-mei-lineup.png)：同骨架、scale 1、同镜头 2.02 m。
- [教堂 360×800](church-360x800.png)：#861 C 版 `4d9668c2` 的艺术装配预览；镜头 43° / 45°、宽 6.72 m，cam_default (0,1.4,-1)。Gabriel 临时摆在 423 评论 `3b31f242` 的 (-1.3,.54,-1.2)、yaw 180。未改正式 layout、导航、房间代码或 UI，这张不是接入后的游戏验收。
- [16 项导入检查](cloth-import-validation.json)：全部通过，含 NPC catalog 可用、玩家衣柜排除、材质与几何保留。
- [桌面实渲与 idle / walk](render-validation.json)：Godot 4.7.2 Vulkan Mobile / Deck RADV。
- [Android smoke](android-smoke.json)、[画面](android-front.png)：独立 APK / API 37 GFXStream SwiftShader；完整蒙皮、3 次真实点按、行走时间推进、APK 和打包 .res / 贴图回读一致。现成头发、黑鞋仍有模拟器偏亮色差；本检查不代表整机色彩一致或实体手机性能。
- 运行时资产冷导入与新件 UID 检查见 `cold-import.json`（5 个交付文件字节稳定，0 错误）。原始 authoring FBX 的历史外链贴图缺失诊断在完整源码导入中仍存在；配方明确绑定新贴图，原 FBX 单独通过结构审计，本次未改。复用的原始 `.fbx.import` 保留 `nodes/root_script=null`；贴图无损，缩略图用现有 `PartThumbnailer` 实渲。

## 程序交接：追加，保留已有注册表

本美术分支的基底 `5585f325` 只有 25 个基础部件，**没有运行时的 NPC 扩充表**。
因此 PR 在美术 manifest 追加一个条目，新 `npc_only.json` 仅列 Gabriel。
整合到 farm-dev 时，只追加 `cloth1_npc_gabriel` 到现有两个列表，不能整文件覆盖；
`outpost_npcs.json` 未改。测试夹具基于 farm-dev `8493a5c4`，保留已有 22 个 NPC-only
部件，加入 Gabriel 后为 23 个。

`assets/avatar/source/recipes_gabriel.json` 按 `recipes_284.json` 的 schema 新列独立配方。
`tools/art/extract_gabriel_423.gd` 复用现有提取器的单件处理，并保留所有旧条目；可用于
美术分支和运行时分支。不要在美术基底直接跑旧提取器：该版本不支持 `--append`。

## 可复现源

`tools/art/inspect_gabriel_423.py` 只读取 FBX 的 UV / 坐标；
`tools/art/recolor_gabriel_423.py` 按原 UV 生成贴图，不导出或修改几何。
`tools/art/source/gabriel_423/collar-trim-mask.png`：R 白领，G 袖口 / 下摆。
贴图及原始 FBX 哈希、alpha 保留记录在同目录 `texture-validation.json`。

```sh
blender --background --python tools/art/inspect_gabriel_423.py
python tools/art/recolor_gabriel_423.py
python tools/art/source/gabriel_423/stage_review.py
# 以下在打印出的隔离项目内，Godot 命令均持有 ~/gs66-render.lock。
godot --headless --path . --editor --import
godot --headless --path . --script res://tools/art/verify_gabriel_423.gd
godot --path . --script res://tools/art/review_gabriel_423.gd
```

## 头像已补齐

`assets/p0/art/residents/gabriel_card.jpg`（300×660，JPEG .92）已用居民头像流程开窗口烘出，
原舞台、光照、镜头、姿态与裁切算法保留。[头像 / 邮票 / 脸框审阅](portrait-review.png)。
`portrait_crops.json` 仅追加 `gabriel`：stamp `[68,47,170,213]`，face `[70,51,165,165]`；
原有 11 条保持原值与文本前缀。产出先在隔离项目的 `assets/p0/art/residents/` 下生成，
再取出 JPEG 和单条 crop 合并，未覆盖其他居民照片或 crop。

现版运行时的 P0Logic 引用图在 `--script` 过早编译时找不到 Avatar / Localization。
仅在临时烘焙副本中把 `P0Logic.content()` 改为延迟 `load(...).content()`，待 autoload 就绪后
读取内容；正式 `tools/art/bake_resident_portraits.gd` 字节不变。唯一行改动及脚本 SHA-256
见 [provenance](portrait-script-provenance.json)，产出核对见 [portrait-validation](portrait-validation.json)。
