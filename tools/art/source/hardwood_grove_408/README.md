# SGODOT-408 硬木林可编辑源

赵云。来源是农场tree_0/旧Old Tree，方向由上官婉儿11-04派活、不知火舞同意：深红棕胡桃树干、偏橄榄深绿树冠、脚边独立年轮树桩和码放木料。reference/保存硬木/普通木图标、旧采集点脚本、已通过槽位v2清单和示意图。

生成器`tools/art/build_hardwood_grove.py`读取farm_reference_kit.blend的tree_0集合，撤销原始联系表偏移，保留树干、三根枝条及三团椭球冠体布局，整体按X×.78、Z×.82、Y×(2.3/2.68)拟合槽位，并降低细分。源码与源SHA记录在spec.json；没有修改旧树文件。

原tree_0为1624面；去掉原根部4团草，冠体16×10改12×8、枝条倒角改一段，树干/枝条/三冠共672面。添加24面树根、214面年轮树桩、132面三根木料，合计1042面。`hardwood_grove.blend`保留15个命名可编辑部件；导出副本才合并。

坐标用Godot米制Y上/+Z前，Blender映射(x,-z,y)。全包围盒底部中心为原点，树冠及脚边物件都在1.5m槽内。活树完整、木桩独立，不是采后态。

运行时使用线性顶点色和农场哑光参数（roughness .9 / metallic 0 / specular .18）。专用import脚本不改其他材质；light_baking=1，texture_map_mode=1，Godot自动生成UID。

复现（已验证Blender5.2.2/Godot4.7.2/Node22.20，Python需NumPy和Pillow）：

```bash
source ~/.codex-zhaoyun/env.sh
HARDWOOD_SOURCE="$PWD/tools/art/source/hardwood_grove_408"
blender --background --factory-startup --python-exit-code 1 --python "$PWD/tools/art/build_hardwood_grove.py"
python3 "$HARDWOOD_SOURCE/prepare.py" --runtime-ref 2d481d66
node --experimental-transform-types --loader "$HARDWOOD_SOURCE/ts_resolve.mjs" "$HARDWOOD_SOURCE/make_view.ts"
godot --headless --path output/hardwood-408/project --import > output/hardwood-408/import.log 2>&1
godot --headless --path output/hardwood-408/project --script res://configure.gd
godot --headless --path output/hardwood-408/project --import > output/hardwood-408/reimport.log 2>&1
python3 "$HARDWOOD_SOURCE/prepare.py" --sync-import
python3 "$HARDWOOD_SOURCE/verify.py"
nvidia-smi
SENSEN_LANGUAGE=en P0_SERVER_URL=http://127.0.0.1:9/v1 P0_SCENE=pond:pond_san_francisco_03 godot --path output/hardwood-408/project --display-driver wayland --rendering-method mobile --rendering-driver vulkan --max-fps 30 --resolution 360x800 > output/hardwood-408/render.log 2>&1
python3 "$HARDWOOD_SOURCE/package.py"
```

prepare只在output隔离副本里改PondScenery，临时添加L2模型，并在随机数取完后过滤槽位周围2.1m方形内的大灌木/花草，避免原有布景穿入新件；不改随机序列、导航、水面、镜头边界、出生点。细小地面草绒保留。生产接入时由程序按槽位选取规则处理避让。

review读取P0_SCENE，实例化原生P0Pond；调用原生goto:0.95:-8.4，保留43°/6.72m默认缩放，不冒充从出生点就能看到L2。并排图用同一环境/太阳、原生比例的spot_grove/spot_reed_bank/spot_herb_patch，旧脚本与farm-dev版本仅差class_name这一行。所有审阅实例及对照用件都不入运行时分支。
