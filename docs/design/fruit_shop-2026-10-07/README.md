# SGODOT-182 · Fruit Shop · 刘备 R2

依据 Figma `545:2957` 原图和本卡复审、父卡 171 共性意见。五种已可辨水果、Basic Room 建筑与家具比例保留。等待不知火舞复审。

| 修改项 | 本轮交付 |
|---|---|
| 花藤 | 拱侧增加六束独立小叶藤，后角及墙顶补白花藤；实景首版白花过密，已改为绿叶填密、白花点缀，避免连成白色泡沫。追加叶片复用共享植物构形与新版深绿。 |
| 橄榄树 | 两株增加交错叶冠，右株放大到 1.12 倍并移到陈列桌右前侧；陶土盆保留，向后退少许避免被前花箱遮住。树叶模块单独导出，不重复盆/树干。 |
| 招牌 | 木边奶油底、粗圆深绿 ORCHARD MARKET 两行字、橙子切面和枝叶图案、黑铁灯。4mm 文字厚度加 5mm 面偏移，文字使用固定图集色块防串色；全景原生像素和近景均检查。 |
| 前沿与水果 | 共享深绿花丛；地上无花果箱向内移至无遮挡位置；既有橙、柠檬、无花果、桃、葡萄造型不变，单果/串≤80面。 |
| 百叶 | 新机位对应亮面首次量到偏差 10.648°，基色由 #4D768C 微调为 #4D7698，复核记录见取色 JSON。 |

总摆放 **118,318** 三角面，全部植物 **55,294**，静态 surfaces **21**；限制为 200,000 / 100,000 / 60。草木、花藤、装饰按组合并，独立 GLB / 本地轴心 / Blender 命名件保留；小叶和白花不投影。房间和共享植物各一张 2048 图集，不在各 GLB 内重复嵌图。

机位用地台左、前、右角拟合并推定后角，固定 6.18×5.68m 比例，不缩放建筑、不变形图像。1400 方图角点残差 **6.48 / 6.84 / 6.86px**，见 camera-registration。墙高、果箱排列和招牌高度仍与插画存在可见差异；直接叠图保留这些差异。

角色与碰撞使用真实 Godot Mobile / Vulkan 隔离测试；入口、果箱间通道、柜台与左右树盆绕行、家具/墙阻挡、贴墙滑行、输入和动画。右盆前移后，侧墙阻挡检测起点随之避开树盆，检测目标和断言不变。无椅场景明确 `applicable:false`，不再以基线假数填写椅高。门 2.63m、台面/桌面 1.01m，符合既定 ±15%。最终 33/33 PASS，四处色相差为 0.404° / 5.546° / 5.745° / 2.009°；15 秒原速录像已检查 8 个时间点，完整角色可见；证据见同目录 JSON；桌面检查不代表 Android 或物理手机性能。

```sh
blender -b -t 8 --python tools/art/build_fruit_shop.py
python tools/art/source/coffee_shop/render_r1.py r2 fruit_shop
python tools/art/source/coffee_shop/run_bench.py fruit_shop --record
output/art-tools/bin/python tools/art/source/coffee_shop/package_series.py fruit_shop r2
output/art-tools/bin/python tools/art/source/coffee_shop/check_series_colour.py fruit_shop r2
output/art-tools/bin/python tools/art/source/coffee_shop/prepare_series_media.py fruit_shop r2
output/art-tools/bin/python tools/art/source/coffee_shop/package_r2_details.py fruit_shop
```

源文件为 tools/art/source/fruit_shop/fruit_shop.blend，revision.py / revision2.py 可复现；素材不是运行时游戏地图更新。
