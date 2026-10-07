# SGODOT-180 · Milk Tea Shop · 刘备 R1 修订

依据原始 Figma `OMLTC3yw3u2WDjOZhLnhaR / 545:2962` 的 1544×1544 reference.png，以及不知火舞两轮评论。179 R2 放行后接入共享植物 R2.1。状态目标为 Review，由美术总监确认效果；不把技术检查视为视觉验收。

| Review 项 | 本轮处理 |
|---|---|
| 粉桃 / 薰衣草 / 薄荷色板 | 重做粉白错缝长砖、粉米方砖与四角薰衣草菱形；紫粉柱和压顶、薄荷门拱与冷柜；独立暖粉日光配桃色背景。 |
| 卡座 | 方鼓软包薰衣草长凳，粉/薄荷靠枕。前沿局部矮墙降低，让接受尺度的座面可见，不用抬高座面来掩盖遮挡。 |
| 桌椅 | 原木框椅配粉坐垫；白色圆桌、木柱脚。桌椅高度按不变的 Basic Room 基线校准。 |
| 菜单与左墙 | 原菜单英文，加入杯子/珍珠插画并腾出文字栏；薄荷 FRESHLY MADE；圆形奶茶标牌与暖光壁灯、GOOD TEA BRIGHTER DAYS。 |
| 冷柜 | 薄荷外壳、4 层彩瓶、透明门，顶部两只纸箱与垂吊植物。 |
| 吧台 | 6 个不同色配料格，透明茶桶罩/内层茶液，糖浆瓶高度轻微变化；薰衣草封口机、收银、花瓶、3 杯取餐架、吸管和糖果罐。 |
| 植物 | 大龟背竹、两端绿萝、7 簇半球白花与垂藤，保留场景需要的覆盖。 |
| 入口 | A 字牌、紫色地垫、两级视觉台阶与连续坡道碰撞。 |

| 预算 | 修订前 | 当前 | 限制 |
|---|---:|---:|---:|
| 总摆放三角面 | 150,800 | 154,222 | 200,000 |
| 植物（含桌花） | 未单独统计 | 40,452 | 100,000 |
| 静态 surface | 45 | 27 | 60 |

本场景原件 34 个，含实例共 43 个；共享植物 17 个摆放。按前后装饰、玻璃、花草合并，运行时商品与藤段不产生独立节点；原件 GLB 和命名源对象保留。两张共享 2048 图集（房间 / 全系列植物），mipmap + VRAM 压缩，不向每个 GLB 内嵌纹理。小花、藤蔓和桌花不投影，大盆栽保留投影。`asset_stats.json` / `revision-verification.json` 包含分组与文件大小，实际 Godot 静态 surface 数与预算一致。

对应物理部位 9×9 像素中位数：粉白墙砖色相差 **2.73°**，薰衣草柱 **0.74°**，粉色地砖 **9.16°**。位置见 `colour-samples.json` 与 `colour-patch-comparison.jpg`；只测声明部位，饱和度/亮度另保留，当前墙面仍比原图浅，不能用色相通过宣称全图一致。

Basic Room 不变，角色 H≈1.7455m：台面 1.2005m、椅面 0.69365m、桌面 1.048m、侧拱净高 2.63m，同类偏差均在 ±15%。源尺寸计算见 `layout.json > bench.scale`；真实测量报告见 `bench-scale-measurements.json`。

实际 Godot Mobile/Vulkan **39/39 PASS**：入口→桌间→取餐→卡座→冷柜；家具/边界阻挡、入口往返、贴墙滑行、按键/摇杆、idle/run、放手停止。椅间净宽 0.76m、桌与柜台 1.27m、入口 1.85m，物理射线实测。首次缺少依赖脚本的空碰撞失败没有用于交付；刘备自己的适配器已复制装配器依赖，未修改共享 harness 核心。坡道平台延伸到地板边缘外，修复返回入口被地板侧面阻挡的问题。

15 秒原速实际视口录像，按墙钟采集，不加速；8 个时间点解码确认非黑、完整角色与运动。这是桌面美术/行为证据，未做 Android 或物理手机性能验收。

重建（仓库根目录）：

```sh
blender --background --factory-startup --python "$PWD/tools/art/build_milk_tea_shop.py"
python tools/art/source/coffee_shop/render_r1.py r1 milk_tea_shop
python tools/art/source/coffee_shop/run_bench.py milk_tea_shop --record
output/art-tools/bin/python tools/art/source/coffee_shop/package_series.py milk_tea_shop r1
output/art-tools/bin/python tools/art/source/coffee_shop/check_series_colour.py milk_tea_shop r1
output/art-tools/bin/python tools/art/source/coffee_shop/prepare_series_media.py milk_tea_shop r1
```

可编辑源 `tools/art/source/milk_tea_shop/milk_tea_shop.blend`，修订脚本同目录 `revision.py` / `milk_bench.py`，米制 Y-up、各物件保持地面或安装轴心；源中有共享植物实例，运行时独立引用共享图集。生成会覆盖源，手工修改须回填脚本。基础制作脚本保留旧道具，再由修订脚本替换，不改其他人的场景。

待视觉复审的简化：软椅木背比设计图更方；取餐架较窄、糖浆瓶仍较规则；墙和桌面的饱和度较淡；花簇使用共享形态，没有逐叶复刻插画。玻璃用透明材质与内层模型，无昂贵折射。三栏图为完整参考 / 完整运行时 / 50% 直接叠图，未变形配准，布局仍有差异。
