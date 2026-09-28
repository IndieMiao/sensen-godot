import { createHash } from 'node:crypto';
import { rasterize, regionContains, pathPoints, PLOT_KINDS, KIND_TRAITS, type PlotLayout, type PlotLayoutSource, type PlotRegion } from '../domain/plot.js';
import type { FarmLocation } from '../http/farm_location.js';
import type { Navigation } from '../realtime/model.js';
import type { FishingSite } from '../domain/fishing.js';

/** Legacy generation remains available for old clients and stored previews. */
export const GEOGRAPHY_EXTENT_M = 240;
export type FarmGenerationVersion = 1 | 2 | 3;
export const FARM_GENERATIONS: Record<FarmGenerationVersion, {
  generation_version: FarmGenerationVersion; grid: [number, number]; cell_mm: number;
  play_area_m: number; geography_extent_m: number;
}> = {
  1: { generation_version: 1, grid: [64, 64], cell_mm: 750, play_area_m: 48, geography_extent_m: 240 },
  2: { generation_version: 2, grid: [40, 40], cell_mm: 800, play_area_m: 32, geography_extent_m: 160 },
  3: { generation_version: 3, grid: [40, 40], cell_mm: 800, play_area_m: 32, geography_extent_m: 160 },
};
export const LATEST_FARM_GENERATION: FarmGenerationVersion = 3;
export const MAX_FACILITY_RASTERIZATIONS = 96;
export const MAX_FACILITY_CANDIDATES = 4096;
/** Optional internal instrumentation for bounded-generation regression checks. */
export interface FarmGenerationDiagnostics { facility_rasterizations: number; facility_candidates: number }
/** Asset identifiers shared with modules/farm/farm_art.gd, not arbitrary asset paths. */
export const FARM_STYLES = ['cottage', 'mushroom', 'thatch', 'dome', 'east_asian', 'barn', 'windmill'] as const;
export type FarmStyle = (typeof FARM_STYLES)[number];
const EAST_ASIAN = new Set(['CN', 'JP', 'KR', 'TW', 'HK', 'MO']);
const BARN = new Set(['US', 'CA', 'AU', 'NZ']);
/** Curated cities keep their hand-picked style; every other city follows its country. */
export function farmStyleForRegion(regionId: string, countryCode = ''): FarmStyle {
  if (regionId === 'shanghai') return 'east_asian';
  if (regionId === 'los_angeles') return 'barn';
  return EAST_ASIAN.has(countryCode) ? 'east_asian' : BARN.has(countryCode) ? 'barn' : 'cottage';
}
function validFarmStyle(value: unknown): value is FarmStyle {
  return typeof value === 'string' && (FARM_STYLES as readonly string[]).includes(value);
}
export type GeoPoint = [number, number]; // longitude, latitude
export interface GeoFeature {
  id: string;
  /** Supplemental land cover fills only gaps; known OSM shapes always take precedence. */
  layer?: 'supplement';
  kind: 'land' | 'water' | 'desert' | 'rock' | 'road';
  surface?: 'soil' | 'lawn';
  polygon?: GeoPoint[];
  holes?: GeoPoint[][];
  line?: GeoPoint[];
}
export interface Geography {
  provider: 'osm'; fetched_at: string; features: GeoFeature[];
  attribution: string; license: string; source_checksum: string;
  land_cover?: LandCoverSource;
}
export interface LandCoverSource {
  provider: 'esa_worldcover'; dataset: string; year: number; license: string; attribution: string;
  resolution_m: number; tiles: string[]; classes: Record<string, number>; source_checksum: string;
}
export interface LandCoverSupplement { features: GeoFeature[]; source: LandCoverSource }
export type LandCoverProvider = (location: FarmLocation, extentM: number) => Promise<LandCoverSupplement>;
export type GeographyProvider = (location: FarmLocation, extentM: number) => Promise<Geography>;
export interface FarmTerrain {
  format: 1;
  layout_id: string;
  farm_style?: FarmStyle;
  plot: PlotLayoutSource;
  source: {
    provider: 'osm'; generator_version: FarmGenerationVersion; center: FarmLocation; extent_m: number;
    attribution: string; license: string; fetched_at: string; source_checksum: string;
    feature_ids: string[]; known_fraction: number; water_fraction: number; desert_fraction: number;
    land_cover?: LandCoverSource;
  };
}
export class GeographyError extends Error {
  constructor(readonly code: 'GEOGRAPHY_UNAVAILABLE' | 'GEOGRAPHY_INCOMPLETE' | 'LOCATION_ALL_WATER' | 'LOCATION_ALL_DESERT' | 'LOCATION_UNSUITABLE') { super(code); }
}

