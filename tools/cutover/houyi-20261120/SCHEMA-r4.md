# 动态农场 schema-r4 · 实施接口 v1（后裔，11-18 20:50）

依据REQ-1118.md和参考图；核心/扩展解释由本文件统一。r4独立demo，阶段二复用同一数据进入gensen独立美术场景；当前不启用种植/摆放服务器指令。旧r1/r2/r3源与运行数据不覆盖。

## 1. 固定版本与区域语义

- dataset_version=`sf-dynamic-farm-20261118-r4`；manifest/client-manifest/catalog **schema4**；farm **schema4**。新增schema是显式不兼容，不能把r3三元cells按新规则猜读。
- selection_unit=`parcel`，block_id保留p-<canonical>，包括官方星号ID；farm_path仍farms/<block_id>.json。claim仍父parcel，身份own/pending按新dataset隔离，不自动迁旧认领。
- 核心区core：按公开parcel轮廓、约800格（目标760–840）；**800只数核心，不含扩展**。core是未来可编辑区域：walk、till、plant、arrange、place均允许；实际种植/摆放业务本阶段没有接入，不能把字段当命令已实现。
- 扩展区extension：围绕核心的**本地场景空间**，仅walk；till/plant/arrange/place全部false。程序可按美术白名单布景，玩家不能编辑扩展区；权限不从材质、颜色或是否已有树石推断。
- 未列入core或extension的格子为outside：不行走/不编辑，不把bbox空白填实。两区必须互斥，同一格只能有一个zone。
- 基础surface只是视觉地面：0=soil、1=grass、2=path，完整palette随payload；**DataSF住宅/商业/建筑8/水5不再直接决定能力或碰撞**，原分类放geo_hints用于主题建议/追溯。r4全核心默认土/草可编辑基础，参考图核心树石只能是以后可清的装饰语义，不能把原屋色强制成不可建区。

## 2. 与道路、邻地、水的关系

扩展区在等比归一化后的游戏格坐标生成，不回投经纬度、不扩大地图认领面、不占/合并邻人的parcel，也不作为Mapbox新图层。相邻真实parcel各自是独立农场场景，外圈可在各自场景存在；这是程序美术场景而非连续真实地籍世界。地图只有源parcel负责选择与认领，黄色建筑框只负责高亮。

不按真实道路/邻地裁剪扩展区，否则紧贴道路的住宅无法得到外圈；道路方向最多提示入口/小路朝向，不把公开地表数据误写成通行权。源建筑不强制复刻或压掉核心格，房屋/道具由刘邦＋婉儿按独立场景布局放置。

r4默认以完整可编辑核心为优先。源水体保留geo_hints.water_fraction；不把真实水自动投影成核心不可耕障碍。视觉水/崖只能布置在外边界之外的纯景观带，或由美术后续给出明确的不可达景观洞；**第一批不在两区基础walk mask里自动生成水障碍**。这保证扩展“只可走”的基础能力不被暗中改变。若要严格保留真实内部水作为不可走洞，须另改能力/排除规则，不在本版偷偷做。

核心源洞不补成core；距离扩展规则覆盖的洞边可为extension，只走不可编辑；仍未覆盖部分保持outside并在outer boundary中保洞。不能因填洞扩大核心格数。

## 3. 扩展区宽度、轮廓与预算

1. 先冻结核心格mask C，再生成外圈，不能为了外圈美观反向改核心轮廓/编辑权限。
2. 在游戏格坐标中，距离核心边界的宽度为 **4–10格（3.2–8.0m），名义7格（5.6m）**。使用seed驱动低频平滑value noise（网格间隔16格，平滑插值），width(x,y)=4+6*N(x,y)，N∈[0,1]。非逐格白噪声、不从中心作星形射线（凹形也要跟随）。
3. extension = 核心之外、格心到C边界距离≤width的格；C原格全保留。保证核心外侧至少4格的基础廊带（离散边界处按格心距离定义），外围允许平滑鼓出/收回；外轮廓由mask提取，渲染简化误差≤0.25游戏格，不用于修改权限mask。
4. 从core/extension并集核4邻连通；孤立噪声岛不保留、不让玩家传送到无法到达处。多源面只要经extension自然连通可保留全部core；不能为了“单岛”静默丢掉大块core。
5. **total_cell_count≤8192，grid.width/height≤544**（核心轴允许至512、外圈最多两侧各10格并保余量）。超过总量时先降低噪声振幅，再把宽度向4格收敛；不得削core凑预算。仍超限则列extension_budget_exceeded，不假装成功。当前r3核心最大254轴，上限扩大主要为救狭长来源，需2D/3D适屏与分块。
6. core边界向外前 **2格（1.6m）是no_solid_decor通行保护带**；spawn附近半径2格、入口到core的2格宽路径同样保护。扩展其余位置允许程序树/石等有碰撞装饰，但只在不切断保护廊道/入口/必要可达路径时放；不能靠“装饰不属玩法”豁免导航校验。
7. 基础导航mask=core∪extension。装饰障碍是场景层occupancy叠加，不改zone权限；放置后刘邦核spawn/入口/core边界可达。第一阶段2D仅显示区域与计数、不放实际碰撞物。

