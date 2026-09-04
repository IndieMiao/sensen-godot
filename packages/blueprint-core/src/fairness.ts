/**
 * 公平指标（spec §6，2026-09-04 决策③）。全部是绝对秒数。
 *
 * 为什么不用相对差值：r1 的门槛是「六蓝图 tour_s 两两相差 < 10%」，而 tour_s 里
 * 掺了一个对所有蓝图都相同的常数动作时间。常数取 18 秒时算出 6.8% 过线，取 0 秒
 * （纯步行）时算出 29% 不过线——同一批蓝图，换个常数就在过线与不过线之间跳。
 * 基数只有 5.6 秒时，1.6 秒的差就是 29%，而 1.6 秒玩家根本感觉不到。改为绝对秒数后
 * 指标衡量的是玩家真能感知的量。
 *
 * far_bed_s 的相对差值更是结构性恒为 0：anchors.place() 选畦永远优先离出生点最近的
 * 三条，所以它在候选之间没有差异，那条断言什么也证明不了，已删除。
 */
import { bfs, cellKey } from './grid.js';
import type { Blueprint, Cell, Report } from './types.js';

export const WALK_SPEED = 2.5; // m/s
export const ACTION_S = 2.0; // 单格动作
/** 一轮完整九格农活的动作次数：清理、翻土、播种、照料各一遍（PRD §6.3）。 */
export const ACTIONS_PER_ROUND = 36;
export const MAX_FAR_BED_S = 12.0;
/** 六蓝图之间纯步行巡回时间的最大允许差（秒）。 */
export const MAX_WALK_TOUR_SPREAD_S = 5.0;

const key = (c: Cell, gx: number) => cellKey(c[0], c[1], gx);
const round2 = (v: number) => Math.round(v * 100) / 100;

export function metrics(bp: Blueprint): Report {
  const gx = bp.grid[0];
  const walk = bp.masks.walkable;
  const a = bp.anchors;
  const cellM = bp.cell_mm / 1000;
  const secs = (steps: number) => (steps * cellM) / WALK_SPEED;

  const fromSpawn = bfs(walk, a.spawn, gx);
  const d = (c: Cell) => fromSpawn.get(key(c, gx)) ?? Number.POSITIVE_INFINITY;

  const far = (beds: { cells: Cell[] }[]) => Math.max(...beds.flatMap(b => b.cells.map(d)));
  const tour = (beds: { cells: Cell[] }[]) => {
    let steps = 0;
    let cur: Cell = a.spawn;
    for (const next of [...beds.map(b => b.cells[0]), a.spawn]) {
      steps += bfs(walk, cur, gx).get(key(next, gx)) ?? Number.POSITIVE_INFINITY;
      cur = next;
    }
    return steps;
  };

  const nine = a.beds;
  const twelve = [...a.beds, a.reserved_bed];
  const walkTour9 = secs(tour(nine));
  const errors: string[] = [];
  const farBed9 = secs(far(nine));
  const farBed12 = secs(far(twelve));
  if (farBed9 > MAX_FAR_BED_S) errors.push(`最远田格 ${farBed9.toFixed(1)}s > ${MAX_FAR_BED_S}s`);
  if (farBed12 > MAX_FAR_BED_S) errors.push(`含第四畦的最远田格 ${farBed12.toFixed(1)}s > ${MAX_FAR_BED_S}s`);

  return {
    far_bed_9_s: round2(farBed9),
    far_bed_12_s: round2(farBed12),
    walk_tour_9_s: round2(walkTour9),
    walk_tour_12_s: round2(secs(tour(twelve))),
    tour_s: round2(walkTour9 + ACTIONS_PER_ROUND * ACTION_S),
    errors,
  };
}

/** 六蓝图之间的绝对差；调用方传同一指标在各蓝图上的取值。 */
export function spreadSeconds(values: number[]): number {
  if (values.length === 0) return 0;
  return Math.max(...values) - Math.min(...values);
}
