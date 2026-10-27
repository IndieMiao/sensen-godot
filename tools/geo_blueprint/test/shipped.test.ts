import { describe, it, expect } from 'vitest';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import * as config from '../src/config.js';
import * as writer from '../src/writer.js';
import * as anchors from '../src/anchors.js';
import type { Blueprint } from '../src/types.js';

// 七份出货蓝图当前 revision 的 checksum 字面量，2026-09-04 从 assets/blueprints/*/r2/ 读出。
// 这是跨语言契约：Godot 客户端固定读取这些 mask 字符串对应的布局。这里的比对不是内部一致性
// 自证（writer.checksum(bp) 也是从同一份 JSON 算出来的，永远自洽），而是钉住 canonical() 与
// 生成器当前输出的真实值——一旦 geos-wasm / proj4（两者都是 ^ 依赖）升级悄悄改变了几何计算，
// 或 canonical()/generator 逻辑变了，这里就会跳变。跳变意味着需要人工做出决定并同步更新客户端，
// 绝不能为了让测试变绿而直接编辑这些字面量。
//
// 2026-09-04 从 r1 换到 r2：canonical 收紧（补 grid/cell_mm/play_area_mm/reserved，尺寸改
// 整数毫米）后 checksum 必然变化，而 revision 不可变（PRD §4.5），所以出新 revision 而不是
// 原地改写 r1。r1 的目录原样留在库里，validateAll 只看每个 id 的最高 revision。
const GOLDEN_CHECKSUMS: Record<string, string> = {
  safe_grid: '49b5174eff453c42939302621fc4cf9bc4840477427131b1c3cc3511cc21d8a5',
  sh_a: '8e0fafcd856a2a35207973ad60d47ada2abc6652737a5c52861ad6de5d3ee7c2',
  sh_b: 'b9304248232ce22b8ad05d3316e7a720d27b6e655bd2d2b4273fb9466105e5c7',
  sh_c: '07357c116d617a5e2625c76b557c9b18dd3ce9ce565bed92df5f520b85f3235a',
  la_a: '91fb49ab17d9d803ed25902bb7787da82340ea6dda27bd74a99e06d3bbc3c46e',
  la_b: 'cc4674961c3cce7b7616012562a0bbc8863db6704182d9c2b7f26db4b8aa0e33',
  la_c: '2ad94f3902e29153da740c91367d5a1bdd7a75dd389af533293e0e002008efa9',
};

const OSM_IDS = ['sh_a', 'sh_b', 'sh_c', 'la_a', 'la_b', 'la_c'] as const;
/** 当前出货 revision。revision 不可变，改 canonical 只能出新的（2026-09-04：r1 → r2）。 */
const SHIPPED_REVISION = 2;

describe('shipped blueprints', () => {
  it('regions.json points to existing, valid, checksum-matching blueprints', () => {
    expect(existsSync(config.REGIONS_OUT)).toBe(true);
    const data = JSON.parse(readFileSync(config.REGIONS_OUT, 'utf8'));
    // San Francisco (SGODOT-270, 804be8a7) is a region for the map and placement only: P0 lays its farms out from its
    // own templates, so it ships no blueprint candidates; the blueprint regions keep their three.
    expect(new Set(data.regions.map((r: { id: string }) => r.id))).toEqual(new Set(['shanghai', 'los_angeles', 'san_francisco']));
    for (const r of data.regions) {
      if (r.id === 'san_francisco') { expect(r.candidates ?? []).toEqual([]); continue; }
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

  it('shipped checksums match the pinned golden values', () => {
    for (const [id, golden] of Object.entries(GOLDEN_CHECKSUMS)) {
      const file = path.join(config.BLUEPRINTS_DIR, id, `r${SHIPPED_REVISION}`, 'farm_blueprint.json');
      const bp = JSON.parse(readFileSync(file, 'utf8')) as Blueprint;
      expect(bp.checksum).toBe(golden);
    }
  });

  it('OSM-sourced blueprints carry ODbL provenance', () => {
    for (const id of OSM_IDS) {
      const file = path.join(config.BLUEPRINTS_DIR, id, `r${SHIPPED_REVISION}`, 'farm_blueprint.json');
      const bp = JSON.parse(readFileSync(file, 'utf8')) as Blueprint;
      expect(bp.source.provider).toBe('osm');
      expect(bp.source.license).toBe('ODbL 1.0');
      expect(typeof bp.source.attribution).toBe('string');
      expect((bp.source.attribution as string).length).toBeGreaterThan(0);
    }
  });
});
