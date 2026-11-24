/** Generator parameters. Every value is a configurable default; see README.md for the rationale. */

export const GENERATOR_VERSION = 'building-raster-2';
export const SCHEMA = 4;
export const GAME_CELL_M = 0.8;
/** Client hard limits (modules/dynamic_farm/farm_data.gd). */
export const CLIENT_MAX_CELLS = 8192;
export const CLIENT_MAX_AXIS = 544;

export interface GeneratorParams {
  /** Real edge length of one cell before any cap scaling (m). 0.5 m = 0.25 m² per cell. */
  cell_m: number;
  /** Core cells above this scale the cell up instead (same shape, fewer cells). */
  core_cell_cap: number;
  /** Core + extension cells; never above the client's 8192 budget. */
  total_cell_cap: number;
  /** Parcels whose core stays below this are still generated but flagged too_small. */
  min_core_cells: number;
  /** A cell is core when at least this fraction of it lies inside a building. */
  coverage_threshold: number;
  /** Isolated core islands smaller than this (cells) are dropped as raster noise. */
  min_component_cells: number;
  /** Extension depth beyond the 2-cell walking ring: base ± amplitude, value noise. */
  extension_cells: number;
  extension_jitter: number;
  extension_noise_period: number;
  /** Narrowest extension tried (jitter capped below it) before the cell grows for the total budget. */
  min_extension_cells: number;
  /** Snap the grid to the buildings' dominant wall direction (rotation within ±45°). */
  align_to_building: boolean;
  /** Farms whose exact core IoU stays below this are excluded (`low_iou`); just above the audit's 0.85 exclusion line. */
  min_core_iou: number;
}

export const DEFAULT_PARAMS: GeneratorParams = {
  cell_m: 0.5,
  core_cell_cap: 4096,
  total_cell_cap: CLIENT_MAX_CELLS,
  min_core_cells: 400,
  coverage_threshold: 0.5,
  min_component_cells: 4,
  extension_cells: 5,
  extension_jitter: 2,
  extension_noise_period: 8,
  min_extension_cells: 2,
  align_to_building: true,
  min_core_iou: 0.8505,
};

export function resolveParams(overrides: Partial<GeneratorParams> = {}): GeneratorParams {
  const p: GeneratorParams = { ...DEFAULT_PARAMS };
  for (const [key, value] of Object.entries(overrides)) {
    if (!(key in DEFAULT_PARAMS)) throw new Error(`unknown parameter ${key}`);
    if (typeof value !== typeof DEFAULT_PARAMS[key as keyof GeneratorParams]) throw new Error(`parameter ${key} has the wrong type`);
    (p as unknown as Record<string, unknown>)[key] = value;
  }
  const positive: (keyof GeneratorParams)[] = ['cell_m', 'core_cell_cap', 'total_cell_cap', 'extension_noise_period'];
  for (const key of positive) if (!(Number(p[key]) > 0)) throw new Error(`parameter ${key} must be positive`);
  if (p.total_cell_cap > CLIENT_MAX_CELLS) throw new Error(`total_cell_cap cannot exceed ${CLIENT_MAX_CELLS}`);
  if (p.core_cell_cap >= p.total_cell_cap) throw new Error('core_cell_cap must leave room for the extension');
  if (p.min_core_cells < 0 || p.min_core_cells > p.core_cell_cap) throw new Error('min_core_cells must be within [0, core_cell_cap]');
  if (!(p.coverage_threshold > 0 && p.coverage_threshold <= 1)) throw new Error('coverage_threshold must be in (0, 1]');
  if (p.extension_jitter < 0 || p.extension_jitter >= p.extension_cells) throw new Error('extension_jitter must be below extension_cells');
  if (!Number.isInteger(p.min_extension_cells) || p.min_extension_cells < 1 || p.min_extension_cells > p.extension_cells) {
    throw new Error('min_extension_cells must be an integer in [1, extension_cells]');
  }
  if (!(p.min_core_iou >= 0 && p.min_core_iou < 1)) throw new Error('min_core_iou must be in [0, 1)');
  if (!Number.isInteger(p.extension_cells) || !Number.isInteger(p.extension_jitter)) {
    throw new Error('extension sizes must be integers');
  }
  return p;
}
