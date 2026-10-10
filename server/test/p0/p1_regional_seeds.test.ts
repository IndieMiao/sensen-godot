import { describe, expect, it } from 'vitest';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { cropGrowH } from '../../src/p0/garden.js';
import { applyP0, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { catalog } from '../../src/p0/shops.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

// P1 (§5.2.3, SGODOT-240): a Market sells its own climate's regional seed from Farming Lv5, 10 a day per climate;
// away from their zone regional crops ripen ×1.5 in the open field. San Francisco is Temperate: Pumpkin at home.
const c: P0Content = loadP0Content();
const T0 = Date.UTC(2026, 9, 10, 18, 0, 0);
const H = 3_600_000;
const SINGAPORE = 'gn-1880252', TOKYO = 'gn-1850147', LA = 'gn-5368361';

function step(s: P0State, cmd: P0Command, now = T0): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return { s: r.state, ev: r.events };
}
function refused(s: P0State, cmd: P0Command, now = T0) {
  const r = applyP0(c, s, cmd, now);
  if (r.ok) throw new Error(`${cmd.type} was accepted`);
  return r;
}
/** Farming Lv5 at home with coins for a day's seeds. */
function f5(): P0State {
  const s = freshState(c, 'player-regional-01', T0, 7);
  s.skills.farming = c.skills.farming[4];
  s.coins = 1000;
  s.energy.value = 200;
  return s;
}
const buy = (item: string, qty = 1) => ({ type: 'buy', shop: 'market', item, qty }) as P0Command;
const marketIds = (s: P0State) => viewOf(c, s, T0).shops.market.buy.map(o => o.id);
const crop = (id: string) => c.crops.find(x => x.id === id)!;

describe('regional seeds at the Market (§5.2.3)', () => {
  it('the home Market sells only the home climate\'s seed, between the goods and the City Specialty', () => {
    expect(c.profile.climate).toBe('Temperate');
    const ids = marketIds(f5());
    expect(ids).toEqual([...c.market.buy, 'seed_pumpkin', 'seed_apple', 'seed_citrus', 'seed_grape', 'fert_orchard', ...c.market.specialty]);
    for (const other of ['seed_pineapple', 'seed_sweet_potato', 'seed_beet']) expect(ids).not.toContain(other);
    expect(refused(f5(), buy('seed_pineapple')).code).toBe('bad_item');
    expect(c.stall.buy).not.toContain('seed_pumpkin');   // the Homestead Stall never has them
  });

  it('a city\'s Market sells that climate\'s seed: Singapore Pineapple, Los Angeles Sweet Potato, Tokyo Pumpkin', () => {
    for (const [cluster, seed] of [[SINGAPORE, 'seed_pineapple'], [LA, 'seed_sweet_potato'], [TOKYO, 'seed_pumpkin']]) {
      const s = { ...f5(), travel: { ...f5().travel, here: cluster } };
      const regional = new Set(c.crops.filter(x => x.regional).map(x => x.seed));
      expect(catalog(c, 'market', s).filter(id => regional.has(id))).toEqual([seed]);
    }
    // a command at a named outpost uses that outpost's city, wherever the player was last
    expect(catalog(c, 'market', { ...f5(), travel: { ...f5().travel, here: SINGAPORE } }, `${LA}~market0`)).toContain('seed_sweet_potato');
  });

  it('opens at Farming Lv5, 10 a day per climate, back at the rollover', () => {
    const low = f5();
    low.skills.farming = c.skills.farming[4] - 40;
    expect(refused(low, buy('seed_pumpkin'))).toMatchObject({ code: 'locked', detail: { skill: 'farming', level: 5, xp_to_go: 40 } });
    const row = viewOf(c, low, T0).shops.market.buy.find(o => o.id === 'seed_pumpkin')!;
    expect(row).toMatchObject({ unlocked: false, gate: 5, xp_to_go: 40, daily: 10, left: 10 });
    let s = step(f5(), buy('seed_pumpkin', 6)).s;
    expect(s.coins).toBe(1000 - 6 * 17);
    expect(viewOf(c, s, T0).shops.market.buy.find(o => o.id === 'seed_pumpkin')).toMatchObject({ left: 4, daily: 10 });
    expect(refused(s, buy('seed_pumpkin', 5))).toMatchObject({ code: 'sold_out', detail: { left: 4 } });
    s = step(s, buy('seed_pumpkin', 4)).s;
    expect(refused(s, buy('seed_pumpkin')).code).toBe('sold_out');
    const tomorrow = T0 + 24 * H;
    expect(viewOf(c, s, tomorrow).shops.market.buy.find(o => o.id === 'seed_pumpkin')?.left).toBe(10);
    step(s, buy('seed_pumpkin', 10), tomorrow);
  });
});

describe('regional crops on the home farm (§5.2.3)', () => {
  it('ripen in their own time at home and ×1.5 away from their zone (Pumpkin 20 h, Pineapple 36 h here)', () => {
    expect(cropGrowH(c, f5(), crop('crop_pumpkin'))).toBe(20);
    expect(cropGrowH(c, f5(), crop('crop_pineapple'))).toBe(36);
    expect(cropGrowH(c, f5(), crop('crop_radish'))).toBe(crop('crop_radish').grow_h);
    const v = viewOf(c, f5(), T0).crops;
    expect(v.find(x => x.id === 'crop_pumpkin')).toMatchObject({ grow_h: 20, zone: 'Temperate', native: true });
    expect(v.find(x => x.id === 'crop_pineapple')).toMatchObject({ grow_h: 36, zone: 'Tropical', native: false });
    expect(v.find(x => x.id === 'crop_radish')).not.toHaveProperty('native');
  });

  it('judge native by the home city, not profile.climate (哪吒 on #235): a Singapore home grows Pineapple in 24 h', () => {
    const s = { ...f5(), travel: { ...f5().travel, home: SINGAPORE, here: SINGAPORE } };
    expect(cropGrowH(c, s, crop('crop_pineapple'))).toBe(24);
    expect(cropGrowH(c, s, crop('crop_pumpkin'))).toBe(30);
    expect(viewOf(c, s, T0).crops.find(x => x.id === 'crop_pineapple')).toMatchObject({ grow_h: 24, native: true });
  });

  it('cost 4 Energy to sow and start their own clock when watered', () => {
    let s = f5();
    s.bag.push({ id: 'seed_pineapple', qty: 1 }, { id: 'seed_pumpkin', qty: 1 });
    const before = s.energy.value;
    s = step(s, { type: 'sow', plot: 0, seed: 'seed_pineapple' }).s;
    s = step(s, { type: 'sow', plot: 1, seed: 'seed_pumpkin' }).s;
    expect(s.energy.value).toBe(before - 8);
    s = step(s, { type: 'water', plot: 0 }).s;
    s = step(s, { type: 'water', plot: 1 }).s;
    expect(s.plots[0].ready_at).toBe(T0 + 36 * H);
    expect(s.plots[1].ready_at).toBe(T0 + 20 * H);
  });
});
