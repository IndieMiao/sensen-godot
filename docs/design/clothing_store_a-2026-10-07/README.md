# SGODOT-186 · BLOCK THEORY · 刘备 R1 修订

根据 Figma `545:2959` 原图与不知火舞两轮评论改材质、造型和陈列。保持 Basic Room 尺度，以冷灰/宝蓝为本场景色调，暖色照明只来自灯具。待总监视觉 Review。

| Review 项 | 当前处理 |
|---|---|
| 地面 | 改为 1.2×1.08m 水泥大板，细缝、烘焙斑驳、粗糙度 0.42；深灰地毯。 |
| 墙 | 黑金属分框、宝蓝墙板，保留 BLOCK THEORY 和橙皇冠；增加四组橙/紫不规则干刷条及细碎边。 |
| 长凳 | 黑钢框、连续厚皮垫、六段横缝及双排细针脚，去掉圆柱状鼓包；保留占地。 |
| 中岛 | 深胡桃木台面/下层、黑钢框、印花折叠衫、棒球帽、蓝白高帮鞋、木质格栅箱；桌面高度对齐既定基线范围。 |
| 服装 | 灰/黑/白/紫上衣，左右三色工装裤；右侧黑白印花 T 恤、紫帽衫、B 棒球夹克；厚度、口袋、袖口条纹。 |
| 灯光 | 三盏黑吊灯独立发光底盘及三个不投影 SpotLight 灯下光池；四根自发光暖白壁灯，镜框独立暖 LED。无体积雾、无额外阴影 pass。 |
| 柜台/海报 | 黑竖纹柜身、木台面、显示器、笔筒、黑盆共享龟背竹；三幅黑框原创字样/线描海报。 |
| 入口/植物 | 黑框双门、外部树冠剪影、闪电垫；空心黑方盆加共享白掌；衣架使用共享绿萝加龟背竹冠部，密度不靠删植物压预算。 |
| 试衣间 | 黑拱、深灰帘、圆凳保留；镜面仍为绘制高光。 |

总摆放 **82,872 面**，植物 **9,286 面**（含入口树冠，整个窗景保守计入），静态 surface **24**，低于 200,000 / 100,000 / 60。房间与共享植物各一张 2048 图集，无 GLB 内嵌图片，mipmap + VRAM 压缩。衣服/鞋/帽/叠衣按前后分组合并，原件 GLB 和命名 Blender 仍可复用；植物、小叶/花、窗景不投影，落地盆有碰撞。七组共享植物使用 179 R2.1 原图集，无本场景调亮植物贴图。

角色 **35/35 PASS**：门内→绕桌完整一圈→试衣间→镜前→收银，家具阻挡、进出、滑行、输入、动画和释放停止。桌—凳 **1.215m**，桌—右衣架 **1.595m**，桌—收银 **1.22m**，都按真实碰撞面射线取宽度；右衣架测量由初稿误指右边界更正为衣架前面到桌后面。门 2.46m、柜台 1.202m、桌 1.01255m、长凳 0.682m，全部在 Basic Room 同类 ±15%，未改角色或基线。15 秒实际视口原速视频与八时点检查，非 Android/实机性能验收。

色相样本：宝蓝墙、入口一块冷光水泥、胡桃木和黑皮面，色相差分别为 **3.04° / 7.00° / 3.49° / 5.00°**，9×9 中位数，≤10°，详见 `colour-verification.json` / `colour-patch-comparison.jpg`。地板首次取到入口垫，已重新定位到入口侧的真实冷光水泥区域；参考地板和皮革饱和度很低，色相对像素位置敏感，必须同时看完整原图和 RGB/明度。仅代表标注表面，不声称所有地板都与插画同色。当前整体比原图更冷，灯池、金属反光、服装印花和树冠仍有视觉差异。

```sh
blender -b -t 8 --python tools/art/build_clothing_store_a.py
python tools/art/source/coffee_shop/render_r1.py r1 clothing_store_a
python tools/art/source/coffee_shop/run_bench.py clothing_store_a --record
output/art-tools/bin/python tools/art/source/coffee_shop/package_series.py clothing_store_a r1
output/art-tools/bin/python tools/art/source/coffee_shop/check_series_colour.py clothing_store_a r1
output/art-tools/bin/python tools/art/source/coffee_shop/prepare_series_media.py clothing_store_a r1
```

可编辑源 `tools/art/source/clothing_store_a/clothing_store_a.blend`，同目录 `revision.py`、`street_bench.py`。仅本店 `scenes/clothing_store_a/street_art.gd` 添加三个 SpotLight；五盏短距点光提供壁灯/镜前局部亮度。未修改共享 benchmark core；隔离适配器沿用 Jolt 全接触点采集。

待视觉复审：构图仍为既有房间版本，服装、鞋和海报都是简化静态陈列；印花是原创几何笔划，镜子无实时反射；大叶以共享植物替代设计图种类；局部涂鸦仍偏立体，光池与插画不同。附原图/实景/直接 50% 叠图、细节、正交、角色/碰撞和面数证据，技术通过不替代视觉验收。
