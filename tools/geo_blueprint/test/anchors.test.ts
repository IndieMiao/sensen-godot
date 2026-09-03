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
const bpOf = (m: Blueprint['masks'], a: Blueprint['anchors'], nblocks = 4): Blueprint => ({
  format: 1, layout_patch_id: 't', revision: 1, region_id: 'r', name: 't', checksum: '', source: {},
  play_area_m: 64, cell_m: 1, grid: [64, 64], masks: m, paths: [],
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
  it('place gives nine cultivable cells and reachable anchors', () => {
    const { m, pcs } = scene();
    const a = anchors.place(m, pcs, 64);
    expect(masks.count(m.cultivable)).toBe(9);
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
    expect(r.far_bed_s).toBeGreaterThan(0); expect(r.far_bed_s).toBeLessThanOrEqual(config.MAX_FAR_BED_S);
    expect(r.tour_s).toBeGreaterThan(9 * config.ACTION_S);
  });
  it('validate flags unreachable house', () => {
    const { m, pcs } = scene();
    const a = anchors.place(m, pcs, 64);
    a.house = [63, 63];
    expect(anchors.validate(bpOf(m, a)).errors.some(e => e.includes('house'))).toBe(true);
  });
});
