# 调研：水塘（游戏地点）数据能否托管在 Mapbox

2026-09-30。起因：旧金山要加水塘；现状是 `assets/ponds/catalog.json` 打进包 + 服务端同读一份，整文件 sha256 做版本栅栏，改一个字节旧包就看不到所有水塘。目标：以后只靠工具维护数据，不发版。

## 现状要点

- 一个水塘 = **地点元数据**（id、region_id、name、lat/lng、template_id、decoration_seed、layout_revision）+ **模板**（岸线多边形、导航格、出生点、鱼种档）。
- 模板决定场景几何，和贴图（`*_shore.png`、水底图、泡沫图）一起打在包里；服务端用同一模板做多人房间的走位/抛竿校验（`server/src/ponds/catalog.ts`）。
- 地图上的水塘图标由 Godot 自己画（`/v1/ponds` → `city_map_view.gd`），不是 Mapbox 图层。
- 安卓地图桥有 `querySourceFeatures`（`tools/android/overlay/GodotMapPlugin.kt` 查 `composite/poi_label`）；iOS 桥没有 POI 查询。

## Mapbox 能提供的三种"自有数据"形态

| 形态 | 说明 | 维护方式 | 客户端读法 | 费用 |
| --- | --- | --- | --- | --- |
| **MTS 自定义 tileset** | 上传行分隔 GeoJSON + recipe，生成矢量瓦片 | Tilesets CLI / Data Workbench；需 `sk.` 密钥（tilesets:write） | 地图里加 vector source（`mapbox://账号.tileset`），`querySourceFeatures` 免费读；或 Tilequery 按点查 | 处理免费额度 10 GB + 20 CU/月，托管免费 750 tileset·天/月——一两个 tileset 基本 0 元 |
| **Tilequery API** | 按经纬度 + 半径查任意 tileset（含自定义）的要素 | 同上（查询对象是 tileset） | HTTP，每次最多 50 条 | 免费 10 万次/月，之后 $1.5/千次；限流 600 次/分 |
| **Datasets API** | 逐要素增删改的 GeoJSON 集合 | API 可改单条 | **不能直接当地图数据源**，要再导出成 tileset；Studio 数据集编辑器已于 2026-06-01 停止支持 | — |

结论：可行的是 **MTS tileset（+ 可选 Tilequery）**；Datasets 只适合当编辑中转，不适合做运行时数据源。

## 另一条路：不上传，直接用 Mapbox 自带数据派生

实测 streets-v8 用现有公开 token 即可 Tilequery：
- 金门公园 (-122.4862, 37.7694)：`landuse` 返回 park / grass 多边形，`poi_label` 有 park_like 野餐点。
- Spreckels Lake (-122.4955, 37.7707)：`water` 多边形 + `natural_label` "Spreckels Lake"。

所以"在每个城市公园/真实湖边自动出水塘"技术上可做，**全球城市零维护**。代价：
- 瓦片数据会随 Mapbox 更新变化，地点 id 必须由我们自己按规则生成并**落库固化**（否则水塘会漂移/消失，多人房间和存档对不上）。
- 需要服务端在生成时调用 Tilequery 做"这里是公园/水边"的判定，结果写入我们的库；客户端仍从我们的服务拿列表。
- 中国区 Mapbox 数据稀疏（上海 POI 已知较少），上海可能仍需人工点。

## 放进 Mapbox 解决不了的事（必须保留在我们这边）

1. **服务端权威**：进水塘房间要按 pond_id 查模板做导航/抛竿校验。Mapbox 是只读外部数据，服务端要么每次去 Mapbox 查（延迟、配额、单点故障），要么定期同步一份——还是两份数据。
2. **模板与美术**：岸线、导航格、贴图必须在包里（场景几何），Mapbox 只能存"哪里有一个用模板 X 的水塘"。新增模板仍需发版。
3. **版本栅栏**：当前整文件 hash 的问题与数据放哪无关；只要客户端要求整份目录逐字节一致，任何增删都会让旧包失效。无论选哪条路，都要改成"按单个地点校验模板 revision"。
4. **iOS**：地图桥需新增 `querySourceFeatures` 或 Tilequery 调用（安卓已有同类实现）。
5. **更新时效**：MTS 发布要跑 job（分钟级），设备有瓦片缓存，下线一个水塘不能保证即时生效。

## 对比与建议

| 方案 | 加新城市 | 旧包兼容 | 改动面 | 数据真相 |
| --- | --- | --- | --- | --- |
| A. 维持包内 catalog | 发版 + 服务端同时上线 | 旧包全丢 | 最小 | 包 + 服务端 |
| B. **服务端下发地点列表**（工具写库/JSON，客户端只内置模板） | 跑工具即可 | 按地点校验后兼容 | 中：去掉整文件 hash，`/v1/ponds` 返回完整地点，客户端缓存 | 我们的服务 |
| C. MTS tileset 当地点源 | 跑工具上传 tileset | 同 B（仍需改栅栏） | 大：B 的全部 + 双端地图加 source/查询 + 服务端同步 Mapbox + `sk.` 密钥管理 | Mapbox + 服务端副本 |
| D. 从 streets-v8 公园/水体自动派生 | 自动（全球） | 同 B | 大：B + 生成器 + 固化入库 | 我们的服务（生成源来自 Mapbox） |

建议：**先做 B**——它单独就满足"之后只靠工具维护数据"，且是 C/D 的前置（C、D 都绕不开"服务端权威 + 按地点栅栏"）。地点维护工具可以直接写服务端数据；若希望在 Mapbox Studio 里可视化编辑，再把工具的产物同时推一份到 MTS tileset 作为编辑/预览层（C 的轻量版），运行时仍以服务端为准。D 适合下一步做"全球任意城市都有水塘"时再评估。

## 参考

- MTS：https://docs.mapbox.com/mapbox-tiling-service/guides/ ，定价 https://docs.mapbox.com/mapbox-tiling-service/guides/pricing/
- Tilequery：https://docs.mapbox.com/api/maps/tilequery/
- Datasets（旧编辑器 2026-06-01 停止支持）：https://docs.mapbox.com/studio-manual/reference/datasets/
- 价格：https://www.mapbox.com/pricing
