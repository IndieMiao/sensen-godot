# NPC Batch 3 · Sources

赵云，2026-10-29。对应 SGODOT-362 / 347 / 357，由上官婉儿派工。
运行时资产位于单独 farm-dev 分支 `art/npc-parts-batch3`，美术审阅分支为
`art/npc-parts-batch3-review`。

第一段三件是纯纹理变体，不需要导出新几何或 Blender 场景。可编辑几何是运行时
`assets/avatar/source/<新 ID>/` 内与底件逐字节相同的 FBX，新 PNG 由
`recolor_npc_batch3.py` 生成。每件的掩码和 `texture-validation.json` 在本目录。

`inspect_npc_batch3.py` 用 Blender 只读导入底件，输出连通块、三角面、顶点和 UV。
`recolor_npc_batch3.py` 依这些 UV 区域保护头发、帽檐 / 金带 / 徽章、短裤，
将所有更改限定到记录的像素掩码；alpha 与掩码外像素保持一致。

Lou 预检：cloth36_npc_sigrid 的 cloth 共 3,192 三角面。外套袖子与衬衫 / 马甲
主体连在同一 1,698 面连通块（component 9），无法独立摘掉外套、留下完整内搭。
领带、纽扣等是小块，长裤是另一块。已回报；本会话已确认改用 cloth1 加酒红马甲、
黑领结和深色长裤，部件名 cloth1_npc_lou。

完整复现和验收入口见
[审阅 README](../../../../docs/design/npc-parts-batch3-2026-10-29/README.md)。

347 第二段的两个源场景为 nadia-baker-hat.blend、nadia-apron.blend，纹理打包在 blend
中，保留原骨架和 EDIT_ 命名编辑组。build_nadia_batch3.py 生成局部几何，沿用
284 的二进制 FBX 容器编码方法；对 SK 衣服仅额外扩展已有 skin clusters 的权重数组，
并校验原数组前缀和所有 bind transforms。没有节点层级重导出或 recipe 补偿偏移。
prepare_nadia_textures.py 生成新 PNG；nadia-geometry-validation.json 记录几何与容器检查。

帽子保留原长发的 303 个顶点 / 592 面，去掉花冠后增加低冠白软帽；共 1,296 面。
围裙共 1,869 面，原 862 个衣服顶点和权重保留，新增 183 顶点 / 240 面。
底件中所有其他源网格不变；提取仅选择 cloth，所以运行时仍一个 mesh / surface。
