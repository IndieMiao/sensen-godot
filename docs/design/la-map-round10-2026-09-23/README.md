# 第 10 轮（2026-09-23 深夜）

## POI 贴图扩充到每类 20 套
餐饮四类（restaurant / chinese_restaurant / cafe / bakery）与 museum 各 20 套（含原图），本轮新增 83 张。
- 生图：Sensenjoy `gpt-image-2` `/images/edits`，参考输入 = 原批次风格裁图 + 该类已上线原图；`make_prompts.py` 每张一条不同的建筑描述（轮廓/屋顶/材质各异）。
- 批量：`run_batch.sh`（5 并发、失败重试一次），83/83 成功。
- 处理：`extract_normalize.py`（alpha = min(源 alpha, 品红色键 matte)，底边锚点 y=480/512）。
- 预览：`sheet-<类别>.png`，每类两行十列，第一张为原图。
- 运行时：`CityMapData.ART_VARIANTS` 设为 20，按 POI 名字哈希固定选图；测试断言全部 95 个变体文件随包。

## 全 app 视觉对齐
按已认可的 `../la-map-round9-2026-09-23/mockups/farm-restyle-mockup-v1.png`，`modules/ui/game_ui.gd` 与 `assets/ui/app_theme.tres` 统一为地图页语言：白卡无描边、大圆角柔阴影、墨色字 `#232b30`、青柠主按钮 `#cafa91`；紫/青贴图边框不再使用。
