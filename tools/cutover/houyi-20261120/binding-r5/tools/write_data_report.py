from pathlib import Path
import json
R=Path(__file__).resolve().parents[1];O=R/'generated';m=json.loads((O/'manifest.json').read_text());g=json.loads((O/'generation-report.json').read_text());source=json.loads((O/'reports/source-geometry-audit.json').read_text());reassess=json.loads((O/'reports/r3-exclusion-reassessment.json').read_text());delivery=json.loads((R/'delivery-hashes.json').read_text());receipt=json.loads((R/'evidence/full-author-validation.json').read_text());tiles=json.loads((O/'reports/mvt-validation.json').read_text());counts=m['counts']
text=f'''审核绑定增补：本轮重新审核全部farm，结果逐行绑定farm原始字节SHA、完整源记录SHA、dataset/schema/generator版本；审核分片头绑定原冻结manifest/source快照/审核代码SHA和依赖版本。finalize逐文件读回并严格核对这些绑定，任何同ID替换或版本漂移均阻止封包。旧包与旧报告另保留，新包只更新审核/metadata，farm和MVT字节不变。

# SGODOT-499 动态农场 r4 作者数据交件

全旧金山按固定公开源重新生成首轮，再经源拓扑返修和最终逐地块源感知审核：**{counts['included_parcels']:,}可选，{counts['excluded_parcels']}排除，{counts['alias_parcels']}别名**。这里只交独立demo的数据与工具，不是正式版本/业务玩法部署。静态归档和独立review归档由delivery-hashes.json共同pin，最终周瑜审核批准单独绑定两组hash；本报告不自行赋予reviewed状态。

## 源与集合

复用2026-11-17已冻结DataSF公开分页，没有重新查上游或取玩家位置。5页{counts['source_records']:,}行，接受{counts['source_accepted_records']:,}、原始拒绝{counts['source_rejected_records']}。固定下载manifest和每页集合/bytes/rows/SHA均核过。源有效编号{counts['source_distinct_parcels']:,} = {counts['included_parcels']:,}可选canonical + {counts['excluded_parcels']}排除canonical + {counts['alias_parcels']}别名；三集合精确互斥并覆盖input-parcels，不只比较数量。canonical与farm/catalog/MVT严格对应。

和r3相比：旧163项排除中恢复{reassess['recovered']}项；原可选中有{len(reassess['new_excluded_from_r3'])}项不满足新门而排除，净增{counts['included_parcels']-154444}项。逐ID原因/尝试与源hash在reports/r3-exclusion-reassessment.json和excluded-parcels.json。排除主因：{json.dumps(g['exclusion_reasons'],ensure_ascii=False)}。

## 核心、扩展、形状与权限

核心实际{g['cell_ranges']['core'][0]}–{g['cell_ranges']['core'][1]}格，门仍760–840；扩展{g['cell_ranges']['extension'][0]}–{g['cell_ranges']['extension'][1]}格；总数{g['cell_ranges']['total'][0]}–{g['cell_ranges']['total'][1]}（预算≤8192）；最大轴{max(g['cell_ranges']['width'][1],g['cell_ranges']['height'][1])}（预算≤544）。每格游戏边长0.8m，扩展名义7±3格，必要时收敛到4格，不削核心凑预算。

核心声明walk/till/plant/arrange/place；扩展仅walk。当前没有接种植/摆放业务API，字段只是后续场景能力。所有核心、外围2格、入口/spawn及保护路径不放实体阻挡；基础walk与reserve四邻连通。扩展仅本地场景空间，不回投地图、不扩大真实认领、不按道路/邻地强裁。源建筑/历史水估计只是geo_hints，不决定权限；未知为null。

{source['count']:,}份输出均由独立源审核重新投影源几何、从RLE矩形重建并计算IoU，实际范围{source['iou_range'][0]:.6f}–{source['iou_range'][1]:.6f}。其中{len(source['approximation_warning'])}份低于.90且≥.85，均带approximation_warning并在源审核报告单列，不能将其描述为全部≥90%。多源面和源洞逐特征≥85%保留且绑定正确父面，洞按扣除全部内岛后的真实空白核。无洞单面允许栅格碎为多个core组件，按合计覆盖核；extension须连通它们。

源拓扑首审发现的窄面/窄洞、嵌套洞错配均有旧算法反例与修复证据。首轮两worker是旧源码诊断；所有77个复杂源经修复重算，简单无洞源154474份逐SHA复制。最终全部included经过实际新源IoU/拓扑审核，不冒称154528份都由最后一次源码重新生成。两轮完整诊断目录、逐项hash差异与失败审核日志保留；详细链见reports/topology-reconciliation.json。

## 地图瓦片与数据分发

parcels source-layer、block_id promoteId、z15–18；地图几何始终真实parcel，扩展不上地图。Mapbox建筑仅native瞬时选择/高亮，不进farm/claim数据。MVT带name/address、core/extension/total计数；兼容cell_count明确等于core。

'''
for z,d in tiles['zooms'].items():text+=f"- z{z}：{d['tile_count']}片，{d['unique_parcels']}个唯一parcel，缺{d['missing_count']}，gzip {d['compressed_bytes']:,} bytes；最大片{d['max_compressed_tile_bytes']:,} bytes。\n"
text+=f'''
瓦片逐条解码核ID/字段/格数/路径和逐zoom集合；禁按密度/体积主动丢feature，但不把实际简化顶点数冒称0，缺失统计为实测。XYZ由MBTiles TMS反转y导出，文件gzip。手机client-manifest无大files列表，单farm按需取。

静态只含数据；reports固定13个JSON、catalog等审计sidecar与generation-report不通过HTTP公开。SCHEMA、源码和日志独立review包，不挂服务。HTTP公开边界由蒙恬已审工具实现，作者静态核验不代其上线验证。

## pin、校验与未覆盖边界

- 作者static archive：{delivery['archive']}\n  SHA256 `{delivery['archive_sha256']}`（{delivery['archive_bytes']:,} bytes）。
- 作者完整manifest：`{delivery['author_manifest_sha256']}`。
- 手机client-manifest：`{delivery['client_manifest_sha256']}`。
- {receipt['file_count']:,}个manifest文件全部SHA通过，实际文件集精确相等，归档所有成员再校hash通过。
- 已核源分页、源有效ID分区、所有最终源几何、核心/扩展权限与连通、MVT字段和覆盖。独立托管inventory门离线通过。

尚未由本交件证明：devserver实际启动/HTTPS、公网时延、Android APK、原生地图操作、A看B/B看A、3D最终画面或帧率。由蒙恬/盘古/刘邦/李元芳分别提交；旧r1/r2/r3服务与隧道保持。代码审过与最终数据审过必须区别，最终双归档批准以后才能部署。
'''
(R/'499-r4-data-review.md').write_text(text)
