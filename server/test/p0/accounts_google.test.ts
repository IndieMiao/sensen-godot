/** Sign in with Google for P0 accounts (SGODOT-489 PR-B, contract-accounts §2, 周瑜): session/google, link/google, and
 *  that only the account number is ever kept (李白's store forms ◆E). */
import Fastify from 'fastify';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import { registerGoogleRoutes } from '../../src/p0/accounts/google.js';
import { sha256Hex } from '../../src/p0/accounts/jwt.js';
import { PendingSignIns } from '../../src/p0/accounts/link.js';
import { P0Accounts } from '../../src/p0/accounts/store.js';
import { loadP0Content } from '../../src/p0/content.js';
import { P0Store } from '../../src/p0/store.js';
import { makeKeys, signToken } from '../fixtures/firebase_tokens.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 10, 13, 6);
const WEB = '870347303349-web.apps.googleusercontent.com', IOS = '870347303349-ios.apps.googleusercontent.com';
const NONCE = 'n'.repeat(43);
const SUB = '109876543210987654321';
const TOKEN = 'a1'.repeat(32), OTHER_TOKEN = 'b2'.repeat(32), OLD_TOKEN = 'c3'.repeat(32), ADMIN_TOKEN = 'd4'.repeat(32);
const k = makeKeys('google-1');
/** An Android token: email, name and picture beside the account number, as Credential Manager's carry. */
const idToken = (over: Record<string, unknown> = {}, keys = k) => {
  const s = Math.floor(T0 / 1000);
  return signToken(keys, { iss: 'https://accounts.google.com', aud: WEB, sub: SUB, iat: s - 5, exp: s + 3600, nonce: sha256Hex(NONCE),
    email: 'mia.rose@gmail.com', email_verified: true, name: 'Mia Rose', given_name: 'Mia', picture: 'https://lh3.example/p.jpg', ...over });
};

const dirs: string[] = [];
afterEach(() => { for (const d of dirs.splice(0)) rmSync(d, { recursive: true, force: true }); });

function setup(over: { audiences?: string[]; keys?: () => Promise<Map<string, import('node:crypto').KeyObject>> } = {}) {
  const dir = mkdtempSync(path.join(tmpdir(), 'p0-google-'));
  dirs.push(dir);
  const file = path.join(dir, 'accounts.json');
  const store = new P0Store(c);
  const accounts = new P0Accounts(file, null, () => T0);
  const pending = new PendingSignIns(() => T0);
  const kicked: string[] = [], warned: string[] = [];
  const app = Fastify();
  registerGoogleRoutes(app, { store, accounts, identify: { accounts, legacyId: false }, now: () => T0, pending,
    audiences: over.audiences ?? [WEB, IOS], keys: over.keys ?? k.keys, kick: p => kicked.push(p), warn: l => warned.push(l) });
  const post = (url: string, payload: unknown, headers: Record<string, string> = {}) =>
    app.inject({ method: 'POST', url, payload: payload as object, headers });
  /** A farm with a user token, as a guest or a claim leaves it. */
  const farm = (player: string, token: string) => { store.get(player, T0); accounts.ensure(player); accounts.issue(player, token); };
  return { file, store, accounts, pending, kicked, warned, post, farm };
}

