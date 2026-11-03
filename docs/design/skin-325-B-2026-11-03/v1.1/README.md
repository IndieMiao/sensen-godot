# 325 B 皮肤 v1.1 门头增量

【黄忠】按上官婉儿 325 fa8c70a2，覆盖 v1 的 N2 B 写字区约定。

- N2 B `sign.size_m = [0.66, 0.23]`，`offset_m = [0.10, 0, 0.009]`。A 的大小、偏移不变。
- 偏移沿**房间坐标 +X**，实渲为绿十字的另一侧。原 sign_name marker 的 yaw=180；Label3D 正面 +Z，因此审阅文字相对 marker 再转 180°，面对牌面。
- 两张 `sign_b.png.import` 的 `detect_3d/compress_to` 均为 2，UID 保持。N2 原本就是 2，仅 N1 该项有字节变化。
- 两张门头 PNG、两张 B 图集、所有 A 资源、GLB、布局和开关场景均未改变。

近景中的 Service Hall 是 Godot 运行时 Label3D，不写进 PNG。字体按指定区域缩放，
实际文字 AABB、与十字的距离、文字方向和源文件哈希见本目录验证 JSON。
本次不改变正式场景脚本，也不把审阅示例文本提交为运行时店名。

复现与镜头脚本见 `tools/art/source/skin_325/README.md`。
