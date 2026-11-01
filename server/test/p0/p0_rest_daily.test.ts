import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 8, 1, 0, 0); // 09:00 Shanghai
const H = 3_600_000, MIN = 60_000;

function run(s: P0State, cmd: P0Command, now: number): P0State {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code}`);
  return r.state;
}
const tired = () => { const s = freshState(c, 'player-rest-01', T0, 4); s.energy = { value: 100, tick_ms: T0 }; return s; };
const rest = (s: P0State, now: number) => applyP0(c, s, { type: 'rest', space: 'home' }, now);
const ping = (space: string): P0Command => ({ type: 'equip', item: 'rod_starter', space });   // any accepted command

describe('Rest: once a player day, at home; no 2 h away first (q(269), SGODOT-377)', () => {
  it('a new player who has not left home rests at once; the view has no away countdown', () => {
    let s = tired();
    s = run(s, ping('home'), T0);
    const r = rest(s, T0 + MIN);
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.state).toMatchObject({ day: { rest: 1 }, energy: { value: 160 } });
    expect(viewOf(c, s, T0).rest).toEqual({ used: 0, limit: 1, resets_in: expect.any(Number), amount: 60 });
  });

  it('back home 3 min after a trip out (Joey, 11-01: "always 1h 57m"): rests at once; trips do not restart anything', () => {
    let s = tired();
    s = run(s, ping('home'), T0);
    s = run(s, ping('pond'), T0 + 30 * MIN);
    s = run(s, ping('home'), T0 + 33 * MIN);
    s = run(s, ping('outpost'), T0 + 35 * MIN);
    s = run(s, ping('home'), T0 + 37 * MIN);
    expect(rest(s, T0 + 37 * MIN).ok).toBe(true);
  });

  it('only at home: from the pond, an outpost or the mine it is refused not_home', () => {
    let s = tired();
    s = run(s, ping('pond'), T0);
    for (const space of ['pond', 'outpost', 'mine']) {
      expect(applyP0(c, s, { type: 'rest', space }, T0 + MIN)).toMatchObject({ ok: false, code: 'not_home' });
    }
  });

  it('once a player day: a second rest is rest_used until the 04:00 reset; Energy full is still refused', () => {
    let s = tired();
    s = run(s, { type: 'rest', space: 'home' }, T0);
    expect(rest(s, T0 + H)).toMatchObject({ ok: false, code: 'rest_used' });
    s.energy = { value: 100, tick_ms: T0 + 20 * H };
    expect(rest(s, T0 + 20 * H).ok).toBe(true);   // 09:00 → the next day's 05:00, past the 04:00 reset
    const full = tired();
    full.energy = { value: 200, tick_ms: T0 };
    expect(rest(full, T0)).toMatchObject({ ok: false, code: 'energy_full' });
  });

  it('a save from before q(269) that left home a minute ago (left_at kept, unread) rests at once; no space still works', () => {
    let s = tired();
    s.presence = { ...s.presence, left_at: T0 - MIN, last_at: T0 - MIN, space: 'home' };
    expect(rest(s, T0).ok).toBe(true);
    s = tired();
    expect(applyP0(c, s, { type: 'rest' }, T0).ok).toBe(true);   // an older client sends no space
  });
});

describe('arriving home (hook for SGODOT-231)', () => {
  it('trackPresence reports the first command back at home', async () => {
    const { trackPresence } = await import('../../src/p0/presence.js');
    const s = tired();
    expect(trackPresence(c, s, 'home', T0)).toBe(true);
    expect(trackPresence(c, s, 'home', T0 + MIN)).toBe(false);
    expect(trackPresence(c, s, 'map', T0 + 2 * MIN)).toBe(false);
    expect(trackPresence(c, s, 'pond', T0 + 3 * MIN)).toBe(false);
    expect(trackPresence(c, s, 'home', T0 + 4 * MIN)).toBe(true);
  });
});

describe('the state read on entering a space (PR #16 review)', () => {
  it('GET /v1/p0/state?space=outpost moves presence; the rest view says nothing of being away (q(269))', async () => {
    const { default: Fastify } = await import('fastify');
    const { registerP0Routes } = await import('../../src/p0/routes.js');
    const { P0Store } = await import('../../src/p0/store.js');
    let now = T0;
    const store = new P0Store(c);
    const app = Fastify();
    registerP0Routes(app, { content: c, store, now: () => now, dev: false });
    const headers = { 'x-p0-player': 'player-rest-02' };
    await app.inject({ method: 'GET', url: '/v1/p0/state?space=home', headers });
    now = T0 + 20 * MIN;
    await app.inject({ method: 'GET', url: '/v1/p0/state?space=outpost', headers });   // sat in the tea house, no command
    expect(store.get('player-rest-02', now).presence).toMatchObject({ space: 'away' });
    now = T0 + 23 * MIN;
    const back = await app.inject({ method: 'GET', url: '/v1/p0/state?space=home', headers });
    expect(store.get('player-rest-02', now).presence).toMatchObject({ space: 'home' });
    const rest = back.json().state.rest;
    expect(rest).not.toHaveProperty('away_ready_in');
    expect(rest).not.toHaveProperty('away_h');
  });
});
