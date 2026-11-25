/** Builds one parcel's schema-4 farm from its buildings (UTM polygons). */
import { createHash } from 'node:crypto';
import { trace } from './boundaries.js';
import { GAME_CELL_M, GENERATOR_VERSION, SCHEMA, CLIENT_MAX_AXIS, type GeneratorParams } from './config.js';
import { dominantAngle, polygonArea, round, unrotate, UTM_CRS, type Polygon } from './geo.js';
import { buildLayout, CORE, EXTENSION, LayoutError, type Dir, type Layout } from './layout.js';
import { bestCore, maskIou, type CoreRaster } from './raster.js';

export const SURFACE_PALETTE = [
  { id: 0, name: 'Soil', color: '#D8BF8D' },
  { id: 1, name: 'Grass', color: '#8FAD69' },
  { id: 2, name: 'Path', color: '#BBA882' },
];
export const ATTRIBUTION = 'DataSF building footprints and parcels (PDDL 1.0); scene extension is procedural';
/** A farm whose buildings come from OpenStreetMap (C-113): ODbL 1.0 asks for this credit. */
export const OSM_ATTRIBUTION = 'Buildings © OpenStreetMap contributors (ODbL 1.0); DataSF parcels (PDDL 1.0); scene extension is procedural';
const CAPABILITIES = {
  core: { walk: true, till: true, plant: true, arrange: true, place: true },
  extension: { walk: true, till: false, plant: false, arrange: false, place: false },
};

export interface FarmInput {
  dataset_version: string;
  parcel_id: string;
  aliases: string[];
  name: string;
  address: string | null;
  /** Building footprints in UTM metres. */
  buildings: Polygon[];
  building_source: string;
  /** Defaults to ATTRIBUTION (DataSF footprints). */
  attribution?: string;
  parcel_area_m2: number;
  /** Direction from the buildings toward the street, in the rotated grid frame. */
  front: (rotation_deg: number) => Dir;
  source_geometry_hash: string;
}

export interface FarmResult {
  farm: Record<string, unknown>;
  layout: Layout;
  core: CoreRaster;
  /** Exact IoU of the written core cells against the footprints (`stats.core_iou`). */
  iou: number;
  cell_m: number;
  rotation_deg: number;
  area_m2: number;
  too_small: boolean;
  flags: string[];
}

export function seedHex(blockId: string, geometryHash: string): string {
  return createHash('sha256').update(`sensen-dynamic-farm|${blockId}|${geometryHash}`).digest('hex');
}

/** Runs of equal value per row: [y, x, length, value] (or [y, x, length] when `withValue` is false). */
export function encodeRuns(w: number, h: number, pick: (i: number) => number | null, withValue: boolean): number[][] {
  const runs: number[][] = [];
  for (let y = 0; y < h; y++) {
    let x = 0;
    while (x < w) {
      const v = pick(y * w + x);
      if (v === null) { x++; continue; }
      let end = x + 1;
      while (end < w && pick(y * w + end) === v) end++;
      runs.push(withValue ? [y, x, end - x, v] : [y, x, end - x]);
      x = end;
    }
  }
  return runs;
}

/** The farm's core could not follow the footprints closely enough; the parcel is excluded. */
export class LowIouError extends LayoutError {
  constructor(readonly iou: number, readonly cell_m: number) { super(`core IoU ${round(iou, 4)} at cell ${cell_m} m`); }
}

/** Exact IoU of the layout's core cells (a subset of the raster mask: dropped islands are gone). */
export function layoutIou(core: CoreRaster, layout: Layout): number {
  const mask = new Uint8Array(core.cov.length);
  const fw = core.frame.width;
  for (let i = 0; i < layout.zone.length; i++) {
    if (layout.zone[i] !== CORE) continue;
    const x = i % layout.width;
    const y = (i - x) / layout.width;
    mask[(y + layout.offset[1]) * fw + x + layout.offset[0]] = 1;
  }
  return maskIou(core.cov, mask);
}

/** Extension band settings to try in order: the configured one, then one cell narrower each step. */
export function extensionLevels(p: GeneratorParams): GeneratorParams[] {
  const out: GeneratorParams[] = [];
  for (let e = p.extension_cells; e >= p.min_extension_cells; e--) {
    out.push({ ...p, extension_cells: e, extension_jitter: Math.min(p.extension_jitter, e - 1) });
  }
  return out;
}

