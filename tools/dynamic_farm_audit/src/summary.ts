/** Human-readable summary of an audit report. */
import type { AuditReport } from './audit.js';

const list = (ids: string[], max = 20) => (ids.length === 0 ? 'none' : ids.length > max ? `${ids.slice(0, max).join(', ')} … (+${ids.length - max})` : ids.join(', '));

export function summaryMarkdown(report: AuditReport): string {
  const { reconciliation: rec, summary: s, parameters: p } = report;
  const lines: string[] = [];
  lines.push(`# Dynamic farm audit: ${report.status.toUpperCase()}`, '');
  lines.push(`- audit ${report.audit_version}; snapshot manifest ${report.inputs.snapshot_manifest_sha256}; dataset manifest ${report.inputs.dataset_manifest_sha256}`);
  lines.push(`- thresholds: IoU warning < ${p.iou_warn}, exclusion < ${p.iou_exclude}, generator IoU difference > ${p.iou_delta_warn}, building inside its parcel < ${p.attribution_min_fraction}, source area difference > ${p.area_rel_warn * 100}%`, '');
  lines.push('## Id reconciliation', '');
  const c = rec.counts;
  lines.push(`- valid input parcels ${c.input_valid} = generated ${c.generated} + excluded ${c.excluded}: ${c.input_valid === c.generated + c.excluded ? 'yes' : 'NO'}`);
  lines.push(`- lots (aliases counted separately): ${c.input_lots} valid = ${c.generated_lots} under farms + ${c.excluded_lots} under excluded parcels: ${c.input_lots === c.generated_lots + c.excluded_lots ? 'yes' : 'NO'}`);
  lines.push(`- farm files ${c.farm_files}, manifest farm entries ${c.manifest_farm_files}, index features ${c.index_features}`);
  lines.push(`- excluded by reason: ${Object.entries(rec.excluded_by_reason).map(([k, v]) => `${k} ${v}`).join(', ') || 'none'}`);
  lines.push(`- input parcel features left out: ${Object.entries(rec.input_invalid_by_reason).map(([k, v]) => `${k} ${v}`).join(', ') || 'none'}`);
  lines.push(`- discrepancies: ${rec.discrepancies.length === 0 ? 'none' : ''}`);
  for (const d of rec.discrepancies) lines.push(`  - ${d.check}: ${list(d.ids)}`);
  lines.push('', '## Source geometry', '');
  lines.push(`- farms audited ${s.farms_audited}: ok ${s.levels.ok}, warn ${s.levels.warn}, fail ${s.levels.fail}`);
  lines.push(`- audited IoU min ${s.iou.min}, median ${s.iou.median}, mean ${s.iou.mean}, max ${s.iou.max}`);
  lines.push(`- audited minus generator IoU: mean ${s.iou_delta.mean}, mean |Δ| ${s.iou_delta.mean_abs}, max |Δ| ${s.iou_delta.max_abs}, over threshold ${s.iou_delta.over_threshold}`);
  lines.push(`- below exclusion line: ${list(s.below_exclusion.map(f => `${f.block_id} ${f.iou.toFixed(4)}`))}`);
  lines.push(`- below warning line: ${list(s.below_warning.map(f => `${f.block_id} ${f.iou.toFixed(4)}`))}`);
  lines.push(`- IoU differs from generator: ${list(s.iou_differs_from_generator.map(f => `${f.block_id} ${f.iou.toFixed(4)} vs ${f.reported_iou}`))}`);
  lines.push(`- components/holes differ (source vs core): ${list(s.topology_differs.map(f => `${f.block_id} ${f.source.join('/')} vs ${f.core.join('/')}`))}`);
  lines.push(`- buildings outside / mostly in another parcel: ${list(s.attribution_findings.map(b => `${b.block_id} #${b.area_id} own ${b.share_in_parcel}, ${b.best_other_parcel ?? '-'} ${b.best_other_share}, none ${b.share_outside_parcels}`))}`);
  lines.push(`- issues: ${Object.entries(s.issues).map(([k, v]) => `${k} ${v}`).join(', ') || 'none'}`);
  lines.push('', '## Flags', '');
  lines.push(`- ${Object.entries(s.flags).map(([k, v]) => `${k} ${v}`).join(', ') || 'none'}`);
  lines.push(`- too_small ${s.too_small}; cell_scaled_for_total_cap ${s.cell_scaled_for_total_cap}`);
  lines.push(`- cell_scaled_for_total_cap AND too_small: ${s.total_cap_and_too_small.count}${s.total_cap_and_too_small.count ? ` (${list(s.total_cap_and_too_small.block_ids)})` : ''}`);
  return `${lines.join('\n')}\n`;
}
