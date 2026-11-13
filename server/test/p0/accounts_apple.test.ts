/** Sign in with Apple for P0 accounts (SGODOT-489 PR-B; contract-accounts §2): the token check, the client secret, the
 *  code exchange and session/apple; only the account number (and the sealed refresh token) is ever kept. */
import Fastify from 'fastify';
import { generateKeyPairSync, verify as cryptoVerify } from 'node:crypto';
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import { AppleClient, appleClientSecret, registerAppleRoutes, verifyAppleIdToken } from '../../src/p0/accounts/apple.js';
import { sha256Hex } from '../../src/p0/accounts/jwt.js';
import { PendingSignIns } from '../../src/p0/accounts/link.js';
import { P0Accounts } from '../../src/p0/accounts/store.js';
import { loadP0Content } from '../../src/p0/content.js';
import { P0Store } from '../../src/p0/store.js';
import { makeKeys, signToken } from '../fixtures/firebase_tokens.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 10, 13, 6);
const APP = 'app.gensen.maps', WEB = 'app.gensen.maps.web';
const NONCE = 'f'.repeat(64);
const SUB = '001234.abcdef0123456789abcdef0123456789.0123';
const TOKEN = 'a1'.repeat(32), OTHER = 'b2'.repeat(32);
const k = makeKeys('apple-1');
const idToken = (over: Record<string, unknown> = {}) => {
  const s = Math.floor(T0 / 1000);
  return signToken(k, { iss: 'https://appleid.apple.com', aud: APP, sub: SUB, iat: s - 5, exp: s + 600, nonce: sha256Hex(NONCE),
    email: 'x7c9@privaterelay.appleid.com', email_verified: 'true', is_private_email: 'true', ...over });
};
const ec = generateKeyPairSync('ec', { namedCurve: 'P-256' });
const CFG = { teamId: 'XN4Z77ZX73', keyId: '8J47FB5YJN', privateKeyFile: '-', bundleIds: [APP], servicesIds: [WEB] };

const dirs: string[] = [];
afterEach(() => { for (const d of dirs.splice(0)) rmSync(d, { recursive: true, force: true }); });

describe('verifyAppleIdToken', () => {
  const o = { audiences: [APP], keys: k.keys, now: () => T0 };
  it('takes Apple\'s token for our app with the nonce\'s hash, and reads only sub and aud', async () => {
    expect(await verifyAppleIdToken(idToken(), NONCE, o)).toEqual({ sub: SUB, aud: APP });
  });
  it('refuses another issuer, another aud (the web page\'s too), a stale one, another nonce, a short nonce', async () => {
    const no = async (t: string, n = NONCE) => (await verifyAppleIdToken(t, n, o).then(() => 'ok', e => e.code));
    expect(await no(idToken({ iss: 'https://accounts.google.com' }))).toBe('BAD_ISSUER');
    expect(await no(idToken({ aud: WEB }))).toBe('BAD_AUDIENCE');
    expect(await no(idToken({ exp: Math.floor(T0 / 1000) - 120 }))).toBe('EXPIRED');
    expect(await no(idToken({ nonce: sha256Hex('another-nonce-0000') }))).toBe('BAD_NONCE');
    expect(await no(idToken(), 'short')).toBe('BAD_NONCE');
  });
});

