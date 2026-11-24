import { describe, expect, it } from 'vitest';
import { resolveParams, CLIENT_MAX_AXIS, CLIENT_MAX_CELLS } from '../src/config.js';
import { encodeRuns, extensionLevels, generateFarm, LowIouError, type FarmInput } from '../src/farm.js';
import { insideRings, signedArea, unrotate, type Polygon } from '../src/geo.js';
import { DIRS, RING_OFFSETS } from '../src/layout.js';
import { CURRENT_CLIENT, decodeFarm, RELAXED } from '../src/validate.js';

const rect = (x: number, y: number, w: number, h: number): Polygon => [[[x, y], [x + w, y], [x + w, y + h], [x, y + h], [x, y]]];
const params = resolveParams();

function input(buildings: Polygon[], extra: Partial<FarmInput> = {}): FarmInput {
  return {
    dataset_version: 'sf-dynamic-farm-test-r5', parcel_id: '1234001', aliases: ['1234001'], name: '1 TEST ST', address: '1 TEST ST',
    buildings, building_source: 'test', parcel_area_m2: 500, front: () => DIRS.south, source_geometry_hash: 'f'.repeat(64), ...extra,
  };
}

function decoded(farm: Record<string, unknown>) {
  const result = decodeFarm(JSON.parse(JSON.stringify(farm)), RELAXED);
  if (!result.ok) throw new Error(result.error);
  return result;
}

