/** SGODOT-354 / q(245): short farm loops cannot enter ordinary crop reward/economy paths. */
import { describe, expect, it } from 'vitest';
import { cropById, cropBySeed, fastCrop, ingredient, itemKind, itemName, loadP0Content, plotCrop, type P0Content } from '../../src/p0/content.js';
import { add, count } from '../../src/p0/bag.js';
import { coverOf, seedSaver } from '../../src/p0/garden.js';
import { applyP0, sellPrice, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { matches, haveFor, pick } from '../../src/p0/requests.js';
import { buyback, catalog } from '../../src/p0/shops.js';
import { noteHarvested } from '../../src/p0/residents.js';
import { guidePred } from '../../src/p0/guide.js';
import { freshState, upgradeState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content(), T = Date.UTC(2026, 9, 28, 2), H = 3600000;
const rows = [
  ['crop_cress', 'Cress', 1, 10, 1, 1], ['crop_pea_shoots', 'Pea Shoots', 1, 60, 2, 3],
  ['crop_spinach', 'Baby Spinach', 2, 300, 2, 3], ['crop_scallion', 'Scallion', 2, 1200, 3, 4],
  ['crop_bok_choy', 'Bok Choy', 3, 3600, 3, 4],
] as const;
const fresh = (cc = c): P0State => ({ ...freshState(cc, 'fast-crop-test', T, 7), created_at: T - 8 * 24 * H });
function run(s: P0State, cmd: P0Command, now = T, cc = c) {
  const r = applyP0(cc, s, { space: 'home', ...cmd } as P0Command, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail)}`);
  return r;
}
function ready(id: string, cc = c) {
  const s = fresh(cc), f = fastCrop(cc, id)!;
  s.skills.farming = cc.skills.farming[f.gate - 1];
  add(cc, s, f.seed, 3);
  return s;
}
function planted(id: string, cc = c) { return run(ready(id, cc), { type: 'sow', plot: 0, seed: fastCrop(cc, id)!.seed }, T, cc).state; }

describe('fast crops, isolated content and real buy → sow → water → harvest → sell', () => {
  it('loads the five approved rows separately, with no ingredient or ordinary crop identity', () => {
    expect(c.fast_crops!.map(f => [f.id, f.name, f.farming, f.grow_s, f.seed_price, f.price])).toEqual(rows);
    for (const f of c.fast_crops!) {
      expect([f.energy, f.xp, f.first_xp]).toEqual([2, 2, 10]);
      expect(cropById(c, f.id)).toBeUndefined(); expect(cropBySeed(c, f.seed)).toBeUndefined();
      expect(ingredient(c, f.id)).toBeNull(); expect(ingredient(c, f.seed)).toBeNull();
      expect(itemKind(f.id)).toBe('crop'); expect(plotCrop(c, f.id)?.quick?.ms).toBe(f.grow_s * 1000);
      expect(itemName(c, f.id)).toBe(f.name); expect(itemName(c, f.seed)).toBe(f.seed_name);
    }
  });

  it.each(rows)('%s has its own fixed duration, harvest, first XP and Stall price', (id, name, farming, seconds, seedPrice, price) => {
    let s = fresh(); s.skills.farming = c.skills.farming[farming - 1];
    const seed = id.replace('crop_', 'seed_'), energy = s.energy.value, coins = s.coins, xp = s.skills.farming;
    s = run(s, { type: 'buy', shop: 'stall', item: seed, qty: 1 }).state;
    expect(s.coins).toBe(coins - seedPrice);
    s = run(s, { type: 'sow', plot: 0, seed }).state;
    expect(s.energy.value).toBe(energy - 2); expect(s.plots[0]).toMatchObject({ state: 'sown', crop: id, xp_pct: 100 });
    expect(viewOf(c, s, T).plots[0]).toMatchObject({ state: 'sown', crop: id });
    s = run(s, { type: 'water', plot: 0 }, T + 5000).state;
    const at = T + 5000 + seconds * 1000;
    expect(s.plots[0].ready_at).toBe(at);
    expect(viewOf(c, s, at - 1000).plots[0]).toMatchObject({ state: 'growing', crop: id, ready_in: 1000 });
    expect(applyP0(c, s, { type: 'harvest', plot: 0 }, at - 1)).toMatchObject({ ok: false, code: 'not_ready' });
    const r = run(s, { type: 'harvest', plot: 0 }, at); s = r.state;
    expect(count(s.bag, id)).toBe(1); expect(s.skills.farming - xp).toBe(12);
    expect(r.events).toContainEqual({ kind: 'item', id, delta: 1 });
    expect(r.events).toContainEqual(expect.objectContaining({ kind: 'first', what: `harvest:${id}`, xp: 10 }));
    expect(r.events.some(e => e.kind === 'seed_saved')).toBe(false);
    expect(s.plots[0]).toEqual({ id: 0, state: 'tilled' });
    const v = viewOf(c, s, at);
    expect(v.items[id]).toMatchObject({ name, kind: 'crop', sell: price, cook: false });
    expect(v.items[id]).not.toHaveProperty('family');
    const before = s.coins;
    s = run(s, { type: 'sell', shop: 'stall', item: id, qty: 1 }, at).state;
    expect(s.coins - before).toBe(price); expect(count(s.bag, id)).toBe(0);
    expect(s.firsts).toContain(`harvest:${id}`);
  });

  it('gates both bought and externally obtained seeds, and keeps refused commands atomic', () => {
    expect(applyP0(c, ready('crop_cress'), { type: 'sow', plot: 0, seed: 'crop_cress' }, T)).toMatchObject({ ok: false, code: 'bad_item' });
    for (const id of ['crop_spinach', 'crop_scallion', 'crop_bok_choy']) {
      const s = fresh(), f = fastCrop(c, id)!;
      add(c, s, f.seed, 1); const before = structuredClone(s);
      expect(applyP0(c, s, { type: 'buy', shop: 'stall', item: f.seed, qty: 1 }, T)).toMatchObject({ ok: false, code: 'locked' });
      expect(applyP0(c, s, { type: 'sow', plot: 0, seed: f.seed }, T)).toMatchObject({ ok: false, code: 'skill_level_required', detail: { level: f.gate } });
      expect(s).toEqual(before);
    }
    const low = ready('crop_cress'); low.energy.value = 1;
    expect(applyP0(c, low, { type: 'sow', plot: 0, seed: 'seed_cress' }, T)).toMatchObject({ ok: false, code: 'need_energy' });
  });

  it('Stall seeds have no daily purchase cap and no wallet floor; other counters cannot sell or buy them', () => {
    let s = fresh(); s.coins = 2;
    s = run(s, { type: 'buy', shop: 'stall', item: 'seed_cress', qty: 2 }).state;
    expect(s.coins).toBe(0);
    for (const f of c.fast_crops!) {
      expect(catalog(c, 'homestead')).toContain(f.seed);
      expect(viewOf(c, s, T).shops.homestead.buy.find(x => x.id === f.seed)).toMatchObject({ daily: null, left: null, gate: f.farming });
      expect(viewOf(c, s, T).stall.buy.find(x => x.id === f.seed)).toMatchObject({ energy: f.energy });
      expect(sellPrice(c, f.id)).toBe(f.price); expect(sellPrice(c, f.seed)).toBeNull();
      for (const shop of ['market', 'post', 'tackle', 'tea'] as const) {
        expect(catalog(c, shop, s)).not.toContain(f.seed);
        expect(buyback(c, shop, f.id)).toEqual({ code: 'not_sellable_here' });
      }
    }
    s.coins = 500; s.day.bought.seed_cress = 999;
    expect(count(run(s, { type: 'buy', shop: 'stall', item: 'seed_cress', qty: 99 }).state.bag, 'seed_cress')).toBe(101);
  });

  it('locks the level difference at sowing and gives first harvest XP only once', () => {
    let s = ready('crop_cress'); s.skills.farming = c.skills.farming[3];
    s = run(s, { type: 'sow', plot: 0, seed: 'seed_cress' }).state;
    const pct = s.plots[0].xp_pct!; expect(pct).toBeLessThan(100);
    s = run(s, { type: 'water', plot: 0 }).state;
    const first = run(s, { type: 'harvest', plot: 0 }, T + 10000);
    expect(first.events).toContainEqual(expect.objectContaining({ kind: 'first', what: 'harvest:crop_cress', xp: 10 }));
    s = run(first.state, { type: 'sow', plot: 1, seed: 'seed_cress' }, T + 10000).state;
    s = run(s, { type: 'water', plot: 1 }, T + 10000).state;
    const next = run(s, { type: 'harvest', plot: 1 }, T + 20000);
    expect(next.events.some(e => e.kind === 'first' && e.what === 'harvest:crop_cress')).toBe(false);
    expect(next.events.filter(e => e.kind === 'xp')).toEqual([expect.objectContaining({ skill: 'farming', percent: pct, amount: 1 })]);
  });

  it('row sow charges each seed and each plot, while full bags preserve the ripe crop', () => {
    let s = ready('crop_cress'); s.gear.hoe = c.tools.row_hoe.id;
    const e = s.energy.value;
    s = run(s, { type: 'sow', plots: [0, 1, 2], seed: 'seed_cress' }).state;
    expect(s.energy.value).toBe(e - 6); expect(count(s.bag, 'seed_cress')).toBe(0);
    s = run(s, { type: 'water', plot: 0 }).state;
    s.bag = Array.from({ length: 25 }, () => ({ id: 'fish_crucian', qty: 10 }));
    const before = structuredClone(s);
    expect(applyP0(c, s, { type: 'harvest', plot: 0 }, T + 10000)).toMatchObject({ ok: false, code: 'bag_full' });
    expect(s).toEqual(before);
    s.bag[0] = { id: 'crop_cress', qty: 49 };
    expect(count(run(s, { type: 'harvest', plot: 0 }, T + 10000).state.bag, 'crop_cress')).toBe(50);
  });
});

describe('fast crops cannot escape their three allowed paths', () => {
  it('sprinklers/greenhouses auto-water but never shorten fixed seconds, including when newly placed', () => {
    for (const kind of ['sprinkler', 'greenhouse']) {
      const plot = kind === 'sprinkler' ? 8 : coverOf(c, 'greenhouse', 4, 30).find(id => fresh().plots[id].state === 'tilled')!;
      let s = ready('crop_bok_choy'); s.facilities = [{ id: 1, kind, plot: kind === 'sprinkler' ? 7 : 4 }];
      s = run(s, { type: 'sow', plot, seed: 'seed_bok_choy' }).state;
      expect(s.plots[plot]).toMatchObject({ state: 'growing', ready_at: T + H });
    }
    let s = ready('crop_cress'); s.skills.farming = c.skills.farming[5]; s.storage = { wood: 20, stone: 20, copper_ore: 7 };
    s = run(s, { type: 'sow', plot: 8, seed: 'seed_cress' }).state;
    s = run(s, { type: 'place', recipe: 'craft_sprinkler', plot: 7 }, T + 5000).state;
    expect(s.plots[8].ready_at).toBe(T + 15000);
  });

  it('rejects Compost before cropById dereference, in sown and growing states without spending it', () => {
    for (const f of c.fast_crops!) {
      let s = planted(f.id); add(c, s, 'fert_compost', 3);
      for (const growing of [false, true]) {
        if (growing) s = run(s, { type: 'water', plot: 0 }).state;
        const before = structuredClone(s);
        expect(applyP0(c, s, { type: 'fertilize', plot: 0, item: 'fert_compost' }, T)).toMatchObject({ ok: false, code: 'wrong_state' });
        expect(s).toEqual(before);
      }
    }
  });

  it('never triggers Seed Saver even at chance 100%, while an ordinary annual still does', () => {
    const cc = loadP0Content(); cc.farming!.seed_saver_chance = 1;
    const s = fresh(cc); s.skills.farming = cc.skills.farming[9];
    const ev: P0Event[] = [], plot = { id: 0, state: 'growing' as const, ready_at: T };
    for (const f of cc.fast_crops!) seedSaver(cc, s, plotCrop(cc, f.id)!, plot, ev);
    expect(ev).toEqual([]);
    seedSaver(cc, s, cropById(cc, 'crop_radish')!, plot, ev);
    expect(ev.some(e => e.kind === 'seed_saved')).toBe(true);
  });

  it('all generic, family, rarity and explicit crop requests exclude the harvests', () => {
    const s = fresh(); s.bag = c.fast_crops!.map(f => ({ id: f.id, qty: 50 }));
    for (const f of c.fast_crops!) for (const need of [{ kind: 'crop' as const }, { kind: 'crop' as const, family: 'F' as const }, { kind: 'crop' as const, rarity: 1 }]) {
      for (const ids of [[], [f.id]]) {
        expect(matches(c, need, ids, f.id)).toBe(false);
        expect(haveFor(c, s, need, ids)).toBe(0);
        expect(pick(c, s, need, ids, 1)).toBeNull();
      }
    }
    expect(matches(c, { kind: 'crop' }, [], 'crop_radish')).toBe(true);
  });

  it('Hana and Nadia arbitrary-crop deliveries cannot consume fast harvests', () => {
    for (const [owner, def] of Object.entries(c.residents)) for (const q of def.requests.filter(q => q.need.kind === 'crop' && !q.need.id)) {
      const s = fresh(); s.bag = c.fast_crops!.map(f => ({ id: f.id, qty: 50 }));
      s.residents[owner] = { affinity: 100, chat_day: '', gift_day: '', next: def.requests.indexOf(q), req: { id: q.id, at: T, progress: 0 }, done_day: '' };
      const row = viewOf(c, s, T).residents[owner]; expect(row.request?.have).toBe(0);
      const before = structuredClone(s);
      const result = applyP0(c, s, { type: 'deliver', request: q.id }, T);
      expect(result).toMatchObject({ ok: false, code: 'not_enough', detail: { have: 0 } });
      expect(s).toEqual(before);
    }
  });

  it('all residents sow requests ignore fast plots, but still count ordinary and teaching radishes', () => {
    let s = ready('crop_cress'); s.gear.hoe = c.tools.row_hoe.id;
    for (const [id, def] of Object.entries(c.residents)) for (const q of def.requests.filter(q => q.need.kind === 'sow'))
      s.residents[id] = { affinity: 100, chat_day: '', gift_day: '', next: 0, req: { id: q.id, at: T, progress: 0 }, done_day: '' };
    expect(Object.keys(s.residents).length).toBeGreaterThanOrEqual(3);
    s = run(s, { type: 'sow', plots: [0, 1, 2], seed: 'seed_cress' }).state;
    expect(Object.values(s.residents).every(r => r.req!.progress === 0)).toBe(true);
    s = run(s, { type: 'sow', plot: 3, seed: 'seed_radish' }).state;
    expect(Object.values(s.residents).every(r => r.req!.progress === 1)).toBe(true);
    add(c, s, 'seed_quick_radish', 1);
    s = run(s, { type: 'sow', plot: 4, seed: 'seed_quick_radish' }).state;
    expect(Object.values(s.residents).every(r => r.req!.progress === 2)).toBe(true);
    const cc = structuredClone(c); cc.residents.res_nadia.requests[0].need = { kind: 'harvest', id: 'crop_cress' };
    s.residents.res_nadia = { affinity: 100, chat_day: '', gift_day: '', next: 0, req: { id: cc.residents.res_nadia.requests[0].id, at: T, progress: 0 }, done_day: '' };
    noteHarvested(cc, s, 'crop_cress', 1); expect(s.residents.res_nadia.req!.progress).toBe(0);
  });

  it('rejects fast harvests for cooking, gifting, compost and regional barter without mutation', () => {
    for (const f of c.fast_crops!) {
      const s = ready(f.id); add(c, s, f.id, 10); s.facilities = [{ id: 1, kind: 'compost_bin', plot: -1, cell: [17, 16] }];
      const before = structuredClone(s);
      for (const cmd of [{ type: 'cook', items: [f.id] }, { type: 'gift', resident: 'res_pip', item: f.id },
        { type: 'compost', item: f.id, qty: 1 }, { type: 'barter', item: f.id, mineral: 'stone', qty: 1 }] as P0Command[]) {
        expect(applyP0(c, s, cmd, T).ok).toBe(false); expect(s).toEqual(before);
      }
      expect(guidePred(c, s, { common_crop: 1 }, T)).toBe(false);   // not a soup-recovery crop either
    }
  });

  it('view/save roundtrips keep separate data, item names, plot clock and ordinary crop lists intact', () => {
    let s = planted('crop_cress'); s = run(s, { type: 'water', plot: 0 }).state;
    const restored = upgradeState(c, JSON.parse(JSON.stringify(s)), T + 3000);
    expect(restored.v).toBe(s.v); expect(restored.plots[0]).toEqual(s.plots[0]);
    const v = viewOf(c, restored, T + 3000);
    expect(v.fast_crops).toEqual(c.fast_crops);
    expect(v.crops.some(x => c.fast_crops!.some(f => f.id === x.id))).toBe(false);
    expect(v.quick_seeds).toHaveLength(1);
    expect(v.plots[0]).toMatchObject({ crop: 'crop_cress', ready_in: 7000 });
    for (const f of c.fast_crops!) { expect(v.names[f.id]).toBe(f.name); expect(v.names[f.seed]).toBe(f.seed_name); }
  });
});
