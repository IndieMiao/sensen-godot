/** Builds one parcel's schema-4 farm from its buildings (UTM polygons). */
import { createHash } from 'node:crypto';
import { trace } from './boundaries.js';
import { GAME_CELL_M, GENERATOR_VERSION, SCHEMA, CLIENT_MAX_AXIS, type GeneratorParams } from './config.js';
import { dominantAngle, polygonArea, round, unrotate, UTM_CRS, type Polygon } from './geo.js';
import { buildLayout, CORE, EXTENSION, LayoutError, type Dir, type Layout } from './layout.js';
import { bestCore, type CoreRaster } from './raster.js';

export const SURFACE_PALETTE = [
  { id: 0, name: 'Soil', color: '#D8BF8D' },
  { id: 1, name: 'Grass', color: '#8FAD69' },
  { id: 2, name: 'Path', color: '#BBA882' },
];
export const ATTRIBUTION = 'DataSF building footprints and parcels (PDDL 1.0); scene extension is procedural';
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
  parcel_area_m2: number;
  /** Direction from the buildings toward the street, in the rotated grid frame. */
  front: (rotation_deg: number) => Dir;
  source_geometry_hash: string;
}

export interface FarmResult {
  farm: Record<string, unknown>;
  layout: Layout;
  core: CoreRaster;
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

export function generateFarm(input: FarmInput, p: GeneratorParams): FarmResult {
  const area = input.buildings.reduce((sum, poly) => sum + polygonArea(poly), 0);
  if (!(area > 0)) throw new LayoutError('buildings have no area');
  const rotation = p.align_to_building ? dominantAngle(input.buildings) : 0;
  const front = input.front(rotation);
  const flags: string[] = [];
  const seed = parseInt(seedHex(`p-${input.parcel_id}`, input.source_geometry_hash).slice(0, 8), 16);
  let cell = Math.max(p.cell_m, Math.ceil(Math.sqrt(area / p.core_cell_cap) * 1e4) / 1e4);
  if (cell > p.cell_m) flags.push('cell_scaled_for_core_cap');
  for (let attempt = 0; attempt < 80; attempt++) {
    const core = bestCore(input.buildings, rotation, cell, p.samples, p.coverage_threshold);
    if (core.count > p.core_cell_cap) {
      cell = round(cell * 1.02, 4);
      continue;
    }
    if (core.count === 0) throw new LayoutError('footprint smaller than one cell');
    const layout = buildLayout(core.mask, core.frame.width, core.frame.height, front, seed, p);
    if (layout.counts.total > p.total_cell_cap || layout.width > CLIENT_MAX_AXIS || layout.height > CLIENT_MAX_AXIS) {
      if (!flags.includes('cell_scaled_for_total_cap')) flags.push('cell_scaled_for_total_cap');
      cell = round(cell * 1.03, 4);
      continue;
    }
    if (layout.connectors > 0) flags.push('buildings_joined_by_path');
    if (layout.dropped_core_cells > 0) flags.push('raster_islands_dropped');
    const tooSmall = layout.counts.core < p.min_core_cells;
    if (tooSmall) flags.push('too_small');
    return { farm: farmJson(input, p, layout, core, cell, rotation, area, flags, tooSmall), layout, core, cell_m: cell, rotation_deg: rotation, area_m2: area, too_small: tooSmall, flags };
  }
  throw new LayoutError('could not fit the cell budget');
}

function farmJson(input: FarmInput, p: GeneratorParams, layout: Layout, core: CoreRaster, cell: number, rotation: number,
  area: number, flags: string[], tooSmall: boolean): Record<string, unknown> {
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
    source_transform: { crs: UTM_CRS, rotation_deg: rotation, origin_m: [round(origin[0], 3), round(origin[1], 3)] },
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
      core_iou: round(core.iou, 4),
      core_components: layout.core_components,
      walk_components: 1,
      building_source: input.building_source,
      cell_area_m2: round(cell * cell, 4),
      core_area_m2: round(layout.counts.core * cell * cell, 2),
      too_small: tooSmall,
      recovery_flags: flags,
      parameters: { cell_m: p.cell_m, core_cell_cap: p.core_cell_cap, total_cell_cap: p.total_cell_cap, min_core_cells: p.min_core_cells },
    },
    attribution: ATTRIBUTION,
    source_geometry_hash: input.source_geometry_hash,
  };
}
