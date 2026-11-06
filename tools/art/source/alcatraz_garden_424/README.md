# 恶魔岛台地花园源文件 · 赵云

`alcatraz_garden.blend` 包含五个命名collection及可编辑花瓣、花穗、茎叶、绿篱和陶盆。`build_alcatraz_garden_424.py`重建本包，不修改#802的十件或主场景模型。输出的五个GLB各以占地底部中心为原点，源文件为了检查并排摆开；不把源文件检视位移烘到运行时模型。

`placements.py`以固定v6 `b16c3198`的原地面三角形和摆位表生成建议：保留15个看点站位、排除地面高度不符或碰到既有道具的候选；不改正式layout/navigation。`suggested_placements.json`直接交马可波罗，里面记录拒绝候选，便于以后按新地形重新计算。每层前三个间隔6.5m，楼梯端最后一个间隔4.1m；不能拿这个补充花园包代替整岛每屏验收。

必须使用共享渲染锁，并按顺序等每一步退出后再继续。Python需要NumPy/Pillow。首次运行先建output目录：

```bash
mkdir -p output/alcatraz-garden-424
source ~/.codex-zhaoyun/env.sh
flock ~/gs66-render.lock blender --background --python-exit-code 1 --python "$PWD/tools/art/build_alcatraz_garden_424.py" > output/alcatraz-garden-424/build.log 2>&1
python3 tools/art/source/alcatraz_garden_424/prepare.py
python3 tools/art/source/alcatraz_garden_424/placements.py
python3 tools/art/source/alcatraz_garden_424/prepare.py
flock ~/gs66-render.lock godot --headless --path "$PWD/output/alcatraz-garden-424/project" --import > output/alcatraz-garden-424/import.log 2>&1
flock ~/gs66-render.lock godot --headless --path "$PWD/output/alcatraz-garden-424/project" --script configure.gd > output/alcatraz-garden-424/configure.log 2>&1
flock ~/gs66-render.lock godot --headless --path "$PWD/output/alcatraz-garden-424/project" --import > output/alcatraz-garden-424/reimport.log 2>&1
python3 tools/art/source/alcatraz_garden_424/prepare.py --sync-imports
python3 tools/art/source/alcatraz_garden_424/verify.py
nvidia-smi
flock ~/gs66-render.lock godot --path "$PWD/output/alcatraz-garden-424/project" --rendering-method mobile --rendering-driver vulkan --display-driver x11 --disable-vsync --max-fps 60 --resolution 720x800 --quit-after 2400 res://review.tscn > output/alcatraz-garden-424/render.log 2>&1
python3 tools/art/source/alcatraz_garden_424/package.py
```

`prepare.py`导出独立v6副本，只追加新花园GLB及审阅脚本，启用单一Avatar autoload、独立QA用户目录。原海面/岸石/地面/导航/主体/旧道具不改，不读取生产存档、不使用网络。`.import`由Godot实际创建UID，后续保留；光照使用原岛设置，新增花园材质用农场哑光参数。主场景文件和layout均做哈希回读。

`review.gd`按类型和区块组成6个MultiMesh，不烘在一起；检查15个看点默认投影、新盆栽沿原路线的v6操作区净空、导入缓存与实际面数/AABB。默认截图360×800、全景1200×1400、并排1500×850；打包后均≤1600长边。完成后自动退出，不能开着编辑器挂机。

`verify.py`直接读最终GLB独立核对面数、surface、法线、底部原点、UID、精确1m绿篱端面；`package.py`要求报告晚于当前脚本/点位、最终GLB SHA一致，再生成署名图。不要在锁仍排队时拿旧报告打包。
