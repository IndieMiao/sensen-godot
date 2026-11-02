import Fastify from 'fastify';
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { addPlots } from '../../src/p0/garden.js';
import { applyP0, count, type P0Command } from '../../src/p0/reducer.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { dayKey, levelFor, settleEnergy, xpPercent } from '../../src/p0/rules.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { P0Store } from '../../src/p0/store.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 5, 2, 0, 0); // 10:00 Shanghai
const MIN = 60_000, H = 3_600_000;

function run(s: P0State, cmd: P0Command, now = T0): P0State {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return r.state;
}
// A veteran account (past the 7-day Newcomer Blessing) so base rates are under test; the blessing has its own tests.
const fresh = () => ({ ...freshState(c, 'player-test-01', T0, 42), created_at: T0 - 8 * 24 * H });

describe('P0 energy (§3.1.1)', () => {
  it('regenerates +1 per 4 minutes, caps at max, and holds the timer while full', () => {
    const s = fresh();
    s.energy = { value: 190, tick_ms: T0 };
    settleEnergy(c, s, T0 + 4 * MIN + 30_000);
    expect(s.energy.value).toBe(191);
    expect(s.energy.tick_ms).toBe(T0 + 4 * MIN);
    settleEnergy(c, s, T0 + 3 * 24 * H);
    expect(s.energy.value).toBe(200);
    expect(s.energy.tick_ms).toBe(T0 + 3 * 24 * H);
  });
  it('a spend at full starts a fresh 4-minute period from the spend', () => {
    let s = fresh();
    s = run(s, { type: 'sow', plot: 0, seed: 'seed_radish' }, T0 + 10 * MIN);
    expect(s.energy.value).toBe(198);
    expect(viewOf(c, s, T0 + 10 * MIN).energy.next_in).toBe(4 * MIN);
    expect(viewOf(c, s, T0 + 14 * MIN).energy.value).toBe(199);
  });
  it('refuses with need / have / next +1 when short', () => {
    const s = fresh();
    s.energy = { value: 1, tick_ms: T0 - MIN };
    const r = applyP0(c, s, { type: 'sow', plot: 0, seed: 'seed_radish' }, T0);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r).toMatchObject({ code: 'need_energy', detail: { need: 2, have: 1, next_in: 3 * MIN } });
  });
});

describe('P0 levels and XP (§4.2.1 / §4.5)', () => {
  it('maps cumulative XP to levels and level gaps to percentages', () => {
    expect(levelFor(c.skills.farming, 49)).toBe(1);
    expect(levelFor(c.skills.farming, 50)).toBe(2);
    expect(levelFor(c.skills.farming, 412)).toBe(4);
    expect([1, 2, 3, 4, 5, 6].map(lv => xpPercent(c, lv, 1))).toEqual([100, 100, 75, 50, 25, -1]);
  });
});

describe('P0 farming loop (§5.3 / §5.4.1)', () => {
  it('sow costs the tier energy and a seed; water starts growth; harvest pays XP + first-harvest bonus', () => {
    let s = fresh();
    s = run(s, { type: 'sow', plot: 3, seed: 'seed_radish' });
    expect(s.energy.value).toBe(198);
    expect(count(s.bag, 'seed_radish')).toBe(11);   // the start bag's 12 (q(217) ②, v4q(4) ⑥ 戊1)
    expect(s.plots[3]).toMatchObject({ state: 'sown', crop: 'crop_radish', xp_pct: 100 });
    expect(applyP0(c, s, { type: 'harvest', plot: 3 }, T0).ok).toBe(false);
    s = run(s, { type: 'water', plot: 3 });
    expect(s.plots[3].ready_at).toBe(T0 + 4 * H);
    const early = applyP0(c, s, { type: 'harvest', plot: 3 }, T0 + 3 * H);
    expect(early).toMatchObject({ ok: false, code: 'not_ready' });
    const r = applyP0(c, s, { type: 'harvest', plot: 3 }, T0 + 4 * H);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(count(r.state.bag, 'crop_radish')).toBe(1);
    expect(r.state.skills.farming).toBe(2 + 10);
    expect(r.state.plots[3].state).toBe('tilled');
    expect(r.events).toContainEqual({ kind: 'first', what: 'harvest:crop_radish', xp: 10 });
  });

  it('20 radishes reach Farming Lv2 with 5 carrot seeds and no Energy (§4.5, §5.3, q(101))', () => {
    // SGODOT-355 b1: a new homestead has 8 Plots; Homestead Lv7 has the 20 this ledger counts (the first session's own
    // ledger is v4's, calibrated by Li Bai)
    let s = fresh();
    s.homestead.level = 7;
    addPlots(c, s);
    s.bag.find(x => x.id === 'seed_radish')!.qty = 20;   // the start bag has 12 now (v4q(4) ⑥ 戊1); this ledger sows 20
    for (let i = 0; i < 20; i++) { s = run(s, { type: 'sow', plot: i, seed: 'seed_radish' }); s = run(s, { type: 'water', plot: i }); }
    expect(s.energy.value).toBe(160);
    let levelEvent: unknown;
    for (let i = 0; i < 20; i++) {
      const r = applyP0(c, s, { type: 'harvest', plot: i }, T0 + 4 * H);
      if (!r.ok) throw new Error(r.code);
      s = r.state;
      levelEvent ??= r.events.find(e => e.kind === 'level');
    }
    expect(s.skills.farming).toBe(50);
    expect(levelEvent).toMatchObject({ kind: 'level', skill: 'farming', level: 2, energy: 0 });
    expect(s.energy.value).toBe(160 + 60);   // 4 h of regeneration under Lv7's 260; the level added nothing (q(101))
    expect(count(s.bag, 'seed_carrot')).toBe(5);
    expect(count(s.bag, 'crop_radish')).toBe(20);
  });

  it('locks the XP percentage at sowing time', () => {
    let s = fresh();
    s.skills.farming = 500; // Lv5: radish (content Lv1) is d = 4 → 25 %
    s = run(s, { type: 'sow', plot: 0, seed: 'seed_radish' });
    expect(s.plots[0].xp_pct).toBe(25);
    s.skills.farming = 2800; // levelling later does not change the locked percentage
    s = run(s, { type: 'water', plot: 0 });
    expect(s.plots[0].xp_pct).toBe(25);
  });

  it('tills wild ground for free and refuses sowing on it (only a save from before SGODOT-355 b1 has any)', () => {
    let s = fresh();
    s.plots[5] = { id: 5, state: 'wild' };
    expect(applyP0(c, s, { type: 'sow', plot: 5, seed: 'seed_radish' }, T0)).toMatchObject({ ok: false, code: 'wrong_state' });
    s = run(s, { type: 'till', plot: 5 });
    expect(s.plots[5].state).toBe('tilled');
    expect(s.energy.value).toBe(200);
  });
});

