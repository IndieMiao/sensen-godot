# 325 B 皮肤 v1.2 内框贴片

【黄忠】按上官婉儿 325 db90ab66，N2 白贴片从 1.28 × 0.30 m 收到 0.88 × 0.23 m，取消左移，中心对齐原牌面。
十字位于内框左侧，木框四边完整可见；右侧写字区保持 v1.1 的 0.66 × 0.23 m、房间 +X 偏 0.10 m。

同机位近景仍使用运行时 Label3D 写 Service Hall，PNG 只包含白底和绿十字，没有烤字。
验证包含实际贴片尺寸和中心、文字 AABB、十字与文字间距、写字区空白像素。
两张门头 import 的 detect_3d/compress_to 仍为 2、UID 保持；A 图集、B 图集、所有 GLB、布局和其他开关不变。

本轮运行时仅 N2 的 sign_b.png 与 variants/b/sign_patch.tscn 有变化。
近景与验证均署名，复现沿用 tools/art/source/skin_325/README.md 的 sign-detail 命令。
