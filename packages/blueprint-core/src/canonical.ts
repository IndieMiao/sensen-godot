/**
 * canonical 字符串与 checksum。**改这里必须同步改 modules/blueprint/blueprint.gd**，
 * 两端由 golden/corpus.json 逐字节钉住。
 *
 * 文法（单行，用 | 连接；spec §5.1）：
 *   <id>|<format>|<revision>|<gx>,<gy>|<cell_mm>|<play_area_mm>
 *   |<walkable>|<cultivable>|<buildable>|<visual>
 *   |spawn:i,j;house:i,j;storage:i,j;well:i,j;exit:i,j;beds:<畦0>/<畦1>/<畦2>;reserved:<畦>
 *
 * 相对 r1 的两处扩大（2026-09-04 决策①）：
 *   1. 补上 grid / cell_mm / play_area_mm / reserved_bed。r1 的公式不覆盖它们，
 *      把 grid 从 [64,64] 手改成 [32,128]、或把 cell_m 从 1 改成 2（驱动每一次距离与
 *      耗时换算），checksum 照样通过，而客户端会把同一份 4096 字符的 mask 解读成完全
 *      不同的网格。
 *   2. 尺寸用整数毫米而不是浮点。JSON 解析器不保留数值词法，"1.0" 在 JS 里 String() 得
 *      "1"、在 GDScript 里 str() 得 "1.0"，同一份文件两端算出不同 checksum。
 *
 * name 与 region_id 刻意不进 canonical：改显示名不该让已有存档失效。
 */
import { createHash } from 'node:crypto';
import type { Blueprint, Cell } from './types.js';

const cells = (cs: Cell[]): string => cs.map(c => `${c[0]},${c[1]}`).join(',');

export function canonical(bp: Blueprint): string {
  const m = bp.masks;
  const a = bp.anchors;
  const anchors =
    `spawn:${a.spawn[0]},${a.spawn[1]};house:${a.house[0]},${a.house[1]};` +
    `storage:${a.storage[0]},${a.storage[1]};well:${a.well[0]},${a.well[1]};` +
    `exit:${a.exit[0]},${a.exit[1]};beds:${a.beds.map(b => cells(b.cells)).join('/')};` +
    `reserved:${cells(a.reserved_bed.cells)}`;
  return [
    bp.layout_patch_id,
    String(bp.format),
    String(bp.revision),
    `${bp.grid[0]},${bp.grid[1]}`,
    String(bp.cell_mm),
    String(bp.play_area_mm),
    m.walkable.join(''),
    m.cultivable.join(''),
    m.buildable.join(''),
    m.visual.join(''),
    anchors,
  ].join('|');
}

export function checksum(bp: Blueprint): string {
  return createHash('sha256').update(canonical(bp), 'utf8').digest('hex');
}
