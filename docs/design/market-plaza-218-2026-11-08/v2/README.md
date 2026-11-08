# 集市旧金山排屋 v2 · #883 增量

按上官婉儿对 `2516abd7b` 的复审，将旧金山套改成八栋独立彩色维多利亚排屋。通用套、摆位、锚点、碰撞与导航保持原值。黄忠正在 #877 改Mei遮阳；本轮实拍仍固定使用其已审 `288b47b9`，不混入未审增量。

## 排屋变化

[前后全景](sf-before-after.png) / [旧金山与通用套](sf-vs-generic.png) / [新全景原图](overview_san_francisco.png) / [远角前后](far-before-after.png) / [远角原图](far_corner.png)。全景1000×1000独立美术机位，P0远角360×800、yaw45°、pitch33°、宽6.72 m。沿用相同镜头和灯光；通用全景逐像素与v1一致。

从西侧近端沿排屋到北侧近端依次为蓝、粉、奶油、黄、薄荷、蓝、粉、奶油，转角两栋也不同色。每栋整墙着色，奶油白窗框和檐口：

| 部位 | 色值 |
|---|---|
| 蓝 / 粉 / 奶油 / 黄 / 薄荷墙 | `#6398BC / #D5888C / #E8D1A4 / #DDB354 / #7DAE9A` |
| 统一描边 | `#F5ECD9` |
| 相应屋面 | `#85786D / #98766D / #A18B6C / #9B825E / #6F8579` |

八栋各有一个二层三面凸窗，主体从墙面1.25 m探到1.65 m，投影0.40 m，另有薄窗框/压顶。三角山花与带奶油檐口的平顶交替；相邻檐口6.0/6.4 m，差0.4 m。三角屋脊朝进深方向，不再沿整条排屋连成屋脊。按m45_v1保留浅台阶、奶油侧墩、门廊立边及小山花门罩，所有门窗只做装饰，无文字。

完整封闭屋顶/后背保留。独立GLB测量见 [geometry.json](geometry.json)：三角屋顶款5125三角，平顶款5292三角，每栋1 surface；总高含饰线分别6.665/6.530 m，主体进深2.5 m。八栋合计41,668三角，比v1八次摆放的42,176略低。

## 保持项与验证

`layout.json` 只改8段排屋的SF模型引用及SF文件列表（4→8个文件），其余JSON深比较相同。通用GLB、材料、地面、小件、导航快照等42份非SF运行时文件逐字节不变；运行时全部11,449个导航格逐格相同，可走格仍7371。669个0.5 m可走站位，胸口/头顶遮阳及树冠遮挡仍0；座位、入口左右通路与环路可达。

[保全/冷导入证据](preservation.json)、[实拍状态](review.json)、[遮挡与路径结果](validation.json)、[本次实时导航快照](navigation_snapshot.json)。资产目录的导航快照保留v1原件；本次快照只因layout SF文件引用变化有新的来源SHA，walkable内容完全一致。

独立无缓存导入0 ERROR；8份SF import/UID没有被导入改写，两套场景装配通过。新UID由Godot生成。所有渲染/导入使用gs66-render.lock，进程已退出。正式P0和测试代码没有改；v1 `test_p0_outpost` 的7个旧fruit_shop/锚点/镜头断言仍由程序接入时更新，本次不改测试。

## 远角/环路的门图标核查

不是重复锚点，也不是常驻屏外贴边指示。layout及运行时只有一个exit和一个`badge_exit=(5.6,1.1,8.0)`，临时P0配置的anchors覆盖为空；两张图中的节点都是同一个 `room:exit` 名字条。

旧审阅脚本切位后等待10帧（录制60FPS，约167 ms）。现行 `P0Ui._fold_name_bar` 用160 ms收起、170 ms计时器隐藏，恰好拍到宽度已经缩至32 px但尚未隐藏的最后一帧。这个折叠条沿用上一次位置：远角(73.09,522.54)，环路(73.09,411.10)，因而看起来浮在Nadia旁或叠座位。真实badge投影分别在y=839.72和720.06，均在HUD可用标记区y=98…708外，常规exit图标已经隐藏。

[第10帧/稳定帧对照](exit-icon-timing.png)、[节点状态与投影JSON](exit-icon-diagnosis.json)。第10帧记录`bar_visible=true, bar_folding=true, openness=0`；再等30帧，两个位置均为`bar_visible=false, icon_visible=false`。审阅脚本改为至少等待30帧后取验收图，另保留过渡帧供诊断；没有改布局或程序UI。[稳定环路](ring.png)、[开场](opening.png)可直接复核。

源Blend和SF生成脚本已同步。只重导SF件可用：

```sh
flock ~/gs66-render.lock blender --background --factory-startup --python "$PWD/tools/art/source/market_plaza/build_market_plaza.py" -- --sf-only
```
