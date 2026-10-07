# SGODOT-180 · Milk Tea Shop · 刘备 R2.1

按不知火舞本轮评论及父卡 171 修订。原始参考 Figma `545:2962`，1544×1544；Basic Room 尺度不变，等待视觉复审。

| 复审项 | R2 / R2.1 处理 |
|---|---|
| 招牌缺笔画 P0 | 本场景显式启用附许可证的 Nunito Black 粗圆体，挤出 4mm、离板 5mm；加大 PICK UP 与 A 字牌。文字所有面显式使用图集留边固定色块，避免 K / I 的小 UV 岛串到底板色。全景逐字检查 MILK TEA / GOOD / MOOD、PICK UP、COLD DRINKS，细竖画现在可见。`signage-check.png` 上行是全景原像素，下行仅作 3 倍最近邻检查。小菜单文字保留，但不声称缩略图能读所有价格。 |
| 卡座被挡 | R2.1 将卡座重做为沿矮墙内侧的 2.05m 完整长凳，四段 18cm 厚薰衣草软垫、前沿包边线、短木脚和低靠背；粉/薄荷靠枕立起并后倾。左桌移到 (-1.80,1.15) 的卡座前，两把椅子放到对面，形成完整座位组合。座面离地 0.675m，保持 Basic Room 椅面基线。 |
| 冷灰墙砖、过黄木色 | 粉米色错缝砖分四档颜色，底层砂浆改相近粉米色；吧台面板与取餐柜为去黄、低饱和的粉米浅木。 |
| 地砖菱形 | 薰衣草方片由 0.115m 扩到 0.1495m，旋转 45°，保留 0.5m 地砖尺寸。 |
| 冷饮瓶在柜门外 | 重建空腔薄荷冷柜与背板、两侧、四层内架；彩瓶位于玻璃以内，增加低能量冷白柜内灯，玻璃及把手位于最前。 |
| 叶色 | 使用共享深绿修正 1ec21f9e。植物密度不因预算削减；龟背竹暗部不再泛黄发白。 |
| 相机对齐 | 三个可见地台边线交点，第四角按平行四边形推定；固定 6.18×5.68m 地台，最小二乘拟合正交相机，不缩放模型、不变形图片。相机与角点数据见 `camera-registration.json/png`。 |

| 当前预算 | 数量 | 限制 |
|---|---:|---:|
| 总摆放三角面 | 177,030 | 200,000 |
| 全部植物，含桌花 | 40,452 | 100,000 |
| 静态 surfaces | 27 | 60 |

34 个独立可复用原件，43 个房间摆放和 17 个共享植物摆放。装饰、玻璃、花草按组合并；原件 GLB 与命名源对象保留，两张 2048 图集，不嵌入每个 GLB。修复合并器在累计顶点数超过 65,535 时的索引溢出：加偏移前转 uint32，完整实际场景导出和 Godot 载入验证通过。第一版字体曲线过细分曾超预算，现以 2 段曲线保留粗轮廓并控制面数。小花和藤叶不投影；大盆栽保持原投影规则。

9×9 对应表面取色：墙砖 3.913°、入口薰衣草柱 2.449°、前沿粉瓷地砖 1.714°，均≤10°。新机位重新定位同一物理部位；原参考采样不变。墙面饱和度仍低于参考，完整 RGB/HSV 与位置见取色报告，不以三个样本代替全图视觉验收。

相机拟合的可见角点残差为 35.5 / 33.4 / 35.3px（1400 全景，最大约 2.5%）。设计图地台边长与现有固定地台比例不同，不能在保持比例的同时用单个正交机位完全重合；报告保留此限制。叠图是完整参考和完整实景的 50% 直接混合，没有图像变形。墙高、柜台和桌子的构图仍与插画有差异。

角色 H≈1.7455m；侧拱净高 2.63m、台面 1.2005m、椅面 0.69365m、桌面 1.048m，均保持已有 ±15% 基线检查。Godot Mobile / Vulkan 最终 **39/39 PASS**：入口、桌间、取餐、卡座、冷柜路线，碰撞、净宽、贴墙滑行、摇杆/按键、动画与松手停止。未修改共享 benchmark 核心。15 秒实际视口原速录像，8 个时间点检查完整角色、非黑画面与运动；这是桌面证据，不是物理手机性能结论。

```sh
blender -b -t 8 --python tools/art/build_milk_tea_shop.py
python tools/art/source/coffee_shop/render_r1.py r21 milk_tea_shop
python tools/art/source/coffee_shop/run_bench.py milk_tea_shop --record
output/art-tools/bin/python tools/art/source/coffee_shop/package_series.py milk_tea_shop r21
output/art-tools/bin/python tools/art/source/coffee_shop/check_series_colour.py milk_tea_shop r21
output/art-tools/bin/python tools/art/source/coffee_shop/prepare_series_media.py milk_tea_shop r21
```

可编辑源 `tools/art/source/milk_tea_shop/milk_tea_shop.blend`；修订脚本 `revision.py` / `revision21.py`，本系列显式启用的字体与相机工具为 `coffee_shop/liubei_r2.py`，不会修改赵云生成器。米制 Y-up、原局部轴心。生成会覆盖源，手工修改须回填生成器。

R2.1 根据 11:13 的新增复审只修卡座组合；39/39 路线、家具阻挡和净宽全部重跑，桌前/中央/入口净宽为 1.17 / 1.635 / 1.85m。新卡座近景、最新全景和录像作为 R21 附件另发，保留 R2 原附件与交付核验，不覆盖已发文件。
