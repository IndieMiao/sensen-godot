/** 几何 → 逻辑格。判定用格中心点；所有 mask 都是 grid 行 × grid 列的 '0'/'1' 字符串。 */
import type { LineString, Polygon } from 'geojson';
import type { Masks } from './types.js';
import * as geos from './geos.js';

export const cellKey = (i: number, j: number, grid: number): number => j * grid + i;

export function pathCells(paths: LineString[], grid: number, cellM: number, widthM: number): Set<number> {
  const out = new Set<number>();
  if (paths.length === 0) return out;
  const pc = geos.preparedContains(geos.unaryUnion(paths.map(p => geos.buffer(p, widthM / 2))));
  for (let j = 0; j < grid; j++) for (let i = 0; i < grid; i++)
    if (pc.contains([(i + 0.5) * cellM, (j + 0.5) * cellM])) out.add(cellKey(i, j, grid));
  pc.dispose();
  return out;
}

export function rasterize(paths: LineString[], blocks: Polygon[], grid: number, cellM: number, widthM: number): Masks {
  const pcs = pathCells(paths, grid, cellM, widthM);
  const blockArea = blocks.length ? geos.preparedContains(geos.unaryUnion(blocks)) : null;
  const eroded = blocks.map(b => geos.buffer(b, -1.0)).filter(g => !geos.isEmpty(g));
  const buildArea = eroded.length ? geos.preparedContains(geos.unaryUnion(eroded)) : null;
  const visual: string[] = [], walkable: string[] = [], buildable: string[] = [], cultivable: string[] = [];
  for (let j = 0; j < grid; j++) {
    let w = '', b = '';
    for (let i = 0; i < grid; i++) {
      const c: [number, number] = [(i + 0.5) * cellM, (j + 0.5) * cellM];
      const onPath = pcs.has(cellKey(i, j, grid));
      const inBlock = blockArea?.contains(c) ?? false;
      w += onPath || inBlock ? '1' : '0';
      b += !onPath && (buildArea?.contains(c) ?? false) ? '1' : '0';
    }
    visual.push('1'.repeat(grid)); walkable.push(w); buildable.push(b); cultivable.push('0'.repeat(grid));
  }
  blockArea?.dispose(); buildArea?.dispose();
  return { visual, walkable, buildable, cultivable };
}

export function count(mask: string[]): number {
  return mask.reduce((n, r) => n + (r.match(/1/g)?.length ?? 0), 0);
}