export function supplementGeography(geography: Geography, supplement: LandCoverSupplement): Geography {
  return { ...geography, features: [...supplement.features.map(feature => ({ ...feature, layer: 'supplement' as const })), ...geography.features],
    source_checksum: createHash('sha256').update(JSON.stringify({ osm: geography.source_checksum, land_cover: supplement.source.source_checksum })).digest('hex'),
    attribution: geography.attribution + '; ' + supplement.source.attribution,
    license: geography.license + '; ' + supplement.source.license, land_cover: structuredClone(supplement.source) };
}

/** Generator coordinates are cell centres; same WGS84 equirectangular window as selection. */
export function projectToPlot(point: GeoPoint, center: FarmLocation, generationVersion: FarmGenerationVersion = 1): GeoPoint {
  const spec = FARM_GENERATIONS[generationVersion], size = spec.grid[0], midpoint = (size - 1) / 2;
  return [(point[0] - center.lng) * 111320 * Math.cos(center.lat * Math.PI / 180) / spec.geography_extent_m * size + midpoint,
    (point[1] - center.lat) * 111320 / spec.geography_extent_m * size + midpoint];
}
/** Clip geographic rings to the finite selected window; enclosing polygons remain valid. */
export function clipRing(input: GeoPoint[], size = 64): GeoPoint[] {
  let ring = input;
  for (const [axis, boundary, direction] of [[0, -.5, 1], [0, size - .5, -1], [1, -.5, 1], [1, size - .5, -1]]) {
    const clipped: GeoPoint[] = [];
    if (!ring.length) return [];
    for (let i = 0; i < ring.length; i++) {
      const a = ring[(i + ring.length - 1) % ring.length], b = ring[i];
      const aIn = (a[axis] - boundary) * direction >= 0, bIn = (b[axis] - boundary) * direction >= 0;
      if (aIn !== bIn) {
        const t = (boundary - a[axis]) / (b[axis] - a[axis]);
        clipped.push([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]);
      }
      if (bIn) clipped.push(b);
    }
    ring = clipped;
  }
  return ring.length >= 3 ? ring : [];
}
function clipSegment(a: GeoPoint, b: GeoPoint, size: number): [GeoPoint, GeoPoint] | null {
  let lo = 0, hi = 1;
  for (const axis of [0, 1]) {
    const delta = b[axis] - a[axis];
    if (Math.abs(delta) < 1e-12) { if (a[axis] < -.5 || a[axis] > size - .5) return null; continue; }
    const t1 = (-.5 - a[axis]) / delta, t2 = (size - .5 - a[axis]) / delta;
    lo = Math.max(lo, Math.min(t1, t2)); hi = Math.min(hi, Math.max(t1, t2));
  }
  if (lo >= hi) return null;
  const at = (t: number): GeoPoint => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
  return [at(lo), at(hi)];
}
const largestComponent = (mask: Uint8Array, size: number): number => {
  const visited = new Uint8Array(mask.length); let largest = 0;
  for (let k = 0; k < mask.length; k++) {
    if (!mask[k] || visited[k]) continue;
    const queue = [k]; visited[k] = 1;
    for (let n = 0; n < queue.length; n++) {
      const at = queue[n], x = at % size, y = Math.floor(at / size);
      for (const next of [x > 0 ? at - 1 : -1, x < size - 1 ? at + 1 : -1, y > 0 ? at - size : -1, y < size - 1 ? at + size : -1])
        if (next >= 0 && mask[next] && !visited[next]) { visited[next] = 1; queue.push(next); }
    }
    largest = Math.max(largest, queue.length);
  }
  return largest;
};

