/** Audit thresholds. Every value is a configurable default (`--params file.json`); see README.md. */

export interface AuditParams {
  /** Audited IoU below this is a warning (r4: 0.90). */
  iou_warn: number;
  /** Audited IoU below this is a failure: the farm would be excluded (r4: 0.85). */
  iou_exclude: number;
  /** |audited IoU - generator's own IoU| above this is listed as a discrepancy. */
  iou_delta_warn: number;
  /** A building whose area lies less than this fraction inside its parcel is listed. */
  attribution_min_fraction: number;
  /** Relative difference between the audited source area and the farm's source_area_m2 that is listed. */
  area_rel_warn: number;
  /** Tolerance (degrees) when comparing buildings.geojson coordinates with the snapshot. */
  coordinate_tolerance_deg: number;
}

export const DEFAULT_AUDIT_PARAMS: AuditParams = {
  iou_warn: 0.9,
  iou_exclude: 0.85,
  iou_delta_warn: 0.01,
  attribution_min_fraction: 0.5,
  area_rel_warn: 0.001,
  coordinate_tolerance_deg: 1e-7,
};

export function resolveAuditParams(overrides: Record<string, unknown> = {}): AuditParams {
  const p: AuditParams = { ...DEFAULT_AUDIT_PARAMS };
  for (const [key, value] of Object.entries(overrides)) {
    if (!(key in DEFAULT_AUDIT_PARAMS)) throw new Error(`unknown audit parameter ${key}`);
    if (typeof value !== 'number' || !Number.isFinite(value)) throw new Error(`audit parameter ${key} must be a finite number`);
    (p as unknown as Record<string, number>)[key] = value;
  }
  for (const key of ['iou_warn', 'iou_exclude', 'attribution_min_fraction'] as const) {
    if (!(p[key] >= 0 && p[key] <= 1)) throw new Error(`audit parameter ${key} must be in [0, 1]`);
  }
  if (p.iou_exclude > p.iou_warn) throw new Error('iou_exclude must not exceed iou_warn');
  for (const key of ['iou_delta_warn', 'area_rel_warn', 'coordinate_tolerance_deg'] as const) {
    if (!(p[key] >= 0)) throw new Error(`audit parameter ${key} must not be negative`);
  }
  return p;
}