describe('session/google (contract §2)', () => {
  it('no farm linked: no_farm with a pending sign-in that holds the account number only', async () => {
    const { pending, post, file } = setup();
    const r = await post('/v1/p0/session/google', { id_token: idToken(), nonce: NONCE, token: TOKEN });
    expect(r.statusCode).toBe(404);
    expect(r.json()).toEqual({ ok: false, code: 'no_farm', pending: expect.stringMatching(/^[0-9a-f]{64}$/) });
    expect(pending.take(r.json().pending)).toEqual({ provider: 'google', link: { sub: SUB }, at: T0 });
    expect(JSON.stringify(readFileSafe(file))).not.toMatch(/mia|Mia|picture|lh3/);
  });

  it('the linked farm signed in here: its other phone revoked and kicked, a test device kept, the new token in', async () => {
    const { accounts, kicked, post, farm } = setup();
    farm('p0-farmgoogle01', OLD_TOKEN);
    accounts.issue('p0-farmgoogle01', ADMIN_TOKEN, 'admin', T0 + 86_400_000);
    accounts.link('p0-farmgoogle01', 'google', { sub: SUB });
    const r = await post('/v1/p0/session/google', { id_token: idToken({ aud: IOS }), nonce: NONCE, token: TOKEN.toUpperCase() });
    expect(r.json()).toEqual({ ok: true, player: 'p0-farmgoogle01', linked: ['google'] });
    expect(accounts.byToken(TOKEN)).toEqual({ player: 'p0-farmgoogle01', kind: 'user' });
    expect(accounts.byToken(OLD_TOKEN)).toBeUndefined();
    expect(accounts.byToken(ADMIN_TOKEN)?.kind).toBe('admin');
    expect(kicked).toEqual(['p0-farmgoogle01']);
  });

  it('a linked account whose farm is gone reads as no farm', async () => {
    const { accounts, post } = setup();
    accounts.link('p0-farmgone0001', 'google', { sub: SUB });   // in accounts.json, no save
    expect((await post('/v1/p0/session/google', { id_token: idToken(), nonce: NONCE, token: TOKEN })).json().code).toBe('no_farm');
  });

  it('refuses: a bad token (aud, nonce, expired, signature, not a JWT) as bad_token only; a token shape; a token of another farm', async () => {
    const { accounts, post, farm } = setup();
    const s = Math.floor(T0 / 1000);
    for (const [id_token, nonce] of [[idToken({ aud: 'someone-else.apps.googleusercontent.com' }), NONCE], [idToken(), 'm'.repeat(43)],
      [idToken({ exp: s - 600 }), NONCE], [idToken({}, makeKeys('google-1')), NONCE], ['not.a.jwt', NONCE], [undefined, NONCE]]) {
      const r = await post('/v1/p0/session/google', { id_token, nonce, token: TOKEN });
      expect([r.statusCode, r.json()]).toEqual([401, { ok: false, code: 'bad_token' }]);
    }
    expect((await post('/v1/p0/session/google', { id_token: idToken(), nonce: NONCE })).json().code).toBe('schema');
    expect((await post('/v1/p0/session/google', { id_token: idToken(), nonce: NONCE, token: 'ab'.repeat(8) })).json().code).toBe('token_too_short');
    farm('p0-farmgoogle02', OTHER_TOKEN);
    farm('p0-farmgoogle03', OLD_TOKEN);
    accounts.link('p0-farmgoogle03', 'google', { sub: SUB });
    const taken = await post('/v1/p0/session/google', { id_token: idToken(), nonce: NONCE, token: OTHER_TOKEN });
    expect([taken.statusCode, taken.json()]).toEqual([400, { ok: false, code: 'schema' }]);
    expect(accounts.byToken(OLD_TOKEN)?.player).toBe('p0-farmgoogle03');   // nothing revoked
  });

  it("Google's keys out of reach, or no client ids set: provider_unavailable, the log without the token", async () => {
    const down = setup({ keys: async () => { throw new TypeError('fetch failed'); } });
    const t = idToken();
    const r = await down.post('/v1/p0/session/google', { id_token: t, nonce: NONCE, token: TOKEN });
    expect([r.statusCode, r.json()]).toEqual([503, { ok: false, code: 'provider_unavailable' }]);
    expect(down.warned.map(l => JSON.parse(l))).toEqual([{ google: 'provider_unavailable', error: 'TypeError' }]);
    expect(down.warned.join('')).not.toContain(t.split('.')[1]);
    const off = setup({ audiences: [] });
    expect((await off.post('/v1/p0/session/google', { id_token: t, nonce: NONCE, token: TOKEN })).json().code).toBe('provider_unavailable');
  });
});

