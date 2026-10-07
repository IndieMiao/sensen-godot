# SGODOT-186 · BLOCK THEORY · 刘备 R2

按 Figma `545:2959`（1544×1544）与不知火舞复审修订。保持已定房间、家具与角色比例，以宝蓝、黑框和冷灰为主；混凝土与背景去掉原先薰衣草紫，局部暖光来自灯具，入口有冷色窗光。

| 复审项 | R2 实现 |
|---|---|
| 工装裤 | 两条有间隙的锥形裤腿，侧面立体风琴袋与袋盖、裤脚翻边、压缝线、对折腰头回片、金属衣架与夹子。橄榄/黑/卡其三件原件，左右实例化；保持衣架和裤装总占地。 |
| 印花 | BT/42 字母、经纬地球轨道、山峰月亮、手绘交叉涂鸦四类，按挂衣和叠衣交错分配；保留 B 棒球夹克。印花仍走一张房间图集，水平印花压薄贴服装表面，原来重复锯齿笔画删除。 |
| 立体字 | BLOCK THEORY 与两幅字牌用 Nunito Black 粗圆体，主字保留凸起厚度，曲线细分 10；细字用稳定色块 UV，附整景原像素与 3 倍最近邻检查。 |
| 灯池 | 三盏真实不投影 SpotLight 分别照左侧通道、陈列台、后侧通道；调整方向、角度与能量，让整景实际可见。逐灯开/关对照见灯光核验，不用贴片假充光照。 |
| 地面 / 入口 | 大板地面改灰褐三档，背景灰褐；入口冷色窗光，黑皮凳减少紫色。深灰闪电垫移到入口可见空地，避开长凳。 |

最终总摆放 **183,894** 三角面，静态 surface **24**，低于 200,000 / 60。角色 **35/35 PASS**；墙 / 入口地板 / 胡桃木 / 皮凳四处色相差 **2.652° / 5.000° / 6.276° / 3.158°**，均 ≤10°。逐灯控制目标平均 RGB 增量 **46.967 / 60.450 / 60.225**，三个检查通过；全开控制与最终整景逐像素相同。完整结果见 `revision-verification.json` 与 `light-pool-verification.json`。植物沿用本轮共享深绿图集；植物 **9,286 面**，含入口树冠 **568 面**。按前后陈列、植物、玻璃分组合并；衣架/裤装/服装/印花原件和命名 Blender 仍可编辑、可复用，单独局部 pivot 不变。共享 benchmark core 未改。

机位用地台左/前/右角点拟合并推定后角，固定 **6.16×5.76m** 地台，不改模型尺度，不扭曲图片。三个角点残差 **8.82 / 10.09 / 9.39px**，原图不是校准物理相机；叠图仍允许总监看出布局与插画差异。

取色点随新相机重新定位到同一实体表面。首轮地板灰褐调整后，入口对应冷光地面色相未通过；按原图补入口冷色窗光，并纠正皮革偏紫，再验原坐标。皮凳保留烘焙纹理，实例材质额外使用 `[1.0,0.95,1.0]` 的微量颜色乘数校准压缩后的灰色；参数在摆放清单与本店组装脚本中可复现。低饱和灰色的色相敏感，保留完整 RGB/明度/饱和度和整图，不把四个样本当成全图相似分数。

灯光控制图使用同一模型、相机、环境，只开关三盏 SpotLight；各目标 49×49 像素差量证明每盏有实际贡献。画面标圈用于指明位置，差值图明确标注为诊断图。三盏不投影，原有五个壁灯/镜前点光和新增一个入口窗光都不增加阴影 pass；方向光仍是唯一阴影光源。

角色闭环路线：门内 → 绕陈列台 → 收银 → 试衣间 → 镜前；验证阻挡、通道净宽、进出、滑行、输入、动画与停止。15 秒实际桌面视口原速录像核对八时点，完整人物可见。本轮是 Godot Mobile/Vulkan 桌面证据，不是物理手机性能验收。服装是简化静态陈列、镜面使用绘制高光；最终视觉仍待不知火舞 Review。

```sh
blender -b -t 8 --python tools/art/build_clothing_store_a.py
python tools/art/source/coffee_shop/render_r1.py r2 clothing_store_a
python tools/art/source/coffee_shop/run_bench.py clothing_store_a --record
output/art-tools/bin/python tools/art/source/coffee_shop/package_series.py clothing_store_a r2
output/art-tools/bin/python tools/art/source/coffee_shop/check_series_colour.py clothing_store_a r2
output/art-tools/bin/python tools/art/source/coffee_shop/prepare_series_media.py clothing_store_a r2
output/art-tools/bin/python tools/art/source/coffee_shop/package_r2_details.py clothing_store_a
output/art-tools/bin/python tools/art/source/clothing_store_a/check_lights.py
```

可编辑源：`tools/art/source/clothing_store_a/clothing_store_a.blend`；重建逻辑：`revision.py` / `revision2.py`；本店灯光：`scenes/clothing_store_a/street_art.gd`。
