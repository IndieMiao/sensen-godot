# Market plaza · SGODOT-218 · 黄忠

本目录此批提供 12 件独立模型。以用户 2026-11-08 批准的房间版 v2.1 和上官婉儿派工尺寸为准；当前阶段见 `asset_stats.json` 的 `stage`。

米制，Y 朝上，+Z 为柜台/牌面的正面，原点在地面中心。模型不预转 45°，整场的摆位、旋转、导航和人物锚点由装配方的 layout 提供。无内置碰撞、相机、灯光或动画。遮阳有真实厚度、完整底面及两侧封口，柜台背面完整。

| 文件 | 占地 W×D | 高度上限 | 三角面上限 |
|---|---|---|---|
| stall_keeper | 3.20×1.60 m | 2.90 m | 2500 |
| stall_veg / fish / bakery / spice / tools | 各2.00×1.60 m | 2.60 m | 各1500 |
| flower_cart | 2.00×1.40 m | 2.40 m | 1500（按普通摊预算控制） |
| market_board | 1.20×0.30 m | 1.80 m | 600 |
| fountain | 直径3.00 m | 2.20 m | 2000 |
| produce_crate / basket / flower_tub | 实测见asset_stats | — | 各300 |

掌柜柜台台面 Y=1.05 m；柜台后局部 Z=-0.76…+0.04 留0.80 m净深。左右支柱在站位区外，建议Mei站在局部(0,0,-0.6364)，对应设定中的(1.75,1.75)与摊中心(2.2,2.2)、yaw45°。真正锚点以装配layout为准。普通摊正面同为+Z。

委托板右上角局部 X=0.24…0.49、Y=1.35…1.56 m留空；便签、招牌和价牌不包含文字或符号，`!` 徽标由运行时UI挂。`flower_tub.glb`是独立可复用件，喷泉旁放4个实例，不烘入喷泉。花盆与其他小件的尺寸可直接读取统计表。

12件均为单surface、哑光顶点色，无贴图。GLB导入按房间件关闭自动LOD/动画、light_baking=0，保留root_script=null；UID由Godot导入生成。`market_props_matte.tres`由每份.import的materials映射共用，实例化GLB即可正确显示顶点色。没有新增PNG，不涉及纹理compress/mode。

模型、源Blend和生成脚本对应；修改脚本后请在共享锁中运行Blender。`asset_stats.json`列出本批12件实际导出顶点的面数、AABB、字节和SHA256，装配场景统计由装配方另合并。未包含路灯、长椅、花槽，装配时复用street_kit。

审阅基准已更新为 yaw45° / pitch33°，背面附20°低俯角检查。最终v1为13,036三角面、12surface；12件均无开放边，所有尺寸/预算检查通过。
