# SGODOT-408 硬木林 Hardwood v1

赵云。本轮只交硬木模型，按上官婉儿11-04派活方向：以旧采集点Old Tree的tree_0为底，改胡桃色树干、深橄榄树冠，脚边独立年轮树桩和码放木料。卡408的槽位及亚麻等其他工作不在本提交范围。草稿PR进wp-3d-scene，等技术检查和不知火舞画面验收，不合并。

## 资产

- `assets/farm/art/hardwood_grove.glb`：**1,042三角形 / 1 surface**。整件含树冠及附件包围盒**1.4235 × 2.3000 × 1.297454 m（X/Y/Z）**，完全在1.5×1.5m槽位内。
- 原点为整件水平包围盒底部中心，Y上/+Z前，1.0倍摆放。无骨骼、动画或采后态；活树完整，旁边的小树桩不是将主树截断。
- 原tree_0为1,624面：保留树干和三条枝干、三团椭球树冠布局，整体按X×.78、Z×.82、Y×(2.3/2.68)拟合槽位，降低冠体细分与枝条倒角。核心672面；小树根24、年轮树桩214、三根木料132，共1,042面。移除原根部四团草，给树桩和木料让位。
- 树冠基础色7D9145、亮面96A954，保持橄榄色与饱和度；树干78472F、木料945B3D，截面BD895C/D0A575、年轮855235。年轮为分色几何，所有部件都使用同一个农场顶点色哑光材质，无贴图。
- 实际材质为线性顶点色，roughness=.9、metallic=0、specular=.18。`.import`的**light_baking=1**、texture_map_mode=1，UID为**uid://cbsp854xyhutr**；无自动LOD和动画导入。
- manifest只追加hardwood_grove一条，旧条目与顺序保持；原tree_0/tree_1/tree_2/sign文件未改。源部件及源SHA见spec.json。

## 两张审阅图

`SGODOT-408_HARDWOOD_v1_pond_L2_43.png`：固定b1头`2d481d66efd5d69f11101736db0799109c991218`的隔离副本，P0_SCENE=pond:pond_san_francisco_03（Fern Pond），模型位于**L2 (-.3,0,-9)**。调用原生调试步骤**goto:0.95:-8.4**，人物站在旁边，43°、6.72m默认缩放，原场景灯光、水面、HUD和镜头边界。360×800逻辑构图，桌面125%缩放原生450×1000像素；这是指定站位的默认镜头，不是出生点开场。

`SGODOT-408_HARDWOOD_v1_resource_comparison.png`：硬木、原spot_grove、spot_reed_bank、spot_herb_patch并排，全部原生比例，采用同一塘内环境及太阳参数、43°，独立SubViewport拍1800×1000。旧件来自附件zz_spot_art_old.gd，与farm-dev旧脚本仅差class_name这一行，未自行重配色或缩放旧件。

两图都是Godot Mobile Vulkan渲染，未后期调色、未裁剪，署名与标签附在图外。首轮检查后将深橄榄色提亮一档、三根木料转为横向码放，最终版本在塘中仍可辨认树冠体积、胡桃色木料和年轮。

## 验证和接入边界

29项原始GLB/尺寸/拓扑/朝向/顶点色/UID/manifest检查、17项Godot真实导入及场景检查通过；包括整个冠体/附件未超槽、156个年轮顶面三角形朝上、实际surface与面数、指定站位可走、模型完整入画。数据和SHA-256在validation-v1.json。

审阅只在output隔离副本中临时改PondScenery：增加L2模型，在随机抽样结束后过滤L2周围2.1m方形内的大灌木和花草，避免旧布景穿入新件；原随机序列及槽外散布不变，细地面草绒保留。不修改导航格、抛竿带、水面、MEADOW、出生点或镜头边界。真实接入时由程序按照已通过的槽位v2规则避让选中槽位；此PR没有提交modules/ponds/pond_scenery.gd。

Godot4.7.2 / Mobile Vulkan / RTX2060，渲染前确认GPU空闲、私有ADB5099，自己的Godot已退出。隔离P0 view由固定b1服务端代码生成，无线上采集、多人功能或真机性能结论。

源文件：`tools/art/source/hardwood_grove_408/hardwood_grove.blend`；生成器：`tools/art/build_hardwood_grove.py`。15个命名部件可编辑，导出副本合并；复现命令见源目录README。
