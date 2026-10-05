# 洛杉矶地图 第 9 轮反馈（2026-09-23）

> **资料范围（2026-10-05 清理）**：此页保留美术来源、技术或原日期的验证过程；旧界面/布局不是当前验收稿。当前规则和有效稿入口见 [设计索引](../README.md)。已移除的旧图按清理记录中的固定 Git 版本查阅。

生图渠道：Sensenjoy Image API `https://sub.sensenjoy.cn/v1`，模型 `gpt-image-2`，`/images/edits` 多参考图调用（`mockups/call_image_api.sh`）。密钥只从环境变量 `SENSENJOY_API_KEY` 读取，不落盘。

## 设计稿
- `mockups/player-card-mockup-v1.png`：选中其他玩家时的底部详情卡（头像 + 名字 + “农场 · 洛杉矶” + 青柠色“拜访农场”跳转按钮），参考当前真机地图截图生成。已按此实现。
- `mockups/farm-restyle-mockup-v1.png`：农场页 UI 换成地图页的奶油卡 + 墨色字 + 青柠主按钮风格（3D 场景不变）。第 ③ 项“其他页面对齐”的目标稿，尚未实现。

## 餐饮 POI 变体
- `poi-variants/`：restaurant / chinese_restaurant / cafe / bakery 各新增 3 套（`assets/map/poi/<key>_2..4.png`），与原图共 4 套。
- 参考输入：原批次的风格裁图 + 该类已上线贴图；提示词要求同材质同机位、不同轮廓。
- 处理：`extract_normalize.py`——API 可能直接返回透明底，alpha 取“源 alpha 与品红色键 matte 的最小值”；alpha 包围盒裁切、Lanczos 缩到 448、底边落在 512 画布 y=480（与原批次锚点一致）。
- 运行时选择：`CityMapData.art_texture()` 按 POI 名字哈希固定选图，同名同图。
- `contact-sheet.png`：每行一类，第一列为原图。
