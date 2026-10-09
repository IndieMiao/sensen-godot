import Fastify from 'fastify';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { P0Store } from '../../src/p0/store.js';

const c = loadP0Content();
const T = Date.UTC(2026, 9, 5, 2);
function step(s: P0State, cmd: P0Command, at = T, content = c) {
  const r = applyP0(content, s, cmd, at);
  if (!r.ok) throw new Error(r.code);
  return r.state;
}
const REED = 'pond_shanghai_05', PEBBLE = 'pond_shanghai_04';
const fresh = () => freshState(c, 'progression-player', T, 7);
/** Enter a pond (space + place, q(36)) and land one fish there. */
function catchFish(s: P0State, place = REED, at = T, content = c) {
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
    expect(s.firsts).toContain('fishing_city:shanghai');
    s = catchFish(s, PEBBLE, T + 60_000);
    expect(s.skills.fishing).toBe(55);
  });

  it('takes the city from the server pond table, ignoring a forged site or city in the command', () => {
    let s = step(fresh(), { type: 'cast', space: 'pond', place: REED, site: 'river', city: 'invented' } as P0Command);
    expect(s.cast).toMatchObject({ site: 'pond', place: REED });
    s = step(s, { type: 'reel', outcome: 'landed' }, T + s.cast!.bite_ms + 10);
    expect(s.firsts.filter(f => f.startsWith('fishing_city:'))).toEqual(['fishing_city:shanghai']);
    const other = structuredClone(c);
    other.fishing.places[PEBBLE].city = 'test-other-city';
    s.presence.place = PEBBLE;   // entered before the table changed
    s = step(s, { type: 'cast' }, T + 60_000, other);
    s = step(s, { type: 'reel', outcome: 'landed' }, T + 60_000 + s.cast!.bite_ms + 10, other);
    expect(s.skills.fishing).toBe(65);
    expect(s.firsts).toContain('fishing_city:test-other-city');
  });

  it('cancel and escape do not grant city/landing XP; first-cast bonus cannot be repeated', () => {
    let s = step(fresh(), { type: 'cast', space: 'pond', place: REED });
    s = step(s, { type: 'reel', outcome: 'cancel' }, T + 10);
    expect(s.skills.fishing).toBe(10);
    expect(s.firsts).not.toContain('fishing_city:shanghai');
    s = step(s, { type: 'cast' }, T + 100);
    s = step(s, { type: 'reel', outcome: 'escaped' }, T + 100 + s.cast!.bite_ms + 10);
    expect(s.skills.fishing).toBe(10);
    expect(s.firsts).not.toContain('landed');
    s = catchFish(s, REED, T + 60_000);
    expect(s.skills.fishing).toBe(50);
  });

  it('two first Good dishes give 15 + 30 Cooking XP and unlock the Lv2 soup recipe', () => {
    let s = fresh();
    s.bag.push({ id: 'fish_crucian', qty: 3 }, { id: 'crop_herb', qty: 2 });
    s = goodDish(s, ['fish_crucian']);
    expect(s.skills.cooking).toBe(15);
    s = goodDish(s, ['fish_crucian', 'crop_herb'], T + 20_000);
    expect(s.skills.cooking).toBe(45);
    expect(s.cookbook).toContain('dish_fish_soup');
    expect(s.inbox.granted.filter(k => k === 'level:cooking:2')).toHaveLength(1);
    expect(s.skills.farming).toBe(0);
    expect(s.skills.fishing).toBe(0);
  });

  it('a Cooking level gives no Energy and leaves the first-level +50 for Farming / Fishing (q(37))', () => {
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
    s = catchFish(done.state, REED, T + 60_000);
    s.skills.fishing = 69;
    s = catchFish(s, REED, T + 120_000);
    expect(s.rewards).toContain('levelup_first');
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
      await app.inject({ method: 'POST', url: '/v1/p0/commands', headers, payload: { type: 'cast', space: 'pond', place: REED } });
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