describe('appleClientSecret', () => {
  it('is an ES256 JWT of the team for the client, five minutes long, that the key\'s public half checks', () => {
    const s = appleClientSecret(CFG, ec.privateKey, APP, T0);
    const [h, p, sig] = s.split('.');
    expect(JSON.parse(Buffer.from(h, 'base64url').toString())).toEqual({ alg: 'ES256', kid: '8J47FB5YJN' });
    const iat = Math.floor(T0 / 1000);
    expect(JSON.parse(Buffer.from(p, 'base64url').toString())).toEqual({ iss: 'XN4Z77ZX73', iat, exp: iat + 300, aud: 'https://appleid.apple.com', sub: APP });
    expect(cryptoVerify('sha256', Buffer.from(`${h}.${p}`), { key: ec.publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(sig, 'base64url'))).toBe(true);
  });
});

describe('AppleClient', () => {
  it('spends a code for a refresh token and revokes it, as the aud\'s client', async () => {
    const posts: [string, Record<string, string>][] = [];
    const client = new AppleClient(CFG, () => ec.privateKey.export({ format: 'pem', type: 'pkcs8' }) as string,
      async (url, form) => { posts.push([url, form]); return url.endsWith('/token') ? { status: 200, json: { refresh_token: 'r.1' } } : { status: 200, json: null }; }, () => T0);
    expect(await client.refreshFor('code-1', APP)).toBe('r.1');
    await client.revoke(APP, 'r.1');
    expect(posts.map(([u, f]) => [u.split('/').pop(), f.client_id, f.grant_type ?? f.token_type_hint])).toEqual([['token', APP, 'authorization_code'], ['revoke', APP, 'refresh_token']]);
  });
});

function setup(exchange: string | null = 'r.secret') {
  const dir = mkdtempSync(path.join(tmpdir(), 'p0-apple-')); dirs.push(dir);
  const file = path.join(dir, 'accounts.json');
  const store = new P0Store(c), accounts = new P0Accounts(file, Buffer.alloc(32, 3), () => T0), pending = new PendingSignIns(() => T0);
  const kicked: string[] = [];
  const app = Fastify();
  registerAppleRoutes(app, { store, accounts, now: () => T0, pending, apple: CFG, keys: k.keys, kick: p => kicked.push(p), warn: () => {},
    client: { refreshFor: async () => exchange } });
  const post = (payload: object) => app.inject({ method: 'POST', url: '/v1/p0/session/apple', payload });
  return { file, store, accounts, pending, kicked, post };
}

describe('session/apple (contract §2)', () => {
  it('no farm linked: no_farm with a pending sign-in that holds the account number and the refresh token', async () => {
    const { post, pending, file } = setup();
    const r = await post({ id_token: idToken(), nonce: NONCE, auth_code: 'c1', token: TOKEN });
    expect([r.statusCode, r.json().code]).toEqual([404, 'no_farm']);
    expect(pending.take(r.json().pending)).toEqual({ provider: 'apple', link: { sub: SUB, aud: APP, refresh: 'r.secret' }, at: T0 });
    expect(existsSync(file) ? readFileSync(file, 'utf8') : '').not.toMatch(/privaterelay|x7c9/);   // nothing written for a pending one
  });
  it('a linked farm is signed in here: the other phones\' tokens revoked, its socket kicked, a new refresh kept sealed', async () => {
    const { post, store, accounts, kicked, file } = setup();
    store.get('p0-apple00001', T0); accounts.issue('p0-apple00001', OTHER); accounts.link('p0-apple00001', 'apple', { sub: SUB, aud: APP, refresh: 'r.old' });
    const r = await post({ id_token: idToken(), nonce: NONCE, auth_code: 'c1', token: TOKEN });
    expect(r.json()).toEqual({ ok: true, player: 'p0-apple00001', linked: ['apple'] });
    expect(accounts.byToken(OTHER)).toBeUndefined();
    expect(kicked).toEqual(['p0-apple00001']);
    expect(accounts.find('p0-apple00001')?.apple?.refresh).toBe('r.secret');
    expect(readFileSync(file, 'utf8')).not.toContain('r.secret');
  });
  it('a link left on a farm gone is no farm (liveOwner), and a bad token or nonce is bad_token', async () => {
    const { post, accounts } = setup();
    accounts.link('p0-gone00001', 'apple', { sub: SUB, aud: APP });
    expect((await post({ id_token: idToken(), nonce: NONCE, token: TOKEN })).json().code).toBe('no_farm');
    expect((await post({ id_token: idToken({ aud: WEB }), nonce: NONCE, token: TOKEN })).json().code).toBe('bad_token');
    expect((await post({ id_token: idToken(), nonce: 'x'.repeat(20), token: TOKEN })).json().code).toBe('bad_token');
  });
  it('a code Apple turns down still signs in, keeping no refresh token', async () => {
    const { post, pending } = setup(null);
    const r = await post({ id_token: idToken(), nonce: NONCE, auth_code: 'spent', token: TOKEN });
    expect(pending.take(r.json().pending)?.link).toEqual({ sub: SUB, aud: APP });
  });
});
