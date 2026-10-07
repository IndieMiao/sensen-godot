import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, count, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { maxEnergy, foodCap } from '../../src/p0/rules.js';
import { freshState, upgradeState, type P0State } from '../../src/p0/state.js';
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
/** Farming Lv2 + Fishing Lv1 = 3 (Lv2 gate); Farming Lv3 + Fishing Lv2 = 5 (Lv3 gate). */
const LV2_SKILLS = { farming: 50, fishing: 0, cooking: 0 };
const LV3_SKILLS = { farming: 150, fishing: 70, cooking: 0 };
const LV2_MATS: Record<string, number> = { wood: 12, stone: 8, fiber: 6, rock_salt: 3 };
const LV3_MATS: Record<string, number> = { wood: 16, stone: 12, fiber: 10, clay: 4, rock_salt: 4 };

function ready(level: 2 | 3): P0State {
  const s = fresh();
  s.skills = { ...(level === 2 ? LV2_SKILLS : LV3_SKILLS) };
  s.storage = { ...(level === 2 ? LV2_MATS : LV3_MATS) };
  s.coins = (level === 2 ? 250 : 400) + 40;
  if (level === 3) s.homestead.level = 2;
  return s;
}

describe('Homestead Lv1–3 (§8.1–8.3)', () => {
  it('a new homestead is Lv1: 200 Energy, 200 meals, 2 Stall Board slots, nothing unlocked', () => {
    const v = viewOf(c, fresh(), T0);
    expect(v.homestead).toMatchObject({ level: 1, max: 3, unlocks: { spice_rack: false, warming_cabinet: false, bag_upgrade_1: 'locked', board_slots: 2 } });
    expect(v.energy.max).toBe(200);
    expect(v.meals.cap).toBe(200);
    expect(v.bag.capacity).toBe(25);
  });

  it('Lv2 takes 250 coins and the four materials, refills Energy to 210 and unlocks the Spice Rack', () => {
    const s = ready(2);
    s.energy = { value: 120, tick_ms: T0 };
    const { s: after, ev } = step(s, { type: 'homestead_upgrade' });
    expect(after.homestead.level).toBe(2);
    expect(after.coins).toBe(40);
    expect(after.storage).toEqual({});
    expect(after.energy.value).toBe(210);
    expect(maxEnergy(c, after)).toBe(210);
    expect(foodCap(c, after, T0)).toBe(210);
    expect(after.homestead.plaque).toEqual([{ level: 2, at: T0 }]);
    expect(ev).toContainEqual({ kind: 'homestead', level: 2, energy: 90, unlocks: ['spice_rack'] });
    expect(ev).toContainEqual({ kind: 'item', id: 'wood', delta: -12 });
    const v = viewOf(c, after, T0);
    expect(v.homestead.unlocks).toMatchObject({ spice_rack: true, warming_cabinet: false, bag_upgrade_1: 'locked', board_slots: 2 });
  });

  it('Lv3 unlocks the Warming Cabinet, Bag Upgrade I for sale, a third Stall Board slot and the full fence', () => {
    const { s } = step(ready(3), { type: 'homestead_upgrade' });
    expect(s.homestead.level).toBe(3);
    expect(maxEnergy(c, s)).toBe(220);
    const v = viewOf(c, s, T0);
    expect(v.homestead.unlocks).toEqual({ spice_rack: true, warming_cabinet: true, bag_upgrade_1: 'for_sale', board_slots: 3, fence: true });
    expect(v.homestead.next).toBeNull();
    expect(applyP0(c, s, { type: 'homestead_upgrade' }, T0)).toMatchObject({ ok: false, code: 'max_level' });
  });

  it('refuses with the first gap in button order: skills, then materials, then coins (40-coin floor included)', () => {
    let s = ready(2);
    s.skills = { farming: 0, fishing: 0, cooking: 900 }; // Cooking is not counted (§8.1.1)
    expect(applyP0(c, s, { type: 'homestead_upgrade' }, T0)).toMatchObject({ ok: false, code: 'skills_short', detail: { need: 3, have: 2 } });
    s = ready(2);
    s.storage.stone = 5;
    expect(applyP0(c, s, { type: 'homestead_upgrade' }, T0)).toMatchObject({ ok: false, code: 'need_material', detail: { item: 'stone', need: 8, have: 5 } });
    s = ready(2);
    s.coins = 270; // 250 + 40 floor = 290
    expect(applyP0(c, s, { type: 'homestead_upgrade' }, T0)).toMatchObject({ ok: false, code: 'no_coins', detail: { need: 20 } });
  });

  it('a refused upgrade changes nothing (atomic)', () => {
    const s = ready(2);
    s.coins = 100;
    const r = applyP0(c, s, { type: 'homestead_upgrade' }, T0);
    expect(r.ok).toBe(false);
    expect(s.storage).toEqual(LV2_MATS);
    expect(s.homestead.level).toBe(1);
  });

  it('materials come from storage first, then the bag; gift meals never count', () => {
    const s = ready(2);
    s.storage.wood = 5;
    s.bag.push({ id: 'wood', qty: 9 });
    expect(haveTotal(s, 'wood')).toBe(14);
    const { s: after } = step(s, { type: 'homestead_upgrade' });
    expect(after.storage.wood).toBeUndefined();
    expect(count(after.bag, 'wood')).toBe(2);
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
    expect(next.coins).toEqual({ need: 290, have: 180 });
    expect(next.skills).toEqual({ need: 3, have: 2, farming: 1, fishing: 1 });
    expect(next.materials[0]).toEqual({ id: 'wood', name: 'Timber', need: 12, have: 11, storage: 10, bag: 1 });
    expect(next.can_upgrade).toBe(false);
    expect(next.block).toMatchObject({ code: 'skills_short' });
  });

  it('the Profile page reads the homestead level and the account start (SGODOT-225)', () => {
    const s = fresh();
    s.homestead.level = 2;
    expect(viewOf(c, s, T0).profile).toEqual({ name: 'Farmer', city: 'Shanghai', climate: 'Subtropical', since_ms: s.created_at,
      farm: { name: "Farmer's Homestead", level: 2 } });
  });

  it('v2 saves gain Homestead Lv1, storage and the boards; the tutorial request keeps its status', () => {
    const old = fresh() as unknown as Record<string, unknown>;
    for (const k of ['bag_cap', 'storage', 'locked', 'owned', 'homestead', 'residents', 'boards']) delete old[k];
    old.v = 2;
    (old.requests as { status: string }[])[0].status = 'accepted';
    (old.gear as Record<string, unknown>).hoes = undefined;
    const s = upgradeState(c, old as unknown as P0State, T0);
    expect(s.v).toBe(3);
    expect(s.homestead.level).toBe(1);
    expect(s.bag_cap).toBe(25);
    expect(s.boards.stall[0].req).toMatchObject({ id: 'req_pond_catch', status: 'accepted', qty: 2 });
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
