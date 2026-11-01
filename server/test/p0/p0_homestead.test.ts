import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, count, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { maxEnergy, foodCap } from '../../src/p0/rules.js';
import { freshState, upgradeState, type P0State, SAVE_VERSION } from '../../src/p0/state.js';
import { haveTotal, takeStorageFirst } from '../../src/p0/storage.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 8, 2, 0, 0); // 10:00 Shanghai
const H = 3_600_000;

function step(s: P0State, cmd: P0Command, now = T0): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return { s: r.state, ev: r.events };
}
/** Past the Newcomer Blessing so meals and regen are the base numbers. */
const fresh = () => ({ ...freshState(c, 'player-home-01', T0, 7), created_at: T0 - 8 * 24 * H });
/** XP at a skill's level (content skills: [level − 1] is where it starts). */
const xp = (skill: 'farming' | 'fishing' | 'cooking', level: number) => c.skills[skill][level - 1];
/** v4q(1) ②③: Lv2 1 / 1 and wood 6, stone 4, reeds 3, 40 coins; Lv3 2 / 1 and stone 8, wood 4, clay 2, 60 coins. */
const LV2_SKILLS = { farming: 0, fishing: 0, cooking: 0 };
const LV3_SKILLS = { farming: xp('farming', 2), fishing: 0, cooking: 0 };
const LV2_MATS: Record<string, number> = { wood: 6, stone: 4, fiber: 3 };
const LV3_MATS: Record<string, number> = { stone: 8, wood: 4, clay: 2 };

function ready(level: 2 | 3): P0State {
  const s = fresh();
  s.skills = { ...(level === 2 ? LV2_SKILLS : LV3_SKILLS) };
  s.storage = { ...(level === 2 ? LV2_MATS : LV3_MATS) };
  s.coins = (level === 2 ? 40 : 60) + 40;
  if (level === 3) s.homestead.level = 2;
  return s;
}

