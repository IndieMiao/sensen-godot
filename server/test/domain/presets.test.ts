/** 预置访客农场：确定性 id、真归约器生成、两种风格确实不同。 */
import { describe, expect, it } from 'vitest';
import path from 'node:path';
import { PRESET_SPECS, buildPresetFarm, deterministicUuid, presetByFarmId, presetFarmId } from '../../src/domain/presets.js';
import { plotFor, loadBlueprint } from '../../src/http/app.js';
import { DEFAULT_CONTENT_DIR, loadContent } from '../../src/domain/content.js';
import { derive } from '../../src/domain/derive.js';
import { at } from './helpers.js';

const content = loadContent(DEFAULT_CONTENT_DIR);
const ROOT = path.resolve(DEFAULT_CONTENT_DIR, '..', '..', '..');
const T0 = at('2026-09-04T10:00:00+08:00');
const tzOf = (region: string) => region === 'shanghai' ? 'Asia/Shanghai' : 'America/Los_Angeles';

describe('预置农场', () => {
  it('provides distinct public neighbours around every selectable neighbourhood', () => {
    for (const region of ['shanghai', 'los_angeles']) {
      const specs = PRESET_SPECS.filter(s => s.region === region);
      expect(specs).toHaveLength(18);
      expect(new Set(specs.map(s => presetFarmId(s.id ?? s.layout))).size).toBe(18);
      const demos = specs.filter(s => s.id?.startsWith('demo_'));
      expect(demos).toHaveLength(16);
      expect(new Set(demos.map(s => JSON.stringify(s.location))).size).toBe(16);
      for (const spec of demos) expect(presetByFarmId(presetFarmId(spec.id!))).toEqual(spec);
      for (const layout of (region === 'shanghai' ? ['sh_a', 'sh_b', 'sh_c'] : ['la_a', 'la_b', 'la_c'])) {
        const bp = loadBlueprint(path.join(ROOT, 'assets', 'blueprints'), layout, 2)!;
        const [lat, lng] = bp.overlay_wgs84!.center;
        const neighbours = demos.filter(s => Math.abs(s.location!.lat - lat) < .0016 && Math.abs(s.location!.lng - lng) < .0018);
        expect(neighbours.length).toBeGreaterThanOrEqual(4);
      }
    }
  });
  it('id 确定且是合法 UUID；随包快照与线上因此是同一座农场', () => {
    const a = presetFarmId('sh_b');
    expect(a).toBe(presetFarmId('sh_b'));
    expect(a).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
    expect(presetFarmId('sh_b')).not.toBe(presetFarmId('sh_c'));
    expect(deterministicUuid('x')).not.toBe(deterministicUuid('y'));
    expect(presetByFarmId(a)?.layout).toBe('sh_b');
  });

  for (const spec of PRESET_SPECS) {
    it(`${spec.layout} (${spec.style}) 能用真实归约器建出来`, () => {
      const bp = loadBlueprint(path.join(ROOT, 'assets', 'blueprints'), spec.layout, spec.revision);
      expect(bp, '蓝图必须在架').toBeTruthy();
      const farm = buildPresetFarm(spec, plotFor(content), content, tzOf(spec.region), T0);
      expect(farm.visit_access).toBe('anyone');
      expect(farm.location_visible).toBe(true);
      const cells = Object.values(farm.state.cells).filter(c => c !== undefined);
      const growing = cells.filter(c => c.state === 'growing');
      if (spec.style === 'lush') {
        expect(growing).toHaveLength(9);
        for (const c of growing) expect(c.ready_at, 'growing 必有 ready_at').not.toBeNull();
        // 6 小时后：萝卜（4h）熟了，生菜（8h）没熟——一眼有层次
        const d = derive(farm.state, T0 + 6 * 3600_000, tzOf(spec.region), content);
        expect(d.ripe_cells).toHaveLength(6);
        expect(farm.state.nursery.stage).toBe('cleared');
      } else {
        // 自由格子种田起，荒地不进状态：early 风格就是「开垦了三格，还没种」。
        expect(growing).toHaveLength(0);
        expect(cells.filter(c => c.state === 'tilled')).toHaveLength(3);
        expect(cells).toHaveLength(3);
      }
    });
  }

  it('两种风格的格子分布明显不同', () => {
    const [lush, early] = ['sh_b', 'sh_c'].map(l => {
      const spec = PRESET_SPECS.find(s => s.layout === l)!;
      const bp = loadBlueprint(path.join(ROOT, 'assets', 'blueprints'), l, 2)!;
      return buildPresetFarm(spec, plotFor(content), content, 'Asia/Shanghai', T0);
    });
    const hist = (f: typeof lush) => Object.values(f.state.cells).map(c => c?.state).sort().join(',');
    expect(hist(lush)).not.toBe(hist(early));
  });
});
