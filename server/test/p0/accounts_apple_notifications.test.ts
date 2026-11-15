import Fastify from 'fastify';
import { mkdtempSync, readFileSync, rmSync, mkdirSync, statSync, writeFileSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { APPLE_NOTIFICATION_MAX_AGE_MS, AppleNotificationJournal, registerAppleNotifications,
  verifyAppleNotification, type AppleNotificationDeps } from '../../src/p0/accounts/apple_notifications.js';
import { appleVerifier, registerAppleRoutes } from '../../src/p0/accounts/apple.js';
import { sha256Hex } from '../../src/p0/accounts/jwt.js';
import { PendingSignIns } from '../../src/p0/accounts/link.js';
import { P0Accounts } from '../../src/p0/accounts/store.js';
import { P0Store } from '../../src/p0/store.js';
import { registerAccountRoutes } from '../../src/p0/accounts/routes.js';
import { P0Voice } from '../../src/p0/online/voice.js';
import { OutpostRooms } from '../../src/p0/online/rooms.js';
import { loadOutposts } from '../../src/p0/online/outposts.js';
import { loadP0Content } from '../../src/p0/content.js';
import { makeKeys, signToken } from '../fixtures/firebase_tokens.js';
import { registerP0Guard, snapshotState } from '../../src/p0/guard.js';

const keys = makeKeys('apple-notification-test');
const APP = 'app.gensen.maps', WEB = 'app.gensen.maps.web', SUB = 'synthetic-apple-sub';
const PLAYER = 'p0-notify0001', NOW = Date.UTC(2026, 10, 15, 7), WHEN = NOW - 10_000;
const USER = 'ab'.repeat(32), ADMIN = 'cd'.repeat(32), NEXT = 'ef'.repeat(32);
const dirs: string[] = [], apps: ReturnType<typeof Fastify>[] = [];
afterEach(async () => { vi.restoreAllMocks(); for (const a of apps.splice(0)) await a.close(); for (const d of dirs.splice(0)) rmSync(d, { recursive: true, force: true }); });
function jwt(type = 'consent-revoked', overrides: Record<string, unknown> = {}, eventOverrides: Record<string, unknown> = {}) {
  return signToken(keys, { iss: 'https://appleid.apple.com', aud: APP, iat: NOW / 1000, jti: 'notification-1',
    events: { type, sub: SUB, event_time: WHEN / 1000, ...eventOverrides }, ...overrides });
}
function setup(extra?: { other?: 'google' | 'email'; unknown?: boolean }) {
  const dir = mkdtempSync(path.join(tmpdir(), 'apple-notify-')); dirs.push(dir);
  let clock = WHEN - 1000;
  const now = () => clock;
  const store = new P0Store(loadP0Content(), path.join(dir, 'state.json'));
  const accountsFile = path.join(dir, 'accounts.json'), journalFile = path.join(dir, 'notifications.json');
  const accounts = new P0Accounts(accountsFile, Buffer.alloc(32, 7), now);
  if (!extra?.unknown) {
    store.get(PLAYER, clock); accounts.ensure(PLAYER);
    accounts.link(PLAYER, 'apple', { sub: SUB, aud: APP, refresh: 'synthetic-refresh-secret' });
    if (extra?.other) accounts.link(PLAYER, extra.other, { sub: 'other-sub' });
    accounts.issue(PLAYER, USER); accounts.issue(PLAYER, ADMIN, 'admin', NOW + 1_000_000);
  }
  const rooms = new OutpostRooms(loadOutposts());
  const voice = new P0Voice(null, rooms, { ages: path.join(dir, 'ages.json'), blocks: path.join(dir, 'blocks.json'), reports: path.join(dir, 'reports.jsonl') }, now);
  voice.setAge(PLAYER, true);
  const drop = vi.spyOn(voice, 'drop'), kick = vi.fn(), warn = vi.fn();
  const pending = new PendingSignIns(now);
  const ticket = pending.create('apple', { sub: SUB, aud: APP, refresh: 'pending-secret' });
  clock = NOW;
  const deps: AppleNotificationDeps = { store, accounts, voice, hub: { kick }, now, pending, audiences: [APP, WEB],
    keys: keys.keys, journal: new AppleNotificationJournal(journalFile, now), warn };
  const register = () => { const app = Fastify(); apps.push(app); registerAppleNotifications(app, deps); return app; };
  const app = register();
  const post = (payload = jwt(), ip = '127.0.0.1') => app.inject({ method: 'POST', url: '/v1/apple/notifications', payload: { payload }, remoteAddress: ip });
  return { deps, app, register, post, dir, accountsFile, journalFile, drop, kick, warn, ticket, clock: (n: number) => { clock = n; } };
}

describe('Apple notification validation (no Apple private key or real provider)', () => {
  it('accepts Apple documented object events without exp, and JSON-string events', async () => {
    const o = { audiences: [APP], keys: keys.keys, now: () => NOW };
    expect(await verifyAppleNotification(jwt(), o)).toMatchObject({ type: 'consent-revoked', sub: SUB, at: WHEN });
    expect(await verifyAppleNotification(jwt('account-delete', { events: JSON.stringify({ type: 'account-deleted', sub: SUB, event_time: WHEN / 1000 }) }), o))
      .toMatchObject({ type: 'account-deleted' });
  });
  it.each([
    { iss: 'https://attacker.invalid' }, { aud: 'wrong-client' }, { iat: NOW / 1000 + 61 },
    { iat: (NOW - APPLE_NOTIFICATION_MAX_AGE_MS) / 1000 - 1 }, { jti: '' }, { exp: NOW / 1000 - 61 },
    { events: '{bad' }, { events: [] }, { events: { type: 'consent-revoked', sub: SUB, event_time: NOW / 1000 + 61 } },
    { iat: NOW / 1000 + 60, events: { type: 'consent-revoked', sub: SUB, event_time: NOW / 1000 + 120 } },
  ])('rejects invalid signed claims without mutating any accounts (%j)', async overrides => {
    const { post, deps } = setup();
    expect((await post(jwt('consent-revoked', overrides))).statusCode).toBe(401);
    expect(deps.accounts.byToken(USER)?.player).toBe(PLAYER);
    expect(deps.accounts.find(PLAYER)?.apple?.refresh).toBe('synthetic-refresh-secret');
  });
  it('rejects unsigned/bad signature and distinguishes key lookup failure', async () => {
    const { post, deps } = setup();
    const signed = jwt();
    expect((await post(signed.slice(0, -10) + 'AAAAAAAAAA')).statusCode).toBe(401);
    expect((await post(signToken(keys, {}, { alg: 'none', kid: keys.kid }, true))).statusCode).toBe(401);
    deps.keys = async () => { throw new Error('secret-provider-detail'); };
    expect((await post()).json()).toEqual({ ok: false, code: 'provider_unavailable' });
    expect(deps.accounts.byToken(USER)).toBeDefined();
  });
});

describe('Apple notification actions and recovery', () => {
  it.each(['login', 'claim', 'pending'])('rechecks a %s proof after code exchange awaits a completed revocation', async route => {
    const f = setup({ unknown: route === 'pending' });
    let finish!: (refresh: string) => void;
    const exchange = vi.fn(() => new Promise<string>(r => { finish = r; }));
    const apple = { teamId: 'synthetic', keyId: 'unused', privateKeyFile: '/not-read', bundleIds: [APP], servicesIds: [] };
    const ad = { ...f.deps, apple, client: { refreshFor: exchange }, pending: f.deps.pending!, authorized: f.deps.journal.authorized };
    const nonce = 'n'.repeat(43), proof = signToken(keys, { iss: 'https://appleid.apple.com', aud: APP, sub: SUB,
      iat: WHEN / 1000 - 1, exp: NOW / 1000 + 600, nonce: sha256Hex(nonce) });
    if (route === 'claim') {
      const verify = appleVerifier(ad);
      registerAccountRoutes(f.app, { ...f.deps, identify: { accounts: f.deps.accounts, legacyId: false },
        authorizedApple: f.deps.journal.authorized,
        verify: async (_provider, b) => { const v = await verify(b); return 'status' in v ? v : { link: v }; } });
    } else registerAppleRoutes(f.app, ad);
    const signing = f.app.inject({ method: 'POST', url: route === 'claim' ? '/v1/p0/session/claim' : '/v1/p0/session/apple',
      headers: { 'x-p0-player': PLAYER }, payload: { provider: 'apple', id_token: proof, nonce, auth_code: 'one-use', token: NEXT } });
    await vi.waitFor(() => expect(exchange).toHaveBeenCalledOnce());
    expect((await f.post()).statusCode).toBe(200);
    finish('revoked-while-exchanging');
    const response = await signing;
    expect([response.statusCode, response.json().code]).toEqual([401, 'bad_token']);
    expect(f.deps.accounts.byToken(NEXT)).toBeUndefined();
    expect(f.deps.accounts.find(PLAYER)?.apple?.refresh).toBeUndefined();
    expect(f.deps.pending!.size()).toBe(0);
    expect(exchange).toHaveBeenCalledOnce();
  });
  it('late old-proof pending is invalidated after a newer authorization while its new-proof sibling survives', async () => {
    const f = setup();
    const verify = appleVerifier({ ...f.deps, apple: { teamId: 't', keyId: 'k', privateKeyFile: '/not-read', bundleIds: [APP], servicesIds: [] },
      client: null, authorized: f.deps.journal.authorized });
    const nonce = 'n'.repeat(43);
    const get = async (iat: number) => {
      const v = await verify({ nonce, id_token: signToken(keys, { iss: 'https://appleid.apple.com', aud: APP, sub: SUB,
        iat, exp: NOW / 1000 + 600, nonce: sha256Hex(nonce) }) });
      if ('status' in v) throw new Error('unexpected refusal');
      return v;
    };
    const oldProof = await get(WHEN / 1000 - 1);
    const old = f.deps.pending!.create('apple', oldProof); // received after the event, but proof itself is old
    const freshProof = await get(NOW / 1000);
    const fresh = f.deps.pending!.create('apple', freshProof);
    expect((await f.post()).statusCode).toBe(200);
    expect(f.deps.pending!.peek(old)).toBeUndefined();
    expect(f.deps.pending!.peek(fresh)).toBeDefined();
  });
  it('claim rechecks after an enclosing async verifier wrapper, immediately before account writes', async () => {
    const f = setup();
    const verify = appleVerifier({ ...f.deps, apple: { teamId: 't', keyId: 'k', privateKeyFile: '/not-read', bundleIds: [APP], servicesIds: [] },
      client: null, authorized: f.deps.journal.authorized });
    registerAccountRoutes(f.app, { ...f.deps, identify: { accounts: f.deps.accounts, legacyId: false },
      authorizedApple: f.deps.journal.authorized,
      verify: async (_provider, b) => {
        const v = await verify(b); if ('status' in v) return v;
        expect((await f.post()).statusCode).toBe(200); // revocation after appleVerifier's own last check
        return { link: v };
      } });
    const nonce = 'n'.repeat(43);
    const r = await f.app.inject({ method: 'POST', url: '/v1/p0/session/claim', headers: { 'x-p0-player': PLAYER },
      payload: { provider: 'apple', token: NEXT, nonce, id_token: signToken(keys, { iss: 'https://appleid.apple.com', aud: APP,
        sub: SUB, iat: WHEN / 1000 - 1, exp: NOW / 1000 + 600, nonce: sha256Hex(nonce) }) } });
    expect([r.statusCode, r.json().code]).toEqual([401, 'bad_token']);
    expect(f.deps.accounts.byToken(NEXT)).toBeUndefined();
  });
  it.each(['no_farm', 'guest_conflict'])('preserves Apple proof time when %s reissues a pending ticket', async kind => {
    const f = setup({ unknown: kind === 'no_farm' });
    registerAccountRoutes(f.app, { ...f.deps, identify: { accounts: f.deps.accounts, legacyId: false },
      authorizedApple: f.deps.journal.authorized });
    const old = f.deps.pending!.create('apple', { sub: SUB, aud: APP }, WHEN - 1000);
    const r = await f.app.inject({ method: 'POST', url: kind === 'no_farm' ? '/v1/p0/session/pending' : '/v1/p0/session/guest',
      payload: { pending: old, token: NEXT, age_ok: true, terms: '2026-11-13', privacy: '2026-11-13', skip: true } });
    expect(r.json().code).toBe(kind === 'no_farm' ? 'no_farm' : 'conflict');
    const ticket = r.json().pending;
    expect(f.deps.pending!.peek(ticket)?.appleIssuedAt).toBe(WHEN - 1000);
    f.deps.journal.authorized(SUB, NOW); // newer proof must not promote the older ticket
    expect((await f.post()).statusCode).toBe(200);
    expect(f.deps.pending!.peek(ticket)).toBeUndefined();
  });
  it('consent revocation preserves binding, farm, age/admin; clears user/refresh/pending and disconnects', async () => {
    const { post, deps, drop, kick, ticket, journalFile } = setup();
    const save = structuredClone(deps.store.peek(PLAYER));
    expect((await post()).json()).toEqual({ ok: true });
    expect(deps.accounts.byToken(USER)).toBeUndefined(); expect(deps.accounts.byToken(ADMIN)).toBeDefined();
    expect(deps.accounts.find(PLAYER)?.apple).toEqual({ sub: SUB, aud: APP, refresh: undefined });
    expect(deps.accounts.byIdentity('apple', SUB)).toBe(PLAYER);
    expect(deps.accounts.isDeleted(PLAYER)).toBe(false); expect(deps.store.peek(PLAYER)).toEqual(save);
    expect(deps.voice.status(PLAYER).age).toBe('ok'); expect(deps.pending!.peek(ticket)).toBeUndefined();
    expect(drop).toHaveBeenCalledWith(PLAYER, { requireConfirmed: true }); expect(kick).toHaveBeenCalledWith(PLAYER);
    const raw = readFileSync(journalFile, 'utf8');
    expect(raw).not.toContain(SUB); expect(raw).not.toContain('notification-1'); expect(raw).not.toContain('secret');
    expect(statSync(journalFile).mode & 0o777).toBe(0o600);
  });
  it.each(['account-delete', 'account-deleted'])('%s deletes Apple-only with the shared deletion function', async type => {
    const { post, deps } = setup(); vi.spyOn(console, 'warn').mockImplementation(() => {});
    expect((await post(jwt(type))).statusCode).toBe(200);
    expect(deps.store.peek(PLAYER)).toBeUndefined(); expect(deps.accounts.find(PLAYER)).toBeUndefined();
    expect(deps.accounts.byToken(ADMIN)).toBeUndefined(); expect(deps.accounts.isDeleted(PLAYER)).toBe(true);
  });
  it.each(['google', 'email'] as const)('preserves a farm with another %s sign-in and unlinks only Apple', async other => {
    const { post, deps } = setup({ other });
    expect((await post(jwt('account-deleted'))).statusCode).toBe(200);
    expect(deps.store.peek(PLAYER)).toBeDefined(); expect(deps.accounts.linked(PLAYER)).toEqual([other]);
    expect(deps.accounts.isDeleted(PLAYER)).toBe(false); expect(deps.accounts.byToken(ADMIN)).toBeDefined();
  });
  it('durable deduplication survives restart and normalized spelling; same jti conflicting contents refused', async () => {
    const { post, deps, register, journalFile, kick } = setup({ other: 'google' });
    expect((await post(jwt('account-delete'))).statusCode).toBe(200);
    deps.journal = new AppleNotificationJournal(journalFile, deps.now);
    const next = register();
    expect((await next.inject({ method: 'POST', url: '/v1/apple/notifications', payload: { payload: jwt('account-deleted') } })).statusCode).toBe(200);
    expect(kick).toHaveBeenCalledTimes(1);
    expect((await post(jwt('consent-revoked'))).statusCode).toBe(401);
  });
  it('concurrent duplicate notifications share the operation', async () => {
    const { post, drop, kick } = setup();
    let finish!: () => void; drop.mockImplementation(() => new Promise<void>(r => { finish = r; }));
    const a = post(), b = post(); await vi.waitFor(() => expect(kick).toHaveBeenCalledTimes(1)); finish();
    expect((await Promise.all([a, b])).map(r => r.statusCode)).toEqual([200, 200]); expect(drop).toHaveBeenCalledTimes(1);
  });
  it('unknown/unsupported events neither create farms nor alter data', async () => {
    const { post, deps } = setup({ unknown: true });
    expect((await post(jwt('email-disabled'))).statusCode).toBe(200);
    expect((await post(jwt('account-deleted', { jti: 'second' }))).statusCode).toBe(200);
    expect(deps.store.size()).toBe(0); expect(deps.accounts.players()).toEqual([]);
  });
  it('a partial delete stays retryable and resumes after the Apple identity disappears and process restarts', async () => {
    const { post, deps, journalFile, accountsFile, register } = setup(); vi.spyOn(console, 'warn').mockImplementation(() => {});
    const remove = vi.spyOn(deps.store, 'remove').mockImplementationOnce(() => { throw new Error('synthetic-secret'); });
    expect((await post(jwt('account-deleted'))).json()).toEqual({ ok: false, code: 'notification_incomplete' });
    expect(deps.accounts.byIdentity('apple', SUB)).toBeUndefined(); expect(deps.store.peek(PLAYER)).toBeDefined();
    deps.accounts = new P0Accounts(accountsFile, Buffer.alloc(32, 7), deps.now);
    deps.journal = new AppleNotificationJournal(journalFile, deps.now); remove.mockRestore();
    const next = register();
    expect((await next.inject({ method: 'POST', url: '/v1/apple/notifications', payload: { payload: jwt('account-deleted') } })).statusCode).toBe(200);
    expect(deps.store.peek(PLAYER)).toBeUndefined();
  });
  it('journaling failure precedes account changes; invalidation write failure rolls memory back', async () => {
    const { post, deps, journalFile, accountsFile } = setup();
    mkdirSync(journalFile + '.tmp');
    expect((await post()).statusCode).toBe(503); expect(deps.accounts.byToken(USER)).toBeDefined();
    rmSync(journalFile + '.tmp', { recursive: true }); mkdirSync(accountsFile + '.tmp');
    expect((await post()).statusCode).toBe(503); expect(deps.accounts.byToken(USER)).toBeDefined();
    expect(deps.accounts.find(PLAYER)?.apple?.refresh).toBe('synthetic-refresh-secret');
    rmSync(accountsFile + '.tmp', { recursive: true });
    expect((await post()).statusCode).toBe(200);
  });
  it('a newer verified Apple authorization protects even a logged-out refreshed binding across restart', async () => {
    const { post, deps, journalFile, register, clock } = setup();
    const verify = appleVerifier({ apple: { teamId: 't', keyId: 'k', privateKeyFile: '/not-read', bundleIds: [APP], servicesIds: [] },
      client: null, keys: keys.keys, now: deps.now, authorized: deps.journal.authorized });
    const nonce = 'n'.repeat(43);
    const id = signToken(keys, { iss: 'https://appleid.apple.com', aud: APP, sub: SUB, iat: NOW / 1000, exp: NOW / 1000 + 600, nonce: sha256Hex(nonce) });
    expect(await verify({ id_token: id, nonce })).toMatchObject({ sub: SUB, aud: APP, authorizationAt: NOW });
    deps.accounts.link(PLAYER, 'apple', { sub: SUB, aud: APP, refresh: 'new-refresh' });
    deps.accounts.issue(PLAYER, NEXT); deps.accounts.revoke(NEXT); deps.accounts.revoke(USER); // logout leaves no current token timestamp
    clock(NOW + 1000); deps.journal = new AppleNotificationJournal(journalFile, deps.now);
    const next = register();
    expect((await next.inject({ method: 'POST', url: '/v1/apple/notifications', payload: { payload: jwt() } })).statusCode).toBe(200);
    expect(deps.accounts.find(PLAYER)?.apple?.refresh).toBe('new-refresh'); expect(deps.store.peek(PLAYER)).toBeDefined();
    expect((await post(jwt('account-deleted', { jti: 'another' }))).statusCode).toBe(200);
    expect(deps.store.peek(PLAYER)).toBeDefined();
  });
  it('lookup occurs after async verification so a moved identity cannot delete the earlier farm', async () => {
    const { post, deps, clock } = setup();
    let resume!: () => void; deps.keys = async () => { await new Promise<void>(r => { resume = r; }); return keys.keys(); };
    const pending = post(jwt('account-deleted'));
    await vi.waitFor(() => expect(resume).toBeTypeOf('function'));
    clock(NOW); const newer = 'p0-newer0001'; deps.store.get(newer, NOW); deps.accounts.unlink(PLAYER, 'apple');
    deps.accounts.link(newer, 'apple', { sub: SUB, aud: APP }); resume();
    expect((await pending).statusCode).toBe(200); expect(deps.store.peek(PLAYER)).toBeDefined(); expect(deps.store.peek(newer)).toBeDefined();
  });
  it('revoked Apple ID tokens cannot log back in, even after restart; a newly issued token can reauthorize', async () => {
    const { post, deps, journalFile } = setup();
    expect((await post()).statusCode).toBe(200);
    const journal = new AppleNotificationJournal(journalFile, deps.now);
    const app = Fastify(); apps.push(app);
    registerAppleRoutes(app, { store: deps.store, accounts: deps.accounts, pending: deps.pending!, now: deps.now,
      apple: { teamId: 'synthetic', keyId: 'unused', privateKeyFile: '/not-read', bundleIds: [APP], servicesIds: [] }, client: null,
      keys: keys.keys, authorized: journal.authorized });
    const nonce = 'n'.repeat(43);
    const token = (iat: number) => signToken(keys, { iss: 'https://appleid.apple.com', aud: APP, sub: SUB,
      iat, exp: NOW / 1000 + 600, nonce: sha256Hex(nonce) });
    const signIn = (iat: number) => app.inject({ method: 'POST', url: '/v1/p0/session/apple',
      payload: { id_token: token(iat), nonce, token: NEXT } });
    expect((await signIn(WHEN / 1000)).json().code).toBe('bad_token');
    expect(deps.accounts.byToken(NEXT)).toBeUndefined();
    expect((await signIn(NOW / 1000)).json()).toMatchObject({ ok: true, player: PLAYER });
    expect(deps.accounts.byToken(ADMIN)).toBeDefined();
  });
  it('a newer game token from a pre-event Apple token is not a new Apple authorization', async () => {
    const { post, deps } = setup();
    deps.journal.authorized(SUB, WHEN - 1000); // verified old Apple iat, though delivered to the game after the event
    deps.accounts.issue(PLAYER, NEXT); // session at NOW > event, not a provider reauthorization
    expect((await post()).statusCode).toBe(200);
    expect(deps.accounts.byToken(NEXT)).toBeUndefined(); expect(deps.accounts.byToken(USER)).toBeUndefined();
    expect(deps.accounts.find(PLAYER)?.apple?.refresh).toBeUndefined();
    expect(deps.accounts.byToken(ADMIN)).toBeDefined();
  });
  it('late delivery also invalidates pending grants received after the event without a newer Apple authorization', async () => {
    const { post, deps } = setup();
    const late = deps.pending!.create('apple', { sub: SUB, aud: APP });
    expect((await post()).statusCode).toBe(200);
    expect(deps.pending!.peek(late)).toBeUndefined();
  });
  it('a new farm created after a delayed deletion is preserved but its old credential is not left active', async () => {
    const { post, deps } = setup({ unknown: true });
    deps.store.get(PLAYER, NOW); deps.accounts.link(PLAYER, 'apple', { sub: SUB, aud: APP, refresh: 'old-proof' });
    deps.accounts.issue(PLAYER, USER);
    expect((await post(jwt('account-deleted'))).statusCode).toBe(200);
    expect(deps.store.peek(PLAYER)).toBeDefined(); expect(deps.accounts.isDeleted(PLAYER)).toBe(false);
    expect(deps.accounts.byToken(USER)).toBeUndefined(); expect(deps.accounts.find(PLAYER)?.apple?.refresh).toBeUndefined();
  });
  it('media cleanup failure returns retryable 503 with no raw exception details', async () => {
    const { post, drop, warn } = setup(); drop.mockRejectedValueOnce(new Error('private-media-token'));
    const r = await post(); expect(r.statusCode).toBe(503); expect(r.body).not.toContain('private-media-token');
    expect(warn).toHaveBeenCalledWith(JSON.stringify({ apple_notification: 'incomplete', event: 'consent-revoked' }));
    expect((await post()).statusCode).toBe(200);
  });
  it('real voice release failure stays incomplete until a retry confirms the captured lease is gone', async () => {
    const { post, deps } = setup(); vi.spyOn(console, 'warn').mockImplementation(() => {});
    const rooms = new OutpostRooms(loadOutposts()); rooms.join(PLAYER, 'sh_tea_1');
    let fail = true, metadata = '';
    const remove = vi.fn(async () => {});
    deps.voice = new P0Voice({ url: 'ws://fake.invalid', apiKey: 'fake', apiSecret: 'fake-secret-at-least-thirty-two-bytes', namespace: 'notify-test' },
      rooms, null, deps.now, { getParticipant: async () => { if (fail) throw new Error('private-provider-error'); return { metadata }; }, removeParticipant: remove });
    deps.voice.setAge(PLAYER, true);
    const grant = await deps.voice.join(PLAYER) as { lease_id: string }; metadata = grant.lease_id;
    expect((await post()).statusCode).toBe(503);
    expect(deps.accounts.byToken(USER)).toBeUndefined(); expect(deps.store.peek(PLAYER)).toBeDefined();
    fail = false;
    expect((await post()).statusCode).toBe(200); expect(remove).toHaveBeenCalledOnce();
  });
  it('caps unauthenticated requests by IP without requiring the game access key', async () => {
    const { app } = setup();
    for (let i = 0; i < 60; i++) expect((await app.inject({ method: 'POST', url: '/v1/apple/notifications', payload: {} })).statusCode).toBe(400);
    expect((await app.inject({ method: 'POST', url: '/v1/apple/notifications', payload: {} })).statusCode).toBe(429);
    expect((await app.inject({ method: 'POST', url: '/v1/apple/notifications', remoteAddress: '127.0.0.2', payload: { payload: jwt() } })).statusCode).toBe(200);
  });
  it('remains outside the real game-key guard while P0 routes remain protected', async () => {
    const { deps } = setup();
    const app = Fastify(); apps.push(app);
    await registerP0Guard(app, { keys: ['synthetic-access-key'], perMinute: 600, perAddress: 2000 });
    registerAppleNotifications(app, deps);
    app.get('/v1/p0/test', async () => ({ ok: true }));
    expect((await app.inject({ method: 'POST', url: '/v1/apple/notifications', payload: { payload: jwt() } })).statusCode).toBe(200);
    expect((await app.inject({ method: 'GET', url: '/v1/p0/test' })).statusCode).toBe(401);
  });
  it('snapshots the operational journal with the same hour and retention as accounts/state', () => {
    const { dir } = setup();
    const file = path.join(dir, 'state.json'), acc = path.join(dir, 'accounts.json'), journal = path.join(dir, 'journal.json');
    writeFileSync(journal, '{"v":1,"entries":{},"authorizations":{}}');
    const snaps = path.join(dir, 'snapshots');
    for (let hour = 0; hour < 3; hour++) snapshotState(file, snaps, 2, NOW + hour * 3_600_000, acc, journal);
    expect(readdirSync(snaps).filter(f => f.startsWith('apple-notifications-'))).toHaveLength(2);
    const last = readdirSync(snaps).filter(f => f.startsWith('apple-notifications-')).sort().at(-1)!;
    expect(readFileSync(path.join(snaps, last), 'utf8')).toBe(readFileSync(journal, 'utf8'));
  });
});