describe('Homestead batch 1 (v4q(1)): Lv1–3', () => {
  it('a new homestead is Lv1 of 17: 200 Energy, 200 meals, 2 Stall Board slots, 8 Plots of 41, nothing unlocked', () => {
    const v = viewOf(c, fresh(), T0);
    expect(v.homestead).toMatchObject({ level: 1, max: 17, plots: { now: 8, max: 41 },
      unlocks: { spice_rack: false, warming_cabinet: false, bag_upgrade_1: 'locked', board_slots: 2, stoves: 1, cabinet: 0 } });
    expect(v.energy.max).toBe(200);
    expect(v.meals.cap).toBe(200);
    expect(v.bag.capacity).toBe(25);
  });

  it('Lv2 takes 40 coins and three materials, gives 50 Energy back and unlocks the Spice Rack', () => {
    const s = ready(2);
    s.energy = { value: 120, tick_ms: T0 };
    const { s: after, ev } = step(s, { type: 'homestead_upgrade' });
    expect(after.homestead.level).toBe(2);
    expect(after.coins).toBe(40);
    expect(after.storage).toEqual({});
    expect(after.energy.value).toBe(170);
    expect(maxEnergy(c, after)).toBe(210);
    expect(foodCap(c, after, T0)).toBe(210);
    expect(after.homestead.plaque).toEqual([{ level: 2, at: T0 }]);
    expect(ev).toContainEqual({ kind: 'homestead', level: 2, energy: 50, unlocks: ['spice_rack'] });
    expect(ev).toContainEqual({ kind: 'item', id: 'wood', delta: -6 });
    const v = viewOf(c, after, T0);
    expect(v.homestead.unlocks).toMatchObject({ spice_rack: true, warming_cabinet: false, bag_upgrade_1: 'locked', board_slots: 2 });
  });

  it('Lv3 unlocks the Warming Cabinet, Bag Upgrade I for sale, a third Stall Board slot, the fence and Pip\'s first dive', () => {
    const { s, ev } = step(ready(3), { type: 'homestead_upgrade' });
    expect(s.homestead.level).toBe(3);
    expect(maxEnergy(c, s)).toBe(220);
    expect(ev).toContainEqual(expect.objectContaining({ kind: 'homestead', level: 3,
      unlocks: ['bag_upgrade_1', 'warming_cabinet', 'board_slot_3', 'fence', 'pip_first_dive'] }));
    const v = viewOf(c, s, T0);
    expect(v.homestead.unlocks).toMatchObject({ spice_rack: true, warming_cabinet: true, bag_upgrade_1: 'for_sale', board_slots: 3, fence: true,
      stoves: 1, big_pot: false, notice_board: false, chefs_sign: false, cabinet: 6, bag_upgrade_2: 'locked', bag_upgrade_3: 'locked', bag_upgrade_4: 'locked' });
    expect(v.homestead.next).toMatchObject({ level: 4, unlocks: ['second_stove', 'healing_potion'], plots: 14, energy_gain: 50 });
  });

  it('refuses with the first gap in button order: each skill (Farming → Fishing → Cooking), then materials, then coins', () => {
    let s = ready(3);
    s.skills = { farming: 0, fishing: 0, cooking: 900 };
    expect(applyP0(c, s, { type: 'homestead_upgrade' }, T0)).toMatchObject({ ok: false, code: 'skills_short', detail: { skill: 'farming', need: 2, have: 1 } });
    s = ready(3);
    s.homestead.level = 3;   // Lv4: 2 / 2
    s.skills = { farming: xp('farming', 2), fishing: 0, cooking: 0 };
    expect(applyP0(c, s, { type: 'homestead_upgrade' }, T0)).toMatchObject({ ok: false, code: 'skills_short', detail: { skill: 'fishing', need: 2, have: 1 } });
    s.homestead.level = 5;   // Lv6: 3 / 3 / 2 — Cooking from Lv6
    s.skills = { farming: xp('farming', 3), fishing: xp('fishing', 3), cooking: 0 };
    expect(applyP0(c, s, { type: 'homestead_upgrade' }, T0)).toMatchObject({ ok: false, code: 'skills_short', detail: { skill: 'cooking', need: 2, have: 1 } });
    s = ready(2);
    s.storage.stone = 3;
    expect(applyP0(c, s, { type: 'homestead_upgrade' }, T0)).toMatchObject({ ok: false, code: 'need_material', detail: { item: 'stone', need: 4, have: 3 } });
    s = ready(2);
    s.coins = 60; // 40 + 40 floor = 80
    expect(applyP0(c, s, { type: 'homestead_upgrade' }, T0)).toMatchObject({ ok: false, code: 'no_coins', detail: { need: 20 } });
  });

  it('from Lv16 the travel gate comes after the skills: city stamps, then other climate bands (v4q(1) ④)', () => {
    const s = fresh();
    s.homestead.level = 15;
    s.skills = { farming: xp('farming', 6), fishing: xp('fishing', 7), cooking: xp('cooking', 8) };
    s.coins = 1000;
    s.storage = { hardwood: 13, flax: 9, iron_ore: 4, quartz: 2 };
    const block = () => applyP0(c, s, { type: 'homestead_upgrade' }, T0);
    expect(block()).toMatchObject({ ok: false, code: 'travel_short', detail: { kind: 'stamps', need: 6, have: 0 } });
    const day = '2026-10-08';
    s.travel.stamps = ['c1', 'c2', 'c3', 'c4', 'c5', 'wd-w1', 'c6'].map(cluster => ({ cluster, kind: 'climate' as const, at: T0, counted_on: day }));
    expect(viewOf(c, s, T0).homestead.next).toMatchObject({ level: 16, travel: { stamps: { need: 6, have: 6 }, climates: { need: 1, have: 0 } },
      energy_gain: 0, plots: 39 });
    expect(block()).toMatchObject({ ok: false, code: 'travel_short', detail: { kind: 'climates', need: 1, have: 0 } });
    // an arrival in another band counts once; home's own band (Beijing, temperate as San Francisco) never does
    const visit = { n: 1, first_at: T0, last_at: T0, deliveries: 0, delivered_day: '' };
    s.travel.visits = { 'gn-1816670': visit, 'gn-1809858': visit, 'gn-1796236': visit };   // Beijing, Guangzhou, Shanghai
    expect(viewOf(c, s, T0).homestead.next!.travel!.climates).toEqual({ need: 1, have: 2 });
    expect(block()).toMatchObject({ ok: true });
  });

  it('every level\'s energy is a number: a missing one stops the content from loading (v4q(1) 复核 ③)', async () => {
    const { checkHomestead } = await import('../../src/p0/content.js');
    const bad = structuredClone(c);
    delete (bad.homestead.levels[14] as { energy?: number }).energy;
    expect(() => checkHomestead(bad)).toThrow(/Lv16: energy must be a number/);
    expect(() => checkHomestead(c)).not.toThrow();
  });

  it('a refused upgrade changes nothing (atomic)', () => {
    const s = ready(2);
    s.coins = 79;
    const r = applyP0(c, s, { type: 'homestead_upgrade' }, T0);
    expect(r.ok).toBe(false);
    expect(s.storage).toEqual(LV2_MATS);
    expect(s.homestead.level).toBe(1);
  });

  it('only at home: refused from the pond and from the map after it, fine once back home (§8.1.1 ①)', () => {
    const s = ready(2);
    const away = applyP0(c, s, { type: 'homestead_upgrade', space: 'pond' }, T0);
    expect(away.ok).toBe(false);
    if (!away.ok) expect(away.code).toBe('not_home');
    const left = structuredClone(s);
    left.presence = { ...left.presence, space: 'away', left_at: T0 - H };   // last seen at the pond
    const map = applyP0(c, left, { type: 'homestead_upgrade', space: 'map' }, T0);
    expect(map.ok).toBe(false);
    expect(step(s, { type: 'homestead_upgrade', space: 'home' }).s.homestead.level).toBe(2);
    expect(step(s, { type: 'homestead_upgrade' }).s.homestead.level).toBe(2);   // a save that never left
  });

  it('materials come from storage first, then the bag; gift meals never count', () => {
    const s = ready(2);
    s.storage.wood = 5;
    s.bag.push({ id: 'wood', qty: 9 });
    expect(haveTotal(s, 'wood')).toBe(14);
    const { s: after } = step(s, { type: 'homestead_upgrade' });
    expect(after.storage.wood).toBeUndefined();
    expect(count(after.bag, 'wood')).toBe(8);
    const t = fresh();
    t.storage.wood = 3;
    t.bag.push({ id: 'wood', qty: 4 });
    expect(takeStorageFirst(t, 'wood', 5)).toEqual({ storage: 3, bag: 2 });
  });

  it('keeps a bonus-zone Energy value above the new max', () => {
    const s = ready(2);
    s.energy = { value: 230, tick_ms: T0 };
    const { s: after, ev } = step(s, { type: 'homestead_upgrade' });
    expect(after.energy.value).toBe(230);
    expect(ev).toContainEqual({ kind: 'homestead', level: 2, energy: 0, unlocks: ['spice_rack'] });
  });

  it('the view lists what the next level needs, with storage and bag shown apart', () => {
    const s = fresh();
    s.storage = { wood: 10 };
    s.bag.push({ id: 'wood', qty: 1 });
    const next = viewOf(c, s, T0).homestead.next!;
    expect(next.level).toBe(2);
    expect(next.coins).toEqual({ need: 80, have: 180 });
    expect(next.skills).toEqual([{ skill: 'farming', need: 1, have: 1 }, { skill: 'fishing', need: 1, have: 1 }]);   // no Cooking gate before Lv6
    expect(next).toMatchObject({ energy: 210, meals: 210, energy_gain: 50, plots: 10, travel: null });
    expect(next.materials[0]).toEqual({ id: 'wood', name: 'Timber', need: 6, have: 11, storage: 10, bag: 1 });
    expect(next.can_upgrade).toBe(false);
    expect(next.block).toMatchObject({ code: 'need_material' });
  });

  it('the Profile page reads the homestead level and the account start (SGODOT-225)', () => {
    const s = fresh();
    s.homestead.level = 2;
    expect(viewOf(c, s, T0).profile).toEqual({ name: 'Farmer', city: 'San Francisco', climate: 'Temperate', since_ms: s.created_at,
      farm: { name: "Farmer's Homestead", level: 2 } });
  });

  it('v2 saves gain Homestead Lv1, storage and the boards; the tutorial request keeps its status', () => {
    const old = fresh() as unknown as Record<string, unknown>;
    for (const k of ['bag_cap', 'storage', 'locked', 'owned', 'homestead', 'residents', 'boards']) delete old[k];
    old.v = 2;
    (old.requests as { status: string }[])[0].status = 'accepted';
    (old.gear as Record<string, unknown>).hoes = undefined;
    const s = upgradeState(c, old as unknown as P0State, T0);
    expect(s.v).toBe(SAVE_VERSION);
    expect(s.homestead.level).toBe(1);
    expect(s.bag_cap).toBe(25);
    expect(s.boards.stall[0].req).toMatchObject({ id: 'req_pond_catch', status: 'accepted', qty: 2, drawn_at: old.created_at });
    expect(s.gear.hoe).toBe('hoe_starter');
  });
});

describe('dev grant (playtests only)', () => {
  it('puts materials in storage or the bag and refuses unknown ids', async () => {
    const { default: Fastify } = await import('fastify');
    const { registerP0Routes } = await import('../../src/p0/routes.js');
    const { P0Store } = await import('../../src/p0/store.js');
    const app = Fastify();
    registerP0Routes(app, { content: c, store: new P0Store(c), now: () => T0, dev: true });
    const headers = { 'x-p0-player': 'player-grant-01', 'content-type': 'application/json' };
    const a = await app.inject({ method: 'POST', url: '/v1/p0/dev/grant', headers, payload: { id: 'wood', qty: 12, to: 'storage' } });
    expect(a.json().state.storage.items).toEqual([{ id: 'wood', name: 'Timber', qty: 12 }]);
    const b = await app.inject({ method: 'POST', url: '/v1/p0/dev/grant', headers, payload: { id: 'clay', qty: 4 } });
    expect(b.json().state.bag.slots).toContainEqual({ id: 'clay', qty: 4, locked: false, gifted: false });
    const bad = await app.inject({ method: 'POST', url: '/v1/p0/dev/grant', headers, payload: { id: 'gold_bar', qty: 1 } });
    expect(bad.statusCode).toBe(400);
  });
});
