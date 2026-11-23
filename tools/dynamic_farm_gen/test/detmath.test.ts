import { describe, expect, it } from 'vitest';
import * as det from '../src/detmath.js';
import { toUtm } from '../src/geo.js';

const close = (a: number, b: number, rel = 4e-16) => Math.abs(a - b) <= rel * Math.max(1, Math.abs(b));

describe('detmath', () => {
  const grid = (from: number, to: number, n: number) => Array.from({ length: n + 1 }, (_, i) => from + ((to - from) * i) / n);
  it('sin, cos, tan agree with libm to a few ulp', () => {
    for (const x of grid(-20, 20, 4001)) {
      expect(close(det.sin(x), Math.sin(x)), `sin ${x}`).toBe(true);
      expect(close(det.cos(x), Math.cos(x)), `cos ${x}`).toBe(true);
    }
    for (const x of grid(-1.5, 1.5, 3001)) expect(close(det.tan(x), Math.tan(x), 1e-15), `tan ${x}`).toBe(true);
  });
  it('atan, atan2', () => {
    for (const x of grid(-50, 50, 5001)) expect(close(det.atan(x), Math.atan(x)), `atan ${x}`).toBe(true);
    for (const [y, x] of [[1, 1], [1, -1], [-1, -1], [-1, 1], [0, 1], [0, -1], [3, 0], [-3, 0], [0.2, 7], [-5, 0.1]]) {
      expect(close(det.atan2(y, x), Math.atan2(y, x)), `atan2 ${y},${x}`).toBe(true);
    }
  });
  it('exp, log and the hyperbolic functions', () => {
    for (const x of grid(-30, 30, 6001)) expect(close(det.exp(x), Math.exp(x)), `exp ${x}`).toBe(true);
    for (const x of [1e-300, 1e-9, 0.3, 0.999999, 1, 1.0000001, 2, 1e9, 1e300]) expect(close(det.log(x), Math.log(x)), `log ${x}`).toBe(true);
    for (const x of grid(-0.5, 0.5, 1001)) {
      expect(Math.abs(det.sinh(x) - Math.sinh(x)), `sinh ${x}`).toBeLessThan(3e-16);
      expect(close(det.cosh(x), Math.cosh(x)), `cosh ${x}`).toBe(true);
      expect(Math.abs(det.asinh(x) - Math.asinh(x)), `asinh ${x}`).toBeLessThan(3e-16);
      expect(Math.abs(det.atanh(x) - Math.atanh(x)), `atanh ${x}`).toBeLessThan(3e-16);
    }
  });
  it('toUtm output is pinned bit for bit (fails if any platform rounds differently)', () => {
    const bits = (v: number) => { const d = new DataView(new ArrayBuffer(8)); d.setFloat64(0, v); return d.getBigUint64(0).toString(16); };
    expect(toUtm(-122.470873757, 37.732717506).map(bits)).toEqual(PINNED);
  });
});

const PINNED = ['4120ae80483bf3dd', '414fdcd1f3348898'];
