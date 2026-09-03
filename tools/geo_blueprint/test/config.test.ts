import { describe, it, expect } from 'vitest';
import * as config from '../src/config.js';

describe('config', () => {
  it('loads six candidates across two regions', () => {
    const c = config.loadCandidates();
    expect(c).toHaveLength(6);
    expect(new Set(c.map(x => x.regionId))).toEqual(new Set(['shanghai', 'los_angeles']));
    expect(c.every(x => x.radiusM > 0)).toBe(true);
  });
  it('constants', () => {
    expect(config.PLAY_AREA_M).toBe(64); expect(config.GRID).toBe(64);
    expect(config.PATH_WIDTH_M).toBe(3); expect(config.WALK_SPEED).toBe(2.5);
  });
});
