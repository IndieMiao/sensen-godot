# 灶上普通锅 / Big Pot · SGODOT-282 · 0.2.8 / q(201)

刘备制作；规格 v1.1、设定审阅 282 `5d6fcf56`。一个 GLB 的两款空心锅、可掀盖结构、实际 Godot 图和检测记录已齐。上官婉儿技术检查、不知火舞画面验收、用户批准后合并；本 PR 仅进 `wp-3d-scene`，房间资产和 anchors 未改，程序由哪吒接入。

## 实际导入结果

| 变体 | 含把宽 × 深 × 高（m） | 面数 | surfaces |
|---|---|---:|---:|
| `pot_normal` | 0.235981 × 0.212 × 0.140 | 380 / 400 | 1 |
| `pot_big` | 0.280 × 0.214 × 0.242 | 684 / 700 | 3：锅身 1、盖子 2 |
| 整个 GLB | 两款共用锅底中心轴心，Y=0，+Z 朝前 | **1,064 / 1,100** | 4 |

[资产及程序挂点说明](../../../assets/props/stove_pot/README.md) · [manifest](../../../assets/props/stove_pot/manifest.json) · [验证摘要](validation.json) · [GLB/房间详细检查](glb-validation.json) · [实际 Godot 导入与镜头记录](godot-validation.json)。

两个 `mouth` 分别在 0.14 / 0.18 m。`pot_big/lid` 是后缘独立子节点，盖钮和小出汽管跟随它；打开是在原位置加 Y=0.06，再绕本地 X 转 **−20°**。闭盖的 `vent` 是 `pot_big` 的直接空子节点。空腔中心射线只命中底部内壁，没有汤面、食材或封口面。

Godot 4.7 会把重复名称自动唯一化成 `mouth2`，随资产交付的 `stove_pot_import.gd` 在导入时恢复两条准确的 `/mouth` 路径。`.import` 已明确 **`gltf/texture_map_mode=1`**、scale 1、关闭自动 LOD。

## 制作选择与接入提醒

- 原房间图集的近似陶色偏黄褐，不能保持设定的陶土红系列。采用规格允许的 **256² 陶色/铜色附图**，木盖钮取原 pantry 的蜂蜜木色；两款复用材质/贴图，原图集字节不变。两材质均不透明、无发光、无实时灯。详见 [取色来源](../../../tools/art/source/stove_pot_282/atlas-swatches.json)。
- **Standard 第 3 口灶用 yaw 45°**；XYZ 不变。yaw 0° 的耳把会碰门框，90° 会碰后墙，45° 两者均清。前两口保持 yaw 0°。按规格与可通行优先选择，并未修改游戏 anchors。
- **Deluxe 还残留一个合在 `kitchen_fittings.glb` 里的旧水壶。** 用户已批准仅在审阅场景剔除这部分。精确移除原水壶的 1,144 面，顶点与原水壶平移后最大误差 0.000000388 m；其余几何、UV、材质、原房间文件保持原样。[提取验证](deluxe-fixture-validation.json)。接入前须把这个旧水壶拆除，不能只隐藏 Basic 的 `kettle`。[原状冲突图](deluxe_original_conflict_detail.png) 和 [原状检测](original-room-validation.json) 保留了这一发现；其中九个失败是三炉 × 普通/大锅/掀盖与旧水壶的交叠，不能当成最终验证。
- **Deluxe 支承高度有 1 mm 差异。** 射线实测最高炉架 Y=1.292，规格表为 1.291。图与 manifest 保留表中 1.291，记录约 1 mm 的底部支承接触，程序接入可按最高炉架面校正。以下“无障碍穿插”不包括这处明确记录的支承接触。

## 验证与审阅图

最终 GLB/UV/挂点/真实房间验证 **1,277 项通过、0 失败**；实际 Godot 导入与 14 张截图验证 **36 项通过、0 失败**。Blender 5.2.2 LTS；Godot 4.7.2，Vulkan Mobile，AMD Custom GPU 0405 / RADV VANGOGH。这里是桌面实际渲染与几何验收资料，不包含 Android/手机性能结论或游戏接入测试。

覆盖九个规定炉眼，普通锅、大锅、开盖状态；盖子 11 个行程采样不碰锅身/耳把；与真实 `range_hood`、调味架、hanging cookware、Basic 烟囱、门框/墙等网格无障碍穿插。三间房都用故意下沉 2 cm 的锅做了检测正对照。前排两口大锅的实际间隙：Basic **0.05 m**、Standard **0.02 m**、Deluxe **0.05 m**。Basic kettle 隐藏，Deluxe 使用上面获准的审阅替换。

默认图均为原生 **360×800**，俯仰 **43°**、房间自己的偏航、P0 默认 6.72 m 视宽；焦点平移到厨房，未把图放大冒充默认镜头。另有明确标注的 1.25 m 视宽细节图。每张均署 `SGODOT-282 / LIU BEI`。

| 内容 | 图 |
|---|---|
| 普通锅 | [正面](pot_normal_front.png) · [3/4](pot_normal_three_quarter.png) · [侧面](pot_normal_side.png) |
| Big Pot | [正面](pot_big_front.png) · [3/4](pot_big_three_quarter.png) · [侧面](pot_big_side.png) · [掀盖](pot_big_open_lid.png) |
| Basic | [43° 默认](basic_room_43deg.png) · [厨房细节](basic_room_detail.png) |
| Standard | [43° 默认](standard_room_5_43deg.png) · [两口大锅并排](standard_two_big_43deg.png) · [厨房细节](standard_room_5_detail.png) |
| Deluxe | [43° 默认](deluxe_room_10_43deg.png) · [厨房细节](deluxe_room_10_detail.png) |

## 复现

[Blender 源文件、输入与运行方式](../../../tools/art/source/stove_pot_282/README.md)。生成脚本：`tools/art/build_stove_pot.py`；房间审阅准备与检查：`prepare_stove_pot_review.py`、`verify_stove_pot.py`、`review_stove_pot.gd`。独立 QA 项目在 `output/stove-pot-282/project`，使用独立用户目录、真实房间与实际 Avatar。不会加载游戏账号、存档或网络。

最终 GLB 与 PNG 经再次完整生成逐字节一致；贴图来源、原房间、导出资产和审阅图片 SHA-256 在验证文件内。GLB SHA-256：`04f6faee84c5f25629ce57d4bb884763ca3897dc87df9ac58b04bfc70a5d78ab`。
