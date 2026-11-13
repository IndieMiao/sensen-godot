/** The admin side of accounts (SGODOT-488, contract-accounts §4.1, tech-plan §2.5): a test device's admin token, a
 *  claim reset, and the admin tokens in force on /admin/players. */
import Fastify from 'fastify';
import { describe, expect, it } from 'vitest';
import { ADMIN_TOKEN_MS, registerP0Admin, SMOKE_PLAYER, SMOKE_TOKEN_MS } from '../../src/p0/admin.js';
import { P0Accounts } from '../../src/p0/accounts/store.js';
import { loadP0Content } from '../../src/p0/content.js';
import { P0Store } from '../../src/p0/store.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 10, 13, 6);
const KEY = 'admin-test-key';
const USER_TOKEN = 'ab'.repeat(32);

function setup(withAccounts = true) {
  let t = T0;
  const store = new P0Store(c);
  const accounts = new P0Accounts(undefined, null, () => t);
  const lines: string[] = [], kicked: string[] = [];
  const admin = Fastify();
  registerP0Admin(admin, { content: c, store, now: () => t, key: KEY, log: l => lines.push(l), ...(withAccounts ? { accounts, kick: p => kicked.push(p) } : {}) });
  const post = (url: string, payload: unknown, key = KEY) => admin.inject({ method: 'POST', url, headers: { 'x-p0-admin': key }, payload: payload as object });
  return { store, accounts, admin, lines, kicked, post, tick: (ms: number) => { t += ms; } };
}

describe('admin tokens and claim reset (contract §4.1)', () => {
  it('/admin/session: a 32-byte token, its plain text once, kind admin, 30 days; not a claim; no token in the log', async () => {
    const { store, accounts, lines, post } = setup();
    store.get('test-phone-0001', T0);
    const r = (await post('/admin/session', { player: 'test-phone-0001' })).json();
    expect(r).toMatchObject({ ok: true, player: 'test-phone-0001', expires_at: T0 + ADMIN_TOKEN_MS });
    expect(r.token).toMatch(/^[0-9a-f]{64}$/);
    expect(accounts.byToken(r.token)).toEqual({ player: 'test-phone-0001', kind: 'admin' });
    expect(accounts.find('test-phone-0001')?.claimed_at).toBeUndefined();
    expect(lines.map(l => JSON.parse(l))).toEqual([{ admin: 'session', player: 'e-0001', expires_at: T0 + ADMIN_TOKEN_MS, at: T0 }]);
    expect(lines.join('')).not.toContain(r.token);
    const again = (await post('/admin/session', { player: 'test-phone-0001' })).json();
    expect(again.token).not.toBe(r.token);   // each call its own; both hold
    expect(accounts.byToken(r.token)?.player).toBe('test-phone-0001');
  });

  it('/admin/session only for a stored, not deleted player with a well-formed id, and only with the admin key', async () => {
    const { store, accounts, post } = setup();
    for (const player of ['nobody-here-01', 'bad id!', 7, undefined])
      expect((await post('/admin/session', { player })).json()).toEqual({ ok: false, code: 'unknown_player' });
    store.get('test-phone-0002', T0);
    accounts.markDeleted('test-phone-0002', T0);
    expect((await post('/admin/session', { player: 'test-phone-0002' })).statusCode).toBe(404);
    store.get('test-phone-0003', T0);
    expect((await post('/admin/session', { player: 'test-phone-0003' }, 'wrong')).json()).toEqual({ ok: false, code: 'bad_admin_key' });
  });

  it("an admin token outlasts another device's sign-in (revokeAll without admin) and ends after its 30 days", async () => {
    const { store, accounts, post, tick } = setup();
    store.get('test-phone-0004', T0);
    const { token } = (await post('/admin/session', { player: 'test-phone-0004' })).json();
    accounts.issue('test-phone-0004', USER_TOKEN);
    accounts.revokeAll('test-phone-0004', USER_TOKEN);   // the sign-in elsewhere (session/apple / google, switch)
    expect(accounts.byToken(token)?.kind).toBe('admin');
    tick(ADMIN_TOKEN_MS);
    expect(accounts.byToken(token)).toBeUndefined();
  });

  it('/admin/claim/reset: claimed_at cleared, every token revoked, admin ones too; the count back, no id', async () => {
    const { store, accounts, lines, post, kicked } = setup();
    store.get('test-phone-0005', T0);
    accounts.markClaimed('test-phone-0005');
    accounts.issue('test-phone-0005', USER_TOKEN);
    const { token } = (await post('/admin/session', { player: 'test-phone-0005' })).json();
    expect((await post('/admin/claim/reset', { player: 'test-phone-0005' })).json()).toEqual({ ok: true, revoked: 2 });
    expect(accounts.find('test-phone-0005')?.claimed_at).toBeUndefined();
    expect(accounts.byToken(USER_TOKEN)).toBeUndefined();
    expect(accounts.byToken(token)).toBeUndefined();
    expect(JSON.parse(lines.at(-1)!)).toEqual({ admin: 'claim_reset', player: 'e-0005', revoked: 2, at: T0 });
    expect(kicked).toEqual(['test-phone-0005']);   // its open room socket goes now
    expect((await post('/admin/claim/reset', { player: 'nobody-here-02' })).json()).toEqual({ ok: false, code: 'unknown_player' });
  });

  it('/admin/players lists each player\'s admin tokens in force; without accounts, no such field', async () => {
    const { store, admin, post, tick } = setup();
    store.get('test-phone-0006', T0);
    store.get('test-phone-0007', T0);
    await post('/admin/session', { player: 'test-phone-0006' });
    tick(1000);
    await post('/admin/session', { player: 'test-phone-0006' });
    const players = (await admin.inject({ method: 'GET', url: '/admin/players', headers: { 'x-p0-admin': KEY } })).json().players;
    const by = Object.fromEntries(players.map((p: { player: string; admin_tokens: unknown }) => [p.player, p.admin_tokens]));
    expect(by['test-phone-0006'].map((a: { tail: string; expires_at: number }) => [a.tail, a.expires_at]))
      .toEqual([['0006', T0 + ADMIN_TOKEN_MS], ['0006', T0 + 1000 + ADMIN_TOKEN_MS]]);
    const tails = by['test-phone-0006'].map((a: { token_tail: string }) => a.token_tail);
    expect(tails[0]).toMatch(/^[0-9a-f]{6}$/);
    expect(tails[0]).not.toBe(tails[1]);   // two test devices of one player told apart
    expect(by['test-phone-0007']).toEqual([]);
    const bare = setup(false);
    bare.store.get('test-phone-0008', T0);
    const one = (await bare.admin.inject({ method: 'GET', url: '/admin/players', headers: { 'x-p0-admin': KEY } })).json().players[0];
    expect(one).not.toHaveProperty('admin_tokens');
    expect((await bare.post('/admin/session', { player: 'test-phone-0008' })).statusCode).toBe(404);   // no such route without accounts
  });
});

