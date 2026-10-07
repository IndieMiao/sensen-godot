# SGODOT-183 · Convenience Store · 刘备 R1 修订

依据 Figma `545:2958` 原图与不知火舞两轮评论，使用 179 R2.1 共享植物。Basic Room 比例不变，完成后提交 Review，技术检查不替代美术总监验收。

| Review 项 | 当前处理 |
|---|---|
| 商品 | 八类包装：鼓袋零食、盒装零食、罐头、日用瓶、洗护瓶、卷纸、冷饮、皂盒；每类 2–3 个颜色/标签变体，货架有缺口。商品合并进各货架，运行时无单件商品节点。 |
| 冷饮柜 | 两门透明玻璃、每门五层彩瓶、冷白灯条与一盏冷白填光；灯光降低到能读出瓶身颜色。 |
| 地面 | 米色/薄荷八边形砖、小菱形连接砖，保留地面高度。 |
| 墙 | 加厚圆角方块砖、米白与薄荷交替、薄荷压顶与柱；奶油砖由偏黄调整为微桃。 |
| 标牌与柜台 | 类别图标、浅木柜台与薄荷台面、收银、黑板、雏菊、小商品架、微波炉。 |
| 冰柜 | 粉色边框、透明滑盖、内部冰淇淋盒与侧面三种冰淇淋图案。 |
| 中央货架 | 保持原尺寸，右岛转 90° 并错开位置；左岛水果/罐头，右岛日用品/卷纸/洗护。 |
| 入口与植物 | 红白篷、OPEN、两盏灯、珊瑚垫、玻璃门后天空/树冠；共享龟背竹、垂吊绿萝和 7 簇白花，购物篮推车。 |

| 包装 | 单件三角面 | 变体数 |
|---|---:|---:|
| 鼓袋零食 | 28 | 3 |
| 零食盒 | 16 | 3 |
| 罐头 | 34 | 3 |
| 日用瓶 | 56 | 3 |
| 洗护瓶 | 56 | 2 |
| 卷纸 | 48 | 2 |
| 冷饮瓶 | 56 | 3 |
| 皂盒 | 16 | 3 |

以上均包括标签与图形，最高 56，低于 60 上限；实际生成记录为 `assets/rooms/convenience_store/product-budget.json`。运行时每个货架为单 mesh / 单 surface，前后小道具、玻璃、花草组合并；独立原件 GLB 与命名源对象保留。

总摆放 **101,173 面**，植物 **29,112 面**（包括柜台花瓶和窗外树冠，保守连天空板一并计入），静态 surface **28**，在 200,000 / 100,000 / 60 上限内。房间 / 共享植物各一张 2048 图集，mipmap + VRAM 压缩，无 GLB 内嵌贴图。小叶、花和窗景不投影；大盆栽可投影。局部灯 3 盏，不给商品逐件加灯。

薄荷柱 / 奶油墙砖 / 珊瑚垫对应表面色相差 **1.00° / 7.96° / 4.46°**，使用 9×9 中位数。初选墙样本误落在薄荷块，确认真实表面后改为奶油块，再根据超标值调整墙砖颜色；标注和完整 RGB 在 `colour-patch-comparison.jpg` / `colour-verification.json`。亮度和饱和度仍与插画有差异，不能用色相通过声称全图一致。

Basic Room 不变，门 2.44m、收银台/桌面 1.1025m，均在 ±15%。本店无椅，chair 项明确是不适用的基线占位。实际 Godot Mobile/Vulkan **36/36 PASS**：入口→两岛之间→收银→冷柜→冰柜，以及全部家具阻挡、边界、滑行、输入、动画与放手停止。两岛净宽 **1.365m**，岛至柜台 **0.995m**，前入口 **1.85m**，按实时碰撞面射线测量。15 秒实际视口原速录像，8 个时间点检查；不代表 Android 或实机性能验收。

```sh
blender -b -t 8 --python tools/art/build_convenience_store.py
python tools/art/source/coffee_shop/render_r1.py r1 convenience_store
python tools/art/source/coffee_shop/run_bench.py convenience_store --record
output/art-tools/bin/python tools/art/source/coffee_shop/package_series.py convenience_store r1
output/art-tools/bin/python tools/art/source/coffee_shop/check_series_colour.py convenience_store r1
output/art-tools/bin/python tools/art/source/coffee_shop/prepare_series_media.py convenience_store r1
```

可编辑源 `tools/art/source/convenience_store/convenience_store.blend`，同目录 `revision.py` / `convenience_bench.py`。隔离测试适配器采用 182 已验证的全部接触点采集，未改共享 harness 文件。

待视觉复审：陈列比原图规则，包装图案是低分辨率图标，未复制插画字样；门外是简化静态树冠；货架因通行而转向，构图不同；龟背竹部分遮住左侧冷柜、当前整体更亮。这些不隐瞒，也不以技术通过代替视觉通过。
