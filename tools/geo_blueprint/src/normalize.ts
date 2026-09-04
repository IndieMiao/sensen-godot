/** 区块筛选、窗口 → 游玩区缩放、简化、邻接。 */
import type { Geometry, Polygon, Position } from 'geojson';
import * as geos from './geos.js';

export function selectBlocks(polys: Polygon[], half: number, minFrac = 0.02, maxBlocks = 7): Polygon[] {
  const areaWin = (2 * half) ** 2;
  return polys
    .map(p => ({ p, a: geos.area(p) }))
    .filter(x => x.a >= minFrac * areaWin)
    .sort((x, y) => y.a - x.a)
    .slice(0, maxBlocks)
    .map(x => x.p);
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function mapNested(c: any, f: (p: Position) => Position): any {
  return typeof c[0] === 'number' ? f(c as Position) : (c as unknown[]).map(x => mapNested(x, f));
}

export function mapCoords<T extends Geometry>(g: T, f: (p: Position) => Position): T {
  if (g.type === 'GeometryCollection') return { ...g, geometries: g.geometries.map(x => mapCoords(x, f)) } as T;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return { ...g, coordinates: mapNested((g as any).coordinates, f) } as T;
}

export function toPlay<T extends Geometry>(g: T, half: number, playM: number): T {
  const s = playM / (2 * half);
  return mapCoords(g, ([x, y]) => [(x + half) * s, (y + half) * s]);
}

export function simplify<T extends Geometry>(g: T, tol = 1.5): T {
  return geos.simplify(g, tol) as T;
}

export function adjacency(blocks: Polygon[], gap: number): { ids: string[]; neighbors: Record<string, string[]> } {
  const ids = blocks.map((_, i) => `b${i}`);
  const neighbors: Record<string, string[]> = Object.fromEntries(ids.map(i => [i, [] as string[]]));
  for (let i = 0; i < blocks.length; i++) {
    const grown = geos.buffer(blocks[i], gap);
    for (let j = i + 1; j < blocks.length; j++) {
      if (geos.intersects(grown, blocks[j])) { neighbors[ids[i]].push(ids[j]); neighbors[ids[j]].push(ids[i]); }
    }
  }
  return { ids, neighbors };
}
