# 地图首页：无缝缩放到国家级 + 城市自动切换 + 城市跳转

2026-09-23 用户确认的需求与决策：

| # | 决策 |
|---|---|
| 1 | 最小 zoom = **2**（竖屏能看到中国/美国本土全境） |
| 2 | 拖到未开通城市：左上角显示**真实地名**（取自已加载瓦片），副标题提示 "No farms here yet" |
| 3 | 自动切城**写入** `FarmRegions.save_choice`（下次启动落在最后浏览的城市） |
| 4 | 国家级只显示**城市气泡 + 自己的头像 pin** |

## zoom 取值依据

Mapbox v11 瓦片 512 逻辑像素：竖屏一屏横向经度跨度 ≈ `253 × (屏宽/360) / 2^z`。
z2≈63°（中国 73–135°E、美国本土 ~58° 均可放下），z3≈32°，z4≈16°，z5≈8°，z9.5 为原城市全貌下限。

## 分级（常量在 map_poc.gd）

| zoom | 内容 |
|---|---|
| ≥ 11 | pitch 35°，原有全部内容 |
| 8–11 | pitch 线性压到 0；城市内容照常 |
| ≥ `CITY_DETAIL_ZOOM`(9) | 地标/居民/POI/其他玩家 pin/3D 自己 |
| < 9 | 隐藏 3D 小人、贴图、其他玩家；显示城市气泡 + 自己的 2D 头像 pin |
| ≥ `AUTO_SWITCH_ZOOM`(8) 且中心落在某城 `placement_bounds` 内 | 自动切到该城（离开需超出外扩 10% 的边界，滞回防抖） |

## 关键技术约束

1. **投影一致性**：Godot 叠加层用局部等距近似（geo_math.gd，只在城市尺度准确）。
   pitch=0 时标记改用精确 Web Mercator 2D 公式投影（`map_poc.geo_to_screen`），与 Mapbox 完全重合；
   pitch>0 只出现在 z≥8，城市尺度误差 <1px。低 zoom 不渲染任何 3D 内容。
2. **强制 Mercator**：Streets v12 低 zoom 可能默认 globe 投影，原生侧 `style.setProjection(MERCATOR)`，
   否则 2D 公式失效。
3. **城市模式不再钳拖动范围**（只保留纬度 ±85.05°），选址/搬家模式的范围不变。
4. **切城是轻量的**：`_switch_city` 只替换 region / 标题 / 地标居民 / 附近农场（重新拉 `Net.nearby`），
   相机不动；不走 `enter_street_mode` 整套重建。
5. 标题地名：原生 `queryPlaceLabels` 读 `composite/place_label`，按 zoom 取 settlement(≥8)/state(5–8)/country(<5)；
   iOS 暂无实现 → 回落 "Explore"。

## 城市跳转

左上角城市名打开**地图内城市面板**（已开通城市 + 农场数），选中后 van Wijk 飞行
（先拉远、平移、再拉近到该城 overview）。低 zoom 点城市气泡、"定位我的农场"跨城时同样走飞行。
首次启动选城仍用 `city_select` 场景。

## 分期

- P0 缩放下限 / 去拖动边界 / pitch 随 zoom / 低 zoom 隐藏 3D / Mercator 投影 / 原生强制 Mercator + 标签字号
- P1 当前城市判定 + 轻量切城 + 城市气泡 + 瓦片地名标题
- P2 地图内城市面板 + 飞行动画
- 验收：tests/map 全绿 + vivo 真机主要页面巡检（低 zoom 对位、地球仪是否出现、切城、跳转）