## 4. farm字段（可直接据此做通用门）

```
{
 "schema":4,"dataset_version":"sf-dynamic-farm-20261118-r4",
 "selection_unit":"parcel","block_id":"p-3139019","parcel_id":"3139019",
 "parcel_aliases":["3139019"],"name":"328 FRIDA KAHLO WAY","address":"...",
 "generator_version":"dynamic-core-ext-1","seed_hex":"<64 lowercase hex>",
 "game_cell_m":0.8,"source_area_m2":271.16,"source_cell_m":0.58,
 "source_transform":{"crs":"EPSG:32610","rotation_deg":0},
 "grid":{"width":W,"height":H,"origin_cell":[ox,oy]},
 "zones":{
   "core":{"runs":[[y,x0,length,surface_id],...]},
   "extension":{"runs":[[y,x0,length,surface_id],...]}
 },
 "capabilities":{
   "core":{"walk":true,"till":true,"plant":true,"arrange":true,"place":true},
   "extension":{"walk":true,"till":false,"plant":false,"arrange":false,"place":false}
 },
 "counts":{"core_cell_count":C,"extension_cell_count":E,"total_cell_count":C+E},
 "surface_palette":[{"id":0,"name":"Soil","color":"#D8BF8D"},{"id":1,"name":"Grass","color":"#8FAD69"},{"id":2,"name":"Path","color":"#BBA882"}],
 "boundaries":{"core":[{"outer":[[x,y],...],"holes":[...]}],"outer":[...]},
 "walk_reserve":{"no_solid_decor_runs":[[y,x0,length],...],"spawn_cell":[x,y],"entry_cell":[x,y]},
 "geo_hints":{"water_fraction":0.0,"landuse":"residential","source_building_count":2},
 "stats":{"core_iou":0.96,"width_min_cells":4,"width_max_cells":10,"core_components":1,"walk_components":1,"recovery_flags":[]},
 "attribution":"DataSF / SF Planning (PDDL / CC0); scene extension is procedural"
}
```

上述数值示例是**接口示意，不是已生成r4样本**。RLE的y/x0/length为整数，length>0，索引非负且不越grid；每zone内无重叠、两zone互斥，counts按解码sum(length)核。省存储/HTTP，客户端只在加载该farm时展开，不能逐帧重解码。每区runs按y,x0排序；一格至少有明确zone/ground，不从palette反推权限。

统一格坐标：local world X=(origin_cell.x+x+0.5)*0.8，Z=-(origin_cell.y+y+0.5)*0.8（北-Z）。boundaries是**同一未加origin的格坐标**、闭环、holes明确；转3D时同样加origin再乘0.8。外环/内洞不靠绕序猜，缺格outside。整个场景斜摆和镜头14.5°由刘邦/婉儿配置，对core、extension、碰撞、道具用同一个场景变换，不改地理源数据。

seed_hex = SHA256(dataset+canonical+generator_version+冻结参数串)，每个样本可重现；禁止JSON传uint64 seed而丢精度。算法与库版本写manifest，旧已创建farm不因程序更新而重算。

## 5. catalog、可选/排除集合、MVT与hash

- 发布manifest与手机client-manifest schema4，farm4；native_map沿r3最终键。`dataset_version=sf-dynamic-farm-20261118-r4`，服务用新静态/claims目录，旧环境保留。
- `parcel-catalog.json`：schema4/dataset/parcels数组，每条block_id/parcel_id/aliases/name/address/center/bbox/farm_path/core_cell_count/extension_cell_count/total_cell_count；不再用模糊cell_count代总数。若r4地图还需兼容cell_count，**明确它等于core_cell_count**，不得有时总数有时核心。
- `included-parcels.json`：可选canonical ID集合+计数；`excluded-parcels.json`：[{parcel_id,aliases,stage,reason_code,source_geometry_hash,attempted_repairs,metrics}]；`alias-map.json`：归并别名→canonical。原始缺ID行另raw-record-rejections.json，不凭空造parcel_id。
- 核输入→alias/归并→included/excluded可追溯，included与excluded无交集；每included必须有farm且hash/两mask通过。MVT只收included，同一dataset的service claim只认catalog。排除在地图点选上不可绕过。
- 完整manifest.files包括farms、catalog、included/excluded/aliases/rejections、MVT gzip XYZ、TileJSON模板、报告等SHA。client-manifest另小视图不含files，source_manifest_sha256指完整manifest；单独hash避免循环。公开实际域TileJSON/部署manifest依蒙恬流程另pin，作者pin不覆盖。
- MVT source-layer parcels/promoteId block_id/合法星号ID沿r3，新增core_cell_count/extension_cell_count/total_cell_count，geometry仍**真实parcel**，不含扩展mask/轮廓。图层去蓝框不删可查询layer；建筑黄框与昵称由地图侧处理，核心/扩展只在农场视图显示。

