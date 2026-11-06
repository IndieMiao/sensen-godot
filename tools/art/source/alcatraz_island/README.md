# SGODOT-424 · 恶魔岛源文件

当前v9采用#827草坡v1.1／石板／木纹材质、#828双塔正式色、#826修复.import后的c/d树，以及#825 a/b远档。审阅见[v9](../../../../docs/design/alcatraz-blockout-424-2026-11-05/v9/README.md)，接入见[HANDOFF.md](HANDOFF.md)。

本次只更换地形／码头的材质绑定；六个自制GLB及Blender命名部件的几何、UV、原材质分配与b81605af一致。四个塔只改COLOR_0的RGB；新树按source_name原位替换12棵，树根／旋转／缩放／碰撞及导航保留。草坡显示色由ShaderMaterial控制，palette.json的garden识别键不能改成显示色。

- build.py：生成命名源和装配数据；本轮必须使用--layout-only，读取preserved_geometry.json校验并保留六个自制GLB，不重新导出模型或UV。
- authored.py：按协作包manifest校验原GLB；导入模块预览，可编辑构件源保留在各协作包目录。
- integration.py：原自然件114点替换、码头／废墟／浪花装配、花园和栏杆修正、12棵新树替换。
- alcatraz_blockout.blend：四区装配与61个原型；细分构件和模型可编辑，Godot专用细节材质在运行场景中应用。
- verify_preservation.py：6个GLB全字节、双塔RGB限定、26棵根点/TRS、4份修复.import、导航／镜头／海面及材质版本验证。
- check_preserved_source.py：读取output中的b81605af基准blend，对比六个自制集合的顶点、面、UV、变换与材质分配。
- prepare.py／review.sh／review.gd：隔离Godot工程、导入、路径与HUD、材质绑定、实际近远档渲染、逐屏图和缩放预算。
- package_review.py／check_source.py：归档原生图、前后比较、资源尺寸／UID／哈希及Blender回开证据。

从仓库根目录：

```sh
flock ~/gs66-render.lock blender --background --factory-startup --threads 3 --python-exit-code 1 --python "$PWD/tools/art/source/alcatraz_island/build.py" -- --layout-only
bash tools/art/source/alcatraz_island/review.sh
flock ~/gs66-render.lock timeout 220s env ALCATRAZ_SWEEP=1 ALCATRAZ_REVIEW="$PWD/output/alcatraz-424/v9/review" godot --path output/alcatraz-424/project --resolution 360x800 --fixed-fps 60 --disable-vsync --max-fps 60
python3 tools/art/source/alcatraz_island/verify_preservation.py
python3 tools/art/source/alcatraz_island/package_review.py
```

使用当前有效DISPLAY／XAUTHORITY。所有Godot／Blender持共享锁，执行后退出；output/.gdignore保留。普通走路视频使用ALCATRAZ_MOVIE=1、30Hz和--write-movie，包含逐帧渲染峰值检查。录制是离线固定帧步，不是物理手机FPS；不要把截图脚本的加速走位当作游戏步速。

完整几何生成会重建自制GLB；只有后续明确修改模型时才不用--layout-only，并更新保留基准。本轮不需要完整重导出。未来地标3D不写文字，采用空白牌或图形；近远档都保留灯塔图形。
