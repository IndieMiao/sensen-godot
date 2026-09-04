/** 网格上的 4 邻接 BFS，与 Godot 侧 AStarGrid2D（DIAGONAL_MODE_NEVER）走一样的距离。 */
import type { Cell } from './types.js';

export const cellKey = (i: number, j: number, gx: number): number => j * gx + i;

export function bfs(walkable: string[], start: Cell, gx: number): Map<number, number> {
  const gy = walkable.length;
  if (walkable[start[1]]?.[start[0]] !== '1') return new Map();
  const dist = new Map<number, number>([[cellKey(start[0], start[1], gx), 0]]);
  const q: Cell[] = [start];
  for (let head = 0; head < q.length; head++) {
    const [x, y] = q[head];
    const d = dist.get(cellKey(x, y, gx))!;
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]] as const) {
      const nx = x + dx;
      const ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= gx || ny >= gy) continue;
      const k = cellKey(nx, ny, gx);
      if (walkable[ny][nx] === '1' && !dist.has(k)) {
        dist.set(k, d + 1);
        q.push([nx, ny]);
      }
    }
  }
  return dist;
}
