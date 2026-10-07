# SGODOT-182 · Orchard Market · 刘备 R1 修订

对照 Figma `545:2957` 原图与本卡两轮评论，沿用 179 R2 的共享植物、独立源部件与运行时组合并方法。Basic Room 尺度基线不变。

| Review 项 | 本轮处理 |
|---|---|
| 白抹灰墙 | 移除后墙与门墙的规则方格，保留白色大抹灰面，边角及下沿局部露出大小不一的石块；矮墙同样采用抹灰与局部露石，陶土压顶。 |
| 五种水果 | 橙、长椭圆柠檬、收颈无花果、双色桃和成串葡萄。独立低模 GLB，堆箱时用同源网格、随机尺寸和朝向，两层小堆，每箱 13 件。 |
| 倾斜货箱 | 五只主货箱连水果向外倾斜 20°，木条/角撑/接缝保留。地面另做两只平放箱与碰撞，架上橙/柠檬篮。 |
| 篷、百叶与秤 | 奶油白条纹、缩短挑出、圆弧垂边；三只深蓝百叶采用不同开合角度；红表盘圈、银色秤碗、干香草。 |
| 地板、入口 | 暖橙木板、编织垫和两级白石阶，连续坡道碰撞。 |
| 标牌 | ORCHARD MARKET、橙子和叶片图案、铁艺灯臂。 |
| 植物 | 两棵共享银绿色橄榄树与陶土盆、架上盆栽、11 簇围墙花丛、4 组白花藤，植物密度不因减面稀释。 |

| 水果单体 | 三角面（含叶/梗） | 上限 |
|---|---:|---:|
| 橙子 | 60 | 80 |
| 柠檬 | 60 | 80 |
| 无花果 | 60 | 80 |
| 桃子 | 60 | 80 |
| 整串葡萄 | 76 | 80 |

同源水果在导出时合并成箱，保留独立水果 GLB，运行时不为每件水果创建节点。桌台、玻璃（若有）、前后装饰和植物按组导出。图集为房间 / 共享植物各一张 2048，GLB 无内嵌图片、单网格单 surface。藤叶、花丛与干香草不投影，大橄榄盆栽可投影。

主货台顶 1.01m，门净高 2.63m，均符合 Basic Room 同类 ±15%。本场景没有椅子，测试表中的 chair 项明确记录为不适用，不额外放一把椅子凑基线。货台同时承担桌面测试。通路覆盖入口、两个地箱周围、货台、两侧橄榄树旁，地箱到货台净宽 1.605m，入口 1.85m。所有通行结果以实际 Godot 渲染测试 JSON 为准。

当前总面数 **105,235**，植物 **44,274**，静态 surface **21**。实际角色检查 **33/33 PASS**；白墙 / 陶土压顶 / 地板 / 蓝百叶的对应色相差 **3.35° / 6.50° / 6.63° / 1.34°**。完整预算与通行记录在本目录；完整原图 / 运行时 / 50% 叠图不作几何变形。15 秒原速录像是桌面 Mobile/Vulkan 美术与角色运动证据，不代表 Android 或实机性能验收。

```sh
blender -b -t 8 --python tools/art/build_fruit_shop.py
python tools/art/source/coffee_shop/render_r1.py r1 fruit_shop
python tools/art/source/coffee_shop/run_bench.py fruit_shop --record
output/art-tools/bin/python tools/art/source/coffee_shop/package_series.py fruit_shop r1
output/art-tools/bin/python tools/art/source/coffee_shop/check_series_colour.py fruit_shop r1
output/art-tools/bin/python tools/art/source/coffee_shop/prepare_series_media.py fruit_shop r1
```

可编辑源 `tools/art/source/fruit_shop/fruit_shop.blend`，同目录 `revision.py` 与 `fruit_bench.py`。修改源需要回填生成脚本；保留米制局部地面/安装轴心。

待视觉复审：构图与原图仍有偏差，主台较直、百叶窗间距更规则；低面数水果在近景有棱角，桃色过渡为分区着色；橄榄冠使用全系列银叶形态；花藤未逐段复刻原画。颜色检查只代表声明的亮面，不是全图保真分数。

测试采集修正：Jolt 在一次滑移结果中同时返回地面和墙面接触，旧采集只看第一个地面法线，会漏记实际墙面。对照实际接触日志后，刘备的 `run_bench.py` 在隔离副本中遍历每条结果的全部接触；未修改移动、碰撞体、断言、阈值或仓库中的共享 harness 文件。修正前贴墙滑行失败、修正后通过，原日志保留于 ignored output。
