# r4 数据生成与校验

只在独立目录 `/Volumes/ACASIS/tmp/geo-farm-demo-1117/dynamic-farm` 工作。正式仓库、旧 r1/r2/r3 静态和运行环境不变。源码和数据交周瑜审，蒙恬部署；作者不能把 `reviewed:false` 改成批准。

解释器使用同级 `parcel-r2/.venv/bin/python`；实际依赖版本写最终 manifest.generator.libraries。公开源分页沿用 11-17 已下载的 `parcel-r2/data/parcels-*.json`，URL/文件 hash/行数见 `parcel-download-manifest.json`，此次没有新查官方 API。源 ID 冻结先于几何修复和归并。旧 r3 farm 仅用于 geo_hints 追溯，未知写 null，不决定核心资格/能力。

重跑需另建独立副本；不得在已冻结 generated、staging 或归档上重跑覆盖。把本目录 tools/、SCHEMA-r4.md 与所需相邻公开源快照布局复制到新工作根后依序执行：

1. `python tools/prepare_source.py`：生成输入有效 ID、逐源行拒绝、候选、别名和源歧义清单；保留 `audit/r3-exclusions-baseline.json` 作为旧版排除基线。
2. `python tools/run_city.py`：按大乔明确放行窗口，两个 nice10 worker。该 supervisor 以 free+inactive+spec≥3GB、初始 swap+300MB 为降并发门。记录每个 PID/RSS/退出码。每个输出在写文件前经过独立 RLE/权限/预算/连通/保护带/渲染边界检查。
3. `python tools/reconcile_topology.py` 后执行 `python tools/assemble_city.py`：等两个完整结果，不使用半成品；首轮单独移至diagnostic-firstpass，新目录中重算所有复杂源、逐hash复用未受影响的简单源，精确记录来源。源编号三集合精确对账，并核实际 farm 文件集。写 full manifest 的预切片阶段文件，尚不可部署。
4. `python tools/run_source_audit.py`：重新从源多边形与输出 RLE 独立计算全部 included 的 IoU、源组件/洞数；不导入生成器或信任 stats.core_iou。
5. MVT另向大乔登记。开令后用 `python tools/run_mvt.py --window <批准号> --deadline <带时区硬截止时间>`。只切源 parcel，不含场景扩展；z15–18、parcels、promoteId block_id，2线程。失败/截止先保留证据，再按新窗口重做，不无条件续跑。
6. `python tools/export_validate_tiles.py`：逐 tile 解码，核 ID/名称/门牌/三count/farm_path，导 XYZ gzip；逐 zoom 列覆盖和缺失。maxzoom 缺 ID 阻止冻结。
7. `python tools/finalize_city.py`：完整源几何审计与 included 一一对应；原样使用蒙恬已审 inventory validator 做离线集合门；核所有文件 SHA/真实文件集，生成小 client-manifest（无 files，绑定完整 manifest SHA）。
8. `python tools/archive_static.py`：新建规范静态 tar.gz，逐归档成员再校 hash；交 delivery-hashes.json、完整审计报告和源码快照送审。审核批准单独绑定作者 manifest/archive/client SHA；蒙恬填真实 HTTPS TileJSON 后另钉部署 pin，不覆盖作者 pin。

760–840 核心格、≤8192 总格、≤544 轴为硬门；IoU 0.85–0.90 必带 approximation_warning，报告单列，<0.85排除。失败不得以额外矩形/扩展格凑核心格数，不可只取多部件最大面。不适用或坏的原始行、有效地块排除、同地块别名分别计数。

权限字段仅声明后续场景能力，当前没有种植/摆放业务接口。扩展是独立本地场景空间，不扩大真实地籍、不回投地图、不占邻地。真实 Mapbox 建筑仅 native 瞬时选择/高亮，不进入生成或认领持久数据。

测试结果严格分层：作者静态/源几何/瓦片通过不等于托管启动、APK、帧率或 A/B 互访通过；这些由蒙恬、盘古、刘邦、李元芳提供各自证据。