/** Compact boundaries surround the unchanged full-size homestead/fishing facilities. */
function compactBase(base: PlotLayoutSource): PlotLayoutSource {
  const next = structuredClone(base);
  const move = ([x, y]: GeoPoint): GeoPoint => [x - 4, y - 8];
  next.anchors = Object.fromEntries(Object.entries(next.anchors).map(([name, point]) => [name, move(point)]));
  next.anchors.exit = [22, 2];
  next.anchors.pond_shore = [8, 29];
  next.anchors.mine_approach = [21, 26];
  const edges: Record<string, Pick<PlotRegion, 'path' | 'width'>> = {
    north_cliff: { path: [[0, 40.5], [8, 41], [15, 40.25], [24, 41], [32, 40.4], [40, 41]], width: 6 },
    east_cliff: { path: [[40, 12], [39, 18], [40, 26], [39.4, 33], [41, 41]], width: 5 },
    west_cliff: { path: [[-1, 12], [.2, 20], [.5, 26], [1, 33], [-.5, 41]], width: 5 },
  };
  next.regions = next.regions.map(region => {
    if (region.id && edges[region.id]) return { ...region, ...edges[region.id] };
    if (region.rect) region.rect = [...move([region.rect[0], region.rect[1]]), region.rect[2], region.rect[3]];
    if (region.ellipse) region.ellipse = [...move([region.ellipse[0], region.ellipse[1]]), region.ellipse[2], region.ellipse[3]];
    if (region.path) region.path = region.path.map(move);
    return region;
  });
  return next;
}

/** Trusted host-plot geometry; a visitor's own farm must never choose the visited pond bounds. */
export function farmPondSite(terrain: FarmTerrain | undefined, template: FishingSite): FishingSite {
  if (!terrain || terrain.source.generator_version === 1) return structuredClone(template);
  // Validate generation/grid/checksum before accepting any per-farm fishing geometry.
  plotForFarm({ farm_terrain: terrain }, null as unknown as PlotLayout);
  // Geographic water is polygonal; the mandatory pond is the sole water ellipse.
  // Region labels remain presentation metadata and can be sanitized in visitor views.
  const pond = terrain.plot.regions.find(region => region.kind === 'water' && region.ellipse)?.ellipse;
  if (!pond) throw new Error('TERRAIN_MISMATCH');
  const cell = terrain.plot.cell_mm / 1000;
  return { ...structuredClone(template), center: [pond[0] * cell, -pond[1] * cell],
    radii: [pond[2] * cell, pond[3] * cell], stand: [(pond[0] + .5) * cell, -(pond[1] - 4.5) * cell] };
}

function translateRegion(region: PlotRegion, dx: number, dy: number): PlotRegion {
  const next = structuredClone(region), move = ([x, y]: GeoPoint): GeoPoint => [x + dx, y + dy];
  if (next.rect) next.rect = [...move([next.rect[0], next.rect[1]]), next.rect[2], next.rect[3]];
  if (next.ellipse) next.ellipse = [...move([next.ellipse[0], next.ellipse[1]]), next.ellipse[2], next.ellipse[3]];
  if (next.path) next.path = next.path.map(move);
  if (next.polygon) next.polygon = next.polygon.map(move);
  if (next.holes) next.holes = next.holes.map(ring => ring.map(move));
  return next;
}
function reachableCells(plot: PlotLayout, start: GeoPoint): Uint8Array {
  const seen = new Uint8Array(plot.gx * plot.gy), first = start[1] * plot.gx + start[0];
  if (!plot.walk[first]) return seen;
  const queue = [first]; seen[first] = 1;
  for (let n = 0; n < queue.length; n++) {
    const at = queue[n], x = at % plot.gx, y = Math.floor(at / plot.gx);
    for (const next of [x > 0 ? at - 1 : -1, x < plot.gx - 1 ? at + 1 : -1,
      y > 0 ? at - plot.gx : -1, y < plot.gy - 1 ? at + plot.gx : -1])
      if (next >= 0 && plot.walk[next] && !seen[next]) { seen[next] = 1; queue.push(next); }
  }
  return seen;
}

/** Preserve geographic hazards after cosmetic ground, including water meeting the selected boundary. */
function protectedGeography(classified: Uint8Array, size: number, osmWater: PlotRegion[]): PlotRegion[] {
  const preciseWater = new Uint8Array(size * size);
  for (const region of osmWater) for (let j = 0; j < size; j++) for (let i = 0; i < size; i++)
    if (regionContains(region, i, j)) preciseWater[j * size + i] = 1;
  const kindAt = (i: number, j: number): 'water' | 'rock' | null => {
    const n = j * size + i, value = classified[n];
    return value === 1 || preciseWater[n] ? null : value === 2 ? 'water' : 'rock';
  };
  const regions: PlotRegion[] = [];
  for (let j = 0; j < size; j++) for (let i = 0; i < size;) {
    const kind = kindAt(i, j), first = i++;
    if (!kind) continue;
    while (i < size && kindAt(i, j) === kind) i++;
    regions.push({ id: `protected_${kind}_${j}_${first}`, kind, rect: [first, j, i - first, 1] });
  }
  // Retain smooth, precise OSM shoreline polygons rather than enlarging them to raster rectangles.
  return [...regions, ...structuredClone(osmWater)];
}