## 6. 全城排除重评（不先承诺救回数）

重新读取官方active完整源，不能只把154444旧farm外加一圈当“全城重新生成”。r3账：155028有几何编号-43同ID多geometry-421同geometry别名-50长轴-12面积<1m²-58格数/连通=154444。262缺ID/geometry原始行另计，不等于262parcel；421别名是归并不算丢失。

优先救50+58：多格宽迭代/半格相位搜索；必要时最小旋转包围盒对齐（rotation写source_transform，等面积等比，不能非等比拉伸），放宽轴至512并要求scene适屏。尽量保多面/洞，核心IoU目标>=0.90，0.85–0.90仅经明确降级标记和复验才候选；<0.85不选。不能加矩形补满核心、不靠扩展把额外区域变可耕。

43同ID多geometry先按原记录版本/重复与空间关系分析，只有可证明同一宗地的组成面才合并，歧义保留排除；12<1m²先保留排除（不把测绘碎片无限放大），新证据才恢复。当前38个多部件、41个带洞候选也要进专项，不静默沿用r3只取最大面。具体每ID失败原因在试算中写结构化枚举，不再只有一串失败ID。

r4数量和能救回多少以新生成/验证报告为准。全量运行前先给普通/窄长/凹/洞/多面/水边/星号样本（包含328、424）；此文件冻结后作者们可实现，实际运行资源另向大乔登记。

## 7. 20:53 清单精确shape与对账（蒙恬据此实现）

**core_cell_count 760–840为所有included严格门；recovery不例外。** total≤8192、axis≤544、counts/互斥/基础可走连通等同样没有隐式recovery豁免。IoU的已标记降级只影响形状近似评估，不改变这些硬门。

`included-parcels.json`：
```json
{"schema":4,"dataset_version":"sf-dynamic-farm-20261118-r4","block_ids":["p-3139010","p-3139019"],"count":2}
```
block_ids按字典序排序、唯一，均为canonical完整p-字符串（含合法*）；等于catalog所有block_id及farm集合，不能只计数相同。

`excluded-parcels.json`：
```json
{"schema":4,"dataset_version":"sf-dynamic-farm-20261118-r4","count":1,"parcels":[{"block_id":"p-EXAMPLE","parcel_id":"EXAMPLE","aliases":[],"stage":"core","reason_code":"core_cell_budget","source_geometry_hash":null,"attempted_repairs":["cell_size_search","phase_search","oriented_grid"],"metrics":{"core_cell_count":700}}]}
```
实际block_id必须恰为p-+parcel_id，不能由服务猜补前缀；aliases是未加p-的源别名ID（不含canonical本人），与alias-map一致。stage限定source/geometry/core/extension，reason_code限定`missing_geometry`,`ambiguous_geometry`,`invalid_geometry`,`area_below_minimum`,`core_axis_budget`,`core_cell_budget`,`core_shape_quality`,`core_disconnected`,`extension_budget_exceeded`,`walk_disconnected`,`no_safe_spawn`。字段都必带；没有合法源几何时source_geometry_hash=null。metrics只含有限数值/字符串枚举/布尔，不装原始数据；attempted_repairs为执行过的修复名称列表。每canonical仅一条最终排除主因；细节可进generation-report。列表按block_id排序。

`alias-map.json`：
```json
{"schema":4,"dataset_version":"sf-dynamic-farm-20261118-r4","count":1,"aliases":[{"alias_parcel_id":"4591A013","canonical_parcel_id":"4591A011*","canonical_block_id":"p-4591A011*"}]}
```
仅收非canonical别名，不放self-map；alias_parcel_id唯一，不能既是另一canonical又当alias，不能环；canonical_block_id恰=p-+canonical_parcel_id，并出现在included或excluded其中之一。同几何归并不是排除，不能额外在excluded放alias条。alias-map适用于追溯，不授权客户端用alias绕catalog认领。

