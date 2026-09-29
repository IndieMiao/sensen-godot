# 安卓全球地标与普通地点完整性检查（2026-09-29）

## 地标

- 47 个设计地标的图片（透明）和目录都已打进 0.17.7 APK。
- 对照服务端全部 21,209 座可选城市核对"每个地标至少能从一座城市看到"：原来有 2 个看不到——马蹄湾、羚羊峡谷，都在人口不到 1.5 万、不在城市库里的佩奇镇旁，最近的可选城市 161 km 外。已把这两个的 reach 调到 200 km（弗拉格斯塔夫、锡达城、赫里克能看到），并加了服务端测试 `test/geography/landmark_reach.test.ts` 防回退。
- **缺口：设计地标只覆盖美国。**美国以外没有设计地标，只能靠瓦片地点，而世界级地标大多被现行图标映射丢掉：
  - 埃菲尔铁塔 `maki=monument`、大本钟 `attraction`、东京塔 `communications-tower` 均**不上图**；
  - 悉尼歌剧院 `art-gallery` 只显示成泛"博物馆"图标。

## 普通地点（Mapbox 瓦片 + 现行 maki 映射，街道级 z16、8×8 瓦片）

| 城市 | 具名地点 | 全部上图率 | 主显示层（filterrank≤3） | 主层上图率 |
| --- | ---: | ---: | ---: | ---: |
| 旧金山 | 6,469 | 54% | 1,036 | 71% |
| 纽约 | 8,271 | 62% | 992 | 79% |
| 东京 | 23,104 | 6% | 1,751 | 71% |
| 伦敦 | 10,384 | 57% | 1,121 | 70% |
| 巴黎 | 18,808 | 62% | 1,260 | 84% |
| 西雅图 | 4,881 | 46% | 906 | 64% |
| 芝加哥 | 4,417 | 51% | 968 | 63% |
| 悉尼 | 6,256 | 54% | 892 | 71% |

主显示层没上图的，最多的是 Mapbox 的泛 `marker`（按 2026-09-23 定案不上图）。其次是**没有图标的类别**：attraction、monument、college、hospital、viewpoint、bridge、castle；东京另有 place-of-worship、post、police、pharmacy、religious-buddhist。

逐城明细见 [coverage.json](poi-global-2026-09-29/coverage.json)，脚本 `tools/map/poi_survey/global_coverage.py`（需 mapbox-vector-tile）。
