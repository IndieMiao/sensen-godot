# SGODOT-401 Upgrade Plaque v1

赵云。按上官婉儿45195a15、不知火舞41ad15b6的B案：单柱圆顶木牌、贴着顶缘的小月桂叶、四角哑光钉、空白暖米白牌面。草稿PR进wp-3d-scene，先技术检查及画面验收，再报用户；本轮没有提交b1接入。

## 交付规格

- `assets/farm/art/upgrade_plaque.glb`：**486三角形 / 1 surface**，0.50 m宽、0.70 m高、0.112 m总深度，运行时1.0倍。原点是柱脚底面中心，Y上、+Z前；柱脚实际接触面中心(0,0,0)，牌板前伸，因此整件Z范围为-.036～+.076 m。
- 米白面板0.40×0.28 m，四钉放在木边框上，未侵入米白面板。为圆角与边缘留余量的建议文字区为**0.38×0.24 m**，可容3–4行；牌面没有文字或图案。
- 真正的`Marker3D PlaqueText`位于**(0,.43,.078)**，即牌面中心+.002 m朝外；局部旋转/缩放为单位，metadata含size、face_size、surface_offset_m。raw GLB空节点由同目录导入脚本转换，PackedScene中保留。
- 月桂叶是两条浅浮雕小枝、共8片约4cm小叶，最高点低于木牌顶缘；不在顶上竖起草叶。四钉为暗铜/木色806747，metallic=0。统一农场哑光材质roughness=.9、specular=.18，线性顶点色，无贴图。
- 木色采用原农场wood/wood_light家族，米白FFF0D5比原sign的FFF4D2稍暖。不是照片木纹，也没有另加发光、描边或金属高光。
- `.import`有Godot生成UID `uid://dln378d6gexjw`，texture_map_mode=1；静态件禁用动画/LOD。manifest只追加upgrade_plaque一条，所有旧条目及顺序保持。

## 游戏审阅

两张署名图：默认43°农场开场、门两侧两牌并排近景。使用固定b1头`6cf0bcb2a89dc7aa807291975402ab2a6d5fa6a0`的隔离副本，临时将左牌占位换成新GLB，在原PLAQUE_CELL(7,14)按1.0倍、原yaw=.35 rad摆放。右侧保留原sign.glb的0.8倍（高约.612 m）。玩家、HUD、农舍、灯光均为原游戏实现。

最新b1默认开场会根据已开放田块放宽：本Lv3的12块田为原生43°、约10.927 m正交宽，360×800逻辑构图，桌面125%缩放输出450×1000原始像素；未强改成6.72 m。两牌近景另用同43°/14.5°朝向、4m宽的SubViewport，1400×1000，无HUD遮挡。图片未调色、未裁剪，署名页脚加在游戏画面外。

两行日期`Lv2 · Nov 4 / Lv3 · Nov 6`是临时Label3D演示，挂在PlaqueText，深度测试开启、非billboard，未烘进模型；不是实际玩家升级记录。隔离view只用来令Lv3升级牌显示。

24项原始GLB/尺寸/顶点色/空白面/UID/manifest检查及Godot真实导入、挂点类型、材质、文字区和游戏实渲检查通过；数字与SHA-256见validation-v1.json。RTX2060 / Godot4.7.2 / Mobile Vulkan，私有ADB5099，渲染前GPU空闲，自己的Godot已退出。未进行真机或预览包发布。

## 程序接入提示

用PackedScene实例化可以保留PlaqueText；`FarmArt.instance()`只提取网格，会丢失挂点，若继续用它须按manifest重建Marker3D。模型本身不带碰撞，保留现有升级牌“不阻路”的规则；显示条件、Upgrade Plaque名字条、升级日期管理均由后续程序接入。本PR不改scenes/p0/p0_farm.gd。

源：tools/art/source/upgrade_plaque_401/upgrade_plaque.blend，生成器tools/art/build_upgrade_plaque.py；完整复现步骤见源目录README。