`raw-record-rejections.json`：
```json
{"schema":4,"dataset_version":"sf-dynamic-farm-20261118-r4","count":1,"records":[{"record_key":"sha256:example","source_dataset":"acdm-wktn","source_file":"page.json","record_index":0,"record_sha256":"<64hex>","parcel_id":null,"reason_code":"missing_parcel_id"}]}
```
record_key由source_file+record_index+record_sha256确定且唯一；record_index为该固定源文件JSON数组的0-based下标；parcel_id可null，不为无ID行编造地块。reason_code限定missing_parcel_id/missing_geometry/invalid_geometry/invalid_parcel_id。某条坏记录有合法ID、但同ID另有可用记录时，可以记录raw rejection而最终canonical仍included；raw记录层与parcel层不能加在一起当总地块数。

`parcel-catalog.json`：`{schema:4,dataset_version,selection_unit:"parcel",parcel_count:N,parcels:[...]}`，只included；单条必含block_id/parcel_id/parcel_aliases（含canonical本人＋其全部别名）/name/address（null或字符串）/center:[lon,lat]/bbox/farm_path/core_cell_count/extension_cell_count/total_cell_count。farm_path=farms/<block_id>.json，name不可空（缺门牌用SF Parcel＋源编号，不能UNKNOWN）。

完整manifest增加统一counts：
```json
{"counts":{"source_records":0,"source_accepted_records":0,"source_rejected_records":0,"source_distinct_parcels":0,"canonical_parcels":0,"alias_parcels":0,"included_parcels":0,"excluded_parcels":0},"parcel_count":0,"block_count":0}
```
- source_records = source_accepted_records + source_rejected_records；source_rejected_records = raw-record-rejections.count。接受行可以多条对应一个parcel，不和地块数混算。
- source_distinct_parcels：所有有效非空源parcel ID（即使其全部记录无geometry，也应有最终excluded）；= canonical_parcels + alias_parcels。
- canonical_parcels = included_parcels + excluded_parcels；alias_parcels=alias-map.count；included_parcels=included.count=catalog.parcel_count=manifest.parcel_count=manifest.block_count；excluded_parcels=excluded.count。
- 集合也必须核：input有效ID集合 = included canonical源ID ∪ excluded canonical源ID ∪ aliases源ID，三者互斥；非空但非法ID放raw拒绝，不生成路径。
- manifest.files逐一hash覆盖四名单/catalog/全部farms/tiles/报告/模板；client-manifest是源manifest派生小视图，独立pin、不反写files。原始源快照的URL/hash/记录数列manifest.sources，服务器不需公开原始分页。

## 8. 输入有效ID审计sidecar（蒙恬采证要求）

必须交`input-parcels.json`并列完整manifest.files：
```json
{"schema":4,"dataset_version":"sf-dynamic-farm-20261118-r4","parcel_ids":["3139010","3139019","4591A011*","4591A013"],"count":4}
```
parcel_ids是**未加p-的官方有效原始ID**，排序唯一，count=manifest.counts.source_distinct_parcels。在源读取/ID格式校验后、几何修复/别名归并之前冻结；合法ID即使所有行缺geometry也进入此集合并最终excluded。缺ID/非法ID行进raw-record-rejections，不造ID；不得以最终included倒填输入集合。

服务端精确核`set(input.parcel_ids) == set(catalog.parcel_id) ∪ set(excluded.parcel_id) ∪ set(alias.alias_parcel_id)`且三者互斥，并核每alias canonical落在included或excluded。sidecar随作者源快照hash一起冻结，部署时可只读校验，不要求公网暴露，更不让手机取全154k ID。该校验证明作者冻结输入集合与输出分区对账；源API快照是否完整仍由作者的分页/count/hash报告负责，不能仅此sidecar冒称独立重取上游。

## 9. client小视图与格数归属（盘古确认）

client-manifest只保schema/dataset_version/selection_unit/parcel_count/block_count/**generator_version**/native_map/scope/source_manifest_sha256，不含files和单农场三count。parcel_count/block_count是可选地块数量；generator_version与所有farm一致。

core_cell_count/extension_cell_count/total_cell_count是单farm counts对象与该parcel MVT属性；兼容cell_count严格等于core_cell_count。如果完整manifest/统计报告要发布全城格数汇总，只放独立city_counts对象（三字段全城求和），不把它们扁平放client冒充当前farm。手机初启不需要全城格总和。

视觉/包身份按盘古与蒙恬约定Dynamic Farm DEMO、预留2026111801/0.0.4-demo；实际出包时钉完整源码/包/数据hash，本数据协议不代替出包验证。

