import { describe, it, expect } from 'vitest';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import * as config from '../src/config.js';
import * as writer from '../src/writer.js';
import * as anchors from '../src/anchors.js';
import type { Blueprint } from '../src/types.js';

describe('shipped blueprints', () => {
  it('regions.json points to existing, valid, checksum-matching blueprints', () => {
    expect(existsSync(config.REGIONS_OUT)).toBe(true);
    const data = JSON.parse(readFileSync(config.REGIONS_OUT, 'utf8'));
    expect(new Set(data.regions.map((r: { id: string }) => r.id))).toEqual(new Set(['shanghai', 'los_angeles']));
    for (const r of data.regions) {
      expect(r.candidates).toHaveLength(3);
      for (const c of r.candidates) {
        const file = path.join(config.BLUEPRINTS_DIR, c.layout_patch_id, `r${c.revision}`, 'farm_blueprint.json');
        const bp = JSON.parse(readFileSync(file, 'utf8')) as Blueprint;
        expect(bp.checksum).toBe(writer.checksum(bp));
        expect(anchors.validate(bp).errors).toEqual([]);
        expect(c.lat).toBeUndefined();
      }
    }
  });
});
