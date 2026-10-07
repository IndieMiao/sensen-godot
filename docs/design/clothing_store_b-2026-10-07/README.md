# SGODOT-185 · Clothing Store B · 刘备 R1 修订

依据 Figma `545:2963` 原图与不知火舞两轮评论修订，沿用 179 R2.1 共享植物与合批做法。Basic Room 比例固定，待总监视觉 Review。

| Review 项 | 当前处理 |
|---|---|
| 长凳 | 2×4 方格鼓包：每块有曲面肩部、真实下凹中心和小钉扣；保留原占地，金色脚、连续软包基座。 |
| 地板/墙 | 地板改粉米木色、减窄拼缝、降低粗糙度；墙面粉线框加深加厚。 |
| 左衣架 | 八件裙装，蓬袖与裙褶体积，小花/波点；五种基础裙装，再实例化。 |
| 右衣架 | 上排七件、下排六件，保留衣服厚度；三色上衣复用。 |
| 圆台 | 保留 2.34m 直径，整体后移 0.4m；上层五包与花瓶，下层五双鞋和两摞针织衫。 |
| 鞋包 | 四色基础包；粉/黑鞋、薄荷玛丽珍、小白运动鞋四种鞋型/配色，保留可复用原件。 |
| 首饰柜 | 项链胸像、戒指、耳环 T 架/吊坠、太阳镜，透明玻璃。 |
| 入口/橱窗 | 金框玻璃、门外天空树冠、粉垫、共享盆栽；橱窗粉裙腰部蝴蝶结、礼盒。 |
| 灯与试衣间 | 三层花瓣吊灯、四盏暖壁灯；保留粉拱帘/圆凳，立镜改金框。 |

总摆放 **113,770 面**，植物 **11,272 面**（含花瓶、窗外树冠），静态 surface **18**，低于 200,000 / 100,000 / 60。房间 / 植物各一张 2048 图集；衣服、鞋包按前后组合并，保留独立 GLB、局部 pivot 与命名源零件。小叶、花、窗景不投影；吊灯为自发光，另加五盏局部无阴影点光。实际导入无嵌入贴图，启用 mipmap 和 VRAM 压缩。

取色点见 `colour-patch-comparison.jpg` / `colour-verification.json`：对原图和运行时同类、同位置的亮面取 9×9 中位数，地板/墙板/长凳色相差 **4.21° / 4.50° / 0.87°**，阈值 10°。首轮地板偏差 10.13°，已据此重调；墙首选误取到压顶，重新标定到墙板后再检查。色相指标不涵盖全部明度、饱和度或造型相似度。

门 2.46m、首饰台 1.07625m、圆台 1.033m、长凳约 0.68m，均在 Basic Room 同类 ±15%。圆台碰撞使用 24 边凸体，保持真实圆形外轮廓。实际角色 **35/35 PASS**，完整绕台一圈、到试衣间/镜子/首饰柜；三处通道净宽：左衣架 **0.985m**、后衣架 **1.321m**、长凳 **0.857m**，均实际射线测量，不拿包围盒角落误算通道。15 秒原速视口视频与碰撞截图随卡；不是 Android/物理设备性能验收。

```sh
blender -b -t 8 --python tools/art/build_clothing_store_b.py
python tools/art/source/coffee_shop/render_r1.py r1 clothing_store_b
python tools/art/source/coffee_shop/run_bench.py clothing_store_b --record
output/art-tools/bin/python tools/art/source/coffee_shop/package_series.py clothing_store_b r1
output/art-tools/bin/python tools/art/source/coffee_shop/check_series_colour.py clothing_store_b r1
output/art-tools/bin/python tools/art/source/coffee_shop/prepare_series_media.py clothing_store_b r1
```

源文件 `tools/art/source/clothing_store_b/clothing_store_b.blend`，同目录 `revision.py`、`boutique_bench.py`。隔离适配器沿用全部接触点采集，未改共享 harness。

待视觉复审：服装仍是静态陈列资产；鞋包/首饰和印花比设计图简化；后排鞋部分被上层遮挡，镜面为绘制高光；植物种类和橱窗景色是共享库替代；整体更亮、陈列节奏更规则，圆台和长凳位置有为通行作出的差异。