function fitCompactFacilities(base: PlotLayoutSource, geographic: PlotRegion[], classified: Uint8Array, osmWater: PlotRegion[], diagnostics?: FarmGenerationDiagnostics, includePond = true): PlotLayoutSource {
  const size = 40, dry = (x: number, y: number) => x >= 0 && y >= 0 && x < size && y < size && classified[y * size + x] === 1;
  const components = new Uint16Array(size * size); let component = 0;
  for (let first = 0; first < classified.length; first++) {
    if (classified[first] !== 1 || components[first]) continue;
    const queue = [first]; components[first] = ++component;
    for (let n = 0; n < queue.length; n++) {
      const at = queue[n], x = at % size, y = Math.floor(at / size);
      for (const next of [x > 0 ? at - 1 : -1, x < size - 1 ? at + 1 : -1, y > 0 ? at - size : -1, y < size - 1 ? at + size : -1])
        if (next >= 0 && classified[next] === 1 && !components[next]) { components[next] = component; queue.push(next); }
    }
  }
  const pond = base.regions.find(region => region.id === 'pond')!.ellipse!;
  const edges = base.regions.filter(region => region.id?.endsWith('_cliff'));
  const core = base.regions.filter(region => !region.id?.endsWith('_cliff') && region.id !== 'pond');
  const required: GeoPoint[] = [];
  for (const region of core.filter(region => region.kind === 'building' || region.id === 'mine_mouth'))
    for (let j = 0; j < size; j++) for (let i = 0; i < size; i++) if (regionContains(region, i, j)) required.push([i, j]);
  for (const name of ['spawn', 'house', 'storage', 'well', 'mine', 'stall', 'mine_approach']) required.push(base.anchors[name]);
  const positions = (origin: GeoPoint) => Array.from({ length: size * size }, (_, n) => {
    const point: GeoPoint = [n % size, Math.floor(n / size)];
    return { point, distance: (point[0] - origin[0]) ** 2 + (point[1] - origin[1]) ** 2, n };
  }).sort((a, b) => a.distance - b.distance || a.n - b.n).map(value => value.point);
  const homes = positions(base.anchors.spawn).map(([x, y]) => [x - base.anchors.spawn[0], y - base.anchors.spawn[1]] as GeoPoint)
    .filter(([dx, dy]) => {
      const [sx, sy] = base.anchors.spawn, group = components[(sy + dy) * size + sx + dx];
      return group > 0 && required.every(([x, y]) => dry(x + dx, y + dy) && components[(y + dy) * size + x + dx] === group);
    });
  const pondOffsets: GeoPoint[] = [], bankOffsets: GeoPoint[] = [];
  for (let y = -6; y <= 6; y++) for (let x = -7; x <= 7; x++) {
    if ((x / pond[2]) ** 2 + (y / pond[3]) ** 2 <= 1.00001) pondOffsets.push([x, y]);
    if ((x / (pond[2] + 1)) ** 2 + (y / (pond[3] + 1)) ** 2 <= 1.00001) bankOffsets.push([x, y]);
  }
  bankOffsets.push([0, -5]);
  const ponds: GeoPoint[] = includePond ? positions([pond[0], pond[1]]).filter(([x, y]) => x - pond[2] >= 0 && x + pond[2] <= size
    && y - pond[3] >= 0 && y + pond[3] <= size && bankOffsets.every(([i, j]) => dry(x + i, y + j))) : [[0, 0]];
  if (!homes.length || !ponds.length) throw new GeographyError('LOCATION_UNSUITABLE');
  const protections = protectedGeography(classified, size, osmWater);
  const skeleton: PlotLayoutSource = { revision: 1, name: 'Farm', grid: [size, size], cell_mm: 800, default_kind: 'rock', anchors: base.anchors, regions: geographic };
  // Geographic polygons and protected water can be large; rasterize those invariant layers once.
  const background = rasterize('facility_background', skeleton), protectedKinds = new Uint8Array(size * size).fill(255);
  for (const region of protections) for (let j = 0; j < size; j++) for (let i = 0; i < size; i++)
    if (regionContains(region, i, j)) protectedKinds[j * size + i] = PLOT_KINDS.indexOf(region.kind);
  const rasterFacilities = (plot: PlotLayoutSource, facilities: PlotRegion[]) => {
    const raster: PlotLayout = { ...background, anchors: plot.anchors, kinds: background.kinds.slice(), walk: background.walk.slice(), till: background.till.slice(), place: background.place.slice() };
    for (const region of facilities) {
      const curve = region.path ? pathPoints(region.path) : [], kind = PLOT_KINDS.indexOf(region.kind);
      for (let j = 0; j < size; j++) for (let i = 0; i < size; i++) if (regionContains(region, i, j, curve)) raster.kinds[j * size + i] = kind;
    }
    for (let n = 0; n < raster.kinds.length; n++) {
      if (protectedKinds[n] !== 255) raster.kinds[n] = protectedKinds[n];
      const traits = KIND_TRAITS[PLOT_KINDS[raster.kinds[n]]]; raster.walk[n] = Number(traits.walk); raster.till[n] = Number(traits.till); raster.place[n] = Number(traits.place);
    }
    return raster;
  };
  const tried = new Set<string>();
  let rasterizations = 0, candidates = 0;
  const tryLayout = ([dx, dy]: GeoPoint, [px, py]: GeoPoint): PlotLayoutSource | undefined => {
    const key = [dx, dy, px, py].join(','); if (tried.has(key)) return undefined; tried.add(key);
    if (++candidates > MAX_FACILITY_CANDIDATES) throw new GeographyError('LOCATION_UNSUITABLE');
    if (diagnostics) diagnostics.facility_candidates = candidates;
    const occupied = new Set(required.map(([x, y]) => `${x + dx},${y + dy}`));
    if (includePond && pondOffsets.some(([x, y]) => occupied.has(`${px + x},${py + y}`))) return undefined;
    const anchors = Object.fromEntries(Object.entries(base.anchors).map(([name, [x, y]]) => [name, [x + dx, y + dy] as GeoPoint]));
    anchors.pond_shore = [px, py - 4]; anchors.pond_stand = [px, py - 5];
    if (!includePond) { delete anchors.pond_shore; delete anchors.pond_stand; }
    const start = anchors.spawn;
    const facilities: PlotRegion[] = [
        { id: 'facility_pond_bank', kind: 'soil', rect: [px - 7, py - 7, 15, 14] },
        { id: 'facility_homestead', kind: 'soil', rect: [16 + dx, 21 + dy, 18, 19] },
        { id: 'facility_pond_approach', kind: 'lawn', path: [anchors.pond_shore, [(px + start[0]) / 2, py - 6], start], width: 2 },
        ...structuredClone(edges), ...core.map(region => translateRegion(region, dx, dy)),
        { id: 'pond', kind: 'water', ellipse: [px, py, pond[2], pond[3]] }];
    if (!includePond) {
      for (let i = facilities.length - 1; i >= 0; i--)
        if (['pond', 'facility_pond_bank', 'facility_pond_approach'].includes(facilities[i].id ?? '')) facilities.splice(i, 1);
    }
    const plot: PlotLayoutSource = { revision: 1, name: 'Farm', grid: [size, size], cell_mm: 800, default_kind: 'rock', anchors,
      regions: [...geographic, ...facilities, ...protections] };
    if (plot.regions.length > 1024) throw new GeographyError('GEOGRAPHY_UNAVAILABLE');
    if (rasterizations >= MAX_FACILITY_RASTERIZATIONS) throw new GeographyError('LOCATION_UNSUITABLE');
    rasterizations++; if (diagnostics) diagnostics.facility_rasterizations = rasterizations;
    const raster = rasterFacilities(plot, facilities), reachable = reachableCells(raster, start);
    for (const name of [...(includePond ? ['pond_shore', 'pond_stand'] : []), 'mine_approach', 'stall']) {
      const point = anchors[name]; if (!reachable[point[1] * size + point[0]]) return undefined;
    }
    if (reachable.reduce((sum, value, n) => sum + value * raster.till[n], 0) < 128) return undefined;
    // Exit remains on reachable dry land even when moving the compact homestead near a boundary.
    const exit = positions([Math.max(0, Math.min(size - 1, anchors.exit[0])), Math.max(0, Math.min(size - 1, anchors.exit[1]))])
      .find(([x, y]) => reachable[y * size + x]);
    if (!exit) return undefined;
    anchors.exit = exit;
    return plot;
  };
  if (!includePond) {
    for (const home of homes) { const fit = tryLayout(home, [0, 0]); if (fit) return fit; }
    throw new GeographyError('LOCATION_UNSUITABLE');
  }
  // Prefer the familiar relative composition; if the shoreline is narrow, fit the pond independently.
  const pondKeys = new Set(ponds.map(point => point.join(',')));
  const homeGroup = ([dx, dy]: GeoPoint) => components[(base.anchors.spawn[1] + dy) * size + base.anchors.spawn[0] + dx];
  const pondGroup = ([x, y]: GeoPoint) => components[(y - 4) * size + x];
  const pondsByGroup = new Map<number, GeoPoint[]>();
  for (const point of ponds) { const group = pondGroup(point), list = pondsByGroup.get(group) ?? []; list.push(point); pondsByGroup.set(group, list); }
  for (const home of homes) {
    const point: GeoPoint = [pond[0] + home[0], pond[1] + home[1]];
    if (pondKeys.has(point.join(',')) && homeGroup(home) === pondGroup(point)) { const fit = tryLayout(home, point); if (fit) return fit; }
  }
  for (const home of homes) for (const point of pondsByGroup.get(homeGroup(home)) ?? []) { const fit = tryLayout(home, point); if (fit) return fit; }
  throw new GeographyError('LOCATION_UNSUITABLE');
}

