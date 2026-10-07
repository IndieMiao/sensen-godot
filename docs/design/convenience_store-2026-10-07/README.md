# SGODOT-183 · Convenience Store · 刘备 R2.1

依据 Figma `545:2958` 实图、本卡复审及父卡 171。保留薄荷桃色、Basic Room 比例、既有货架占地与通行净宽，等待不知火舞复审。

| 问题 | 本轮处理 |
|---|---|
| 招牌缺字 | 全部换 Nunito Black 粗圆体、4mm 厚度，离板面再留 5mm。CONVENIENCE / DRINKS / SNACKS / DAILY ESSENTIALS 放大，补篮子/杯子图标；文字 UV 固定到有边距的纯色色块，解决细字丢失及图集串色。 |
| 冷柜发白、货少 | R2.1 重做空腔冷柜，两门各五层、每层四件，共 40 件瓶/罐；陈列前移到玻璃后，薄金属层板与冷白自发光背板。玻璃 alpha 0.025，单独材质绕过固定玻璃合批，关阴影；柜内彩饮用图集自发光相乘，避免额外叠白冲淡包装。 |
| 商品重复 | 鼓胀薯片袋有封口和折痕；易拉罐有金属盖和拉环；彩瓶有肩、颈、瓶盖；另有纸卷、盒、皂。四套独立标签轮廓/图案：圆章、斜带、双横带果叶、异形徽章；八档跳色。少量倾斜、轻转和原有层间缺口。 |
| 地垫和植物 | 珊瑚垫扩宽至约 1.77m，接近 1.85m 的净入口；共享深绿植物图集，叶花不投影。 |

单包装预算由生成器实际三角化断言 ≤60，见 assets/rooms/convenience_store/product-budget.json；商品保留 Blender 命名件并合并进各货架单 surface，不创建逐商品运行节点。独立 GLB、本地轴心、可重建源保留。房间/植物各一张 2048 图集，无逐 GLB 内嵌贴图。

评审机位按地台角点作刚性正交拟合，固定 6.18×5.68m，不改家具尺度，不变形参考/实景。完整对照和 50% 直接叠图保留构图差异。1400 方图角点误差 **2.28 / 2.50 / 2.52px**，见 camera-registration.json；商品仍为原创简化图形，并非参考包装品牌复刻。

Godot Mobile/Vulkan 隔离角色行为、家具阻挡、岛间通行、侧墙滑行、入口往返、输入/idle/run/松手停止；最终 **36/36 PASS**，总三角面 **108,574**、全部植物 **29,112**、静态 surfaces **36**；限制 200,000 / 100,000 / 60。三处对应取色色相差 **2.981° / 7.293° / 3.670°**，均≤10°；新机位墙块首次偏差 10.568°，已微调原背墙色到 #E9D3C8 后复核，点位保留。桌面 15 秒原速录像另附，不将桌面结果当手机性能。门 2.44m、收银台面 1.1025m；无椅分类明确不适用，不填写假尺寸。

```sh
blender -b -t 8 --python tools/art/build_convenience_store.py
python tools/art/source/coffee_shop/render_r1.py r21 convenience_store
python tools/art/source/coffee_shop/run_bench.py convenience_store --record
output/art-tools/bin/python tools/art/source/coffee_shop/package_series.py convenience_store r21
output/art-tools/bin/python tools/art/source/coffee_shop/check_series_colour.py convenience_store r21
output/art-tools/bin/python tools/art/source/coffee_shop/prepare_series_media.py convenience_store r21
output/art-tools/bin/python tools/art/source/coffee_shop/package_r2_details.py convenience_store r21
```

可编辑源 tools/art/source/convenience_store/convenience_store.blend；revision.py / revision2.py / revision21.py 与 convenience_bench.py 可复现。两岛净宽 1.365m，岛与柜台净宽 0.995m，沿用已经确认的通行布局。

R2.1 专项：玻璃、商品、背板各为可复用单 surface 原件；40 件商品仅使用两次整柜货物实例，没有逐瓶节点或逐瓶灯。冷柜整体占地/碰撞和原角色通道不变。`scenes/convenience_store/cold_art.gd` 只把两组冷柜商品材质的 emission_operator 设为 MULTIPLY，共享装配器及已通过的汉堡店/粉店不变。第一版白色相加造成的粉白饮料已在全景检查中发现并纠正，最终截图及 36 项测试/15 秒录像均在修正后重新生成。R21 新附件、冷柜近景与旧 R2 回执独立保留。