describe('generateFarm', () => {
  it('rasterizes an L-shaped house at a fixed 0.25 m² per cell and passes the client checks', () => {
    const l: Polygon = [[[500000, 4180000], [500016, 4180000], [500016, 4180006], [500006, 4180006], [500006, 4180012], [500000, 4180012], [500000, 4180000]]];
    const r = generateFarm(input([l]), params);
    const d = decoded(r.farm);
    expect(r.cell_m).toBe(0.5);
    expect(d.counts.core).toBe(132 / 0.25);
    expect(r.iou).toBeGreaterThan(0.999);
    expect((r.farm.stats as any).core_iou).toBe(1);
    // The notch stays out of the core: the bounding box (16 × 12 m) would be 768 cells.
    expect(d.counts.core).toBeLessThan(768);
    expect((r.farm.boundaries as any).core[0].outer).toHaveLength(7);
    expect(r.too_small).toBe(false);
  });

  it('cell count grows with area', () => {
    const counts = [[8, 10], [12, 14], [20, 22]].map(([w, h]) => decoded(generateFarm(input([rect(0, 0, w, h)]), params).farm).counts.core);
    expect(counts).toEqual([320, 672, 1760]);
  });

  it('joins detached buildings with a protected path', () => {
    const r = generateFarm(input([rect(0, 0, 12, 10), rect(22, 0, 5, 5)]), params);
    decoded(r.farm);
    expect(r.flags).toContain('buildings_joined_by_path');
    expect((r.farm.stats as any).core_components).toBe(2);
  });

  it('puts the spawn and the entry path on the main building, not a garage in front of it', () => {
    const r = generateFarm(input([rect(0, 0, 14, 10), rect(4, -9, 4, 4)]), params);
    const d = decoded(r.farm);
    const parts = (r.farm.boundaries as any).core as { outer: [number, number][] }[];
    const home = parts.find(p => insideRings([p.outer], d.spawn[0] + 0.5, d.spawn[1] + 0.5))!;
    expect(Math.abs(signedArea(home.outer))).toBe(Math.max(...parts.map(p => Math.abs(signedArea(p.outer)))));
  });

  it('keeps a courtyard as a hole in the core', () => {
    const r = generateFarm(input([[...rect(0, 0, 24, 24), rect(6, 6, 12, 12)[0]]]), params);
    decoded(r.farm);
    expect((r.farm.boundaries as any).core[0].holes.length).toBe(1);
    expect(r.layout.counts.core).toBe((576 - 144) / 0.25);
  });

  it('scales the cell up for large buildings so the core stays under the cap', () => {
    const r = generateFarm(input([rect(0, 0, 80, 60)]), params);
    const d = decoded(r.farm);
    expect(d.counts.core).toBeLessThanOrEqual(params.core_cell_cap);
    expect(d.counts.core).toBeGreaterThan(params.core_cell_cap * 0.9);
    expect(d.cells.size).toBeLessThanOrEqual(CLIENT_MAX_CELLS);
    expect(r.cell_m).toBeGreaterThan(0.5);
    expect(r.flags).toContain('cell_scaled_for_core_cap');
  });

  it('a long thin building respects the axis and total budgets', () => {
    const r = generateFarm(input([rect(0, 0, 600, 3)]), params);
    const d = decoded(r.farm);
    expect(d.width).toBeLessThanOrEqual(CLIENT_MAX_AXIS);
    expect(d.height).toBeLessThanOrEqual(CLIENT_MAX_AXIS);
    expect(d.cells.size).toBeLessThanOrEqual(params.total_cell_cap);
  });

  it('flags parcels below the minimum but still writes a valid farm', () => {
    const r = generateFarm(input([rect(0, 0, 6, 6)]), params);
    decoded(r.farm);
    expect(r.layout.counts.core).toBe(144);
    expect(r.too_small).toBe(true);
    expect((r.farm.stats as any).too_small).toBe(true);
    const lower = generateFarm(input([rect(0, 0, 6, 6)]), resolveParams({ min_core_cells: 100 }));
    expect(lower.too_small).toBe(false);
  });

  it('configurable cell size and cap', () => {
    const coarse = generateFarm(input([rect(0, 0, 20, 20)]), resolveParams({ cell_m: 1 }));
    expect(coarse.layout.counts.core).toBe(400);
    const capped = generateFarm(input([rect(0, 0, 20, 20)]), resolveParams({ core_cell_cap: 1000, min_core_cells: 100 }));
    expect(capped.layout.counts.core).toBeLessThanOrEqual(1000);
  });

  it('builds every front direction and rotated footprints', () => {
    const poly: Polygon = [rect(0, 0, 14, 9)[0].map(p => unrotate(p as [number, number], 21))];
    for (const front of Object.values(DIRS)) {
      const r = generateFarm(input([poly], { front: () => front }), params);
      const d = decoded(r.farm);
      expect((r.farm.source_transform as any).rotation_deg).toBeCloseTo(21, 1);
      expect(d.counts.core).toBe(504);
      // The entry sits on the requested side of the core.
      const [ex, ey] = d.entry;
      const [sx, sy] = d.spawn;
      expect(Math.sign((ex - sx) * front.dx + (ey - sy) * front.dy)).toBe(1);
    }
  });

  it('protects the 2-cell ring, the spawn and the entry the way the client requires', () => {
    const r = generateFarm(input([rect(0, 0, 10, 10), rect(10, 0, 5, 20)]), params);
    const d = decoded(r.farm);
    for (const [key, cell] of d.cells) {
      if (cell.zone !== 'core') continue;
      const [x, y] = key.split(',').map(Number);
      for (const [dx, dy] of RING_OFFSETS) {
        const near = `${x + dx},${y + dy}`;
        if (d.cells.has(near)) expect(d.protected.has(near)).toBe(true);
      }
    }
    expect(d.cells.get(d.spawn.join(','))!.zone).toBe('core');
    expect(d.cells.get(d.entry.join(','))!.zone).toBe('extension');
  });

  it('is deterministic for the same input', () => {
    const a = JSON.stringify(generateFarm(input([rect(3, 4, 13, 9), rect(20, 4, 4, 4)]), params).farm);
    const b = JSON.stringify(generateFarm(input([rect(3, 4, 13, 9), rect(20, 4, 4, 4)]), params).farm);
    expect(a).toBe(b);
    const other = JSON.stringify(generateFarm(input([rect(3, 4, 13, 9), rect(20, 4, 4, 4)], { source_geometry_hash: 'e'.repeat(64) }), params).farm);
    expect(other).not.toBe(a); // the seed (extension outline) follows the geometry hash
  });

  it('the current client still rejects counts outside 760–840; C-43 lifts that', () => {
    const r = generateFarm(input([rect(0, 0, 10, 10)]), params);
    expect(decodeFarm(JSON.parse(JSON.stringify(r.farm)), CURRENT_CLIENT)).toEqual({ ok: false, error: 'Dynamic farm core cell count is invalid.' });
    expect(decodeFarm(JSON.parse(JSON.stringify(r.farm)), RELAXED).ok).toBe(true);
  });
});

