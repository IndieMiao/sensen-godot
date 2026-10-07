import Fastify from 'fastify';
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0 } from '../../src/p0/reducer.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { freshState } from '../../src/p0/state.js';
import { P0Store } from '../../src/p0/store.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 5, 2, 0, 0);
const fresh = () => freshState(c, 'player-seq-01', T0, 42);

describe('P0 state version (expect_seq, SGODOT-211)', () => {
  it('applies a command whose expect_seq matches and advances seq', () => {
    const s = fresh();
    const r = applyP0(c, s, { type: 'till', plot: c.start.tilled_plots, expect_seq: s.seq }, T0);
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.state.seq).toBe(s.seq + 1);
  });

  it('refuses a stale expect_seq without changing anything', () => {
    const s = fresh();
    const before = structuredClone(s);
    const r = applyP0(c, s, { type: 'till', plot: c.start.tilled_plots, expect_seq: s.seq + 3 }, T0);
    expect(r).toEqual({ ok: false, code: 'stale_state', detail: { seq: s.seq, expected: s.seq + 3 } });
    expect(s).toEqual(before);
  });

  it('still accepts commands without expect_seq (older clients)', () => {
    const r = applyP0(c, fresh(), { type: 'till', plot: c.start.tilled_plots }, T0);
    expect(r.ok).toBe(true);
  });

  it('a retried purchase over HTTP is applied once', async () => {
    const app = Fastify();
    const store = new P0Store(c);
    registerP0Routes(app, { content: c, store, now: () => T0, dev: false });
    const headers = { 'x-p0-player': 'player-seq-02', 'content-type': 'application/json' };
    const state = await app.inject({ method: 'GET', url: '/v1/p0/state', headers });
    const seq = state.json().state.seq as number;
    const buy = { type: 'buy', item: 'seed_radish', qty: 1, expect_seq: seq };
    const first = await app.inject({ method: 'POST', url: '/v1/p0/commands', headers, payload: buy });
    expect(first.json().ok).toBe(true);
    // The response was "lost"; the client retries the very same command.
    const retry = await app.inject({ method: 'POST', url: '/v1/p0/commands', headers, payload: buy });
    expect(retry.json()).toMatchObject({ ok: false, code: 'stale_state', detail: { seq: seq + 1 } });
    expect(retry.json().state.seq).toBe(seq + 1);
    const seeds = (s: { bag: { slots: { id: string; qty: number }[] } }) =>
      s.bag.slots.filter(x => x.id === 'seed_radish').reduce((n, x) => n + x.qty, 0);
    expect(seeds(retry.json().state)).toBe(seeds(first.json().state));
    await app.close();
  });
});
