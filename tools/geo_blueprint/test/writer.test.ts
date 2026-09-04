import { describe, it, expect } from 'vitest';
import { createHash } from 'node:crypto';
import { existsSync, mkdtempSync, readFileSync } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import * as writer from '../src/writer.js';
import type { Blueprint } from '../src/types.js';

const bp = (): Blueprint => ({
  format: 1, layout_patch_id: 't', revision: 1, region_id: 'r', name: 'T', checksum: '', source: {},
  play_area_m: 2, cell_m: 1, play_area_mm: 2000, cell_mm: 1000, grid: [2, 2],
  masks: { visual: ['11', '11'], walkable: ['11', '10'], buildable: ['00', '01'], cultivable: ['00', '00'] },
  paths: [], blocks: [],
  anchors: { spawn: [0, 0], house: [1, 1], storage: [1, 1], well: [0, 0], exit: [1, 0],
    beds: [{ id: 'bed0', cells: [[1, 1], [1, 1], [1, 1]] }],
    reserved_bed: { id: 'bed3', cells: [[1, 1], [1, 1], [1, 1]] } },
  overlay_wgs84: { center: [0, 0], paths: [], blocks: [] },
});

describe('writer', () => {
  it('canonical exact string and sha256', () => {
    const c = writer.canonical(bp());
    // 逐字节钉住 canonical 文法（spec §5.1）。相对 r1 补了 format / revision / grid /
    // cell_mm / play_area_mm / reserved，尺寸用整数毫米——r1 的公式不覆盖这些字段，
    // 手改 grid 或 cell_m 都能通过校验（2026-09-04 决策①）。
    expect(c).toBe('t|1|1|2,2|1000|2000|1110|0000|0001|1111|spawn:0,0;house:1,1;storage:1,1;well:0,0;exit:1,0;beds:1,1,1,1,1,1;reserved:1,1,1,1,1,1');
    expect(writer.checksum(bp())).toBe(createHash('sha256').update(c).digest('hex'));
  });
  it('writeOutputs roundtrip', () => {
    const dir = mkdtempSync(path.join(os.tmpdir(), 'bp-'));
    writer.writeOutputs(bp(), { type: 'FeatureCollection', features: [] }, dir);
    const loaded = JSON.parse(readFileSync(path.join(dir, 'farm_blueprint.json'), 'utf8'));
    expect(loaded.checksum).toBe(writer.checksum(bp()));
    expect(existsSync(path.join(dir, 'preview.png'))).toBe(true);
    expect(existsSync(path.join(dir, 'map_overlay.geojson'))).toBe(true);
  });
  it('writeRegions strips coordinates from candidates', () => {
    const dir = mkdtempSync(path.join(os.tmpdir(), 'rg-'));
    const file = path.join(dir, 'regions.json');
    // 输入候选带真实 lat/lng/radius_m（不同于 ShippedCandidate 声明的字段），故意越过类型做
    // naive-passthrough 探测：writeRegions 必须显式挑字段，否则精确拓扑可能反推出玩家选的小区。
    const candidateWithCoords = { layout_patch_id: 'sh_a', revision: 1, name: 'A', lat: 31.2, lng: 121.4, radius_m: 200 };
    writer.writeRegions(
      [{ id: 'shanghai', name: '上海', timezone: 'Asia/Shanghai', center: [31.2, 121.4], street_zoom: 16, pitch: 45, candidates: [] }],
      { shanghai: [candidateWithCoords] } as unknown as Record<string, writer.ShippedCandidate[]>, file);
    const data = JSON.parse(readFileSync(file, 'utf8'));
    expect(data.regions[0].candidates[0].layout_patch_id).toBe('sh_a');
    expect(data.regions[0].candidates[0].lat).toBeUndefined();
    expect(data.regions[0].candidates[0].lng).toBeUndefined();
    expect(data.regions[0].candidates[0].radius_m).toBeUndefined();
  });
});
