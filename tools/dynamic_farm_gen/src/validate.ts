/**
 * Line-by-line port of the client's schema-4 checks (modules/dynamic_farm/farm_data.gd decode and
 * map/parcel_metadata.gd decode). `coreRange` defaults to the current client's 760–840; C-43
 * replaces that rule with "any count within the 8192 budget", which is `RELAXED`.
 */
const MAX_AXIS = 544;
const MAX_CELLS = 8192;
const SURFACES = ['soil', 'grass', 'path'];
const ACTIONS = ['walk', 'till', 'plant', 'arrange', 'place'];

export interface CoreRange { min: number; max: number }
export const CURRENT_CLIENT: CoreRange = { min: 760, max: 840 };
export const RELAXED: CoreRange = { min: 1, max: MAX_CELLS };

type Json = unknown;
const isNum = (v: Json): v is number => typeof v === 'number' && Number.isFinite(v);
const isInt = (v: Json): v is number => isNum(v) && Math.floor(v) === v;
const isObj = (v: Json): v is Record<string, Json> => typeof v === 'object' && v !== null && !Array.isArray(v);
const coordinate = (v: Json) => Array.isArray(v) && v.length === 2 && isInt(v[0]) && isInt(v[1]);

export interface Decoded {
  ok: true;
  width: number;
  height: number;
  cells: Map<string, { zone: string; surface: number }>;
  counts: { core: number; extension: number };
  protected: Set<string>;
  spawn: [number, number];
  entry: [number, number];
}
export type Result = Decoded | { ok: false; error: string };
const invalid = (error: string): Result => ({ ok: false, error });
const k = (x: number, y: number) => `${x},${y}`;

