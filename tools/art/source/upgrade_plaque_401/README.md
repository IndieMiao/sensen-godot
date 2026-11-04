# SGODOT-401 可编辑源

赵云。来源为上官婉儿45195a15三选一设定页，不知火舞41ad15b6定B及三条修改；实际设定图在reference/。尺寸以文字为准，图中的人物比例不作测量基准。

`upgrade_plaque.blend`保留命名的单柱、连续圆顶木背板、空白米白牌面、四个哑光钉、两条浅枝及八片小月桂叶，另有PlaqueText空节点。导出时才合并成一个486面网格。没有字体、纹理、骨骼、动画或碰撞；柱脚底部中心为原点，Godot坐标Y上/+Z前，Blender对应(x,-z,y)。

`tools/art/build_upgrade_plaque.py`使用已验证的build_decor_assets基础几何/顶点色导出器，仅重建本件及manifest的追加条目。脚本会覆盖生成源，请将手工改动写回生成器。`spec.json`记录尺寸、颜色、预算和挂点。

原始GLB内PlaqueText是glTF空节点；`assets/farm/art/upgrade_plaque_import.gd`在Godot导入时将其转换成真正Marker3D，并设置与FarmArt.material一致的线性顶点色、roughness=.9 / metallic=0 / specular=.18。不得漏掉这个脚本及其UID。

复现（使用已有Blender5.2.2、Godot4.7.2、Python NumPy/Pillow和Node22.20）：

```bash
source ~/.codex-zhaoyun/env.sh
PLAQUE_SOURCE="$PWD/tools/art/source/upgrade_plaque_401"
blender --background --factory-startup --python-exit-code 1 --python "$PWD/tools/art/build_upgrade_plaque.py"
python3 "$PLAQUE_SOURCE/prepare.py" --runtime-ref 6cf0bcb2
node --experimental-transform-types --loader "$PLAQUE_SOURCE/ts_resolve.mjs" "$PLAQUE_SOURCE/make_view.ts"
godot --headless --path output/plaque-401/project --import > output/plaque-401/import.log 2>&1
godot --headless --path output/plaque-401/project --script res://configure.gd
godot --headless --path output/plaque-401/project --import > output/plaque-401/reimport.log 2>&1
python3 "$PLAQUE_SOURCE/prepare.py" --sync-import
python3 "$PLAQUE_SOURCE/verify.py"
nvidia-smi
SENSEN_LANGUAGE=en P0_SERVER_URL=http://127.0.0.1:9/v1 godot --path output/plaque-401/project --display-driver wayland --rendering-method mobile --rendering-driver vulkan --max-fps 30 --resolution 360x800 > output/plaque-401/render.log 2>&1
python3 "$PLAQUE_SOURCE/package.py"
```

新环境首轮可能需等待字体及资源导入；不要在原游戏工程里写临时场景。私有ADB5099，不改全局端口，用完关闭自己启动的进程。prepare在output/中检出固定b1代码，只在隔离副本替换占位；实际游戏工作树不改。隔离view用该b1的freshState/upgradeState/viewOf生成Lv3并给两条升级记录，无线上账号或存档操作。
