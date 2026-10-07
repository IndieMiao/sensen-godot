# SGODOT-181 · Courtyard Coffee Shop · 刘备 R2

依据原始 Figma `545:2955`（本地 reference.png 为 2048×2048）、本卡 P0 果树/猫与父卡 171 共性意见。房间、门、台面、桌椅的 Basic Room 比例不变；等待美术总监复审。

| 复审项 | R2 处理 |
|---|---|
| 两棵果树 | 保留花坛占地，独立重做更宽、更高的圆润分层树冠：每棵 13 团、520 片小叶，六档共享深绿；树冠顶部约 3.1m，替代原先不足墙高的小冠。每棵 6 只放大的橙子。共享叶片形态复用，不改 179 的树或比例。 |
| 橙子像柠檬 | 以 #F08A1C 的视觉方向为目标，暖光实景发现偏黄后，基色补偿为 #F0781C；最终对应果实亮面色相差 5.616°。保留高饱和橙色，不用黄色遮盖。 |
| 四只静态猫 | 重做圆脸、大眼、鼻口、明确耳朵与四肢。柜台躺橘猫、地上站三花、桌旁坐灰白猫、格子垫上趴灰猫；平滑曲线尾巴和贴近毛面的细虎斑。灰白猫移到无遮挡的桌旁，白胸白脚与灰头身体区分。附 4 张实际近景拼图。 |
| 草地与小径 | 草地从 8×8.3m 扩到 10×10.8m，保留烘焙黄绿色斑驳，加外围草丛、小石子；十块可分辨踏脚石蜿蜒延伸约 2.5m。庭院地台仍为 6.18×5.68m。外围通行/边界同步扩大并实测。 |
| 地垫、豆罐和石墙 | 深橙格纹垫与趴猫；两只透明罐内各有 40 粒橙棕咖啡豆。为避免与研磨机、水槽穿插，豆罐放到连接墙面的小搁板上。墙石四档暖色明度，较深近色接缝。 |
| 共性 | 粗圆字体、4mm 厚度、文字固定图集色块；共享深绿叶色。叶、小花和自制树冠免投影；草木/商品按组合并，原件继续可复用。 |

| 预算 | 当前 | 限制 |
|---|---:|---:|
| 总摆放三角面 | 150,625 | 200,000 |
| 全部植物，含树、草、桌花 | 59,229 | 100,000 |
| 静态 surfaces | 29 | 60 |

草丛每簇 42 面（≤50），共享花丛每簇 2,402 面（≤4,000），普通树叶 6 面。可编辑命名件/独立 GLB 保留；运行时合并自制树冠、花草、装饰、玻璃，两张共享 2048 图集，无逐商品节点或每 GLB 内嵌图。

评审相机按可见地台三角点和推定后角作刚性正交拟合，固定地台比例不变。实际原图为 2048 方图；最初屏幕预览为 1600，记录已换算到原图坐标。角点残差 10.06 / 10.55 / 10.64px（1400 方图），见 `camera-registration.json/png`。对照图是完整参考 / Godot 实景 / 50% 直接叠图，没有图像变形。房间墙高、柜台位置、树冠轮廓仍非逐像素复刻；室外背景在草地资产范围以外保持预览底色。

9×9 对应表面中位数：暖石墙 **2.019°**、石铺地 **9.926°**、草地 **9.270°**、橙子 **5.616°**，均≤10°。位置和完整 RGB/HSV 见取色图及 JSON，不把局部色相通过当作整体美术验收。

Godot Mobile / Vulkan **37/37 PASS**，路线从延长的外侧小径进入庭院，经过桌间、柜台、两侧树坛再回入口；验证边界、家具阻挡、入口往返、贴墙滑行、摇杆/按键、idle/run 与松手停止。曾多加一个重复路点触发测试工具“最多十点”的格式限制，已合并路点，保留长路径覆盖，未改共享测试核心。实际 15 秒原速视口录像，8 个时间点核对角色与运动；庭院专用 QA 机位加宽以容纳小径末端角色，设计对照机位不受影响。仅桌面行为与美术证据，没有物理手机性能结论。

角色 H≈1.7455m；侧拱净高 2.63m、台面 1.2005m、藤椅面 0.6904m、桌面 1.03785m，保持 ±15% 基线。同类已定家具尺寸没有改动。

```sh
blender -b -t 8 --python tools/art/build_coffee_shop_0.py
python tools/art/source/coffee_shop/render_r1.py r2 coffee_shop_0
python tools/art/source/coffee_shop/run_bench.py coffee_shop_0 --record
output/art-tools/bin/python tools/art/source/coffee_shop/package_series.py coffee_shop_0 r2
output/art-tools/bin/python tools/art/source/coffee_shop/check_series_colour.py coffee_shop_0 r2
output/art-tools/bin/python tools/art/source/coffee_shop/prepare_series_media.py coffee_shop_0 r2
output/art-tools/bin/python tools/art/source/coffee_shop/package_r2_details.py coffee_shop_0
```

源文件 `tools/art/source/coffee_shop_0/coffee_shop_0.blend`；`revision.py` / `revision2.py` 与 `courtyard_bench.py` 可复现，米制 Y-up、保留局部轴心。猫是静态装饰，不含动画或交互。豆罐新增小搁板、灰白猫换到无遮挡位置属于本轮为解决穿插/遮挡作的布置调整，已在全景中直接呈现。