补充保护带：no_solid_decor_runs包含**所有核心格**＋核心外侧2格走廊＋入口到spawn路径及周围2格保护；核心保持可开垦布局所需空场，非实体花草点缀由婉儿确认。外圈其余实体树石仍由生成器预置并验证可达，不开放玩家操作。

## 10. 保护带与坐标补充

外围保护严格按**格心到core单位方格并集**距离≤2格核；spawn/entry以格心2格半径保护，reserve自身须4邻连通并包含全部core。允许宽度收敛4–10内的合法减宽，stats.width_min_cells/width_max_cells按实际参数，非默认必须有reduced_extension_width标记；不硬锁width_max_cells=10误拒合法降幅。

+y映射-Z是**本地网格轴约定**；rotation_deg非0时该网格已相对地理北旋转，真实北向需合成source_transform旋转。场景斜摆另由美术统一施加，不能把本地+y直接当永远真实地理北。本协议不要求摄像机按真实北锁定。

geo_hints补充：water_fraction/source_building_count可为null，表示该源提示未知，不得当0；water_fraction_basis写来源（例如旧snapshot格面积估计），不得当实时水情。geo_hints不参与两区能力、导航或资格判断。shape IoU 0.85–0.90的实际恢复候选必须带approximation_warning，并通过同样的独立几何/预算/权限/连通校验，报告另列人工审阅；低于0.85始终排除。

## 11. 源拓扑与源分页硬门（周瑜 P1/P2 返修）

整体 IoU 不能豁免完整源面/源洞丢失。对 make_valid 后的各源 Polygon 与每个 interior ring，候选核心格几何必须有一一对应的独立面/独立洞：每个源面至少85%面积由其对应 core 面承接；每个源洞至少85%面积保留在对应 core 洞中，不能变成 core、不能开口并入外部、不能将多个源面/洞共用一个目标。该逐特征门独立于整体 IoU；失败继续既有格宽/半格相位/朝向搜索，仍失败以 core_shape_quality 排除并记录 topology_rejected_candidates，不放宽760–840等硬门。只有单面且无洞时原候选成功路径不变。独立源审核从输出RLE重建几何，以独立匹配验证所有源面/洞；生成自报统计不代此门。

源读取在写成功审计前必须核下载 manifest 非空、期望页面名唯一且安全、实际页集合精确相等、每页 bytes/rows/SHA 相等；缺页/额外页/重复页/任何内容不一致均失败。此门证明本地固定快照与钉住的下载清单一致，不等于重新查询上游或保证上游在分页时从未变化。

本次在途旧算法结果作为诊断首轮保存；最终报告明确新算法实际重算集合、逐项复验/复用集合与旧审计边界，只有经过新源拓扑审核的结果可冻结，不能把首轮 validator 通过改写为新算法已全量重跑。

洞保持补充：洞必须在该源面的**已匹配目标core面内部**匹配，不能借另一组件的洞通过。源洞范围扣除全部源内岛后才是实际源空白；目标洞范围也扣除全部core内岛后才是实际目标空白。保持比例只比这两种实际空白，不得把洞内另一core岛误算为空地。

## 12. 静态数据与源码审阅包分离（蒙恬/奕星 d2f8cec3）

部署静态包保根manifest/client-manifest/tilejson.template、farms/、tiles/及catalog/included/excluded/alias/input/raw清单。generation-report.json仅离线审核，不通过HTTP公开。完整运行/源审计只在reports/挂只读供hash复核，reports/*不走HTTP路由：source-audit、source-download-manifest、source-manifest-verification、topology-reconciliation、quality-details、r3-exclusion-reassessment、source-geometry-audit、mvt-validation、farm-runtime、source-audit-runtime、reconcile-runtime、reconcile-r3-runtime、mvt-runtime（均.json）。准入用于校验不等于公开读取。

SCHEMA-r4.md、REPRODUCE、源码/author-tools/日志独立放review归档，不进入static manifest.files，不挂HTTP服务。最终delivery-hashes同时pin静态archive/manifest/client及独立review archive/manifest。审核批准须绑定这组hash；实际HTTPS TileJSON发布后另有部署pin，不能改作者归档。

单面无洞栅格碎片澄清：源本身只有一个面且无洞时，允许离散核心产生多个组件（既有§3规定由extension连通）；此时按所有core组件合计核该源面的保留比例和整体IoU，不能要求某一小组件独自承担85%。这不会丢完整源面，也不豁免基础walk连通。多个独立源面或任何源洞仍执行独立目标及父洞保持门。生成器原有无洞单面分支未改；全量源审核按这一真实语义独立计算，失败的旧审核日志保留。
