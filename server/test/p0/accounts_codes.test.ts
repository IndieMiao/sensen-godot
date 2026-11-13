/** Test codes (contract v1.4 §4, must sign in; 周瑜): /admin/code and its revoke, and the code's sign-in — one code an
 *  account, never expiring, never spent, no other device signed out; kept as HMAC only. */
import Fastify from 'fastify';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import { registerP0Admin } from '../../src/p0/admin.js';
import { CODE_PER_MINUTE, newCode, noteOk, registerCodeRoutes } from '../../src/p0/accounts/codes.js';
import { normalizeCode, P0Accounts } from '../../src/p0/accounts/store.js';
import { loadP0Content } from '../../src/p0/content.js';
import { P0Store } from '../../src/p0/store.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 10, 13, 8);
const KEY = 'admin-test-key';
const ACCOUNTS_KEY = Buffer.alloc(32, 7);
const tok = (n: number) => n.toString(16).padStart(2, '0').repeat(32);

const dirs: string[] = [];
afterEach(() => { for (const d of dirs.splice(0)) rmSync(d, { recursive: true, force: true }); });

function setup(key: Buffer | null = ACCOUNTS_KEY) {
  let t = T0;
  const dir = mkdtempSync(path.join(tmpdir(), 'p0-codes-'));
  dirs.push(dir);
  const file = path.join(dir, 'accounts.json');
  const store = new P0Store(c);
  const accounts = new P0Accounts(file, key, () => t);
  const lines: string[] = [], kicked: string[] = [], warned: string[] = [];
  const admin = Fastify(), app = Fastify();
  registerP0Admin(admin, { content: c, store, now: () => t, key: KEY, log: l => lines.push(l), accounts, kick: p => kicked.push(p) });
  registerCodeRoutes(app, { store, accounts, now: () => t, warn: l => warned.push(l) });
  const adm = (url: string, payload: unknown) => admin.inject({ method: 'POST', url, headers: { 'x-p0-admin': KEY }, payload: payload as object });
  const signIn = (code: unknown, token: string, ip = '198.51.100.7') =>
    app.inject({ method: 'POST', url: '/v1/p0/session/code', payload: { code, token }, remoteAddress: ip });
  return { file, store, accounts, lines, kicked, warned, adm, signIn, admin, tick: (ms: number) => { t += ms; } };
}

