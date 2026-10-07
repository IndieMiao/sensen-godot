# SGODOT-184 · Burger Shop · 刘备 R2

依据 Figma `545:2960`、本卡复审与父卡 171。保留已确认的 L 柜台、台凳尺寸和通道；高脚凳 0.9015m 对 1.2015m 吧台的已批准例外仍有效，不修改 Basic Room。

| 复审问题 | 本轮修改 |
|---|---|
| 菜单太小 | 外框从 3.22×1.16m 增至 4.65×1.18m，宽和总面积均约 1.45 倍；深红主板、较大汉堡插画、粗圆 BURGER BAR，下分 BURGERS / SIDES / DRINKS 三栏。为容纳菜单，将它沿墙居中，左标语与壁灯移到剩余前段；不改墙和柜体尺度。首版下栏被排烟罩/保温架遮住，已抬高菜单信息区、保温架下移 16cm，顶层酱瓶移到架内，三栏文字避开设备。 |
| 冷饮柜像两台、奶瓶 | 重做单一红色空腔柜体、深色内背、红门框与深色把手，四层各六件红/绿/蓝/黄汽水罐/瓶。金属盖、拉环和汽水带，删除原奶瓶及 B 标签；清透玻璃、冷白 LED。碰撞补足已存在的前部玻璃/层板占地。 |
| 标语发白 | 橙黄板、深红粗圆体，完整 GOOD BURGERS BRIGHTER DAYS / FRESH BUNS BETTER PEOPLE，两块均附汉堡小图。全系列字厚 4mm、固定图集色块，检查正常像素和近景。 |
| 左前花箱空 | 8 团共享构形的小叶冠交叠填满，叶冠加高；去花、去重复小盆，单独作为植物模块统计并关闭叶影。 |
| 灯光 | 菜单微弱图集自发光，新增一盏不投影的后厨暖灯；原冷柜灯保留，未给饮料逐件加灯。 |

原件 GLB / 局部轴心 / Blender 命名件可复用，运行时按组合并。房间/植物各一张 2048 图集。总三角面 **128,520**，全部植物 **14,386**，静态 surfaces **26**；限制 200,000 / 100,000 / 60。行为检查 **35/35 PASS**；四处色相差 **7.979° / 1.492° / 0.56° / 8.587°**；详见同目录 verification 和 bench-result；最终取色采用新机位对应实物表面，检查点与 RGB/HSV 全部保留。

相机以可见地台三角点、推定后角拟合，固定实际 6.16×5.76m、地台底高 -0.4056m；角点残差 **8.70 / 9.36 / 10.94px**，无建筑缩放或图像变形。菜单字行适度简化，餐具和柜台仍与插画有布置差异，直接对照/叠图呈现这些差异。

Godot Mobile/Vulkan 实际角色走过凳间、吧台端头、点餐侧、右侧过道与取餐窗；测试碰撞、净宽、贴柜滑行、输入/动画/松手停止。开放前沿无门，门高改为明确 N/A，不拿假尺寸充当测量。取餐灯向左移 38cm，避免灯罩遮住 PICK UP HERE 首字母。桌面 15 秒原速录像，不代表 Android 或物理手机性能验收。

```sh
blender -b -t 8 --python tools/art/build_burger_shop.py
python tools/art/source/coffee_shop/render_r1.py r2 burger_shop
python tools/art/source/coffee_shop/run_bench.py burger_shop --record
output/art-tools/bin/python tools/art/source/coffee_shop/package_series.py burger_shop r2
output/art-tools/bin/python tools/art/source/coffee_shop/check_series_colour.py burger_shop r2
output/art-tools/bin/python tools/art/source/coffee_shop/prepare_series_media.py burger_shop r2
output/art-tools/bin/python tools/art/source/coffee_shop/package_r2_details.py burger_shop
```

源文件 tools/art/source/burger_shop/burger_shop.blend，revision.py / revision2.py 与 burger_bench.py 可复现。等待不知火舞美术复审。
