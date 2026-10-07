# SGODOT-181 · Courtyard Cat Café · 刘备 R1 修订

依据 Figma `545:2955` 原图和不知火舞本卡评论。179 R2 放行后接入共享植物 R2.1；Basic Room 现有比例保留，技术通过不替代美术总监验收。

| Review 项 | 本轮处理 |
|---|---|
| 石墙、城垛 | 大块错缝砂岩、圆角凸面、两面各 7 个大城垛，奶油压顶；后墙两处真实拱形凹龛。 |
| 铺地 | 大块奶油石板，行间错缝和轻微颜色变化；草地岛上 42 簇草、10 块不规则踏脚石与烘焙草地色块。 |
| 两棵果树 | 共享果树各 1.16 倍，石砌花坛与碰撞独立，两棵大树保留投影。 |
| 白花围墙 | 15 簇共享半球花丛，重叠覆盖前沿与右墙；不使用长茎代替花团。另有白掌与架上绿萝。 |
| 桌椅与咖啡台 | 白垫藤编椅、白桌面、木台、透明糕点柜、咖啡机、磨豆机、杯盘、罐子与蓝花瓶。 |
| 四只猫 | 入口灰色睡猫、台上橘色趴猫、地面站立三花、前方灰白坐猫；独立命名模型，无动态宠物行为。 |
| 入口与边界 | 两级石阶、条纹垫、连续坡道、草坪四边封闭碰撞。右侧墙碰撞延伸到真实可见压顶，修复角色碰撞测试漏检。 |

草簇每簇 **42 个三角面**（7 片双面折叶），低于 50 上限。共享花丛每簇 **2,402 个三角面**，低于 4,000 上限。花草、藤、桌花关闭投影，大树可投影；低面数不会用稀疏摆放抵消密度要求。按材质/位置组合并，保留独立 GLB 和源命名部件，不修改共享测试核心。

Basic Room 不变，台面 1.2005m、椅面 0.6904m、桌面 1.03785m、侧拱净高 2.63m。同类尺寸均在 ±15%；椅间净宽 0.82m、桌与柜台 0.84m、入口 1.85m，由真实物理射线和角色行走验证。草坪高度与门内石坪不同，入口坡道连接两者。

当前摆放总面数 **132,026**，其中植物 **54,134**，静态 surface **29**，均在 200,000 / 100,000 / 60 上限内。角色检查 **37/37 PASS**。石墙 / 石坪 / 草地色相差分别 **4.21° / 9.37° / 6.95°**，均小于 10°。交付记录见本目录 JSON；色板使用声明的对应物理表面 9×9 像素中位数，三栏对比为完整原图 / 完整运行时 / 50% 直接叠图，没有变形配准。15 秒实际 Godot Mobile/Vulkan 视口原速录像，不是 Android 或实机性能结论。

重建：

```sh
blender -b -t 8 --python tools/art/build_coffee_shop_0.py
python tools/art/source/coffee_shop/render_r1.py r1 coffee_shop_0
python tools/art/source/coffee_shop/run_bench.py coffee_shop_0 --record
output/art-tools/bin/python tools/art/source/coffee_shop/package_series.py coffee_shop_0 r1
output/art-tools/bin/python tools/art/source/coffee_shop/check_series_colour.py coffee_shop_0 r1
output/art-tools/bin/python tools/art/source/coffee_shop/prepare_series_media.py coffee_shop_0 r1
```

可编辑源 `tools/art/source/coffee_shop_0/coffee_shop_0.blend`；修订与通行定义在同目录 `revision.py` / `courtyard_bench.py`。源中保留共享植物实例和局部轴心，材质表面细节烘入房间图集，共享植物使用全系列图集。

待视觉复审：参考果树的树冠更层叠密实，当前是共享库枝叶形态；猫的轮廓和毛色为简化静态造型；柜台和两组桌子的构图仍不同于原图；草地使用局部地台，没有无限背景草甸；桌面和压顶的明度仍需总监判断。没有宣称逐像素还原。