export function decodeFarm(data: Json, coreRange: CoreRange = CURRENT_CLIENT): Result {
  if (!isObj(data)) return invalid('not an object');
  if (!isInt(data.schema) || data.schema !== 4) return invalid('Unsupported dynamic farm data version.');
  for (const key of ['dataset_version', 'block_id', 'parcel_id', 'name', 'generator_version']) {
    const v = data[key];
    if (typeof v !== 'string' || v.trim() === '' || v.length > 160) return invalid('Dynamic farm details are missing.');
  }
  if (data.selection_unit !== 'parcel' || data.block_id !== `p-${data.parcel_id}`) return invalid('Dynamic farm parcel is inconsistent.');
  if (data.address != null && (typeof data.address !== 'string' || data.address.length > 160)) return invalid('Dynamic farm address is invalid.');
  if (!isNum(data.game_cell_m) || Math.abs(data.game_cell_m - 0.8) > 1e-5) return invalid('Dynamic farm cell scale is invalid.');
  for (const key of ['source_area_m2', 'source_cell_m']) if (!isNum(data[key]) || (data[key] as number) <= 0) return invalid('Dynamic farm area or scale is invalid.');
  if (typeof data.seed_hex !== 'string' || !/^[0-9a-f]{64}$/.test(data.seed_hex)) return invalid('Dynamic farm seed is invalid.');
  if (!isObj(data.source_transform) || !isNum(data.source_transform.rotation_deg)) return invalid('Dynamic farm orientation is missing.');
  const grid = data.grid;
  if (!isObj(grid)) return invalid('Dynamic farm grid is missing.');
  for (const key of ['width', 'height']) if (!isInt(grid[key]) || (grid[key] as number) < 1 || (grid[key] as number) > MAX_AXIS) return invalid('Dynamic farm grid exceeds its budget.');
  if (!coordinate(grid.origin_cell)) return invalid('Dynamic farm origin is invalid.');
  const w = grid.width as number;
  const h = grid.height as number;
  const palette = data.surface_palette;
  if (!Array.isArray(palette) || palette.length !== SURFACES.length) return invalid('Dynamic farm surface palette is invalid.');
  const seenKinds = new Set<number>();
  for (const item of palette) {
    if (!isObj(item) || !isInt(item.id) || item.id < 0 || item.id >= SURFACES.length) return invalid('Dynamic farm surface is invalid.');
    if (seenKinds.has(item.id) || typeof item.color !== 'string' || !/^#?([0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(item.color)) return invalid('Dynamic farm surface color is invalid.');
    seenKinds.add(item.id);
  }
  const zones = data.zones;
  const caps = data.capabilities;
  if (!isObj(zones) || !isObj(caps)) return invalid('Dynamic farm zones or permissions are missing.');
  const cells = new Map<string, { zone: string; surface: number }>();
  const counts = { core: 0, extension: 0 };
  for (const zone of ['core', 'extension'] as const) {
    const z = zones[zone];
    const c = caps[zone];
    if (!isObj(z) || !isObj(c)) return invalid('Dynamic farm zones or permissions are missing.');
    for (const action of ACTIONS) {
      const expected = zone === 'core' || action === 'walk';
      if (typeof c[action] !== 'boolean' || c[action] !== expected) return invalid('Dynamic farm permissions are inconsistent.');
    }
    const runs = z.runs;
    if (!Array.isArray(runs) || runs.length === 0 || runs.length > MAX_CELLS) return invalid('Dynamic farm zone rows are invalid.');
    let lastY = -1;
    let lastEnd = -1;
    for (const run of runs) {
      if (!runValid(run, w, h, 4)) return invalid('Dynamic farm zone row is outside the grid.');
      const [y, x, length, surface] = run as number[];
      if (y < lastY || (y === lastY && x < lastEnd) || surface < 0 || surface >= SURFACES.length) return invalid('Dynamic farm rows overlap or are unsorted.');
      if (cells.size + length > MAX_CELLS) return invalid('Dynamic farm cell budget exceeded.');
      for (let o = 0; o < length; o++) {
        const at = k(x + o, y);
        if (cells.has(at)) return invalid('Core and extension overlap.');
        cells.set(at, { zone, surface });
      }
      counts[zone] += length;
      lastY = y;
      lastEnd = x + length;
    }
  }
  if (counts.core < coreRange.min || counts.core > coreRange.max) return invalid('Dynamic farm core cell count is invalid.');
  const declared = data.counts;
  if (!isObj(declared)) return invalid('Dynamic farm counts are missing.');
  for (const [key, value] of [['core_cell_count', counts.core], ['extension_cell_count', counts.extension], ['total_cell_count', cells.size]] as const) {
    if (!isInt(declared[key]) || declared[key] !== value) return invalid('Dynamic farm counts do not match the cells.');
  }
  if (!connected(new Set(cells.keys()))) return invalid('Dynamic farm walking area is disconnected.');
  const reserve = data.walk_reserve;
  if (!isObj(reserve) || !Array.isArray(reserve.no_solid_decor_runs) || reserve.no_solid_decor_runs.length > MAX_CELLS) return invalid('Dynamic farm walking reserve is missing.');
  const prot = new Set<string>();
  let lastY = -1;
  let lastEnd = -1;
  for (const run of reserve.no_solid_decor_runs) {
    if (!runValid(run, w, h, 3) || run[0] < lastY || (run[0] === lastY && run[1] < lastEnd)) return invalid('Dynamic farm walking reserve rows are invalid.');
    for (let o = 0; o < run[2]; o++) {
      const at = k(run[1] + o, run[0]);
      if (!cells.has(at)) return invalid('Dynamic farm walking reserve leaves the ground.');
      prot.add(at);
    }
    lastY = run[0];
    lastEnd = run[1] + run[2];
  }
  const anchors: Record<string, [number, number]> = {};
  for (const key of ['spawn_cell', 'entry_cell']) {
    const v = reserve[key];
    if (!coordinate(v)) return invalid('Dynamic farm entry is invalid.');
    const [x, y] = v as [number, number];
    if (!cells.has(k(x, y)) || !prot.has(k(x, y))) return invalid('Dynamic farm entry has no protected ground.');
    anchors[key] = [x, y];
  }
  for (const [at, cell] of cells) {
    if (cell.zone !== 'core') continue;
    if (!prot.has(at)) return invalid('The farm core is missing its walking reserve.');
    const [x, y] = at.split(',').map(Number);
    for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) {
      const ax = Math.max(Math.abs(dx) - 0.5, 0);
      const ay = Math.max(Math.abs(dy) - 0.5, 0);
      const near = k(x + dx, y + dy);
      if (ax * ax + ay * ay <= 4 && cells.has(near) && !prot.has(near)) return invalid('The farm core corridor is incomplete.');
    }
  }
  const spawn = anchors.spawn_cell;
  const entry = anchors.entry_cell;
  if (cells.get(k(...spawn))!.zone !== 'core' || cells.get(k(...entry))!.zone !== 'extension') return invalid('The farm entry and spawn zones are invalid.');
  for (const [ax, ay] of [spawn, entry]) {
    for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) {
      const near = k(ax + dx, ay + dy);
      if (dx * dx + dy * dy <= 4 && cells.has(near) && !prot.has(near)) return invalid('The farm arrival clearance is incomplete.');
    }
  }
  if (!connected(prot)) return invalid('The farm walking reserve is disconnected.');
  if (!boundariesValid(data.boundaries, w, h)) return invalid('Dynamic farm boundary is invalid.');
  return { ok: true, width: w, height: h, cells, counts, protected: prot, spawn, entry };
}

function runValid(run: Json, w: number, h: number, fields: number): run is number[] {
  if (!Array.isArray(run) || run.length !== fields || !run.every(isInt)) return false;
  return run[0] >= 0 && run[0] < h && run[1] >= 0 && run[2] > 0 && run[1] < w && run[2] <= w - run[1];
}

