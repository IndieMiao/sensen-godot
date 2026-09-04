/**
 * 结构与语义校验，**必须在 checksum 之前跑**：checksum 只证明文件没被改过，
 * 越界坐标、不可达田畦、与预留畦重叠的初始畦照样能算出合法的 sha256
 * （Codex 二审 Important 10）。字段级校验在 parse.ts，这里只管跨字段的关系。
 */
import { bfs, cellKey } from './grid.js';
import type { Blueprint, Cell } from './types.js';

const BED_CELLS = 3;
const INITIAL_BEDS = 3;
/** 三条初始畦 + 预留畦，全部记进 cultivable（spec §5.2）。预留畦买下即为已翻土的田（决策⑥）。 */
export const CULTIVABLE_CELLS = (INITIAL_BEDS + 1) * BED_CELLS;

const key = (c: Cell, gx: number) => cellKey(c[0], c[1], gx);
const countOnes = (mask: string[]) => mask.reduce((n, r) => n + (r.match(/1/g)?.length ?? 0), 0);

export function validate(bp: Blueprint): string[] {
  const errors: string[] = [];
  const gx = bp.grid[0];
  const walk = bp.masks.walkable;
  const a = bp.anchors;

  if (walk[a.spawn[1]][a.spawn[0]] !== '1') {
    errors.push('spawn 不在 walkable 上');
    return errors; // spawn 不可站立时后面的可达性判断没有意义
  }
  const dist = bfs(walk, a.spawn, gx);
  const reachable = (c: Cell) => dist.has(key(c, gx));

  for (const name of ['house', 'storage', 'well', 'exit'] as const)
    if (!reachable(a[name])) errors.push(`${name} 从 spawn 不可达`);

  const allBeds = [...a.beds, a.reserved_bed];
  const seen = new Map<number, string>();
  for (const b of allBeds) {
    if (b.cells.length !== BED_CELLS) errors.push(`${b.id} 应为 ${BED_CELLS} 格`);
    for (const c of b.cells) {
      const k = key(c, gx);
      const prev = seen.get(k);
      if (prev !== undefined) errors.push(`${b.id} 的格 ${c} 与 ${prev} 重叠`);
      seen.set(k, b.id);
      if (bp.masks.cultivable[c[1]][c[0]] !== '1') errors.push(`${b.id} 的格 ${c} 不在 cultivable 上`);
      if (!reachable(c)) errors.push(`${b.id} 的格 ${c} 从 spawn 不可达`);
    }
    // 三格必须横向相邻：劳作以田畦为操作单元，行级工具一次覆盖同畦 3 格（PRD §6.3）。
    const [p, q, r] = b.cells;
    const contiguous = p[1] === q[1] && q[1] === r[1] && q[0] === p[0] + 1 && r[0] === q[0] + 1;
    if (!contiguous) errors.push(`${b.id} 的三格不是同一行相邻的 i, i+1, i+2`);
  }

  const ncult = countOnes(bp.masks.cultivable);
  if (ncult !== CULTIVABLE_CELLS) errors.push(`cultivable 格数 ${ncult} != ${CULTIVABLE_CELLS}`);

  return errors;
}
