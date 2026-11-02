# SGODOT-347 · Nadia v1

赵云，2026-10-29。上官婉儿派工；按 347 描述和本批规格制作。

| 部件 | 三角形 | 对底件增量 | 内容 |
| --- | ---: | ---: | --- |
| hairhat41_npc_nadia_baker | 1,296 | -1,016 | 原赤褐长发，移除花冠，矮软白帽 |
| cloth1_1_npc_nadia | 1,869 | +240 | 原衣服加浅米白围裙、肩带、空胸袋、腰带；暖粉条纹 |

每件一个 mesh / surface，一张 1024² 源图（runtime 512²），材质参数照底件。
两件的节点名、层级、变换、轴向、单位、骨骼矩阵不变；帽子原长发顶点保留，
衣服原 862 个顶点和原权重保留，新增 183 个顶点由原表面权重插值得到。
没有 FBX 场景重导出：只替换指定 Geometry、向原 skin clusters 追加新顶点权重；
原数组前缀和其他对象逐项比对。编码器另外规范化 FileId / CreationTime。
运行时 59 个 skin binds 与底件相同，不使用 recipe 偏移修补。

原纹理映射到上方 1024×896，留底部 128 px 布料色块区；原 UV 对应做同一变换，
保留长发烘焙层次。围裙胸袋为空，衬衫改暖粉，和 Lena 蓝条纹、Mei 棕围裙分开。

## 审阅

- [原造型 / 新造型](SGODOT-347_NADIA_v1_01_before_after.png)
- [帽子正背近景](SGODOT-347_NADIA_v1_02_nadia_hat.png)
- [围裙正背近景](SGODOT-347_NADIA_v1_03_nadia_apron.png)
- [Mei / Theo / Nadia 集市并排](SGODOT-347_NADIA_v1_04_market_lineup.png)
- [七个站立、行走、侧背姿态](SGODOT-347_NADIA_v1_05_motion.png)
- [原生名字条 + 72 屏幕像素徽标](SGODOT-347_NADIA_v1_06_native_badge_72px.png)
- [Lena / Rafa / Nadia 三人新装](SGODOT-362_PARTS_v1_07_lena_rafa_nadia.png)

全部来自 farm-dev checkout 的窗口 Godot 4.7.2 / Vulkan Mobile / RTX 2060。
全身卡用未改的 resident portrait baker；近景沿用同一舞台，固定成对镜头。
徽标用游戏 UiNpcNameTag / UiStatusBadge，36 逻辑像素 × 2，720×960 原图中实际
72 屏幕像素；名字锚点沿用 p0_outpost 的 2.0 m，未自定义名字位置去避让帽子。
它是同舞台落位检查，不冒称实际市场房间截图。

已查看所有交付图及七个姿态，修正了初版下摆穿过衬衫尾部和胸袋贴面的问题。
91 项专用导入 / 骨架 / 绑定 / 权重 / 材质 / NPC 隔离检查通过，38 项原测试通过。
原生衣服权重格式为每顶点 8 项，已按真实步长检查归一化。
记录：[godot-validation.json](godot-validation.json)、[geometry-validation.json](geometry-validation.json)、
[motion-validation.json](motion-validation.json)、[tests.xml](tests.xml)。

运行时在 art/npc-parts-batch3 增量，头 85ac1b1efb10e9f073b995454e9e4f6d9b6b5a3b，只推、不建 PR；美术仍在 #561 增量。
manifest 48→50、npc_only 19→21 只追加；首批三个部件保持已交字节。
未改 outpost_npcs.json、NPC portraits 或正式裁切配置。
6 张 Nadia 图传 347，三人新装图补传 362；署名及下载核对见 delivery-verification.json。

## 源文件与复现

源 blend：tools/art/source/npc_batch3/nadia-baker-hat.blend、nadia-apron.blend。
保留原骨架与命名编辑组，纹理已打包。生成器不改公共 FBX 导出管线。

在美术工位设置 RUNTIME 为本批独立 farm-dev 工位后：

~~~sh
source ~/.codex-zhaoyun/env.sh
output/art-setup/venv/bin/python tools/art/prepare_nadia_textures.py --runtime-root "$RUNTIME"
blender --background --factory-startup --threads 4 --python-exit-code 1 \
  --python "$PWD/tools/art/build_nadia_batch3.py" -- --runtime-root "$RUNTIME"
python3 tools/art/stage_npc_batch3_review.py --runtime-root "$RUNTIME"
godot --headless --path "$RUNTIME" --editor --import --quit
godot --headless --path "$RUNTIME" --script res://tools/art/prepare_npc_batch3.gd
godot --headless --path "$RUNTIME" --script res://tools/pipeline/extract_parts.gd -- \
  res://assets/avatar/source/recipes_batch3.json --append
godot --headless --path "$RUNTIME" --script res://tools/art/verify_nadia_batch3.gd
~~~

重提已经注册的某件时，按 README_batch3 只删除该件 manifest 条目再 append。
在运行时工位开窗口拍摄前检查 GPU 空闲：

~~~sh
godot --path . --rendering-method mobile --rendering-driver vulkan \
  --script res://tools/art/bake_resident_portraits.gd -- \
  --looks=res://output/npc-batch3/looks-phase2.json --out=output/npc-batch3/nadia-portraits \
  --ids=nadia_now,nadia_new,nadia_hat_only,lena_new,rafa_new,mei,theo --cols=4
godot --path . --rendering-method mobile --rendering-driver vulkan \
  --script res://tools/art/review_npc_batch3.gd -- --nadia
godot --path . --rendering-method mobile --rendering-driver vulkan \
  --script res://tools/art/review_nadia_motion.gd
~~~

运行时工位中的美术检查脚本仅为临时复制，不进入运行时提交。