describe('fidelity and budget', () => {
  it('reports the exact IoU of the written core, which an independent recount reproduces', () => {
    // 7.3 × 5.1 m turned 12° against an unrotated grid: no sub-cell offset lines its edges up.
    const poly: Polygon = [rect(500000, 4180000, 7.3, 5.1)[0].map(p => unrotate(p as [number, number], 12))];
    const r = generateFarm(input([poly], {}), resolveParams({ align_to_building: false }));
    expect(r.iou).toBeLessThan(0.99);
    // Recount by 64 × 64 centre samples per cell (no clipping), grid unrotated so u, v are metres.
    const f = r.core.frame;
    const n = 64;
    let inter = 0;
    let area = 0;
    for (let y = 0; y < f.height * n; y++) for (let x = 0; x < f.width * n; x++) {
      const u = f.u0 + ((x + 0.5) / n) * f.cell_m;
      const v = f.v0 + ((y + 0.5) / n) * f.cell_m;
      if (!insideRings(poly, u, v)) continue;
      area++;
      const gx = Math.floor(x / n) - r.layout.offset[0];
      const gy = Math.floor(y / n) - r.layout.offset[1];
      if (gx >= 0 && gy >= 0 && gx < r.layout.width && gy < r.layout.height && r.layout.zone[gy * r.layout.width + gx] === 1) inter++;
    }
    const cells = r.layout.counts.core * n * n;
    expect(inter / (cells + area - inter)).toBeCloseTo(r.iou, 3);
  });

  it('excludes a footprint too thin for the cell (low_iou) instead of writing a misleading farm', () => {
    // A 0.6 m wide wall ring around a 20 m courtyard at 0.5 m cells.
    const ring: Polygon = [rect(0, 0, 21.2, 21.2)[0], rect(0.6, 0.6, 20, 20)[0]];
    expect(() => generateFarm(input([ring]), params)).toThrow(LowIouError);
    // A lower line keeps it.
    expect(generateFarm(input([ring]), resolveParams({ min_core_iou: 0.3 })).iou).toBeLessThan(params.min_core_iou);
  });

  it('narrows the extension before growing the cell for scattered buildings', () => {
    const scattered = [0, 1, 2, 3, 4].flatMap(i => [0, 1].map(j => rect(i * 30, j * 30, 8, 6)));
    const r = generateFarm(input(scattered), params);
    decoded(r.farm);
    expect(r.flags).toContain('extension_narrowed');
    expect(r.flags).not.toContain('cell_scaled_for_total_cap');
    expect(r.cell_m).toBe(0.5);
    expect((r.farm.stats as any).extension_cells[0]).toBeLessThan(params.extension_cells);
    expect(r.layout.counts.total).toBeLessThanOrEqual(params.total_cell_cap);
    // Without narrowing the same farm needs bigger cells.
    const wide = generateFarm(input(scattered), resolveParams({ min_extension_cells: params.extension_cells }));
    expect(wide.flags).toContain('cell_scaled_for_total_cap');
    expect(wide.cell_m).toBeGreaterThan(0.5);
    expect(wide.iou).toBeLessThan(r.iou);
  });

  it('a farm that fits keeps the configured extension', () => {
    const r = generateFarm(input([rect(0, 0, 12, 10)]), params);
    expect((r.farm.stats as any).extension_cells).toEqual([params.extension_cells, params.extension_jitter]);
    expect(r.flags).not.toContain('extension_narrowed');
    expect(extensionLevels(params).map(l => [l.extension_cells, l.extension_jitter])).toEqual([[5, 2], [4, 2], [3, 2], [2, 1]]);
  });
});

describe('encodeRuns', () => {
  it('splits rows by value', () => {
    const v = [0, 1, 1, 2, null, 2, 2, null];
    expect(encodeRuns(4, 2, i => v[i], true)).toEqual([[0, 0, 1, 0], [0, 1, 2, 1], [0, 3, 1, 2], [1, 1, 2, 2]]);
    expect(encodeRuns(4, 2, i => (v[i] === null ? null : 1), false)).toEqual([[0, 0, 4], [1, 1, 2]]);
  });
});

describe('resolveParams', () => {
  it('rejects values the client cannot take', () => {
    expect(() => resolveParams({ total_cell_cap: 9000 })).toThrow();
    expect(() => resolveParams({ core_cell_cap: 8192 })).toThrow();
    expect(() => resolveParams({ cell_m: 0 })).toThrow();
    expect(() => resolveParams({ nope: 1 } as never)).toThrow();
    expect(() => resolveParams({ min_core_iou: 1 })).toThrow();
    expect(() => resolveParams({ min_extension_cells: 0 })).toThrow();
    expect(() => resolveParams({ min_extension_cells: 6 })).toThrow();
  });
});
