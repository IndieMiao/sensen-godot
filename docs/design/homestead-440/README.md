# SGODOT-440 · Lv15 整栋 v1.3 · 对齐439

2026-11-08复核：直接读取#858 `262533a7`的GLB顶点，Lv15与对应Lv8的X、Z整体包络完全一致，四件组件逐三角面匹配。`00e7e2ce`的两栋GLB及.import已满足要求，本轮保持原样，新增Lv5/Lv8/Lv15三列实拍、投影包围盒和接入说明。审阅提交到**SGODOT-439**。

[本轮说明及精确测量表](v1.3/README.md) · [默认木作三列](v1.3/default-a-review.png) · [默认石作三列](v1.3/default-b-review.png) · [木作门牌近景](v1.3/close-a-review.png) · [石作门牌近景](v1.3/close-b-review.png) · [45°木作](v1.3/45-default-a-review.png) · [45°石作](v1.3/45-default-b-review.png)。80项GLB检查、148项Godot Mobile实渲检查及冷导入通过。接入时注意Lv8会碰到木桌，长凳从(5,16)挪到(3,16)。

以下保留v1.2的制作与验证记录；Android结果是该轮历史证据，本轮未重跑Android。

刘备。木作 `master_farmhouse_a`、石作 `master_farmhouse_b` 是现有橙瓦小屋向上长成的两层整栋，含双老虎窗、花箱、完整四立面。依据用户2026-11-07 15:13批准的设定 v1.1 与197 LOCK-34；[参考与来源](../../../tools/art/source/homestead_440/reference/provenance.json)。

本次完整复用赵云 [#858](https://github.com/IndieMiao/sensen-godot/pull/858) 头 `262533a76cf8cef31d52782698f5837611aea6dd` 的 `porch_a/b`、`kitchen_wing_a/b`，替换旧的临时门廊和左翼。四件都以 house 锚点、yaw0、scale1合入，尺寸、位置、斜撑、长凳、石拱、烟囱、窗口和AO顶点色一致；没有再叠加旧placeholder偏移。原GLB和导入配置作为锁定源副本存于 [reference/439](../../../tools/art/source/homestead_440/reference/439/provenance.json)，不在运行时重复加载。

导出后逐三角面比较，四件的位置、法线和RGB float32数值全部与439原件一致。Blender内保留可编辑主楼和导入组件；最终合并直接读取原件缓冲，避免Blender自定义法线压缩引入变化。每栋仍仅一个mesh、一个surface。为避开原木门廊较高的悬挑顶，a主楼二层两只花箱抬高0.17m，窗、门廊和主楼轮廓保持原位；b主楼不调整。

| 资产 | 三角面 | surface | 总高（含烟囱） | 全宽 | 当前默认最高点 |
|---|---:|---:|---:|---:|---:|
| `master_farmhouse_a` | 7614 | 1 | 4.1085 m | 4.059971 m | y=227.94 |
| `master_farmhouse_b` | 7844 | 1 | 4.1885 m | 3.670000 m | y=226.32 |

同款Lv8组合（原房+439门廊+左翼）与Lv15的X包络完全相同：a `[-2.425000,1.634970]`，b `[-2.425000,1.245000]`；均在用户指定的合并包络内。1.634970m是439原件精确右界，对应指令中取两位的1.63m，没有截改原件。Z包络为a `[-1.537500,1.920000]`，b `[-1.537500,1.928000]`。两栋总高仍≤4.2m，当前默认及45°视角均整栋入画。

正门板中心仍为 `(-.35,.495,.855)`，原点、+Y上、+Z正面与原房一致。门、路、三牌、邮箱不移。门廊地坪顶0.035/0.036m，木前檐最低2.0295m；第14行原台阶上方0.13–2m无新增几何。原台阶保留。默认、门牌近景及45°正面视角的三牌中心射线均无遮挡。闭合后勤门只作背面外观，不增加出口、道路或交互。

## 配色核对

[配色表](../../../tools/art/source/homestead_440/reference/439/palette-comparison.json)核对了22个共用角色：橙瓦、灰白墙、木、绿窗、石、花叶等相同。440的深色盆土 `soil=#785C40` 对应439的 `soil_dark`；439另一个 `soil=#96764F` 是不同角色，不需把深盆土改浅。主楼继续用原 `house_cottage` 实际COLOR_0采样，四件直接保留439已有AO顶点色。原 `chef_sign_a/b` 的暖木与浅石相容，原文件不变。继续用 `FarmArt.material()`，无新增纹理或材质pass。

## 审阅图

- [默认镜头：Lv8 / Lv15并排](default-review.png)：四列依次木作Lv8、木作Lv15、石作Lv8、石作Lv15。
- [水平45°、默认尺度：Lv8 / Lv15并排](angle-45-review.png)。
- [水平45°近景对照](45-close-review.png)：看清同款斜撑、长凳、拱门和左翼。
- [门牌视角](door-sign-review.png)、[最高点y值](height-review.png)、[背面/左侧近景](rear-left-review.png)。
- 所有原始图随附：`lv8-a/b-*`、`lv15-a/b-*` 和 `current-default.png`。

实拍固定为隔离的真实 `farm-dev 8493a5c42` 农场场景、原光照和UI。同一30块田fixture，只切换外观模型，Lv8列为原房叠439四件，并非另一个等级场地；各列原始360×800，无缩放、重绘或调色。当前默认俯角43°、水平14.5°、视宽13.0227146m；45°默认尺度保持房屋屏幕位置，近景视宽6.72m。45°仅是审阅机位，不改变正式农场相机。近景隐藏画面下缘的远处人物，避免截头，默认图保留完整人物；周边树木不隐藏。原烟雾仅在审阅副本冻结同一相位，并移到新主烟口。

Lv8与Lv15两边都预览439接入建议：Bench从(5,16)移至(3,16)，左灌木向-X移1.50m；门廊地坪覆盖的两枚旧踏石隐藏，下一枚过渡踏石保留。这些都是审阅副本中的摆件操作，正式程序、导航、随机种子、玩家状态未修改。

## 验证与接入

69项GLB审计通过，含四件原始三角面/法线/顶点色逐值匹配、单surface、9000面预算、4.2m高度、Lv8包络、走道净空、有限属性及拓扑。Godot4.7.2 / Deck RADV Vulkan Mobile实际农场93项检查通过。独立Android API37 SwiftShader资产场景完成3次真实点击、完整人物/模型实渲、当前PID日志、安装包与包内模型读回；不代表完整农场玩法或实体手机性能。

空缓存冷导入及资源加载通过，两件源文件/.import hash不变；合法UID与 `nodes/root_script=null` 保留。详细记录：[GLB](glb-validation.json)、[实渲](render-validation.json)、[Android](android-smoke.json)、[冷导入](cold-import.json)。

接入时：将Lv15映射换为两栋整件，停用重复门廊/左翼；移动原烟口并落实Bench、灌木、踏石处理。四件挂接统一house锚点，`(-1.63,0,-.75)`只是已烘进网格的参考中心，不能再当偏移应用。详见 [接口合同](../../../tools/art/source/homestead_440/contract.md) 与 [制作/复拍说明](../../../tools/art/source/homestead_440/README.md)。439同款几何已核完，草稿#854等待两关验收。
