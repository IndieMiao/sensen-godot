/**
 * 蓝图解析与字段级校验。canonical 之前必须先过这一关：checksum 只证明「没被改过」，
 * 不证明「合法」——越界坐标、非法 mask 字符照样能算出一个合法的 sha256
 * （Codex 二审 Important 10）。
 */
import type { Anchors, Bed, Blueprint, Cell, Masks } from './types.js';

export class BlueprintError extends Error {
  constructor(readonly code: string, message: string) {
    super(`${code}: ${message}`);
    this.name = 'BlueprintError';
  }
}

const ID_RE = /^[a-z0-9_]{1,32}$/;
export const MM_MIN = 1;
export const MM_MAX = 100_000;

const fail = (code: string, msg: string): never => {
  throw new BlueprintError(code, msg);
};

function int(v: unknown, code: string, what: string, min: number, max: number): number {
  if (typeof v !== 'number' || !Number.isInteger(v) || v < min || v > max)
    fail(code, `${what} 必须是 [${min}, ${max}] 内的整数，收到 ${JSON.stringify(v)}`);
  return v as number;
}

function cell(v: unknown, grid: [number, number], what: string): Cell {
  if (!Array.isArray(v) || v.length !== 2) fail('INVALID_CELL', `${what} 不是 [i, j]`);
  const a = v as unknown[];
  const i = int(a[0], 'INVALID_CELL', `${what}.i`, 0, grid[0] - 1);
  const j = int(a[1], 'INVALID_CELL', `${what}.j`, 0, grid[1] - 1);
  return [i, j];
}

function mask(v: unknown, grid: [number, number], what: string): string[] {
  if (!Array.isArray(v) || v.length !== grid[1])
    fail('INVALID_MASK', `${what} 应有 ${grid[1]} 行，收到 ${Array.isArray(v) ? v.length : typeof v}`);
  return (v as unknown[]).map((row, j) => {
    if (typeof row !== 'string' || row.length !== grid[0])
      fail('INVALID_MASK', `${what}[${j}] 应是 ${grid[0]} 个字符的字符串`);
    if (!/^[01]*$/.test(row as string)) fail('INVALID_MASK', `${what}[${j}] 只能含 0 与 1`);
    return row as string;
  });
}

function bed(v: unknown, grid: [number, number], what: string): Bed {
  const o = v as Record<string, unknown>;
  if (!o || typeof o.id !== 'string') fail('INVALID_BED', `${what}.id 缺失`);
  if (!Array.isArray(o.cells) || o.cells.length !== 3)
    fail('INVALID_BED', `${what}.cells 必须恰好 3 格`);
  return { id: o.id as string, cells: (o.cells as unknown[]).map((c, k) => cell(c, grid, `${what}.cells[${k}]`)) };
}

/**
 * 从 JSON 解析出 Blueprint。r1 蓝图（只有浮点 cell_m / play_area_m、没有 *_mm）会被
 * `MISSING_MM` 拒绝——r2 起以毫米整数为权威，见 types.ts 的说明。
 */
export function parseBlueprint(raw: unknown): Blueprint {
  const d = raw as Record<string, unknown>;
  if (!d || typeof d !== 'object') fail('INVALID_SHAPE', '蓝图不是对象');

  if (typeof d.layout_patch_id !== 'string' || !ID_RE.test(d.layout_patch_id))
    fail('INVALID_ID', `layout_patch_id 必须匹配 ${ID_RE}，收到 ${JSON.stringify(d.layout_patch_id)}`);

  const format = int(d.format, 'INVALID_NUMBER', 'format', 1, 1000);
  const revision = int(d.revision, 'INVALID_NUMBER', 'revision', 1, 100_000);
  if (!Array.isArray(d.grid) || d.grid.length !== 2) fail('INVALID_NUMBER', 'grid 不是 [x, y]');
  const gx = int((d.grid as unknown[])[0], 'INVALID_NUMBER', 'grid.x', 1, 4096);
  const gy = int((d.grid as unknown[])[1], 'INVALID_NUMBER', 'grid.y', 1, 4096);
  const grid: [number, number] = [gx, gy];

  if (d.cell_mm === undefined || d.play_area_mm === undefined)
    fail('MISSING_MM', 'r2 起必须提供整数毫米字段 cell_mm 与 play_area_mm');
  const cell_mm = int(d.cell_mm, 'INVALID_NUMBER', 'cell_mm', MM_MIN, MM_MAX);
  const play_area_mm = int(d.play_area_mm, 'INVALID_NUMBER', 'play_area_mm', MM_MIN, MM_MAX);

  const masks: Masks = {
    visual: mask((d.masks as Record<string, unknown>)?.visual, grid, 'masks.visual'),
    walkable: mask((d.masks as Record<string, unknown>)?.walkable, grid, 'masks.walkable'),
    buildable: mask((d.masks as Record<string, unknown>)?.buildable, grid, 'masks.buildable'),
    cultivable: mask((d.masks as Record<string, unknown>)?.cultivable, grid, 'masks.cultivable'),
  };

  const a = d.anchors as Record<string, unknown>;
  if (!a) fail('INVALID_SHAPE', 'anchors 缺失');
  if (!Array.isArray(a.beds) || a.beds.length !== 3) fail('INVALID_BED', 'anchors.beds 必须恰好 3 条');
  const anchors: Anchors = {
    spawn: cell(a.spawn, grid, 'anchors.spawn'),
    house: cell(a.house, grid, 'anchors.house'),
    storage: cell(a.storage, grid, 'anchors.storage'),
    well: cell(a.well, grid, 'anchors.well'),
    exit: cell(a.exit, grid, 'anchors.exit'),
    beds: (a.beds as unknown[]).map((b, k) => bed(b, grid, `anchors.beds[${k}]`)),
    reserved_bed: bed(a.reserved_bed, grid, 'anchors.reserved_bed'),
  };

  return {
    format,
    layout_patch_id: d.layout_patch_id as string,
    revision,
    region_id: String(d.region_id ?? ''),
    name: String(d.name ?? ''),
    checksum: String(d.checksum ?? ''),
    source: (d.source as Record<string, unknown>) ?? {},
    cell_mm,
    play_area_mm,
    cell_m: cell_mm / 1000,
    play_area_m: play_area_mm / 1000,
    grid,
    masks,
    paths: (d.paths as Blueprint['paths']) ?? [],
    blocks: (d.blocks as Blueprint['blocks']) ?? [],
    anchors,
    overlay_wgs84: (d.overlay_wgs84 as Blueprint['overlay_wgs84']) ?? { center: [0, 0], paths: [], blocks: [] },
    report: d.report as Blueprint['report'],
  };
}
