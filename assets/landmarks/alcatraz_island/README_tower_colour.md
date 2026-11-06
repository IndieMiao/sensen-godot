# SGODOT-424 双塔正式配色 / 主楼图形牌同步

黄忠。对应马可波罗 #792 / bf0c31b1c871011008b455434d167224d14de59c。
实际色板路径为tools/art/source/alcatraz_island/palette.json；审阅使用该头完整岛景和原光照。

四个塔仅修改COLOR_0的RGB字节，GLB的JSON、其它二进制数据（顶点、法线、索引、alpha等）
全部逐字节一致，四份.import/UID也不变。源blend材质和原生成器色板同步；55m切档和摆位保持。

| 部位 | 调整前 | 调整后 | 依据 |
|---|---|---|---|
| 灯塔墙体 | #EEE8D6 | #EFE7D4 | 暖白靠近暖石墙，仍比主楼浅 |
| 灯塔高光白 | #FFF5E1 | #F6ECD9 | 压低最亮白，保留白塔轮廓 |
| 灯塔屋顶 | #B8AB8C | #A4A08F | 与主楼roof相同 |
| 灯塔窗玻璃 | #547981 | #608F99 | 与主楼glass相同 |
| 水塔石脚 | #B4AE9B | #CBB48F | 与台地stone相同 |
| 水塔锈红中间色 | #A86C48 | #AC7955 | 稍提亮、降饱和 |
| 水塔亮面 | #C48C5E | #C1946D | 收住亮橙，接近整岛暖木色 |
| 水塔暗面 | #80513B | #7F5B44 | 保留深浅层次，降低饱和 |
| 铁箍 | #765344 | #6D5746 | 较安静的深褐 |

HSV饱和度：锈红0.571→0.506，亮面0.520→0.435，暗面0.539→0.465；
灯塔屋顶0.239→0.128。全部旧新值、线性编码和sRGB加权值在source/colour-map.json。
同角色色块在近远档中编码完全一致；灯塔3262/830面，水塔3546/774面，均1surface。

主楼远档是独立小增量：同步bf0c31b1空白青绿牌和中央奶油灯塔剪影，不烘文字。
219面旧字换为7面图形，远档2417→2205面，其余已验收远档三角位置/法线/颜色全部相同。
近档7869面、远档2205面，55m、原点、包围、UID不变。详见README_museum_far.md。

交接：替换4个塔GLB及更新后的alc_far_manifest.json、alc_museum_far.glb和其manifest；
保留原5份import/UID。主体owner保留旧摆位/LOD，避免整岛生成器又写回旧色或museum_proxy。
此PR不改主体layout、场景、海面材质或近档主楼。源与审阅见：

- tools/art/source/alcatraz_tower_color_424/
- docs/design/alcatraz-tower-color-424-2026-11-06/
- docs/design/alcatraz-museum-far-424-2026-11-06/v1.1/
