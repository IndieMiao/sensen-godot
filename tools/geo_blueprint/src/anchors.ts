/** 锚点摆放与蓝图校验。距离用 4 邻接 BFS（与 Godot 侧 AStarGrid2D DIAGONAL_MODE_NEVER 一致）。 */
import * as core from 'blueprint-core';
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
  // 预留畦也记进 cultivable：它买下即为已翻土的田（2026-09-04 决策⑥），
  // 服务端按 beds_unlocked 决定第四畦能不能种，mask 只表达「这格能不能是田」。
  for (const r of beds.slice(0, config.INITIAL_BEDS + 1)) for (const [i, j] of r) cult[j][i] = '1';
  masks.cultivable = cult.map((row: string[]) => row.join(''));
  const bed = (id: string, cells: Cell[]): Bed => ({ id, cells: cells.map(c => [c[0], c[1]]) });
  return {
    spawn, house, storage, well, exit,
    beds: beds.slice(0, 3).map((r, k) => bed(`bed${k}`, r)),
    reserved_bed: bed('bed3', beds[3]),
  };
}

/**
 * 校验 + 公平指标。规则与公式都在 packages/blueprint-core 里，Godot 侧走同一份实现；
 * 这里只补一条管线自己的约束（区块数量），它不是蓝图契约的一部分。
 */
export function validate(bp: Blueprint): Report {
  const errors = [...core.validate(bp)];
  if (bp.blocks.length < config.MIN_BLOCKS || bp.blocks.length > config.MAX_BLOCKS)
    errors.push(`block count ${bp.blocks.length} outside ${config.MIN_BLOCKS}-${config.MAX_BLOCKS}`);
  const m = core.metrics(bp);
  return { ...m, errors: [...errors, ...m.errors] };
}
