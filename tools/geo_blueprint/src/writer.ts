/** 输出：farm_blueprint.json / map_overlay.geojson / preview.png / report.json / regions.json。 */
import { createHash } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { PNG } from 'pngjs';
import type { Region } from './config.js';
import type { Blueprint } from './types.js';

type RGB = [number, number, number];
const COLORS: Record<string, RGB> = {
  ground: [222, 226, 214], path: [232, 214, 172], block: [160, 205, 160], buildable: [140, 190, 140],
  bed: [150, 105, 70], reserved: [200, 170, 140], spawn: [52, 211, 153], house: [60, 90, 200],
  storage: [120, 120, 120], well: [60, 160, 220], exit: [220, 80, 80],
};

export function canonical(bp: Blueprint): string {
  const m = bp.masks, a = bp.anchors;
  const beds = a.beds.map(b => b.cells.map(c => `${c[0]},${c[1]}`).join(',')).join('/');
  const anchors = `spawn:${a.spawn[0]},${a.spawn[1]};house:${a.house[0]},${a.house[1]};` +
    `storage:${a.storage[0]},${a.storage[1]};well:${a.well[0]},${a.well[1]};exit:${a.exit[0]},${a.exit[1]};beds:${beds}`;
  return [bp.layout_patch_id, String(bp.revision), m.walkable.join(''), m.cultivable.join(''),
    m.buildable.join(''), m.visual.join(''), anchors].join('|');
}

export function checksum(bp: Blueprint): string {
  return createHash('sha256').update(canonical(bp), 'utf8').digest('hex');
}

export function renderPreview(bp: Blueprint, px = 8): Buffer {
  const g = bp.grid[0];
  const png = new PNG({ width: g * px, height: g * px });
  const fill = (x0: number, y0: number, w: number, h: number, [r, gg, b]: RGB) => {
    for (let y = y0; y < y0 + h; y++) for (let x = x0; x < x0 + w; x++) {
      const o = (y * png.width + x) * 4; png.data[o] = r; png.data[o + 1] = gg; png.data[o + 2] = b; png.data[o + 3] = 255;
    }
  };
  fill(0, 0, png.width, png.height, COLORS.ground);
  const cell = (i: number, j: number, c: RGB) => fill(i * px, (g - 1 - j) * px, px, px, c); // 图像 y 向下，蓝图 y 向北 → 翻转
  const m = bp.masks;
  for (let j = 0; j < g; j++) for (let i = 0; i < g; i++) {
    if (m.walkable[j][i] === '1') cell(i, j, m.buildable[j][i] === '0' ? COLORS.path : COLORS.block);
    if (m.buildable[j][i] === '1') cell(i, j, COLORS.buildable);
    if (m.cultivable[j][i] === '1') cell(i, j, COLORS.bed);
  }
  for (const [i, j] of bp.anchors.reserved_bed.cells) cell(i, j, COLORS.reserved);
  for (const name of ['house', 'storage', 'well', 'exit', 'spawn'] as const) cell(bp.anchors[name][0], bp.anchors[name][1], COLORS[name]);
  return PNG.sync.write(png);
}

export function writeOutputs(bp: Blueprint, overlayGeojson: unknown, outDir: string): void {
  mkdirSync(outDir, { recursive: true });
  const { report, ...rest } = bp;
  const out: Blueprint = { ...rest, checksum: checksum(bp) };
  writeFileSync(path.join(outDir, 'farm_blueprint.json'), JSON.stringify(out, null, 1));
  writeFileSync(path.join(outDir, 'map_overlay.geojson'), JSON.stringify(overlayGeojson));
  writeFileSync(path.join(outDir, 'preview.png'), renderPreview(out));
  if (report) writeFileSync(path.join(outDir, 'report.json'), JSON.stringify(report, null, 1));
}

export interface ShippedCandidate { layout_patch_id: string; revision: number; name: string }

export function writeRegions(regions: Region[], byRegion: Record<string, ShippedCandidate[]>, file: string): void {
  const out = {
    format: 1,
    regions: regions.map(r => ({
      id: r.id, name: r.name, timezone: r.timezone, center: r.center, street_zoom: r.street_zoom, pitch: r.pitch,
      candidates: (byRegion[r.id] ?? []).map(c => ({ layout_patch_id: c.layout_patch_id, revision: c.revision, name: c.name })),
    })),
  };
  mkdirSync(path.dirname(file), { recursive: true });
  writeFileSync(file, JSON.stringify(out, null, 1));
}
