# SGODOT-424 · 恶魔岛源文件

当前是 v8 正式配色首版（已安装十组通过双审的协作模型）；v2 画面已通过。最新图、预算、验证见 [v8 审阅](../../../../docs/design/alcatraz-blockout-424-2026-11-05/v8/README.md)，坐标／原点／分工／时间见 [HANDOFF.md](HANDOFF.md)。正式交件硬线 **11-09 08:00**。

- `palette.json`：v2参考下的暖石墙、浅砂路、黄绿花园、蓝绿海湾配色；用于生成器及海面材质参数。
- `finish.py`：可编辑的拱窗／玻璃入口／无文字灯塔剪影、岸壁切面、砌石表面和封闭台阶。
- `integration.py`：已验收件的114点位一对一替换、花园／码头／废墟布局、107个岸边叠层点位和十处栏杆转角修复。
- `integration_queue.json`：已整合协作包的固定头、接头／花坛修正和近远档图形招牌同步记录。
- `build.py`：马可波罗的地形、四段台阶、道路、码头、主楼近档，以及导航／layout／分区／LOD 合同。
- `authored.py`：校验并保留十组已合入协作包的GLB／UID；从正式文件导入整岛源预览，命名构件源仍在其独立blend中，生成器不会覆盖已验收件。
- `placeholders.py`：赵云、黄忠和刘备负责件的临时占位及摆位方法；每种一个 GLB，重复件放置表单独生成，斜栏杆支持保持立柱竖直的 basis。
- `alcatraz_blockout.blend`：命名可编辑构件与模块实例，四个区块 collection；Alcatraz_Module_Library 场景保留所有近远档原型，包含当前没有实例引用的远档。原点、单位和坐标转换与运行时一致。
- `prepare.py`：复制最小离线 Godot 项目到 `output/alcatraz-424/project`，仅 Avatar autoload，独立用户目录；回收 Godot 自动生成的 .import／UID。
- `hud_contract.json`：固定b1实测控件位置、12px留白及赵云#802正式冠幅预留；只供审阅检查，不增加运行时控件。
- `review.gd`：程序化沿路线行走、每约一屏拍照、检查导航／镜头／LOD、读取实际可见／阴影／UI 渲染计数。
- `check_source.py`：重新打开保存后的 Blender 源，核对全部近远档模块、60 个命名踏步及四区实例数量。
- `package_review.py`：只归档本次验证清单中的截图，排除以前失败运行的同目录旧图；生成联系表、CSV、尺寸与哈希记录。

原始 v1、v2 参考在 `reference/`，哈希见 `provenance.json`。以 v2 文字尺寸为准，不按生图里夸大的家具量尺寸。v1 源和图可从 `d93763c3` 追溯，v2 审阅头为 `6bb14aa9`。

从仓库根目录重建：

```sh
flock ~/gs66-render.lock blender --background --factory-startup --threads 3 --python-exit-code 1 --python "$PWD/tools/art/source/alcatraz_island/build.py"
bash tools/art/source/alcatraz_island/review.sh
flock ~/gs66-render.lock timeout 220s env ALCATRAZ_SWEEP=1 ALCATRAZ_REVIEW="$PWD/output/alcatraz-424/v8/review" godot --path output/alcatraz-424/project --resolution 360x800 --fixed-fps 60 --disable-vsync --max-fps 60
python3 tools/art/source/alcatraz_island/package_review.py
```

先等 Blender 结束再检查。实渲使用当前合法 DISPLAY／XAUTHORITY；共享锁贯穿每次 Godot／Blender 调用。脚本有超时并主动退出。诊断日志、原始图和过程结果在 `output/alcatraz-424/v8/`。截图命令关闭垂直同步并限60帧，避免虚拟桌面的同步等待长期占锁；截图工具使用固定模拟帧步和加速走位，不能把截图间隔当作实际游戏 FPS。

需要手动点走时，先运行 `prepare.py` 和隔离导入，再在有效桌面中运行：

```sh
flock ~/gs66-render.lock timeout 120s godot --path output/alcatraz-424/project --resolution 360x800
```

未设置 ALCATRAZ_REVIEW 时直接进入可操作场景；不会启动游戏主项目的 Net。检查结束关闭窗口，不留编辑器运行。

完整生成会重建马可波罗白模和剩余临时占位，全部已验收协作GLB由authored.py保护原字节。后续替换其他正式协作件时也需登记来源、导入设置与哈希，不能再用占位覆盖。以后的预算必须用替换后的文件重新测量。地图注册、发布导出清单和 vivo 帧率由亚瑟接入验证。

招牌已采用同底色的无文字灯塔剪影。地标3D中不再写文字，规则见mobile-3d-asset-workflow.md。#819正式远档已换入，远档已使用黄忠fbf5463a图形补丁，与bf0c31b1近档同步；#823动作和#824浪花已安装，9秒视频展示同世界的原生开场与原位特写。录制多视口时隔离项目viewport_width应设840，录制后用prepare.py恢复360，不能只依赖命令行窗口尺寸。
