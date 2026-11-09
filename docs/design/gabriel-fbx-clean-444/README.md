# SGODOT-444 · Gabriel 深色鞋 FBX 缺图引用清理

刘备，2026-11-09。只修 `assets/avatar/source/shoes3_npc_gabriel/SK_dt_skin03.fbx` 的无用全身材质/贴图对象，消除每次无缓存导入时的8行ERROR。鞋子外观、绑定和运行时部件不变。

## 改前 / 改后

| 独立无缓存项目 | ERROR行数 | FBX WARNING行数 |
|---|---:|---:|
| Gabriel 修复前 | 8 | 4 |
| Gabriel 修复后 | **0** | **0** |
| 原版共享 shoes3（仅验证，未修改） | 8 | 4 |

原文：[修复前日志](before-import.log)、[修复后日志](after-import.log)、[共享原版日志](shared-original-import.log)。每个项目只包含目标FBX、它的鞋贴图及原`.import`，从空`.godot`开始，使用Godot4.7.2内置FBX导入器和Mobile设置。计数取行首`ERROR:`/`WARNING:`，不把引擎正常退出误当作无错误。日志仅去除ANSI颜色控制码和末尾空行，错误文本原样保留。

修复前每张缺图对应一条`Resource file not found: res:// (expected type: Texture2D)`、一条`Can't open file from path ...`及一条FBX跳过图片WARNING。四张为`T_skin02_body_D.png`、`T_skin02_eyes_D.png`、`T_skin03_cloth_D.png`、`T_skin03_hair_D.png`。

## 源文件处理

源FBX来自本分支基线`6151fef82a16e822367ee076dacc5eef85c19002`；已核对与当前farm-dev `457ac28b968a89bf4b004a9c6b409856bd06fe27`的同路径文件逐字节一致，源SHA256为`fc8ea72a89c6f0d9b53842c066963af64fd0a3c617c3ed43f5c282ca596c5310`。

该源文件实际上包含eyes/body/cloth/shoes/hairHat五网格，recipe只提取`shoes`。从FBX源文档重新导出时移除四个非鞋材质（eyes_mat/body_mat/cloth_mat/hairHat_mat）、对应四个Texture和四个Video对象及12条相关连接，更新Definitions计数、节点偏移及文件尾部的对齐零字节。最终只保留鞋材质 **shoes_mat** 和 **T_skin03_shoes_D.png**。非鞋网格仍保留原数据，但已不带那四个无用材质；它们不进入Gabriel运行时部件。

[导出脚本](../../../tools/art/source/gabriel_fbx_444/export_clean_fbx.py)直接读取FBX 7500源文档，保留所有存留节点的原始属性字节，包括压缩数组；未走Blender重新计算坐标/骨骼的导入导出流程。未编辑原文件的往返序列化逐字节相同；清理后的636个存留对象属性逐字节相同，包括5个Geometry、68个Model、63个NodeAttribute、89个Deformer、5个Pose和所有动画数据。没有复制贴图别名或修改路径来掩盖缺图。

[源数据审计](source-audit.json)列出删除对象、连接、前后SHA及保留项。新FBX SHA256：`42afc8efdd1909af71cbebfc555085b2f87be36a668a01814c18a36681f55164`。

## 独立导入与实渲核对

用Godot实际加载两次冷导入后的PackedScene，独立检查：

- 五个网格的顶点、法线、UV、索引、骨骼索引、权重数组及变换、包围盒逐值一致。
- 鞋子仍为1202三角面、1 surface、6个skin binds；材质和surface槽名仍为`shoes_mat`。所有绑定名称/索引/矩阵一致。
- 62骨骼的名称、父级、rest/pose矩阵以及原动画轨道一致。
- FBX `.import`逐字节不变，UID仍为 **uid://cancydl8xfiyp**，导入参数、`nodes/root_script=null`均保留。空缓存导入前后，FBX、PNG及二者`.import`四文件SHA不变。

原始报告：[改前导入结构](before-import-structure.json)、[改后导入结构](after-import-structure.json)、[汇总验证](validation.json)。仅非鞋的四个被移除材质不再有槽名；鞋子槽名和实际提取结果保持原样。

[全身同机位对比](full-comparison.png) · [45°鞋部同机位对比](feet-comparison.png)。左右分别为清理前、清理后；均使用**相应冷导入现场提取的Mesh/Skin**，套用原运行时材质后交给Avatar装配，脚本断言实际装上的就是该份资源，避免仅拿旧缓存`.res`互相比。

复用已验证的隔离Avatar审阅场景：Godot4.7.2、Deck RADV Vulkan Mobile、scale1、idle第0帧、原头像审阅光照；正面360×800、脚部45°近景360×320。每组相机、材质、姿态和光照相同。未缩放、调色或重画截图，四张原始帧随附。

鞋的形状和颜色一致。全身鞋部区域`(0,680,360,120)`像素完全相同；整张全身图仅20像素、近景仅10像素出现1–2/255通道微差，最大值2/255；整图平均通道差分别为0.00002778和0.00004630（8bit尺度）。[实渲记录](render-validation.json)包含两组相机与资源来源。

## 范围与复现

原版`assets/avatar/source/shoes3/`、Gabriel贴图、`parts/shoes3_npc_gabriel.res`、recipe、注册表、缩略图和三张头像均不改、不重烘。原版共享FBX单独冷导入也有同样8行ERROR/4行WARNING，留下一轮处理。本次不改共用部件，不做iOS打包；证据范围为输入资产的原生Godot冷导入与Vulkan Mobile实渲。

旧制鞋脚本`tools/art/recolor_gabriel_shoes_444.py`的最后一步已调用本次清理导出，避免日后重新制作时拷回缺图引用。[临时目录重建验证](rebuild-validation.json)确认生成FBX、PNG及两个.import与交付文件逐字节相同，原版共享目录不变。

从仓库根单独重新生成清理后的候选（源commit已固定）：

```sh
python3 tools/art/source/gabriel_fbx_444/export_clean_fbx.py
```

验证时创建两个空Godot项目，均按原相对路径放置目标FBX、PNG及二者`.import`；before的FBX取固定源commit，after取本次新文件。项目使用`renderer/rendering_method="mobile"`及`textures/vram_compression/import_etc2_astc=true`。分别运行`godot --headless --path <项目> --editor --import`，不要沿用`.godot`缓存。把[inspect_import.gd](../../../tools/art/source/gabriel_fbx_444/inspect_import.gd)复制到两个项目根，运行`--script res://inspect_import.gd`，取得结构JSON及实际导入的鞋Mesh/Skin快照。

[render_review.gd](../../../tools/art/source/gabriel_fbx_444/render_review.gd)在现有Gabriel隔离Avatar项目中运行：四个快照分别放在`snapshots/before_mesh.res`、`before_skin.res`、`after_mesh.res`、`after_skin.res`，保留当前Gabriel配方材质和parts资源；将该脚本挂到主场景Node，开窗口运行。快照及原始运行日志保存在本机`output/gabriel-fbx-444/`，不进入正式资源目录。
