import Fastify from 'fastify';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { regenMs } from '../../src/p0/rules.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { P0Store } from '../../src/p0/store.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content();
const T = Date.UTC(2026, 9, 5, 2);
function step(s: P0State, cmd: P0Command, at = T, content = c) {
  const r = applyP0(content, s, cmd, at);
  if (!r.ok) throw new Error(r.code);
  return r.state;
}
const FERN = 'pond_san_francisco_03', BLOSSOM = 'pond_san_francisco_06';   // Fern Pond (Pond) / Blossom Pond (River)
const fresh = () => freshState(c, 'progression-player', T, 7);
/** Enter a pond (space + place, q(36)) and land one fish there. */
function catchFish(s: P0State, place = FERN, at = T, content = c) {
  s = step(s, { type: 'cast', space: 'pond', place }, at, content);
  return step(s, { type: 'reel', outcome: 'landed' }, at + s.cast!.bite_ms + 10, content);
}
function goodDish(s: P0State, items: string[], at = T) {
  s = step(s, { type: 'cook', items }, at);
  const pot = s.stove!;
  const h = pot.heats[0];
  return step(s, { type: 'collect', taps: [h.at + (h.gold + h.width / 2) * h.spin] }, at + pot.ms + 10);
}

describe('P0 first-session XP (q(37); SGODOT-232 S1, rescued from SGODOT-131)', () => {
  it('first crucian totals 50 XP; another pond template in the same city gives no second city bonus', () => {
    let s = catchFish(fresh());
    expect(s.skills.fishing).toBe(50);
    expect(s.firsts).toContain('fishing_city:gn-5391959');   // v5: keyed by the city cluster
    s = catchFish(s, BLOSSOM, T + 60_000);
    expect(s.skills.fishing).toBe(55);
  });

  it('takes the city from the server pond table, ignoring a forged site or city in the command', () => {
    let s = step(fresh(), { type: 'cast', space: 'pond', place: FERN, site: 'river', city: 'invented' } as P0Command);
    expect(s.cast).toMatchObject({ site: 'pond', place: FERN });
    s = step(s, { type: 'reel', outcome: 'landed' }, T + s.cast!.bite_ms + 10);
    expect(s.firsts.filter(f => f.startsWith('fishing_city:'))).toEqual(['fishing_city:gn-5391959']);
    const other = structuredClone(c);
    (other.fishing.places[BLOSSOM] as { cluster?: string }).cluster = 'gn-1850147';   // v5: a place's city is its cluster
    s.presence.place = BLOSSOM;   // entered before the table changed
    s.travel.passes['gn-1850147'] = { kind: 'day', from: T, until: T + 86_400_000 };
    s.travel.here = 'gn-1850147';   // q(256) ④: a pass alone no longer lets a new cast in; the player is there
    s = step(s, { type: 'cast' }, T + 60_000, other);
    s = step(s, { type: 'reel', outcome: 'landed' }, T + 60_000 + s.cast!.bite_ms + 10, other);
    expect(s.skills.fishing).toBe(65);
    expect(s.firsts).toContain('fishing_city:gn-1850147');
  });

  it('cancel and escape do not grant city/landing XP; first-cast bonus cannot be repeated', () => {
    let s = step(fresh(), { type: 'cast', space: 'pond', place: FERN });
    s = step(s, { type: 'reel', outcome: 'cancel' }, T + 10);
    expect(s.skills.fishing).toBe(10);
    expect(s.firsts).not.toContain('fishing_city:gn-5391959');
    s = step(s, { type: 'cast' }, T + 100);
    // q(219): an `escaped` on the first two bites lands; a line in after the bite is how one of them gets away
    s = step(s, { type: 'reel', outcome: 'cancel' }, T + 100 + s.cast!.bite_ms + 10);
    expect(s.skills.fishing).toBe(10);
    expect(s.firsts).not.toContain('landed');
    s = catchFish(s, FERN, T + 60_000);
    expect(s.skills.fishing).toBe(50);
  });

  it('two first Good dishes give 15 + 30 Cooking XP and Cooking Lv2 gives the Grilled Fish card (q(221))', () => {
    let s = fresh();
    s.bag.push({ id: 'fish_crucian', qty: 3 }, { id: 'crop_herb', qty: 2 });
    s = goodDish(s, ['fish_crucian']);
    expect(s.skills.cooking).toBe(15);
    s = goodDish(s, ['fish_crucian', 'crop_herb'], T + 20_000);
    expect(s.skills.cooking).toBe(45);
    expect(s.cookbook).toContain('dish_grilled_fish');
    expect(s.cookbook).not.toContain('dish_fish_soup');   // the soup card now comes from Nadia's first request (q(218))
    expect(s.inbox.granted.filter(k => k === 'level:cooking:2')).toHaveLength(1);
    expect(s.skills.farming).toBe(0);
    expect(s.skills.fishing).toBe(0);
  });

  it('no skill level gives Energy: Cooking never did (q(37)), Fishing Lv2 no longer does (q(101))', () => {
    let s = fresh();
    s.energy.value = 100;
    s.bag.push({ id: 'fish_crucian', qty: 3 }, { id: 'crop_herb', qty: 2 });
    s = goodDish(s, ['fish_crucian']);
    const r = applyP0(c, s, { type: 'cook', items: ['fish_crucian', 'crop_herb'] }, T + 20_000);
    if (!r.ok) throw new Error(r.code);
    const pot = r.state.stove!, h = pot.heats[0];
    const done = applyP0(c, r.state, { type: 'collect', taps: [h.at + (h.gold + h.width / 2) * h.spin] }, T + 20_000 + pot.ms + 10);
    if (!done.ok) throw new Error(done.code);
    expect(done.state.skills.cooking).toBe(45);
    expect(done.events).toContainEqual(expect.objectContaining({ kind: 'level', skill: 'cooking', level: 2, energy: 0 }));
    expect(done.events.some(e => e.kind === 'energy')).toBe(false);
    expect(done.state.rewards).not.toContain('levelup_first');
    s = catchFish(done.state, FERN, T + 60_000);
    s.skills.fishing = 69;
    s = step(s, { type: 'cast', space: 'pond', place: FERN }, T + 120_000);
    const before = s.energy.value;
    const landed = applyP0(c, s, { type: 'reel', outcome: 'landed' }, T + 120_000 + s.cast!.bite_ms + 10);
    if (!landed.ok) throw new Error(landed.code);
    expect(landed.events).toContainEqual(expect.objectContaining({ kind: 'level', skill: 'fishing', level: 2, energy: 0 }));
    expect(landed.events.some(e => e.kind === 'energy')).toBe(false);
    expect(landed.state.energy.value).toBe(before);
  });

  it('first bonus stacks with base XP while repeated pots still obey daily 100/50/0 decay', () => {
    let s = fresh(); s.bag.push({ id: 'fish_crucian', qty: 5 });
    const earned: number[] = [];
    for (let i = 0; i < 3; i++) {
      const before = s.skills.cooking;
      s = goodDish(s, ['fish_crucian'], T + i * 10_000);
      earned.push(s.skills.cooking - before);
    }
    expect(earned).toEqual([15, 2, 0]);
    s = goodDish(s, ['fish_crucian'], T + 24 * 3_600_000);
    expect(s.skills.cooking).toBe(22); // next day: base Good 5, no first bonus
  });

  it("a pot's XP event says which pot of its page today it is, the 3rd with no XP included (q(94))", () => {
    let s = fresh(); s.bag.push({ id: 'fish_crucian', qty: 5 });
    const xp: unknown[] = [];
    for (let i = 0; i < 3; i++) {
      const at = T + i * 10_000;
      s = step(s, { type: 'cook', items: ['fish_crucian'] }, at);
      const pot = s.stove!, h = pot.heats[0];
      const r = applyP0(c, s, { type: 'collect', taps: [h.at + (h.gold + h.width / 2) * h.spin] }, at + pot.ms + 10);
      expect(r.ok).toBe(true);
      if (!r.ok) return;
      s = r.state;
      xp.push(r.events.filter(e => e.kind === 'xp' && e.skill === 'cooking' && !('first' in e)).at(-1));
    }
    expect(xp).toMatchObject([{ nth: 1 }, { amount: 2, nth: 2 }, { amount: 0, nth: 3 }]);
  });

  it('at high skill only the base XP is reduced; the first-cook award remains full', () => {
    let s = fresh(); s.skills.cooking = 220; // Lv4, Common content Lv1: 50%
    s.bag.push({ id: 'fish_crucian', qty: 1 });
    s = goodDish(s, ['fish_crucian']);
    expect(s.skills.cooking).toBe(232); // first 10 + floor((4 × 0.5) × 1.25)
  });

  it('a collected pot cannot give another dish or XP on retry', () => {
    let s = fresh(); s.bag.push({ id: 'fish_crucian', qty: 1 });
    s = goodDish(s, ['fish_crucian']);
    const saved = structuredClone(s);
    expect(applyP0(c, s, { type: 'collect' }, T + 10_000)).toMatchObject({ ok: false, code: 'stove_empty' });
    expect(s).toEqual(saved);
  });

  it('HTTP replay after a file-store restart does not duplicate a catch or its first awards', async () => {
    const dir = mkdtempSync(path.join(tmpdir(), 'p0-xp-'));
    const file = path.join(dir, 'state.json');
    let app = Fastify(); let now = T;
    const headers = { 'x-p0-player': 'progression-player' };
    try {
      const store = new P0Store(c, file);
      registerP0Routes(app, { content: c, store, now: () => now, dev: false });
      await app.inject({ method: 'POST', url: '/v1/p0/commands', headers, payload: { type: 'cast', space: 'pond', place: FERN } });
      now += store.get('progression-player', now).cast!.bite_ms + 10;
      const payload = { type: 'reel', outcome: 'landed' };
      const first = await app.inject({ method: 'POST', url: '/v1/p0/commands', headers, payload });
      expect(first.json().state.skills.fishing.xp).toBe(50);
      await app.close(); app = Fastify();
      registerP0Routes(app, { content: c, store: new P0Store(c, file), now: () => now, dev: false });
      const retry = await app.inject({ method: 'POST', url: '/v1/p0/commands', headers, payload });
      expect(retry.json()).toMatchObject({ ok: false, code: 'no_cast', state: { skills: { fishing: { xp: 50 } }, fishing: { caught: { fish_crucian: 1 } } } });
    } finally { await app.close(); rmSync(dir, { recursive: true, force: true }); }
  });
});

