import { readFileSync } from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { DEFAULT_CONTENT_DIR, loadContent } from '../../src/domain/content.js';
import { plotFor } from '../../src/http/app.js';

// The exported realtime map must follow the same free-farm layout as gameplay.
// A stale 20x20 map otherwise teleports players away from their home on join.
describe('exported free-farm navigation', () => {
  it('matches the cell size, spawn and every walkable cell for all geographical farm variants', () => {
    const plot = plotFor(loadContent(DEFAULT_CONTENT_DIR));
    const maps = JSON.parse(readFileSync(path.join(DEFAULT_CONTENT_DIR, 'online_navigation.json'), 'utf8')).maps;
    const regions = JSON.parse(readFileSync(path.join(DEFAULT_CONTENT_DIR, 'regions.json'), 'utf8')).regions;
    for (const region of regions) for (const candidate of region.candidates) {
      const nav = maps[`farm:${candidate.layout_patch_id}:${candidate.revision}`];
      const unit = plot.cellMm / 1000;
      expect(nav.cell).toBe(unit);
      expect(nav.spawn).toEqual([(plot.anchors.spawn[0] + .5) * unit, -(plot.anchors.spawn[1] + .5) * unit]);
      expect(nav.rows).toHaveLength(plot.gy);
      for (let j = 0; j < plot.gy; j++)
        expect(nav.rows[j]).toBe(Array.from(plot.walk.slice(j * plot.gx, (j + 1) * plot.gx)).join(''));
    }
  });
});
