# SGODOT-184 · Burger Shop · 刘备 R1 修订

以 Figma `545:2960` 原图、不知火舞两轮评论和 179 R2.1 标准修订。Basic Room 基线不变，视觉验收待美术总监 Review。

| Review 项 | 当前处理 |
|---|---|
| L 柜台 | 保留主柜尺寸，补左前回转柜；厚奶油圆角台面，中央汉堡标识和两对横线独立发光材质。标识提高以避开吧台遮挡。 |
| 后厨 | 四片大小与摆放不齐的肉饼、静态浅色蒸汽细带；两个薯条炸篮、蔬菜格、油烟罩、不锈钢柜门，双层面包与酱瓶。 |
| 菜单/冷柜 | 三栏深红菜单与暗底清单，弱自发光；红框冷柜、彩色饮料、冷白灯条。 |
| 取餐窗 | 保留真实开口、PICK UP HERE 和红白棚，纸袋改为两只。 |
| 地面/墙 | 深咖厚底座、加厚红色圆角压顶、接近明度的两种米色棋盘砖。 |
| 道具 | 两个盘装汉堡、酱瓶、两个外卖盒、收银机与餐巾；两幅带汉堡插图竖牌，三盏黄铜灯。 |
| 吧台 | 保留高吧台比例，红凳加厚软垫与深色脚环，酱瓶、餐巾架；调整位置留出前方绕行。 |
| 植物 | 花箱六组共享绿萝，右侧共享白掌；保留密度，小叶/花不投影。 |

食物随各厨房组件合并：汉堡架四种尺寸 0.89/0.925/0.96/0.995，柜台汉堡 0.96/1.03；面包有独立大小变化，薯条交叉散放，饮料有多色包装。保留可复用模块 GLB、命名 Blender 源对象和局部 pivot，不为单件食物创建运行时节点。最终总摆放 **108,544 面**，植物 **13,234 面**，静态 surface **26**；角色 **35/35 PASS**，完整预算见 `revision-verification.json`；房间与共享植物各一张 2048 图集，mipmap + VRAM 压缩，无 GLB 内嵌图片。

红压顶 / 红柜台 / 深咖底座 / 米色砖对应色相检查见 `colour-verification.json`，9×9 像素中位数，阈值 10°。原柜台运行时取样曾落到黄色吧台，已改到真正红柜面；此更正保留在说明中。当前亮度、饱和度高于插画，色相通过不代表全图一致。

柜台 1.1615m、吧台 1.2015m。高脚凳 0.9015m，约吧台高度 75%，采用总监明确允许的高凳例外；本场景开放前沿无门，door 项是明确不适用的基线占位。地面/家具尺寸和角色不随构图任意缩放。柜台—吧台 **0.865m**、左侧进入吧台 **0.935m**、两凳 **0.75m**，实际射线测量。角色从前沿穿凳间，再绕左侧去点餐、沿右侧到取餐窗；墙、柜台、吧台、冷柜、花箱与凳子均有实际阻挡检查。15 秒实际视口原速录像，八时点检查；不代表 Android 或实机性能。

```sh
blender -b -t 8 --python tools/art/build_burger_shop.py
python tools/art/source/coffee_shop/render_r1.py r1 burger_shop
python tools/art/source/coffee_shop/run_bench.py burger_shop --record
output/art-tools/bin/python tools/art/source/coffee_shop/package_series.py burger_shop r1
output/art-tools/bin/python tools/art/source/coffee_shop/check_series_colour.py burger_shop r1
output/art-tools/bin/python tools/art/source/coffee_shop/prepare_series_media.py burger_shop r1
```

源文件 `tools/art/source/burger_shop/burger_shop.blend`，同目录 `revision.py`、`burger_bench.py`。共享 harness 原文件不变，隔离适配器采集 Jolt 全部侧面接触点。

待视觉复审：L 回转柜在左前，吧台为保证通行相对原图移位；左侧绿萝被柜体部分遮挡；金属反射、食物纹理和霓虹溢光较参考简化；蒸汽为静态细带，没有动态烟雾模拟。附原图、真实 Godot 整景、直接 50% 叠图、细节、正交、角色与碰撞证据。
