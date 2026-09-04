import { describe, it, expect } from 'vitest';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import * as config from '../src/config.js';
import * as writer from '../src/writer.js';
import * as anchors from '../src/anchors.js';
import type { Blueprint } from '../src/types.js';

// 七个已出货蓝图的当前 checksum 字面量，2026-09-03 从 assets/blueprints/*/r1/farm_blueprint.json 读出。
// 这是跨语言契约：Godot 客户端固定读取这些 mask 字符串对应的布局。这里的比对不是内部一致性
// 自证（writer.checksum(bp) 也是从同一份 JSON 算出来的，永远自洽），而是钉住 canonical() 与
// 生成器当前输出的真实值——一旦 geos-wasm / proj4（两者都是 ^ 依赖）升级悄悄改变了几何计算，
// 或 canonical()/generator 逻辑变了，这里就会跳变。跳变意味着需要人工做出决定并同步更新客户端，
// 绝不能为了让测试变绿而直接编辑这些字面量。
const GOLDEN_CHECKSUMS: Record<string, string> = {
  safe_grid: '47899861c7bafd0aa95b3eaddaba48ae3764e5ec8180ca1247507dd53f0482e8',
  sh_a: '223f4de32a1f4d558cc4dc4eace0a17bbd7cb8367ee1508ea8d3b4f869d802ed',
  sh_b: '78abf71679f08c211e46dff86289d32ac519d104ef3de7121b0af144f579f0c4',
  sh_c: 'bbd21e6623d4bd30f1129127173c6373fcb30653373f4199396d7e569f64c086',
  la_a: 'ee6b00199ca3ab69661bf81b3b44fa0e3a955b0d5e24080d35c73bb665109008',
  la_b: 'a4c5e0321fcaa63d75b4d24349432b12ef2e64e6545da27dd30ade97e530dc7a',
  la_c: '7ad48c8bd43087dea3b770904c1489720da2344140893890fdac926635021230',
};

const OSM_IDS = ['sh_a', 'sh_b', 'sh_c', 'la_a', 'la_b', 'la_c'] as const;

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

  it('shipped checksums match the pinned golden values', () => {
    for (const [id, golden] of Object.entries(GOLDEN_CHECKSUMS)) {
      const file = path.join(config.BLUEPRINTS_DIR, id, 'r1', 'farm_blueprint.json');
      const bp = JSON.parse(readFileSync(file, 'utf8')) as Blueprint;
      expect(bp.checksum).toBe(golden);
    }
  });

  it('OSM-sourced blueprints carry ODbL provenance', () => {
    for (const id of OSM_IDS) {
      const file = path.join(config.BLUEPRINTS_DIR, id, 'r1', 'farm_blueprint.json');
      const bp = JSON.parse(readFileSync(file, 'utf8')) as Blueprint;
      expect(bp.source.provider).toBe('osm');
      expect(bp.source.license).toBe('ODbL 1.0');
      expect(typeof bp.source.attribution).toBe('string');
      expect((bp.source.attribution as string).length).toBeGreaterThan(0);
    }
  });
});
