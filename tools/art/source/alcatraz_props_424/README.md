# 424 重复小件源文件 / 赵云

`alcatraz_props.blend` 保留十种原型的命名collection及部件；`tools/art/build_alcatraz_props_424.py` 生成几何、顶点色、单surface GLB及独立 `props_manifest.json`。不覆盖主场景manifest/layout。尺寸以本次派活为准，2m段长、角点原点、单根树脚遵循34df9c0b交接合同。

渲染锁和顺序要求：所有Blender/Godot命令使用 `flock ~/gs66-render.lock`，每一步必须等待退出后才执行下一步；锁排队不表示已完成导入。不要让旧缓存替代新导入，不启动常驻编辑器。Godot环境通过私有ADB5099。

从仓库根目录复现（Python需要NumPy/Pillow）：

```bash
mkdir -p output/alcatraz-props-424
source ~/.codex-zhaoyun/env.sh
flock ~/gs66-render.lock blender --background --python-exit-code 1 --python "$PWD/tools/art/build_alcatraz_props_424.py" > output/alcatraz-props-424/build.log 2>&1
python3 tools/art/source/alcatraz_props_424/prepare.py
flock ~/gs66-render.lock godot --headless --path "$PWD/output/alcatraz-props-424/project" --import > output/alcatraz-props-424/import.log 2>&1
flock ~/gs66-render.lock godot --headless --path "$PWD/output/alcatraz-props-424/project" --script configure.gd > output/alcatraz-props-424/configure.log 2>&1
flock ~/gs66-render.lock godot --headless --path "$PWD/output/alcatraz-props-424/project" --import > output/alcatraz-props-424/reimport.log 2>&1
python3 tools/art/source/alcatraz_props_424/prepare.py --sync-imports
python3 tools/art/source/alcatraz_props_424/verify.py
nvidia-smi
flock ~/gs66-render.lock godot --path "$PWD/output/alcatraz-props-424/project" --rendering-method mobile --rendering-driver vulkan --display-driver x11 --disable-vsync --max-fps 60 --resolution 720x800 --quit-after 2400 res://review.tscn > output/alcatraz-props-424/render.log 2>&1
python3 tools/art/source/alcatraz_props_424/package.py
```

`prepare.py` 从固定白模34df9c0b导出隔离工程，只覆盖十个GLB；保持原layout、场景、原出生、灯光、导航和镜头。首次导入继承白模Godot UID，后续生成不换UID。临时工程仅启用Avatar autoload、独立QA用户目录，无网络或实际存档操作。

`verify.py` 读取实际GLB，核对尺寸、每件单mesh/surface、法线、无退化面、预算、旧UID、442个点位、204段长度和石沿一致、20个斜段柱保持竖直、179对端点重合。原layout的10处高度差另列报告，检查不将它们伪称为已解决。`review.gd` 校验当前导入缓存、真正的1.75m人物和原生开场，并在不改原场景文件的前提下拍检查平台与楼梯局部。`package.py` 在脚本版本、图像报告和GLB SHA一致后打包，不接受旧渲染。

交场景方的文件：十个GLB + .import、`props_manifest.json`；配套 `integration_notes.json`、`placement-review.json`、`seam-audit.json` 说明点位与碰撞更新。不要把本包reference目录下的layout快照覆盖到马可波罗当前分支。只替换赵云负责的十件，主体/远景保持各负责人文件。