export function generateFarm(input: FarmInput, p: GeneratorParams): FarmResult {
  const area = input.buildings.reduce((sum, poly) => sum + polygonArea(poly), 0);
  if (!(area > 0)) throw new LayoutError('buildings have no area');
  const rotation = p.align_to_building ? dominantAngle(input.buildings) : 0;
  const front = input.front(rotation);
  const flags: string[] = [];
  const seed = parseInt(seedHex(`p-${input.parcel_id}`, input.source_geometry_hash).slice(0, 8), 16);
  let cell = Math.max(p.cell_m, Math.ceil(Math.sqrt(area / p.core_cell_cap) * 1e4) / 1e4);
  if (cell > p.cell_m) flags.push('cell_scaled_for_core_cap');
  // Over the total budget, first narrow the grass extension (5 ± 2 → … → min_extension_cells), and
  // only then grow the cell: separate buildings' rings and joining paths then keep a finer outline.
  const levels = extensionLevels(p);
  let level = 0;
  for (let attempt = 0; attempt < 80; attempt++) {
    const core = bestCore(input.buildings, rotation, cell, p.coverage_threshold);
    if (core.count > p.core_cell_cap) {
      cell = round(cell * 1.02, 4);
      continue;
    }
    if (core.count === 0) throw new LayoutError('footprint smaller than one cell');
    let layout: Layout | null = null;
    for (; level < levels.length; level++) {
      const fit = buildLayout(core.mask, core.frame.width, core.frame.height, front, seed, levels[level]);
      if (fit.counts.total <= p.total_cell_cap && fit.width <= CLIENT_MAX_AXIS && fit.height <= CLIENT_MAX_AXIS) { layout = fit; break; }
    }
    if (!layout) {
      level = levels.length - 1;
      // Growing the cell only coarsens the outline further: stop once it is already too coarse.
      if (core.iou < p.min_core_iou) throw new LowIouError(core.iou, cell);
      if (!flags.includes('cell_scaled_for_total_cap')) flags.push('cell_scaled_for_total_cap');
      cell = round(cell * 1.03, 4);
      continue;
    }
    const iou = layoutIou(core, layout);
    if (iou < p.min_core_iou) throw new LowIouError(iou, cell);
    if (level > 0) flags.push('extension_narrowed');
    if (layout.connectors > 0) flags.push('buildings_joined_by_path');
    if (layout.dropped_core_cells > 0) flags.push('raster_islands_dropped');
    const tooSmall = layout.counts.core < p.min_core_cells;
    if (tooSmall) flags.push('too_small');
    const ext = levels[level];
    return {
      farm: farmJson(input, p, layout, core, iou, cell, rotation, area, flags, tooSmall, [ext.extension_cells, ext.extension_jitter]),
      layout, core, iou, cell_m: cell, rotation_deg: rotation, area_m2: area, too_small: tooSmall, flags,
    };
  }
  throw new LayoutError('could not fit the cell budget');
}

function farmJson(input: FarmInput, p: GeneratorParams, layout: Layout, core: CoreRaster, iou: number, cell: number, rotation: number,
  area: number, flags: string[], tooSmall: boolean, extension: [number, number]): Record<string, unknown> {
  const { width: w, height: h } = layout;
  const blockId = `p-${input.parcel_id}`;
  let coreMinX = Infinity;
  let coreMinY = Infinity;
  for (let i = 0; i < layout.zone.length; i++) {
    if (layout.zone[i] !== CORE) continue;
    coreMinX = Math.min(coreMinX, i % w);
    coreMinY = Math.min(coreMinY, Math.floor(i / w));
  }
  // Grid point (0,0) in UTM: raster cell `offset` corner, un-rotated.
  const f = core.frame;
  const origin = unrotate([f.u0 + layout.offset[0] * cell, f.v0 + layout.offset[1] * cell], rotation);
  const coreMask = new Uint8Array(layout.zone.length);
  const groundMask = new Uint8Array(layout.zone.length);
  for (let i = 0; i < layout.zone.length; i++) {
    coreMask[i] = layout.zone[i] === CORE ? 1 : 0;
    groundMask[i] = layout.zone[i] ? 1 : 0;
  }
  return {
    schema: SCHEMA,
    dataset_version: input.dataset_version,
    selection_unit: 'parcel',
    block_id: blockId,
    parcel_id: input.parcel_id,
    parcel_aliases: input.aliases,
    name: input.name,
    address: input.address,
    generator_version: GENERATOR_VERSION,
    seed_hex: seedHex(blockId, input.source_geometry_hash),
    game_cell_m: GAME_CELL_M,
    source_area_m2: round(area, 2),
    source_cell_m: cell,
    source_transform: { crs: UTM_CRS, rotation_deg: rotation, origin_m: [round(origin[0], 4), round(origin[1], 4)] },
    grid: { width: w, height: h, origin_cell: [1 - coreMinX, 1 - coreMinY] },
    zones: {
      core: { runs: encodeRuns(w, h, i => (layout.zone[i] === CORE ? layout.surface[i] : null), true) },
      extension: { runs: encodeRuns(w, h, i => (layout.zone[i] === EXTENSION ? layout.surface[i] : null), true) },
    },
    capabilities: CAPABILITIES,
    counts: { core_cell_count: layout.counts.core, extension_cell_count: layout.counts.extension, total_cell_count: layout.counts.total },
    surface_palette: SURFACE_PALETTE,
    boundaries: { core: trace(coreMask, w, h), outer: trace(groundMask, w, h) },
    walk_reserve: {
      no_solid_decor_runs: encodeRuns(w, h, i => (layout.protect[i] ? 1 : null), false),
      spawn_cell: layout.spawn,
      entry_cell: layout.entry,
    },
    geo_hints: { landuse: 'unknown', source_building_count: input.buildings.length, parcel_area_m2: round(input.parcel_area_m2, 2) },
    stats: {
      core_iou: round(iou, 4),
      core_components: layout.core_components,
      walk_components: 1,
      building_source: input.building_source,
      cell_area_m2: round(cell * cell, 4),
      core_area_m2: round(layout.counts.core * cell * cell, 2),
      too_small: tooSmall,
      /** Extension band actually used: [cells, jitter]. */
      extension_cells: extension,
      recovery_flags: flags,
      parameters: { cell_m: p.cell_m, core_cell_cap: p.core_cell_cap, total_cell_cap: p.total_cell_cap, min_core_cells: p.min_core_cells, min_core_iou: p.min_core_iou },
    },
    attribution: input.attribution ?? ATTRIBUTION,
    source_geometry_hash: input.source_geometry_hash,
  };
}
