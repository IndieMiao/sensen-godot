# SGODOT-185 · Clothing Store B · 刘备 R2

依据 Figma `545:2963`（1489×1544 原图）及不知火舞复审。沿用已定的粉桃墙、粉调木地板、方格软凳、圆台直径和家具比例。

| 复审项 | 本轮修改 |
|---|---|
| 花瓣吊灯 | 删除球泡，改为三层交错的曲面花瓣，每片有扇贝轮廓、12mm 内外厚度和封边，单独暖色内扩散罩。保留花茎/金属帽；外罩微弱按图集发光，内罩独立发暖光。 |
| 首饰柜 | 十组可辨陈列：珍珠/金链肩颈胸像各一组、两组宝石耳环 T 架、两组绒面戒指托盘、黑/金太阳镜各一组、两张珍珠耳钉展示卡。实做肩颈、项链珠粒、吊坠、眼镜深色镜片、戒指宝石；降低柜玻璃不透明度。 |
| 鞋 | 粉色高跟鞋有独立后跟和开口鞋面，黑色玛丽珍有低跟/搭带/金扣，白运动鞋有厚底/脚踝衬垫/鞋带；保留一双薄荷玛丽珍和可复用原件。 |
| 右架上衣 | 蓝色有领 Polo、米白圆领花朵、薄荷长袖 V 领、粉色船领条纹四种，替换挂架上下层的分配；不只是同款换色。 |
| 入口 | 粉色垫移入可见入口空地，避开软凳边缘。共享深绿植物保留，小叶和花不投影。 |

陈列件保留独立 GLB 和 Blender 命名对象，运行时合并服装/装饰/玻璃；场景与植物各一张 2048 图集。细首饰/印花采用稳定图集色块防采样串色，非每件一张图。最终总摆放 **120,414** 三角面，其中植物 **11,552**（含内嵌花束等 5,300），静态 surface **19**；限制分别为 200,000 / 100,000 / 60。角色 **35/35 PASS**。地板 / 墙板 / 软凳三个实体对应亮面色相差 **5.662° / 0.566° / 1.436°**。

机位用地台角点刚性拟合，固定 6.16×5.76m 地台；原图不是正方形，1400 输出按同样比例留边，不拉伸。左角被原图裁边，按可见边交点估计，三角点残差为 13.79px / 16.04px / 15.17px，误差如实记录。保留完整参考/实景/直接叠图；陈列与墙面细节仍非像素复刻。

Godot Mobile/Vulkan 隔离角色绕圆台、软凳、衣架、首饰柜与入口，验证家具阻挡、边界、净宽、输入及动画。15 秒原速桌面录像与细节照片另附，不代表物理手机性能或美术验收。

```sh
blender -b -t 8 --python tools/art/build_clothing_store_b.py
python tools/art/source/coffee_shop/render_r1.py r2 clothing_store_b
python tools/art/source/coffee_shop/run_bench.py clothing_store_b --record
output/art-tools/bin/python tools/art/source/coffee_shop/package_series.py clothing_store_b r2
output/art-tools/bin/python tools/art/source/coffee_shop/check_series_colour.py clothing_store_b r2
output/art-tools/bin/python tools/art/source/coffee_shop/prepare_series_media.py clothing_store_b r2
output/art-tools/bin/python tools/art/source/coffee_shop/package_r2_details.py clothing_store_b
```

源文件 tools/art/source/clothing_store_b/clothing_store_b.blend，revision.py / revision2.py 与 boutique_bench.py 可复现；等待不知火舞复审。

细长包带、墙框和滚边也改用稳定图集色块，修正最终 mip 采样黑缝。整景、四项细节与录像八时点已目视核验；独立项链与鞋带是简化静态陈列。
