import { describe, expect, it } from 'vitest';
import { gridTransform, maskTopology, multiArea, runsIntersectionArea, topology, unionAll } from '../src/geometry.js';

const sq = (x0: number, y0: number, x1: number, y1: number): [number, number][][] => [[[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]]];

describe('mask topology', () => {
  const mask = (rows: string[]) => ({ m: Uint8Array.from(rows.join('').split('').map(c => (c === '#' ? 1 : 0))), w: rows[0].length, h: rows.length });

  it('counts a ring as one component with one hole', () => {
    const { m, w, h } = mask(['###', '#.#', '###']);
    expect(maskTopology(m, w, h)).toEqual({ components: 1, holes: 1 });
  });

  it('uses 4-connectivity for cells: diagonal neighbours are separate components', () => {
    const { m, w, h } = mask(['#.', '.#']);
    expect(maskTopology(m, w, h)).toEqual({ components: 2, holes: 0 });
  });

  it('does not count a notch open to the outside as a hole', () => {
    const { m, w, h } = mask(['###', '#..', '###']);
    expect(maskTopology(m, w, h)).toEqual({ components: 1, holes: 0 });
  });

  it('counts two separate blocks and the background reaching the border', () => {
    const { m, w, h } = mask(['##..##', '##..##']);
    expect(maskTopology(m, w, h)).toEqual({ components: 2, holes: 0 });
  });
});

describe('polygon helpers', () => {
  it('unions overlapping footprints instead of adding their areas', () => {
    const u = unionAll([sq(0, 0, 2, 2), sq(1, 0, 3, 2)]);
    expect(multiArea(u)).toBeCloseTo(6, 12);
    expect(topology(u)).toEqual({ components: 1, holes: 0 });
  });

  it('keeps holes of a courtyard footprint', () => {
    const u = unionAll([[...sq(0, 0, 4, 4), sq(1, 1, 3, 3)[0].slice().reverse() as [number, number][]]]);
    expect(multiArea(u)).toBeCloseTo(12, 12);
    expect(topology(u)).toEqual({ components: 1, holes: 1 });
  });

  it('intersects a shape exactly with disjoint cell runs', () => {
    const shape = unionAll([sq(0.5, 0.5, 2.5, 1.5)]);
    // Row 0 run x 0..3, row 1 run x 1..2.
    expect(runsIntersectionArea(shape, [[0, 0, 3], [1, 1, 1]])).toBeCloseTo(1 + 0.5, 12);
  });

  it('maps UTM to grid units with the schema rotation convention', () => {
    const t = gridTransform([100, 200], 90, 0.5);
    // rotate(p, deg) = [x cos + y sin, -x sin + y cos]: (1, 0) -> (0, -1), scaled by 1 / 0.5.
    const [x, y] = t([101, 200]);
    expect(x).toBeCloseTo(0, 12);
    expect(y).toBeCloseTo(-2, 12);
  });
});
