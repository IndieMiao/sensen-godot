import { describe, it, expect, beforeAll } from 'vitest';
import type { LineString, Polygon } from 'geojson';
import * as masks from '../src/masks.js';
import * as anchors from '../src/anchors.js';
import * as config from '../src/config.js';
import * as geos from '../src/geos.js';
import type { Blueprint } from '../src/types.js';

const line = (c: number[][]): LineString => ({ type: 'LineString', coordinates: c });
const box = (x0: number, y0: number, x1: number, y1: number): Polygon =>
  ({ type: 'Polygon', coordinates: [[[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]]] });

function scene() {
  const paths = [line([[0, 32.5], [64, 32.5]]), line([[32.5, 0], [32.5, 64]])];
  // 区块必须贴到步道走廊（列/行 31-33）上：真实数据里 polygonize 出的面直接抵着路中心线；
  // 盒子若停在 30 就会留下 1 格“护城河”，四邻接 BFS 下区块与路不连通（2026-09-03 执行时发现并修正）。
  const blocks = [box(2, 2, 31, 31), box(34, 2, 62, 31), box(2, 34, 31, 62), box(34, 34, 62, 62)];
  const m = masks.rasterize(paths, blocks, 64, 1, 3);
  const pcs = masks.pathCells(paths, 64, 1, 3);
  return { m, pcs };
}
/**
 * 手搭 masks（不走 rasterize）：第 j 行右端两格 (62,63) + 第 j+1 行左端两格 (0,1) 都可建造。
 * cellKey(i,j,grid)=j*grid+i 在无上界检查时，cellKey(64,j)===cellKey(0,j+1)，于是 i=62 会被
 * 误判成一段贯穿两行的合法连续段，产出 x=64 的床格。另加 4 段规规矩矩的合法连续段（够
 * INITIAL_BEDS+1=4 个床位，不依赖越行段），以及两个孤立空地供 house/storage 落位，
 * 避免因空地不足而在越行 bug 触发前先被别的异常挡住。
 */
function wrapScene() {
  const G = config.GRID;
  const zero = '0'.repeat(G);
  const row = (ones: number[]): string => { const cs = Array(G).fill('0'); for (const i of ones) cs[i] = '1'; return cs.join(''); };
  const walkable = Array.from({ length: G }, () => '1'.repeat(G)); // 全通：这个测试只考察床位扫描，不考察可达性
  const buildable = Array.from({ length: G }, () => zero);
  buildable[0] = row([0, 1, 2]);
  buildable[2] = row([0, 1, 2]);
  buildable[4] = row([0, 1, 2]);
  buildable[6] = row([0, 1, 2]);
  buildable[10] = row([62, 63]);  // 行 j 右端起跑的连续段
  buildable[11] = row([0, 1]);    // 无守卫时会被 cellKey 别名判成第 10 行的延续
  buildable[20] = row([32, 33]);  // 供 house/storage 挑选的独立空地
  const m: Blueprint['masks'] = { visual: walkable, walkable, buildable, cultivable: Array.from({ length: G }, () => zero) };
  const pcs = new Set([masks.cellKey(32, 32, G)]);
  return { m, pcs, G };
}

const bpOf = (m: Blueprint['masks'], a: Blueprint['anchors'], nblocks = 4): Blueprint => ({
  format: 1, layout_patch_id: 't', revision: 1, region_id: 'r', name: 't', checksum: '', source: {},
  play_area_m: 64, cell_m: 1, play_area_mm: 64000, cell_mm: 1000, grid: [64, 64], masks: m, paths: [],
  blocks: Array.from({ length: nblocks }, (_, i) => ({ id: `b${i}`, polygon: [], neighbors: [] })),
  anchors: a, overlay_wgs84: { center: [0, 0], paths: [], blocks: [] },
});

describe('anchors', () => {
  beforeAll(geos.initGeos);
  it('bfs is four-neighbour', () => {
    const d = anchors.bfs(['111', '101', '111'], [0, 0]);
    expect(d.get(masks.cellKey(2, 2, 3))).toBe(4);
    expect(d.has(masks.cellKey(1, 1, 3))).toBe(false);
  });
  it('place gives twelve cultivable cells (three beds + reserved) and reachable anchors', () => {
    const { m, pcs } = scene();
    const a = anchors.place(m, pcs, 64);
    // 12 而不是 9：预留畦也记进 cultivable，它买下即为已翻土的田（2026-09-04 决策⑥）。
    expect(masks.count(m.cultivable)).toBe(12);
    expect(a.beds).toHaveLength(3); expect(a.beds.every(b => b.cells.length === 3)).toBe(true);
    expect(a.reserved_bed.id).toBe('bed3');
    expect(pcs.has(masks.cellKey(a.spawn[0], a.spawn[1], 64))).toBe(true);
    const d = anchors.bfs(m.walkable, a.spawn);
    for (const k of ['house', 'storage', 'well', 'exit'] as const) expect(d.has(masks.cellKey(a[k][0], a[k][1], 64))).toBe(true);
    expect([0, 63].includes(a.exit[0]) || [0, 63].includes(a.exit[1])).toBe(true);
  });
  it('validate reports times without errors', () => {
    const { m, pcs } = scene();
    const a = anchors.place(m, pcs, 64);
    const r = anchors.validate(bpOf(m, a));
    expect(r.errors).toEqual([]);
    expect(r.far_bed_9_s).toBeGreaterThan(0); expect(r.far_bed_9_s).toBeLessThanOrEqual(config.MAX_FAR_BED_S);
    expect(r.tour_s).toBeGreaterThan(9 * config.ACTION_S);
  });
  it('validate flags unreachable house', () => {
    const { m, pcs } = scene();
    const a = anchors.place(m, pcs, 64);
    a.house = [63, 63];
    expect(anchors.validate(bpOf(m, a)).errors.some(e => e.includes('house'))).toBe(true);
  });
  it('bed-run scan never wraps a row-edge run into the next mask row', () => {
    const { m, pcs, G } = wrapScene();
    const a = anchors.place(m, pcs, G);
    const allCells = [...a.beds.flatMap(b => b.cells), ...a.reserved_bed.cells];
    for (const [x] of allCells) expect(x).toBeLessThan(G);
    for (const r of m.cultivable) expect(r.length).toBe(G);
  });
});