describe('test codes (contract v1.4 §4)', () => {
  it('a new code is 12 Crockford characters with no I L O U, shown XXXX-XXXX-XXXX; notes are ids, not people', () => {
    for (let i = 0; i < 200; i++) expect(newCode()).toMatch(/^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$/);
    for (const note of ['review-play', 'cn-tester-03', 'review.apple_2']) expect(noteOk(note)).toBe(true);
    for (const note of ['', 'Mia Rose', 'mia@gmail.com', '+8613800000000x', '-lead', 'x'.repeat(41), 7]) expect(noteOk(note)).toBe(false);
  });

  it('/admin/code without a player makes a new account (a new player\'s save, login code); the code once, never stored or logged', async () => {
    const { file, store, accounts, lines, adm } = setup();
    const r = (await adm('/admin/code', { note: 'cn-tester-03' })).json();
    expect(r).toMatchObject({ ok: true, note: 'cn-tester-03' });
    expect(r.player).toMatch(/^p0-[0-9a-f]{20}$/);
    const s = store.peek(r.player)!;
    expect(s.login).toBe('code');
    expect(s.test).toBeUndefined();   // a tester counts; a review does not (below)
    expect(s.travel.pending).toBe(true);   // a new player's start: its home to pick, then the guide
    expect(s.guide).toBeTruthy();
    expect(accounts.codeOf(r.player)).toEqual({ note: 'cn-tester-03', at: T0 });
    const saved = readFileSync(file, 'utf8');
    expect(saved).not.toContain(r.code);
    expect(saved).not.toContain(normalizeCode(r.code));
    expect(lines.join('')).not.toContain(normalizeCode(r.code).slice(0, 8));
    expect(JSON.parse(lines.at(-1)!)).toEqual({ admin: 'code', player: r.player.slice(-6), note: 'cn-tester-03', made: true, at: T0 });
    expect((await adm('/admin/code', { note: 'Mia Rose' })).json()).toEqual({ ok: false, code: 'bad_note' });
  });

  it("the code signs in however it is typed; several devices at once, none signed out; the account's other tokens stay", async () => {
    const { accounts, adm, signIn } = setup();
    const { player, code } = (await adm('/admin/code', { note: 'review-play' })).json();
    accounts.issue(player, tok(9));   // were it signed in another way: kept
    const r1 = await signIn(code, tok(1));
    expect(r1.json()).toEqual({ ok: true, player });
    expect((await signIn(` ${code.toLowerCase().replace(/-/g, ' ')} `, tok(2), '203.0.113.9')).json()).toEqual({ ok: true, player });
    for (const t of [tok(1), tok(2), tok(9)]) expect(accounts.byToken(t)).toEqual({ player, kind: 'user' });
    expect((await signIn(code, tok(1))).json()).toEqual({ ok: true, player });   // the same token again: the same answer
  });

  it('a store review\'s account is marked test, left out of the counts', async () => {
    const { store, adm } = setup();
    const { player } = (await adm('/admin/code', { note: 'review-play' })).json();
    expect(store.peek(player)!.test).toBe(true);
  });

  it('refuses: a wrong code as bad_code, nothing said of why; a token shape; a token of another account', async () => {
    const { accounts, adm, signIn } = setup();
    const { code } = (await adm('/admin/code', { note: 'cn-tester-01' })).json();
    for (const wrong of ['AAAA-AAAA-AAAA', '', 'x'.repeat(40), 7, null]) {
      const r = await signIn(wrong, tok(3), `198.51.100.${String(wrong).length}`);
      expect([r.statusCode, r.json()]).toEqual([401, { ok: false, code: 'bad_code' }]);
    }
    expect((await signIn(code, 'ab'.repeat(8), '192.0.2.1')).json().code).toBe('token_too_short');
    expect((await signIn(code, undefined as unknown as string, '192.0.2.2')).json().code).toBe('schema');
    accounts.issue('someone-else-01', tok(4));
    expect((await signIn(code, tok(4), '192.0.2.3')).json()).toEqual({ ok: false, code: 'schema' });
  });

  it('five tries a minute from an address, none counted for the others; a new minute starts over; a flood logged without the address', async () => {
    const { warned, adm, signIn, tick } = setup();
    const { code } = (await adm('/admin/code', { note: 'cn-tester-02' })).json();
    for (let i = 0; i < CODE_PER_MINUTE; i++) expect((await signIn('AAAA-AAAA-AAAA', tok(5))).statusCode).toBe(401);
    expect((await signIn(code, tok(5))).json()).toEqual({ ok: false, code: 'rate_limited' });   // the right code too: no trying on
    expect((await signIn(code, tok(5), '203.0.113.50')).json().ok).toBe(true);
    for (let i = 0; i < 9; i++) await signIn('AAAA-AAAA-AAAA', tok(5));
    expect(warned).toHaveLength(1);
    expect(warned[0]).not.toMatch(/198\.51|203\.0/);
    tick(60_000);
    expect((await signIn(code, tok(6))).json().ok).toBe(true);
  });

  it('a new code replaces the old, whose tokens go; a revoke takes the code and its tokens, kicks, keeps the rest', async () => {
    const { accounts, kicked, adm, signIn } = setup();
    const first = (await adm('/admin/code', { note: 'cn-tester-04' })).json();
    await signIn(first.code, tok(1));
    const second = (await adm('/admin/code', { player: first.player, note: 'cn-tester-04' })).json();
    expect(second).toMatchObject({ ok: true, player: first.player });
    expect(second.code).not.toBe(first.code);
    expect(accounts.byToken(tok(1))).toBeUndefined();
    expect((await signIn(first.code, tok(2), '192.0.2.10')).json().code).toBe('bad_code');
    await signIn(second.code, tok(3), '192.0.2.11');
    accounts.issue(first.player, tok(9));
    expect((await adm('/admin/code/revoke', { player: first.player })).json()).toEqual({ ok: true, revoked: 1 });
    expect(kicked).toEqual([first.player]);
    expect(accounts.byToken(tok(3))).toBeUndefined();
    expect(accounts.byToken(tok(9))?.player).toBe(first.player);
    expect((await signIn(second.code, tok(4), '192.0.2.12')).json().code).toBe('bad_code');
    expect((await adm('/admin/code/revoke', { player: first.player })).json()).toEqual({ ok: false, code: 'no_code' });
  });

  it('not for an unknown or deleted account, nor one linked to Apple or Google; a deleted account\'s code signs in nowhere', async () => {
    const { store, accounts, adm, signIn } = setup();
    expect((await adm('/admin/code', { player: 'nobody-here-01', note: 'x1' })).json()).toEqual({ ok: false, code: 'unknown_player' });
    store.get('linked-player-01', T0);
    accounts.link('linked-player-01', 'google', { sub: '42' });
    expect((await adm('/admin/code', { player: 'linked-player-01', note: 'x1' })).json()).toEqual({ ok: false, code: 'linked', linked: ['google'] });
    const { player, code } = (await adm('/admin/code', { note: 'cn-tester-05' })).json();
    accounts.markDeleted(player, T0);
    expect((await signIn(code, tok(7))).json().code).toBe('bad_code');
  });

  it('/admin/players lists whose code (its note and day), never the code', async () => {
    const { adm, admin } = setup();
    const { player, code } = (await adm('/admin/code', { note: 'review-apple' })).json();
    const body = (await admin.inject({ method: 'GET', url: '/admin/players', headers: { 'x-p0-admin': KEY } })).body;
    expect(JSON.parse(body).players.find((p: { player: string }) => p.player === player).code).toEqual({ note: 'review-apple', at: T0 });
    expect(body).not.toContain(normalizeCode(code));
  });

  it('without P0_ACCOUNTS_KEY: no code routes — the admin says codes_off, the sign-in is not there', async () => {
    const { adm, signIn } = setup(null);
    expect((await adm('/admin/code', { note: 'cn-tester-06' })).json()).toEqual({ ok: false, code: 'codes_off' });
    expect((await signIn('AAAA-AAAA-AAAA', tok(1))).statusCode).toBe(404);
  });
});
