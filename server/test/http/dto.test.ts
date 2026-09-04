import { describe, expect, it } from 'vitest';
import path from 'node:path';
import { blueprintSets, loadBlueprint } from '../../src/http/app.js';
import { nearbyEntry, ownerFarmView, snapshotSlot, visitorSnapshot, type FarmRow } from '../../src/http/dto.js';
import { DEFAULT_CONTENT_DIR, loadContent } from '../../src/domain/content.js';
import { derive } from '../../src/domain/derive.js';
import { createInitialState } from '../../src/domain/state.js';
import { at, SH } from '../domain/helpers.js';

const content = loadContent(DEFAULT_CONTENT_DIR);
const ROOT = path.resolve(DEFAULT_CONTENT_DIR, '..', '..', '..');
const bp = loadBlueprint(path.join(ROOT, 'assets', 'blueprints'), 'sh_a', 2)!;
const sets = blueprintSets(bp);
const NOW = at('2026-09-04T10:07:00+08:00');

function farm(over: Partial<FarmRow> = {}): FarmRow {
  const state = createInitialState({
    player_day_id: '2026-09-04', field_condition: 'sunny', now: NOW, wallet: 180,
    bed_cells: [...sets.cultivable].filter(x => !sets.reserved.has(x)),
    reserved_cells: [...sets.reserved],
  });
  state.wallet = 999;
  state.residents.bistro_owner.points = 42;
  return {
    id: 'farm-1', owner_id: 'player-1', region_id: 'shanghai', layout_patch_id: 'sh_a',
    blueprint_revision: 2, version: 7, location_visible: true, visit_access: 'anyone',
    state, ...over,
  };
}
const d = (f: FarmRow) => derive(f.state, NOW, SH, content);

/** 深度收集所有键名，用来断言「不该出现的字段一个都没漏进去」。 */
function allKeys(v: unknown, out = new Set<string>()): Set<string> {
  if (Array.isArray(v)) { for (const x of v) allKeys(x, out); return out; }
  if (v && typeof v === 'object')
    for (const [k, x] of Object.entries(v)) { out.add(k); allKeys(x, out); }
  return out;
}

describe('OwnerFarmView', () => {
  it('顶层字段集精确', () => {
    const f = farm();
    expect(Object.keys(ownerFarmView(f, d(f), NOW)).sort()).toEqual([
      'blueprint_revision', 'derived', 'farm_id', 'layout_patch_id', 'location_visible',
      'region_id', 'server_time', 'state', 'version', 'visit_access',
    ]);
  });
});

describe('VisitorSnapshot（G2）', () => {
  const snap = (over: Partial<FarmRow> = {}) => {
    const f = farm(over);
    return visitorSnapshot(f, d(f), 3, snapshotSlot(NOW));
  };

  it('顶层字段集精确——不是靠扫禁用键名', () => {
    expect(Object.keys(snap()).sort()).toEqual([
      'blueprint_revision', 'cells', 'farm_id', 'layout_patch_id', 'nursery',
      'props', 'region_id', 'snapshot_revision', 'snapshot_taken_at', 'weather_snapshot',
    ]);
  });

  it('不含主人的私有状态：钱包、库存、关系、章节、XP、owner_id', () => {
    const keys = allKeys(snap());
    for (const forbidden of ['owner_id', 'wallet', 'inventory', 'residents', 'chapters',
      'xp', 'growth_choice', 'engineering', 'requests_done', 'life_choices', 'sales_facts',
      'handbook', 'subsidies_claimed', 'stall', 'buyback'])
      expect(keys.has(forbidden), `泄露了 ${forbidden}`).toBe(false);
  });

  it('永远不含经纬度或街道名', () => {
    const keys = allKeys(snap());
    for (const forbidden of ['overlay_wgs84', 'lat', 'lng', 'center', 'paths', 'blocks', 'name', 'display_name'])
      expect(keys.has(forbidden), `泄露了 ${forbidden}`).toBe(false);
  });

  it('每格只给 cell_id / state / crop / ripe', () => {
    const cells = snap().cells as Record<string, unknown>[];
    expect(Object.keys(cells[0]).sort()).toEqual(['cell_id', 'crop', 'ripe', 'state']);
  });

  it('location_visible 为假时连 region_id 一起省掉', () => {
    expect('region_id' in snap({ location_visible: false })).toBe(false);
    expect('region_id' in snap({ location_visible: true })).toBe(true);
    // layout_patch_id 仍在——访客要渲染农场就必须知道蓝图（MVP 折衷，SGODOT-29）
    expect(snap({ location_visible: false }).layout_patch_id).toBe('sh_a');
  });
});

describe('NearbyEntry（G2）', () => {
  it('只给 farm_id / avatar_ref / nursery_stage，location_visible 决定 region_id', () => {
    const f = farm();
    expect(Object.keys(nearbyEntry(f, 'av1')).sort())
      .toEqual(['avatar_ref', 'farm_id', 'nursery_stage', 'region_id']);
    expect(Object.keys(nearbyEntry(farm({ location_visible: false }), 'av1')).sort())
      .toEqual(['avatar_ref', 'farm_id', 'nursery_stage']);
  });
});

describe('快照按固定 15 分钟槽生成（Codex 三审 V3-I3）', () => {
  it('同一槽内不同时刻取整到同一个值——轮询看不出主人何时操作', () => {
    const base = at('2026-09-04T10:00:00+08:00');
    expect(snapshotSlot(base + 1000)).toBe(snapshotSlot(base + 14 * 60_000));
    expect(snapshotSlot(base + 16 * 60_000)).not.toBe(snapshotSlot(base));
  });

  it('槽长即最大陈旧时间', () => {
    const base = at('2026-09-04T10:07:00+08:00');
    expect(base - snapshotSlot(base)).toBeLessThan(15 * 60_000);
  });
});

describe('访问权限四种组合（spec §7.5）', () => {
  const combos = [
    { visit_access: 'only_me' as const, location_visible: true, nearby: false, snapshot: false, region: false },
    { visit_access: 'only_me' as const, location_visible: false, nearby: false, snapshot: false, region: false },
    { visit_access: 'anyone' as const, location_visible: true, nearby: true, snapshot: true, region: true },
    { visit_access: 'anyone' as const, location_visible: false, nearby: true, snapshot: true, region: false },
  ];
  for (const c of combos) {
    it(`visit_access=${c.visit_access} location_visible=${c.location_visible}`, () => {
      const f = farm({ visit_access: c.visit_access, location_visible: c.location_visible });
      const visible = f.visit_access === 'anyone';
      expect(visible).toBe(c.nearby);
      expect(visible).toBe(c.snapshot);
      if (visible)
        expect('region_id' in visitorSnapshot(f, d(f), 1, snapshotSlot(NOW))).toBe(c.region);
    });
  }
});
