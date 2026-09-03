/** 地理 → 本地米制（横轴墨卡托，中心为原点，x 东 y 北）、窗口裁剪、区块 polygonize。 */
import proj4 from 'proj4';
import type { LineString, Polygon, Position, Geometry } from 'geojson';
import { HIGHWAY_RE, type Way } from './osm.js';
import * as geos from './geos.js';

export interface Transformer { forward(lnglat: Position): Position; inverse(xy: Position): Position }

export function makeTransformer(lat: number, lng: number): Transformer {
  const def = `+proj=tmerc +lat_0=${lat} +lon_0=${lng} +k=1 +x_0=0 +y_0=0 +ellps=WGS84 +units=m +no_defs`;
  const conv = proj4('EPSG:4326', def);
  return {
    forward: p => conv.forward([p[0], p[1]]) as Position,
    inverse: p => conv.inverse([p[0], p[1]]) as Position,
  };
}

export function projectWays(ways: Way[], lat: number, lng: number, allowedRe: string = HIGHWAY_RE): LineString[] {
  const t = makeTransformer(lat, lng);
  const re = new RegExp(`^(${allowedRe})$`);
  return ways.filter(w => re.test(w.highway)).map(w => ({
    type: 'LineString',
    coordinates: w.coords.map(([la, lg]) => t.forward([lg, la])),
  }));
}

export function windowPolygon(half: number): Polygon {
  return { type: 'Polygon', coordinates: [[[-half, -half], [half, -half], [half, half], [-half, half], [-half, -half]]] };
}

function collectLines(g: Geometry, out: LineString[]): void {
  if (g.type === 'LineString' && g.coordinates.length >= 2) {
    out.push(g);
  } else if (g.type === 'MultiLineString') {
    for (const c of g.coordinates) if (c.length >= 2) out.push({ type: 'LineString', coordinates: c });
  } else if ('geometries' in g) {
    for (const sub of (g as any).geometries) collectLines(sub, out);
  }
}

export function clipLines(lines: LineString[], half: number): LineString[] {
  const win = windowPolygon(half);
  const out: LineString[] = [];
  for (const l of lines) collectLines(geos.intersection(l, win), out);
  return out;
}

/** 道路 + 窗口边界一起 noding，窗口内每个闭合面都成为候选区块。 */
export function polygonizeBlocks(lines: LineString[], half: number): Polygon[] {
  const ring: LineString = { type: 'LineString', coordinates: windowPolygon(half).coordinates[0] };
  const noded = geos.unaryUnion([...lines, ring]);
  return geos.polygonize(noded).filter(p => geos.area(p) > 1.0);
}