function boundariesValid(raw: Json, w: number, h: number): boolean {
  if (!isObj(raw)) return false;
  let points = 0;
  for (const key of ['core', 'outer']) {
    const list = raw[key];
    if (!Array.isArray(list) || list.length === 0 || list.length > MAX_CELLS) return false;
    for (const polygon of list) {
      if (!isObj(polygon) || !Array.isArray(polygon.holes) || polygon.holes.length > MAX_CELLS) return false;
      for (const ring of [polygon.outer, ...polygon.holes]) {
        if (!Array.isArray(ring) || ring.length < 4) return false;
        points += ring.length;
        const first = ring[0];
        const last = ring[ring.length - 1];
        if (points > 65536 || !Array.isArray(first) || !Array.isArray(last) || first[0] !== last[0] || first[1] !== last[1]) return false;
        for (const p of ring) {
          if (!Array.isArray(p) || p.length !== 2 || !isNum(p[0]) || !isNum(p[1])) return false;
          if (p[0] < 0 || p[1] < 0 || p[0] > w || p[1] > h) return false;
        }
      }
    }
  }
  return true;
}

function connected(cells: Set<string>): boolean {
  const first = cells.values().next().value;
  if (first === undefined) return false;
  const seen = new Set([first]);
  const queue = [first];
  while (queue.length) {
    const [x, y] = queue.pop()!.split(',').map(Number);
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const n = k(x + dx, y + dy);
      if (cells.has(n) && !seen.has(n)) { seen.add(n); queue.push(n); }
    }
  }
  return seen.size === cells.size;
}

/**
 * A GeoJSON layer the native map loads as one source (buildings.geojson, index.geojson): one ring
 * with fewer than 4 positions makes the map reject the whole file (C-43 V-167). Returns an error or null.
 */
export function checkMapGeometry(geometry: Json): string | null {
  if (!isObj(geometry) || !Array.isArray(geometry.coordinates)) return 'geometry';
  const polygons = geometry.type === 'Polygon' ? [geometry.coordinates] : geometry.type === 'MultiPolygon' ? geometry.coordinates : null;
  if (!polygons || polygons.length === 0) return 'geometry type';
  for (const [pi, poly] of polygons.entries()) {
    if (!Array.isArray(poly) || poly.length === 0) return `polygon ${pi}: no rings`;
    for (const [ri, ring] of poly.entries()) {
      if (!Array.isArray(ring) || ring.length < 4) return `polygon ${pi} ring ${ri}: ${Array.isArray(ring) ? ring.length : 0} positions`;
      if (!ring.every(p => Array.isArray(p) && p.length === 2 && isNum(p[0]) && isNum(p[1]))) return `polygon ${pi} ring ${ri}: position`;
      const [first, last] = [ring[0], ring[ring.length - 1]];
      if (first[0] !== last[0] || first[1] !== last[1]) return `polygon ${pi} ring ${ri}: not closed`;
    }
  }
  return null;
}

/** Port of parcel_metadata.gd decode for one map feature's properties; returns an error or null. */
export function checkParcelProperties(raw: Record<string, Json>, coreRange: CoreRange = CURRENT_CLIENT): string | null {
  const id = raw.block_id;
  if (typeof id !== 'string' || !/^p-[A-Za-z0-9_*-]{1,98}$/.test(id) || typeof raw.parcel_id !== 'string' || id !== `p-${raw.parcel_id}`) return 'identity';
  if (typeof raw.name !== 'string') return 'name';
  const parsed: Record<string, Json> = { ...raw };
  for (const key of ['center', 'bbox']) {
    if (typeof parsed[key] === 'string') {
      try { parsed[key] = JSON.parse(parsed[key] as string); } catch { return key; }
    }
  }
  if ((parsed.selection_unit ?? 'parcel') !== 'parcel') return 'selection_unit';
  if (parsed.farm_path !== `farms/${id}.json`) return 'farm_path';
  const c = parsed.center;
  if (!Array.isArray(c) || c.length !== 2 || !isNum(c[0]) || !isNum(c[1]) || Math.abs(c[0]) > 180 || Math.abs(c[1]) > 90) return 'center';
  if (parsed.bbox !== undefined) {
    const b = parsed.bbox;
    if (!Array.isArray(b) || b.length !== 4 || !b.every(isNum) || b[0] > b[2] || b[1] > b[3]) return 'bbox';
  }
  for (const key of ['core_cell_count', 'extension_cell_count', 'total_cell_count']) if (!isInt(parsed[key]) || (parsed[key] as number) < 0) return key;
  const core = parsed.core_cell_count as number;
  const extension = parsed.extension_cell_count as number;
  const total = parsed.total_cell_count as number;
  if (core < coreRange.min || core > coreRange.max || extension <= 0 || total !== core + extension || total > MAX_CELLS) return 'counts';
  if (parsed.cell_count !== undefined && parsed.cell_count !== core) return 'cell_count';
  for (const key of ['source_area_m2', 'inset_area_m2']) if (parsed[key] !== undefined && (!isNum(parsed[key]) || (parsed[key] as number) <= 0)) return key;
  return null;
}
