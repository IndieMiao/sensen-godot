# Gabriel 换鞋与头像 · SGODOT-444 · v1.3

本版 shoes4 已被用户退回（白鞋不适合神父）。当前交付为 [v1.4 NPC 专用深色鞋](../dark-shoes-v1.4/README.md)，以下保留比较记录。

刘备，2026-11-07。#863 的 Gabriel 改用现成 `shoes4`，去掉原 `shoes3` 自带的浅蓝星星。
程序在 #867 同步以下 slots；NPC 只对话，本次不涉及 SGODOT-445 的 buff。

```json
{"hairHat":"hairhat0_npc_gabriel","cloth":"cloth36_npc_gabriel","shoes":"shoes4","glass":"glass0"}
```

## 三双鞋的实际比较

[三双并排：全身与鞋部近景](shoe-candidates.png)。上排各 360×800、正面；下排各 360×320、45° 鞋部近景。
同骨架、scale 1、idle 第 0 帧、居民头像原光照，使用 Vulkan Mobile / Steam Deck RADV。
只改变 shoes slot，候选资源和源贴图均与正式共用资源逐字节一致。

| 现成件 | 实渲结果 | 选择 |
|---|---|---|
| shoes4 | 深灰黑低帮鞋，白色鞋头、鞋边和白色纹样；无浅蓝星星 | 三者中深色鞋帮最适合黑衣，采用 |
| shoes5 | 浅棕鞋头、黑色靴筒和明显浅色毛边 | 更像保暖靴 |
| shoes0 | 灰白低帮鞋，浅色面积大 | 整体偏浅 |

这三双都不是纯黑皮鞋；选用鞋保留现有白色部分。未对共用鞋做改色或造型调整。

## 三张头像

[头像审阅图](portraits-review.png)；原图 [card](gabriel_card.jpg)、[head](gabriel_head.jpg)。
用新 slots 开窗口运行现有 `tools/art/bake_resident_portraits.gd`，在隔离项目的
`assets/p0/art/residents/` 下生成，再同步：

- `assets/p0/art/residents/gabriel_card.jpg`：300×660。
- `assets/p0/art/keepers/gabriel_card.jpg`：300×660，与 resident 卡逐字节一致。
- `assets/p0/art/keepers/gabriel_head.jpg`：从新卡的 `[70,51,165,165]` 脸框裁切，LANCZOS 缩至 132×132，JPEG quality 95、无色度抽样。

三张原 `.import` 均保留，`compress/mode=0`、无 mipmaps、原路径 UID。
衣服和头发仍按前次压缩补正使用 `mode=2`。头像 baker 仅沿用已记录的临时 P0Logic 延迟加载适配，
未修改正式 baker、灯光、相机或构图算法。新自动 stamp 框 x=67，比原来偏 1 px；原 crop 表的
`[68,47,170,213]` 仍完整容纳头像，予以保留。face 框完全相同，详见 [裁切记录](baked-crops.json)。

## 验证与复现

[验证记录](validation.json)、[实渲参数](render-validation.json)。三张头像与三份导入文件在独立空缓存
冷导入后哈希不变；实际加载尺寸正确、无 mipmaps。共用 shoes0/3/4/5、部件贴图/网格和其他 NPC
资源未修改。运行时实际的 NPC slots 由程序接入；本 PR 更新交付 slots 与审阅脚本默认值。
本次为桌面实渲和资源导入验证，未重跑 Android 或测量实体手机性能。

在既有隔离 fixture 中，将本目录的 `review_shoes.gd` 复制到 `tools/art/review_shoes_444.gd`，
然后持有 `~/gs66-render.lock` 开窗口运行。完整资源 staging 仍使用
`tools/art/source/gabriel_423/stage_review.py`，它的默认 Gabriel shoes 已更新为 shoes4。

```sh
godot --path <fixture> --script res://tools/art/review_shoes_444.gd
godot --path <fixture> --script res://tools/art/bake_resident_portraits.gd -- --looks=output/gabriel-looks.json --ids=gabriel --out=assets/p0/art/residents
```