export function generateFarmTerrain(center: FarmLocation, geography: Geography, base: PlotLayoutSource,
  farmStyle?: FarmStyle, generationVersion: FarmGenerationVersion = 1, diagnostics?: FarmGenerationDiagnostics): FarmTerrain {
  if (diagnostics) { diagnostics.facility_rasterizations = 0; diagnostics.facility_candidates = 0; }
  if (base.cell_mm !== 750 || base.grid[0] !== 64 || base.grid[1] !== 64 || !geography.features.length)
    throw new GeographyError('GEOGRAPHY_UNAVAILABLE');
  const spec = FARM_GENERATIONS[generationVersion];
  if (!spec) throw new GeographyError('GEOGRAPHY_UNAVAILABLE');
  const size = spec.grid[0], total = size * size;
  // Reproduce historical generation recipes for frozen previews and fixtures.
  // New requests use v3; API persistence also retires ponds from legacy recipes.
  base = structuredClone(base);
  if (generationVersion < 3) {
    const historicalPond = base.regions.find(region => region.id === 'pond' && region.ellipse);
    if (historicalPond) historicalPond.kind = 'water';
  }
  if (generationVersion >= 2) base = compactBase(base);
  const vertexCount = (features: GeoFeature[]) => features.reduce((total, f) => total + (f.polygon?.length ?? 0) + (f.line?.length ?? 0) + (f.holes ?? []).reduce((n, h) => n + h.length, 0), 0);
  const primary = geography.features.filter(feature => feature.layer !== 'supplement');
  if (primary.length > 450 || vertexCount(primary) > 7500 || geography.features.length > 1024 || vertexCount(geography.features) > 18000)
    throw new GeographyError('GEOGRAPHY_UNAVAILABLE');
  const regions: PlotRegion[] = [], osmWater: PlotRegion[] = [];
  const classified = new Uint8Array(total); // 0 unknown, 1 habitable, 2 water, 3 desert, 4 rock
  const polygonArea = (f: GeoFeature) => Math.abs((f.polygon ?? []).reduce((sum, p, i, ring) => {
    const next = ring[(i + 1) % ring.length]; return sum + p[0] * next[1] - next[0] * p[1];
  }, 0));
  // Broad mapped landuse supplies context; more specific nested polygons retain their own cover.
  const features = [...geography.features].sort((a, b) => polygonArea(b) - polygonArea(a) || a.id.localeCompare(b.id));
  for (const layer of ['supplement', undefined] as const) for (const kind of ['land', 'road', 'rock', 'desert', 'water'] as const) {
    for (const feature of features.filter(f => f.kind === kind && f.layer === layer)) {
      const region: PlotRegion = { id: 'geo_' + feature.id.replace(/[^a-zA-Z0-9_]/g, '_'),
        kind: kind === 'land' ? feature.surface ?? 'soil' : kind === 'road' ? 'path' : kind === 'water' ? 'water' : 'rock' };
      if (feature.polygon) {
        region.polygon = clipRing(feature.polygon.map(p => projectToPlot(p, center, generationVersion)), size);
        if (!region.polygon.length) continue;
        if (feature.holes?.length) region.holes = feature.holes.map(h => clipRing(h.map(p => projectToPlot(p, center, generationVersion)), size)).filter(h => h.length);
      } else if (feature.line && kind === 'road') {
        // Preserve original polyline instead of introducing spline overshoot into geography.
        const line = feature.line.map(p => projectToPlot(p, center, generationVersion));
        for (let n = 1; n < line.length; n++) {
          const segment = clipSegment(line[n - 1], line[n], size);
          if (segment) regions.push({ ...region, id: region.id + '_' + n, path: segment, width: 1.5 });
        }
        continue;
      } else continue;
      regions.push(region);
      if (layer === undefined && kind === 'water') osmWater.push(region);
      for (let j = 0; j < size; j++) for (let i = 0; i < size; i++) {
        if (regionContains(region, i, j)) classified[j * size + i] = kind === 'land' ? 1 : kind === 'water' ? 2 : kind === 'desert' ? 3 : 4;
      }
    }
  }
  const count = (value: number) => classified.reduce((n, v) => n + Number(v === value), 0);
  const water = count(2), desert = count(3), unknown = count(0);
  if (water === total) throw new GeographyError('LOCATION_ALL_WATER');
  if (desert === total) throw new GeographyError('LOCATION_ALL_DESERT');
  const land = Uint8Array.from(classified, v => Number(v === 1));
  // Check suitability BEFORE fitting gameplay facilities: those cannot rescue an ocean or tiny island.
  if (largestComponent(land, size) < total / 4) {
    const possible = largestComponent(Uint8Array.from(classified, value => Number(value === 0 || value === 1)), size);
    throw new GeographyError(unknown > 0 && possible >= total / 4 ? 'GEOGRAPHY_INCOMPLETE' : 'LOCATION_UNSUITABLE');
  }
  if (regions.length + base.regions.length + 3 > 1024) throw new GeographyError('GEOGRAPHY_UNAVAILABLE');
  const plot: PlotLayoutSource = generationVersion >= 2 ? fitCompactFacilities(base, regions, classified, osmWater, diagnostics, generationVersion < 3)
    : { revision: 1, name: 'Farm', grid: [...spec.grid], cell_mm: spec.cell_mm,
    default_kind: 'rock', anchors: structuredClone(base.anchors), regions: [
      ...regions,
      // A compact playable homestead is deliberately designed inside the accepted geographic sample.
      { id: 'facility_pond_bank', kind: 'soil', rect: generationVersion === 1 ? [5, 34, 15, 15] : [1, 26, 15, 14] },
      { id: 'facility_homestead', kind: 'soil', rect: generationVersion === 1 ? [20, 29, 18, 20] : [16, 21, 18, 19] },
      { id: 'facility_pond_approach', kind: 'lawn', path: generationVersion === 1 ? [[16, 37], [22, 35], [28, 35]] : [[12, 29], [18, 27], [24, 27]], width: 4 },
      ...structuredClone(base.regions),
    ] };
  const preliminary = rasterize('generated_check', plot);
  const reclaimedWater = classified.reduce((count, kind, n) => count + Number(kind === 2 && preliminary.kinds[n] !== 3), 0);
  // The mandatory homestead may trim a shore, but must not replace a significant real water area.
  if (reclaimedWater > total / 32) throw new GeographyError('LOCATION_UNSUITABLE');
  const spawn = plot.anchors.spawn, start = spawn[1] * size + spawn[0], reachable = new Uint8Array(total), queue = [start];
  if (!preliminary.walk[start]) throw new GeographyError('LOCATION_UNSUITABLE');
  reachable[start] = 1;
  for (let n = 0; n < queue.length; n++) {
    const at = queue[n], x = at % size, y = Math.floor(at / size);
    for (const next of [x > 0 ? at - 1 : -1, x < size - 1 ? at + 1 : -1, y > 0 ? at - size : -1, y < size - 1 ? at + size : -1])
      if (next >= 0 && preliminary.walk[next] && !reachable[next]) { reachable[next] = 1; queue.push(next); }
  }
  const pondShore = plot.anchors.pond_shore ?? [12, 37], mineApproach = plot.anchors.mine_approach ?? [25, 34];
  if ((generationVersion < 3 && !reachable[pondShore[1] * size + pondShore[0]]) || !reachable[mineApproach[1] * size + mineApproach[0]]
    || queue.reduce((total, n) => total + preliminary.till[n], 0) < 128) throw new GeographyError('LOCATION_UNSUITABLE');
  const source: FarmTerrain['source'] = { provider: 'osm', generator_version: generationVersion, center: { ...center }, extent_m: spec.geography_extent_m,
    attribution: geography.attribution, license: geography.license, fetched_at: geography.fetched_at, source_checksum: geography.source_checksum,
    feature_ids: features.map(f => f.id), known_fraction: (total - unknown) / total, water_fraction: water / total, desert_fraction: desert / total,
    ...(geography.land_cover ? { land_cover: structuredClone(geography.land_cover) } : {}) };
  const identity = createHash('sha256').update(JSON.stringify({ center, plot, source_checksum: source.source_checksum, generator_version: generationVersion })).digest('hex');
  const layout_id = 'geo_' + identity.slice(0, 20);
  plot.checksum = rasterize(layout_id, plot).checksum;
  return { format: 1, layout_id, plot, source, ...(validFarmStyle(farmStyle) ? { farm_style: farmStyle } : {}) };
}

