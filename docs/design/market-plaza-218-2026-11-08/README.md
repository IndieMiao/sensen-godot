# SGODOT-218 集市广场整场 v1 · 2026-11-08

最新：[旧金山排屋 v2 与门图标核查](v2/README.md)。下文保留v1审阅证据。

马可波罗交审：16×16 m场子、428铺石、近侧低件、三盆树、串灯和彩旗、两套带完整屋顶的排屋、可替换城市远景、20个锚点、实时碰撞导航。按用户已批v2.1/33°/排屋C和a8/a9制作。黄忠#877成品 `288b47b94f966981603b3d132552d6b16f923303` 装配于审阅副本，摊位坐标和遮阳没有改。

场景：`scenes/market_plaza/market_plaza_art.tscn`。具体坐标、依赖与程序接入见 [LAYOUT_HANDOFF](../../../assets/rooms/market_plaza/LAYOUT_HANDOFF.md)。

## 画面

[开场](opening.png)、[远角](far_corner.png)、[左角](left_corner.png)、[右角](right_corner.png)、[入口角](entry_corner.png)、[环路](ring.png)均为真实P0桌面Vulkan Mobile、360×800、带HUD。使用运行时基线 `069dfeb13a4988fa2c0d04b80b29af69fbcc2746` 加临时art/bounds/anchors/seats/33°镜头补丁，仅在忽略的 output 副本中生效；没有改正式玩法文件。fixture不连接正式服务。

- [开场及三角对照](p0-opening-corners.png)、[入口/环路/座位](p0-route-seats.png)：每屏保留原始360×800，标注置于图外。
- [旧金山全场](overview_san_francisco.png)、[通用全场](overview_generic.png)、[正俯视](topdown.png)：1000×1000独立美术审阅镜头，**不是P0跟随机位**。
- [通用套远角](far_corner_generic.png)：与SF同位置、同33° P0实拍；两套屋顶上缘完整，屏幕没有露空。
- [座位1](seat_1.png)、[座位2](seat_2.png)：实际P0 `_go_sit`、进入坐姿后的截图，非摆放静态人物。approach均可走，seat顺序正确。

开场柜台、委托板、Mei、特产箱、Nadia及喷泉上层入画；Map名字条离玩家屏幕包围盒22.736 px。右下主键区域没有高件。当前P0远角跟随仍受原3 m内缩camera clamp约束，未为截图改动该程序行为。

## 导航与剩余遮挡

[俯视复查图](navigation-review.png)将实际模型正俯视、实时导航采样、原遮挡位置、封闭带及Mei残余合在一张图；[验证JSON](validation.json)附精确结果。

- 运行时导航107×107、0.15 m格宽、角色半径0.21 m；8284→7371个可走格，新封913、新开0。
- 0.5 m采样、胸口1.0 m和头顶1.6 m：754→669个站位；遮阳/树冠遮挡47→0。检测最终成品导入后的世界三角面，遮阳取整面Y>1.8 m，树取全部网格，没有用估计冠幅替代网格。
- 六个小摊的背缝用不可见边界封住；Mei与喷泉之间新增0.445 m高的可见矮花槽。原圈路被a8/a9明确改为其余弧路；入口左右都能到喷泉区域，16段弧路、全部站位和座位均可达。
- **剩余是固定NPC：Mei (1.75,.05,1.75)脸可见，但1.6 m及更高头部射线仍被掌柜遮阳命中，胸口不挡。**她不属于可走采样点，未将“导航0遮挡”写成“所有人物0遮挡”。按指示保留锚点和黄忠模型，红圈标在俯视图，交上官婉儿决定后续。

## 验证与预算

独立无缓存美术项目：导入退出0、0 ERROR；37份本场景及供应件import/UID文件回读字节不变；SF/generic两套场景均能装配。UID全部来自Godot，不手编。

指定 `tests/p0/test_p0_outpost.gd` 在临时接入副本复跑：31个用例，30通过，1失败。`test_every_outpost_opens_on_its_kit` 的7个断言仍写死旧fruit_shop、旧外部锚点和旧镜头宽度/边界；[原始gdUnit结果](gdunit-outpost-results.xml)保留，不修改正式测试。座位顺序、掌柜交互、居民等其余用例通过。

[独立GLB顶点测量](geometry-measurements.json)：SF单段5272三角/1 surface、通用单段4860三角/1 surface；模型约6.508 m高，主体进深2.5 m，装饰突出计入总包络。场景摆放全模型计SF89,490三角、generic86,194三角，各113个实例surface；不含远景卡、角色和阴影重复提交。GLB仅网格/顶点色，地面共享428材质。

RTX2060 / Godot4.7.2 Vulkan Mobile、360×800实际帧总量（含角色、HUD、阴影等）：开场119,025 primitives /121 draw calls；远角144,451/103；环路121,401/102。完整9屏见 [review.json](review.json)。这些是桌面渲染计数，不是真机性能结论。

## 源与复现

`tools/art/source/market_plaza/market_plaza.blend` 保留命名零件、可编辑倒角和各独立导出集合；`build_market_plaza.py` 确定性生成本场模型；`layout.py` 输出布局，`review.gd` 在临时P0副本拍摄并导出实时导航/网格，`check_review.py` 对导出数据检查（依赖NumPy），`overview.gd`生成美术全场/俯视。

```sh
python3 tools/art/source/market_plaza/layout.py
flock ~/gs66-render.lock blender --background --factory-startup --python "$PWD/tools/art/source/market_plaza/build_market_plaza.py"
```

生成会覆盖Blend/GLB；不要丢失未回写脚本的手工编辑。Godot导入、实拍和gdUnit也必须在同一 `gs66-render.lock` 下运行并及时退出。审阅P0副本需叠入#877、上表程序接入字段与33°固定6.72 m临时桥接，再将review.gd复制到该副本作为主场景；不得将临时程序补丁提交。

本次仅草稿交审，程序接入和客户端发布另行安排。旧金山和通用套一并提前交第二眼，未宣称已验收。