describe("the deploy's smoke account (奕星 11-13)", () => {
  it('/admin/smoke: the fixed account made afresh, marked test; an hour-long token, the earlier one revoked; no token logged', async () => {
    const { store, accounts, lines, post, tick } = setup();
    store.get('a-real-player-01', T0);
    const first = (await post('/admin/smoke', {})).json();
    expect(first).toMatchObject({ ok: true, player: SMOKE_PLAYER, expires_at: T0 + SMOKE_TOKEN_MS });
    expect(first.token).toMatch(/^[0-9a-f]{64}$/);
    expect(accounts.byToken(first.token)).toEqual({ player: SMOKE_PLAYER, kind: 'admin' });
    const s = store.peek(SMOKE_PLAYER)!;
    expect(s.test).toBe(true);
    s.plots[0].crop = 'radish';   // a run's sow
    s.coins = 3;
    tick(60_000);
    const second = (await post('/admin/smoke', {})).json();
    expect(accounts.byToken(first.token)).toBeUndefined();
    expect(accounts.byToken(second.token)?.player).toBe(SMOKE_PLAYER);
    expect(store.peek(SMOKE_PLAYER)!.plots[0].crop).not.toBe('radish');   // afresh: the same check each time
    expect(store.peek(SMOKE_PLAYER)!.coins).not.toBe(3);
    expect(store.peek('a-real-player-01')).toBeDefined();
    expect(lines.map(l => JSON.parse(l))).toEqual([{ admin: 'smoke', expires_at: T0 + SMOKE_TOKEN_MS, at: T0 },
      { admin: 'smoke', expires_at: T0 + 60_000 + SMOKE_TOKEN_MS, at: T0 + 60_000 }]);
    tick(SMOKE_TOKEN_MS);
    expect(accounts.byToken(second.token)).toBeUndefined();
  });

  it('needs the admin key; without accounts there is no such route', async () => {
    expect((await setup().post('/admin/smoke', {}, 'wrong')).statusCode).toBe(401);
    expect((await setup(false).post('/admin/smoke', {})).statusCode).toBe(404);
  });
});
