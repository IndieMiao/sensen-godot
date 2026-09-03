import { describe, it, expect, beforeAll } from 'vitest';
import type { LineString, Polygon } from 'geojson';
import * as masks from '../src/masks.js';
import * as geos from '../src/geos.js';

const line = (c: number[][]): LineString => ({ type: 'LineString', coordinates: c });
const box = (x0: number, y0: number, x1: number, y1: number): Polygon =>
  ({ type: 'Polygon', coordinates: [[[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]]] });

describe('masks', () => {
  beforeAll(geos.initGeos);
  it('shapes; walkable includes path and block; buildable eroded', () => {
    const m = masks.rasterize([line([[0, 32], [64, 32]])], [box(4, 4, 28, 28)], 64, 1, 3);
    expect(Object.keys(m).sort()).toEqual(['buildable', 'cultivable', 'visual', 'walkable']);
    expect(m.walkable).toHaveLength(64); expect(m.walkable.every(r => r.length === 64)).toBe(true);
    expect(m.walkable[32][10]).toBe('1');   // 路上（y=32 行）
    expect(m.walkable[10][10]).toBe('1');   // 区块内
    expect(m.walkable[50][50]).toBe('0');   // 空地
    expect(m.buildable[10][10]).toBe('1'); expect(m.buildable[4][4]).toBe('0');
    expect(masks.count(m.cultivable)).toBe(0);
  });
  it('path corridor is three cells wide', () => {
    const pc = masks.pathCells([line([[0, 32.5], [64, 32.5]])], 64, 1, 3);
    const col = [...pc].filter(k => k % 64 === 20).map(k => Math.floor(k / 64)).sort((a, b) => a - b);
    expect(col).toEqual([31, 32, 33]);
  });
  it('count', () => { expect(masks.count(['0110', '0000'])).toBe(2); });
  it('buildable excludes path cells inside block', () => {
    const m = masks.rasterize([line([[0, 16], [64, 16]])], [box(4, 4, 28, 28)], 64, 1, 3);
    expect(m.walkable[16][10]).toBe('1');   // 路穿区块，可行走
    expect(m.buildable[16][10]).toBe('0');  // 路上不可建造
    expect(m.buildable[10][10]).toBe('1');  // 区块内非路可建造
  });
});
