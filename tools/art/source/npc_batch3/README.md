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
领带、纽扣等是小块，长裤是另一块。已向上官婉儿回报并请求改用 cloth1 加马甲、
领结和长裤；底件选择收到回复前不动 Lou。

完整复现和验收入口见
[审阅 README](../../../../docs/design/npc-parts-batch3-2026-10-29/README.md)。
