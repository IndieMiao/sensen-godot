/** 锚点摆放与蓝图校验。距离用 4 邻接 BFS（与 Godot 侧 AStarGrid2D DIAGONAL_MODE_NEVER 一致）。 */
import * as config from './config.js';
import { cellKey } from './masks.js';
import type { Anchors, Bed, Blueprint, Cell, Masks, Report } from './types.js';

export class ValidationError extends Error {}

export function bfs(walkable: string[], start: Cell): Map<number, number> {
  const g = walkable.length;
  const dist = new Map<number, number>([[cellKey(start[0], start[1], g), 0]]);
  const q: Cell[] = [start];
  while (q.length) {
    const [x, y] = q.shift()!;
    const d = dist.get(cellKey(x, y, g))!;
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]] as const) {
      const nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= g || ny >= g) continue;
      const k = cellKey(nx, ny, g);
      if (walkable[ny][nx] === '1' && !dist.has(k)) { dist.set(k, d + 1); q.push([nx, ny]); }
    }
  }
  return dist;
}

const cellsOf = (mask: string[]): Cell[] => {
  const out: Cell[] = [];
  mask.forEach((row, j) => { for (let i = 0; i < row.length; i++) if (row[i] === '1') out.push([i, j]); });
  return out;
};
const fromKey = (k: number, g: number): Cell => [k % g, Math.floor(k / g)];
const sq = (a: Cell, b: Cell) => (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2;
const nearest = (cells: Cell[], target: Cell): Cell => cells.reduce((best, c) => (sq(c, target) < sq(best, target) ? c : best));
const farFrom = (c: Cell, used: Cell[], margin = 1) => used.every(u => Math.abs(c[0] - u[0]) > margin || Math.abs(c[1] - u[1]) > margin);

export function place(masks: Masks, pathCells: Set<number>, grid: number): Anchors {
  if (pathCells.size === 0) throw new ValidationError('no path cells');
  const pcs = [...pathCells].map(k => fromKey(k, grid));
  const center: Cell = [Math.floor(grid / 2), Math.floor(grid / 2)];
  const spawn = nearest(pcs, center);
  const dist = bfs(masks.walkable, spawn);
  const has = (c: Cell) => dist.has(cellKey(c[0], c[1], grid));
  const dOf = (c: Cell) => dist.get(cellKey(c[0], c[1], grid)) ?? Number.POSITIVE_INFINITY;
  const reachablePath = pcs.filter(has);
  const boundary = reachablePath.filter(c => c[0] === 0 || c[0] === grid - 1 || c[1] === 0 || c[1] === grid - 1);
  const pool = boundary.length ? boundary : reachablePath;
  const exit = pool.reduce((best, c) => (dOf(c) > dOf(best) ? c : best));
  const buildable = cellsOf(masks.buildable).filter(has);
  const bset = new Set(buildable.map(c => cellKey(c[0], c[1], grid)));
  const runs: Cell[][] = [];
  for (const [i, j] of buildable)
    // i + 2 必须仍落在同一行内：cellKey(i,j,grid)=j*grid+i 没有上界检查时，cellKey(grid,j)
    // 会与 cellKey(0,j+1) 别名重合，把下一行左端的格子误判成本行的延续，产出 x>=grid 的床格
    // （2026-09-03 终审发现；今天不触发纯属 masks.ts 硬编码 1m 侵蚀让最外圈不可建造的偶然巧合）。
    if (i + 2 < grid && bset.has(cellKey(i + 1, j, grid)) && bset.has(cellKey(i + 2, j, grid))) runs.push([[i, j], [i + 1, j], [i + 2, j]]);
  runs.sort((a, b) => dOf(a[0]) + dOf(a[2]) - (dOf(b[0]) + dOf(b[2])));
  const beds: Cell[][] = []; const used: Cell[] = [];
  for (const r of runs) {
    if (r.every(c => farFrom(c, used))) { beds.push(r); used.push(...r); }
    if (beds.length === config.INITIAL_BEDS + 1) break;
  }
  if (beds.length < config.INITIAL_BEDS + 1) throw new ValidationError(`only ${beds.length} bed sites, need ${config.INITIAL_BEDS + 1}`);
  const free = buildable.filter(c => farFrom(c, used, 2));
  if (free.length < 2) throw new ValidationError('no room for house/storage');
  const house = nearest(free, spawn);
  const storage = nearest(free.filter(c => c !== house), house);
  const wellPool = pcs.filter(c => Math.abs(c[0] - spawn[0]) + Math.abs(c[1] - spawn[1]) === 1);
  const well = wellPool[0] ?? spawn;
  const cult = masks.walkable.map(() => Array(grid).fill('0') as string[]);
  for (const r of beds.slice(0, config.INITIAL_BEDS)) for (const [i, j] of r) cult[j][i] = '1';
  masks.cultivable = cult.map(row => row.join(''));
  const bed = (id: string, cells: Cell[]): Bed => ({ id, cells: cells.map(c => [c[0], c[1]]) });
  return {
    spawn, house, storage, well, exit,
    beds: beds.slice(0, 3).map((r, k) => bed(`bed${k}`, r)),
    reserved_bed: bed('bed3', beds[3]),
  };
}

export function validate(bp: Blueprint): Report {
  const walk = bp.masks.walkable, g = walk.length, a = bp.anchors;
  const dist = bfs(walk, a.spawn);
  const key = (c: Cell) => cellKey(c[0], c[1], g);
  const errors: string[] = [];
  for (const name of ['house', 'storage', 'well', 'exit'] as const)
    if (!dist.has(key(a[name]))) errors.push(`${name} unreachable from spawn`);
  let far = 0; const firsts: Cell[] = [];
  for (const b of a.beds) {
    for (const c of b.cells) {
      if (!dist.has(key(c))) errors.push(`${b.id} cell ${c} unreachable`);
      far = Math.max(far, dist.get(key(c)) ?? 1e6);
    }
    firsts.push(b.cells[0]);
  }
  if (bp.blocks.length < config.MIN_BLOCKS || bp.blocks.length > config.MAX_BLOCKS)
    errors.push(`block count ${bp.blocks.length} outside ${config.MIN_BLOCKS}-${config.MAX_BLOCKS}`);
  const ncult = bp.masks.cultivable.reduce((n, r) => n + (r.match(/1/g)?.length ?? 0), 0);
  if (ncult !== config.INITIAL_BEDS * config.BED_CELLS) errors.push(`cultivable cells ${ncult} != 9`);
  let tour = 0; let cur: Cell = a.spawn;
  for (const nxt of [...firsts, a.spawn]) { tour += bfs(walk, cur).get(key(nxt)) ?? 1e6; cur = nxt; }
  const farS = (far * bp.cell_m) / config.WALK_SPEED;
  const tourS = (tour * bp.cell_m) / config.WALK_SPEED + config.INITIAL_BEDS * config.BED_CELLS * config.ACTION_S;
  if (farS > config.MAX_FAR_BED_S) errors.push(`farthest bed ${farS.toFixed(1)}s > ${config.MAX_FAR_BED_S}s`);
  return { far_bed_s: Math.round(farS * 100) / 100, tour_s: Math.round(tourS * 100) / 100, errors };
}