/**
 * §14.2.1 first-session Energy ledger after q(101) (SGODOT-262: Joey's 11 fish took Energy from 172 up to 188), step by step
 * with the real commands on a new account (Newcomer Blessing: +1 every 2:40). Seed 22 lands casts 5–6 as crucians, so
 * Fishing Lv2 comes on cast 6 at 70 XP and the perch takes it to 110, as in the director table (the cook draws from the
 * same seeded rolls, so another seed may land a Fine fish on cast 5 or 6). Spends 90, gets 90 back, lowest 143, ends full.
 */
describe('first-session Energy ledger (§14.2.1, q(101); SGODOT-262)', () => {
  it('casts cost 5 each all the way, Fishing Lv2 gives no Energy, both meals fit and the session ends at 200/200', () => {
    let s = freshState(c, 'ledger-player', T, 22);
    let t = T + 2 * 60_000;
    const period = regenMs(c, s, t);
    expect(period).toBe(160_000);
    const energyAt = (at: number) => viewOf(c, s, at).energy.value;
    const afterTicks = (n: number) => s.energy.tick_ms + n * period + 1_000;   // just past the n-th +1 from now
    const cast = (bait?: string) => {
      s = step(s, { type: 'cast', space: 'pond', place: FERN, ...(bait ? { bait } : {}) }, t);
      const r = applyP0(c, s, { type: 'reel', outcome: 'landed' }, t + s.cast!.bite_ms + 10);
      if (!r.ok) throw new Error(r.code);
      s = r.state;
      t += 10_000;
      return r.events;
    };
    const cookAndEat = (items: string[], dish: string) => {
      s = goodDish(s, items, t);
      const id = s.bag.find(x => x.id.startsWith(dish))!.id;
      t += 10_000;
      const r = applyP0(c, s, { type: 'eat', item: id }, t);
      if (!r.ok) throw new Error(r.code);
      s = r.state;
      return r.events.find(e => e.kind === 'meal') as { gain: number } | undefined;
    };

    expect(energyAt(t)).toBe(200);
    for (let i = 0; i < 20; i++) { s = step(s, { type: 'sow', plot: i, seed: 'seed_radish' }, t); t += 1_000; }
    expect(energyAt(t)).toBe(160);                                       // the first bed: 20 radishes, 2 each
    for (let i = 0; i < 3; i++) cast();
    expect(energyAt(t)).toBe(145);                                       // casts 1–3, all landed (pin 1: crucians)
    t = afterTicks(6);
    expect(energyAt(t)).toBe(151);                                       // +6 by minute 16 (blessing ×1.5)
    expect(cookAndEat(['fish_crucian'], 'dish_grilled_crucian')).toMatchObject({ gain: 25 });
    expect(energyAt(t)).toBe(176);                                       // Grilled Crucian, Good: 20 + 5
    for (let i = 20; i < 30; i++) { s = step(s, { type: 'till', plot: i }, t); s = step(s, { type: 'sow', plot: i, seed: 'seed_lettuce' }, t); t += 1_000; }
    expect(energyAt(t)).toBe(156);                                       // the second bed: 10 lettuce
    const pin2 = cast();
    expect(pin2).toContainEqual(expect.objectContaining({ kind: 'catch', result: 'broke_free', refund: 5 }));
    expect(energyAt(t)).toBe(156);                                       // cast 4: the Fine fish breaks free, refunded
    cast();
    const lv2 = cast();
    expect(energyAt(t)).toBe(146);                                       // casts 5–6
    expect(lv2).toContainEqual(expect.objectContaining({ kind: 'level', skill: 'fishing', level: 2, energy: 0 }));
    expect(lv2.some(e => e.kind === 'energy' && (e as { delta: number }).delta > 0)).toBe(false);   // q(101): nothing back
    t = afterTicks(2);
    expect(energyAt(t)).toBe(148);                                       // +2, minutes 17–22
    const perch = cast('bait_worm');
    expect(perch).toContainEqual(expect.objectContaining({ kind: 'catch', fish: 'fish_perch', result: 'landed' }));
    expect(perch).toContainEqual({ kind: 'energy', delta: 20, reason: 'reward' });
    expect(energyAt(t)).toBe(163);                                       // cast 7 −5 (143), first Fine fish +20
    t = afterTicks(2);
    expect(s.skills.fishing).toBe(110);                                  // 70 + perch 10 + its first-catch 30
    expect(energyAt(t)).toBe(165);                                       // +2, minutes 23–28
    expect(cookAndEat(['fish_crucian', 'wild_herb'], 'dish_herb_grilled_fish')).toMatchObject({ gain: 35 });
    expect(energyAt(t)).toBe(200);                                       // Herb Grilled Fish, Good 45, only up to max
  });
});
