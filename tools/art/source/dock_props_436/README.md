# 码头小件 SGODOT-436 源与复现

黄忠。新建12件，底面中心原点，Godot米制Y朝上。`build.py` 使用已合入的 street_kit_429 原语与单surface导出函数，只修改本次目录内的 Blender 和GLB；每件blend保留可编辑命名部件。
资料基线是上官婉儿436派活与卡正文；没有另外的概念图。隐藏面按简单木构/箱桶推定。配色沿用 #830 木色、恶魔岛灰蓝屋面与street_kit深褐铁件。
`provenance.json` 固定父提交与426/430/432/434依赖；`dock_connection.json` 固定426接口和SHA。

从仓库根运行（gs66已有工具链）：

```bash
source /home/zhangshaoji/.codex-huangzhong/env.sh
flock /home/zhangshaoji/gs66-render.lock blender --background --python tools/art/source/dock_props_436/build.py
python3 tools/art/source/dock_props_436/prepare.py
flock /home/zhangshaoji/gs66-render.lock godot --headless --path output/dock-props-436/project --editor --import
python3 tools/art/source/dock_props_436/sync_imports.py
flock /home/zhangshaoji/gs66-render.lock godot --path output/dock-props-436/project --rendering-method mobile --rendering-driver vulkan --display-driver x11 --disable-vsync --max-fps 60 --resolution 960x800 res://review.tscn
output/art-setup/venv/bin/python tools/art/source/dock_props_436/verify.py
python3 tools/art/source/dock_props_436/cold_import.py
output/art-setup/venv/bin/python tools/art/source/dock_props_436/package_review.py
```

Blender命令可在末尾加 `-- --only fishing_net_rack` 等，局部重建一件。不要用生成器覆盖未记录的手工修改。
`prepare.py` 的首次运行从固定提交提取最小Avatar依赖，只开Avatar autoload与独立用户目录，不依赖其他任务遗留的output。432尚未进入基线，先确保本地能读到 `74cbc529e9ec72eb8d2e5a527437c4a4f7bfb131`（#837）；不提交这份依赖的副本。
UID首次由Godot导入生成；后续保持源`.import`，`sync_imports.py`只复制本套件的导入配置和脚本UID。`cold_import.py`内部也使用渲染锁，重建自己隔离缓存并核对全部文件和工作区状态。

`review.gd`：43°正交、宽6.72m、yaw−90°、360×800；件表单格24°。人物固定默认装束并实际量高1.745m。只在内存里冻结浪花/海面时间、设置海湾绘制顺序；依赖材质和GLB不写回。接缝碰撞由验证场景临时创建，运行时GLB没有碰撞。
每次渲染都会自动退出；不运行Android、不读生产存档。