describe('account/link/google (contract §2)', () => {
  const auth = (token: string) => ({ authorization: `Bearer ${token}` });

  it('links the farm in hand, the account number only; the same account again is done already', async () => {
    const { accounts, post, farm, file } = setup();
    farm('p0-farmlinker01', TOKEN);
    const r = await post('/v1/p0/account/link/google', { id_token: idToken(), nonce: NONCE }, auth(TOKEN));
    expect(r.json()).toEqual({ ok: true, linked: ['google'] });
    expect(accounts.find('p0-farmlinker01')?.google).toEqual({ sub: SUB });
    expect(accounts.byIdentity('google', SUB)).toBe('p0-farmlinker01');
    expect((await post('/v1/p0/account/link/google', { id_token: idToken(), nonce: NONCE }, auth(TOKEN))).json()).toEqual({ ok: true, linked: ['google'] });
    const saved = JSON.stringify(readFileSafe(file));
    expect(saved).toContain(SUB);
    expect(saved).not.toMatch(/mia|Mia|picture|lh3|email/);
  });

  it('another Google account on this farm: already_linked; this one on another farm: conflict with a pending and its line', async () => {
    const { store, accounts, pending, post, farm } = setup();
    farm('p0-farmlinker02', TOKEN);
    accounts.link('p0-farmlinker02', 'google', { sub: '111' });
    const r1 = await post('/v1/p0/account/link/google', { id_token: idToken(), nonce: NONCE }, auth(TOKEN));
    expect([r1.statusCode, r1.json()]).toEqual([409, { ok: false, code: 'already_linked' }]);
    farm('p0-farmlinker03', OTHER_TOKEN);
    const other = store.get('p0-farmlinker04', T0);
    other.profile = { name: 'Ana' };
    other.homestead.level = 7;
    other.presence.last_at = T0 - 3 * 86_400_000;
    accounts.link('p0-farmlinker04', 'google', { sub: SUB });
    const r2 = await post('/v1/p0/account/link/google', { id_token: idToken(), nonce: NONCE }, auth(OTHER_TOKEN));
    expect(r2.statusCode).toBe(409);
    expect(r2.json()).toEqual({ ok: false, code: 'conflict', pending: expect.stringMatching(/^[0-9a-f]{64}$/),
      farm: { name: 'Ana', home_level: 7, last_played_at: T0 - 3 * 86_400_000 } });
    expect(pending.take(r2.json().pending)?.link).toEqual({ sub: SUB });
    expect(accounts.byIdentity('google', SUB)).toBe('p0-farmlinker04');   // not moved
  });

  it('needs the token: an old id alone is refused, as is no identity or a bad Google token', async () => {
    const { store, accounts, post, farm } = setup();
    store.get('p0-farmlegacy01', T0);   // an unclaimed old farm: identify takes its id in the changeover
    const legacy = await post('/v1/p0/account/link/google', { id_token: idToken(), nonce: NONCE }, { 'x-p0-player': 'p0-farmlegacy01' });
    expect([legacy.statusCode, legacy.json()]).toEqual([401, { ok: false, code: 'unauthenticated' }]);
    expect(accounts.byIdentity('google', SUB)).toBeUndefined();
    expect((await post('/v1/p0/account/link/google', { id_token: idToken(), nonce: NONCE })).statusCode).toBe(400);   // bad_player
    farm('p0-farmlinker05', TOKEN);
    const bad = await post('/v1/p0/account/link/google', { id_token: idToken(), nonce: 'm'.repeat(43) }, auth(TOKEN));
    expect([bad.statusCode, bad.json()]).toEqual([401, { ok: false, code: 'bad_token' }]);
  });
});

function readFileSafe(file: string): unknown {
  try { return JSON.parse(readFileSync(file, 'utf8')); } catch { return null; }
}
