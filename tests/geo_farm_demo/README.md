# SGODOT-499 农场视图验证

独立 demo 展示层测试，不启动游戏 autoload/账号/正式服务，不读玩家存档。请先取得大乔的 Godot 窗口；不运行 editor/import。

准备临时项目（不会启动 Godot）：

```sh
python3 tests/geo_farm_demo/prepare_isolated.py /Volumes/ACASIS/tmp/geo-farm-demo-1117/liubang-view-qa
```

在获准窗口内，记录自身 PID 后运行：

```sh
godot --headless --path /Volumes/ACASIS/tmp/geo-farm-demo-1117/liubang-view-qa --script res://tests/geo_farm_demo/test_farm_view.gd -- /absolute/path/to/real-farm.json
```

带窗口复跑同一脚本时去掉 `--headless`。测试包含 schema / sparse 缺格 / 重复越界与非法颜色 / 北向 / 点格 / 返回信号 / 换块加载与失败清旧图 / 360×640、320×568、412×915适配 / 800格保数；额外JSON参数逐个验证真实生成文件。测试合成格子仅用于断言，不能作为真实区块交付。

截图使用 `capture_farm_view.gd -- /absolute/output/dir /absolute/real-farm.json [...]`，仅截该独立视图。复制新文件后再准备临时项目，防止旧副本误验。所有进程记录PID，退出后核实释放。

地图层负责下载、认领、别人可见与返回地图切换；此脚本只验证视图发出返回信号。独立安卓整包冒烟由盘古/蒙恬/李元芳集成后验收。生产p0/ui_kit未被此测试运行，也不把独立57项写成全仓库通过。