/** Lossless retirement of the authored pond, never real geographic water.
 * Coordinates, provenance and all non-pond regions remain unchanged. The new
 * checksum/id prevents a stale client or cache from reusing the blocked basin.
 */
export function retireFarmPond(terrain: FarmTerrain): FarmTerrain {
  plotForFarm({ farm_terrain: terrain }, null as unknown as PlotLayout);
  if (!terrain.plot.regions.some(region => region.id === 'pond' && region.kind === 'water' && region.ellipse)) return terrain;
  const next = structuredClone(terrain);
  for (const region of next.plot.regions)
    if (region.id === 'pond' && region.kind === 'water' && region.ellipse) region.kind = 'soil';
  delete next.plot.anchors.pond_shore;
  delete next.plot.anchors.pond_stand;
  delete next.plot.checksum;
  // JSONB reorders object keys. Derive identity from the canonical raster so
  // memory, database, owner and visitor paths produce exactly the same layout.
  const signature = rasterize('geo_retired_pond_v1', next.plot).checksum;
  next.layout_id = 'geo_' + createHash('sha256').update(terrain.layout_id + ':' + signature).digest('hex').slice(0, 20);
  next.plot.checksum = rasterize(next.layout_id, next.plot).checksum;
  return next;
}

const terrainPlots = new Map<string, PlotLayout>();
export function plotForFarm(farm: { farm_terrain?: FarmTerrain }, fallback: PlotLayout): PlotLayout {
  const terrain = farm.farm_terrain;
  if (!terrain) return fallback;
  const spec = FARM_GENERATIONS[terrain.source?.generator_version];
  if (!spec || terrain.source.extent_m !== spec.geography_extent_m
    || terrain.plot.grid[0] !== spec.grid[0] || terrain.plot.grid[1] !== spec.grid[1]) throw new Error('TERRAIN_MISMATCH');
  // A claimed checksum alone is not a cache identity: a corrupted stored source
  // can retain it. Changed geometry must reach rasterization and verification.
  const fingerprint = createHash('sha256').update(JSON.stringify({ format: terrain.format, plot: terrain.plot })).digest('hex');
  const key = terrain.layout_id + ':' + terrain.plot.checksum + ':' + fingerprint;
  const cached = terrainPlots.get(key);
  if (cached) return cached;
  const plot = rasterize(terrain.layout_id, terrain.plot);
  if (terrain.format !== 1 || plot.gx !== spec.grid[0] || plot.gy !== spec.grid[1] || plot.cellMm !== spec.cell_mm || plot.checksum !== terrain.plot.checksum)
    throw new Error('TERRAIN_MISMATCH');
  if (terrainPlots.size >= 1000) terrainPlots.delete(terrainPlots.keys().next().value!);
  terrainPlots.set(key, plot);
  return plot;
}