describe('P0 stall (§9.11.1 / §9.13.1)', () => {
  it('gates seeds by Farming level with the XP still needed, then sells them', () => {
    let s = fresh();
    expect(applyP0(c, s, { type: 'buy', item: 'seed_carrot', qty: 2 }, T0)).toMatchObject({ ok: false, code: 'locked', detail: { level: 2, xp_to_go: 50 } });
    s = run(s, { type: 'buy', item: 'seed_radish', qty: 10 });
    expect(s.coins).toBe(180 - 40);
    expect(count(s.bag, 'seed_radish')).toBe(22);   // 12 to start (v4q(4) ⑥ 戊1) + 10
    s.skills.farming = 50;
    s = run(s, { type: 'buy', item: 'seed_carrot', qty: 2 });
    expect(s.coins).toBe(140 - 18);
  });
  it('buys produce at full price with no quota and refuses seeds', () => {
    let s = fresh();
    s.bag.push({ id: 'crop_radish', qty: 12 });
    s = run(s, { type: 'sell', item: 'crop_radish', qty: 12 });
    expect(s.coins).toBe(180 + 60);
    expect(applyP0(c, s, { type: 'sell', item: 'seed_radish', qty: 1 }, T0)).toMatchObject({ ok: false, code: 'not_sellable' });
  });
  it('refuses when the bag has no room', () => {
    const s = fresh();
    s.bag = Array.from({ length: c.bag.capacity }, (_, i) => ({ id: `material_${i}`, qty: 99 }));
    expect(applyP0(c, s, { type: 'buy', item: 'seed_lettuce', qty: 5 }, T0)).toMatchObject({ ok: false, code: 'bag_full' });
  });
});

describe('P0 rest and player day (§3.4.3 / §3.1.1)', () => {
  it('rests once per player day, only up to max, and resets at 04:00', () => {
    let s = fresh();
    expect(applyP0(c, s, { type: 'rest' }, T0)).toMatchObject({ ok: false, code: 'energy_full' });
    s.energy = { value: 100, tick_ms: T0 };
    s = run(s, { type: 'rest' });
    expect(s.energy.value).toBe(160);
    expect(applyP0(c, s, { type: 'rest' }, T0 + H)).toMatchObject({ ok: false, code: 'rest_used' });
    const nextDay = T0 + 18 * H + MIN; // past 04:00 Shanghai
    expect(dayKey(c, null, nextDay)).not.toBe(dayKey(c, null, T0));
    s.energy = { value: 50, tick_ms: nextDay };
    expect(applyP0(c, s, { type: 'rest' }, nextDay).ok).toBe(true);
  });
});

describe('P0 routes', () => {
  it('serves state, applies commands, and skips time in dev', async () => {
    let now = T0;
    const app = Fastify();
    registerP0Routes(app, { content: c, store: new P0Store(c), now: () => now, dev: true });
    const headers = { 'x-p0-player': 'emulator-player-1' };
    const st = await app.inject({ method: 'GET', url: '/v1/p0/state', headers });
    expect(st.json()).toMatchObject({ ok: true, state: { coins: 180, energy: { value: 200, max: 200 } } });
    const sow = await app.inject({ method: 'POST', url: '/v1/p0/commands', headers, payload: { type: 'sow', plot: 0, seed: 'seed_radish' } });
    expect(sow.json()).toMatchObject({ ok: true, events: [{ kind: 'energy', delta: -2 }, { kind: 'item', id: 'seed_radish', delta: -1 }] });
    await app.inject({ method: 'POST', url: '/v1/p0/commands', headers, payload: { type: 'water', plot: 0 } });
    const skip = await app.inject({ method: 'POST', url: '/v1/p0/dev/skip', headers, payload: { minutes: 240 } });
    expect(skip.json().state.plots[0]).toMatchObject({ state: 'ready', crop: 'crop_radish' });
    const bad = await app.inject({ method: 'GET', url: '/v1/p0/state', headers: { 'x-p0-player': 'x' } });
    expect(bad.statusCode).toBe(400);
    now += 1;
    await app.close();
  });
});