export function terrainNavigation(terrain: FarmTerrain): Navigation {
  const plot = plotForFarm({ farm_terrain: terrain }, null as unknown as PlotLayout);
  const cell = plot.cellMm / 1000, spawn = plot.anchors.spawn;
  return { cell, rows: Array.from({ length: plot.gy }, (_, j) => Array.from(plot.walk.slice(j * plot.gx, (j + 1) * plot.gx)).join('')),
    spawn: [(spawn[0] + .5) * cell, -(spawn[1] + .5) * cell] };
}

/** Visitor terrain includes geometry only; original coordinates/provenance reveal private location. */
export function visitorTerrain(terrain: FarmTerrain): Omit<FarmTerrain, 'source'> {
  const plot = structuredClone(terrain.plot);
  // Geographic region IDs contain public OSM element references. Those references
  // locate the original parcel even when coordinates and provenance are hidden.
  // IDs are presentation metadata, outside the authoritative geometry checksum.
  plot.regions = plot.regions.map((region, index) => region.id?.startsWith('geo_')
    ? { ...region, id: `geo_surface_${index}` } : region);
  return { format: 1, layout_id: terrain.layout_id, plot,
    ...(validFarmStyle(terrain.farm_style) ? { farm_style: terrain.farm_style } : {}) };
}
