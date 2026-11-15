import Fastify from 'fastify';
import { mkdirSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { registerWebDeleteRoutes } from '../../src/p0/accounts/web_delete.js';
import { EmailCodes, registerEmailRoutes, type EmailRouteDeps } from '../../src/p0/accounts/email.js';
import { PendingSignIns } from '../../src/p0/accounts/link.js';
import { P0Accounts } from '../../src/p0/accounts/store.js';
import { loadP0Content } from '../../src/p0/content.js';
import { P0Store } from '../../src/p0/store.js';
import { P0Voice } from '../../src/p0/online/voice.js';
import { OutpostRooms } from '../../src/p0/online/rooms.js';
import { loadOutposts } from '../../src/p0/online/outposts.js';
import { guardOptionsFromEnv, registerP0Guard } from '../../src/p0/guard.js';
import { makeKeys, signToken } from '../fixtures/firebase_tokens.js';
import { AppleNotificationJournal, registerAppleNotifications } from '../../src/p0/accounts/apple_notifications.js';

const T = Date.UTC(2026, 10, 15), P = 'web-delete-player', Q = 'web-delete-kept', ORIGIN = 'https://gensen.app';
const APP = 'app.gensen.maps', WEB = 'app.gensen.maps.web', GOOGLE = 'fake-web.apps.googleusercontent.com';
const keys = makeKeys('web-proof'), C = loadP0Content();
const cleanup: (() => Promise<void>)[] = [];
afterEach(async () => { vi.restoreAllMocks(); for (const fn of cleanup.splice(0)) await fn(); });
async function setup(emailOn = true) {
  const dir = mkdtempSync(path.join(tmpdir(), 'web-delete-')), save = path.join(dir, 'save.json'), file = path.join(dir, 'accounts.json');
  let now = T;
  const store = new P0Store(C, save), accounts = new P0Accounts(file, Buffer.alloc(32, 3), () => now);
  for (const p of [P, Q]) { store.get(p, now); accounts.ensure(p); accounts.issue(p, p === P ? '1'.repeat(64) : '2'.repeat(64)); }
  const voice = new P0Voice(null, new OutpostRooms(loadOutposts()), null, () => now), hub = { kick: vi.fn() };
  const mails: { to: string; text: string }[] = [], revokeApple = vi.fn(async () => {}), warn = vi.fn();
  const email: EmailRouteDeps = { store, accounts, now: () => now, pending: new PendingSignIns(() => now),
    on: emailOn, codes: new EmailCodes(() => now), mailer: { send: async (to, mail) => { mails.push({ to, text: mail.text }); } }, warn };
  const app = Fastify(); await registerP0Guard(app, guardOptionsFromEnv({ P0_ACCESS_KEYS: 'fake-game-key' }));
  const startEmail = registerEmailRoutes(app, email);
  const journalFile = path.join(dir, 'apple-notifications.json');
  const journal = new AppleNotificationJournal(journalFile, () => now);
  registerAppleNotifications(app, { store, accounts, voice, hub, now: () => now, pending: email.pending,
    audiences: [APP, WEB], keys: keys.keys, journal, warn });
  registerWebDeleteRoutes(app, { store, accounts, voice, hub, now: () => now, revokeApple, email, startEmail,
    apiBase: 'https://farm.sensenjoy.cn/preview/p0/v1/web', origins: [ORIGIN], appleClientId: WEB, googleClientId: GOOGLE,
    appleWeb: { audiences: [WEB], keys: keys.keys, now: () => now, authorized: journal.authorized }, googleWeb: { audiences: [GOOGLE], keys: keys.keys, now: () => now }, warn });
  cleanup.push(async () => { await app.close(); rmSync(dir, { recursive: true, force: true }); });
  const headers = { origin: ORIGIN };
  const options = async () => (await app.inject({ method: 'GET', url: '/v1/web/delete/options', headers })).json();
  const post = (payload: object) => app.inject({ method: 'POST', url: '/v1/web/delete', headers, payload });
  const start = (address: string) => app.inject({ method: 'POST', url: '/v1/web/email/start', headers, payload: { email: address, lang: 'en' } });
  const token = (o: { nonce_hash: string }, provider = 'apple', extra = {}) => signToken(keys, {
    iss: provider === 'apple' ? 'https://appleid.apple.com' : 'https://accounts.google.com', aud: provider === 'apple' ? WEB : GOOGLE,
    sub: provider + '-subject', iat: Math.floor(now / 1000) - 1, exp: Math.floor(now / 1000) + 600, nonce: o.nonce_hash,
    email: 'private-provider@example.test', name: 'PRIVATE_NAME', ...extra });
  const revoke = async () => {
    const seconds = Math.floor(now / 1000);
    return app.inject({ method: 'POST', url: '/v1/apple/notifications', payload: { payload: signToken(keys, {
      iss: 'https://appleid.apple.com', aud: APP, iat: seconds, jti: 'revocation-' + now,
      events: { type: 'consent-revoked', sub: 'apple-subject', event_time: seconds },
    }) } });
  };
  return { app, store, accounts, save, file, voice, hub, revokeApple, warn, mails, email, options, post, start, token, revoke,
    journal, journalFile, now: () => now, tick: (ms: number) => { now += ms; } };
}

describe('P0 browser deletion: verified identity, then real deletion', () => {
  it.each(['unlinked', 'rebound', 'moved', 'recreated', 'reset_save'] as const)('an old verified challenge cannot delete a live target after %s', async change => {
    const f = await setup(), address = 'owner@example.test', other = 'other@example.test';
    const sub = f.accounts.emailId(address);
    f.accounts.link(P, 'email', { sub }); f.email.codes.put(address, '123456');
    const o = await f.options(), payload = { challenge: o.challenge, provider: 'email', confirmed: true, email: address, code: '123456' };
    vi.spyOn(f.accounts, 'markDeleted').mockImplementationOnce(() => { throw new Error('disk'); });
    expect((await f.post(payload)).json().code).toBe('delete_failed');
    f.tick(1);
    if (change === 'unlinked') f.accounts.unlink(P, 'email');
    if (change === 'rebound') { f.accounts.unlink(P, 'email'); f.accounts.link(P, 'email', { sub: f.accounts.emailId(other) }); }
    if (change === 'moved') { f.accounts.unlink(P, 'email'); f.accounts.link(Q, 'email', { sub }); }
    if (change === 'recreated') { f.accounts.remove(P); f.accounts.ensure(P); f.accounts.link(P, 'email', { sub }); f.store.reset(P, f.now()); }
    if (change === 'reset_save') f.store.reset(P, f.now());
    const accountBefore = readFileSync(f.file, 'utf8'), saveBefore = readFileSync(f.save, 'utf8');
    const result = await f.post(payload);
    expect([result.statusCode, result.json().code]).toEqual([401, 'bad_token']);
    expect(readFileSync(f.file, 'utf8')).toBe(accountBefore); expect(readFileSync(f.save, 'utf8')).toBe(saveBefore);
    expect(f.store.peek(P)).toBeDefined(); expect(f.store.peek(Q)).toBeDefined();
  });

  it('resumes its own persisted tombstone after accounts.remove write failure, even though the email code is spent', async () => {
    const f = await setup(), address = 'owner@example.test'; f.accounts.link(P, 'email', { sub: f.accounts.emailId(address) });
    f.email.codes.put(address, '123456'); const o = await f.options();
    const remove = f.accounts.remove.bind(f.accounts);
    vi.spyOn(f.accounts, 'remove').mockImplementationOnce(player => { mkdirSync(f.file + '.tmp'); remove(player); });
    const payload = { challenge: o.challenge, confirmed: true, provider: 'email', email: address, code: '123456' };
    expect((await f.post(payload)).json().code).toBe('delete_failed');
    expect(f.accounts.isDeleted(P)).toBe(true); expect(f.accounts.find(P)).toBeUndefined(); expect(f.store.peek(P)).toBeDefined();
    rmSync(f.file + '.tmp', { recursive: true }); f.tick(10);
    expect((await f.post(payload)).json()).toEqual({ ok: true });
    expect(f.store.peek(P)).toBeUndefined(); expect(f.store.peek(Q)).toBeDefined();
    expect(f.accounts.deletedPlayers().find(p => p.player === P)?.at).toBe(T);
  });

  it('does not claim a tombstone created by a different operation as this challenge’s authorization to resume', async () => {
    const f = await setup(), address = 'owner@example.test'; f.accounts.link(P, 'email', { sub: f.accounts.emailId(address) });
    f.email.codes.put(address, '123456'); const o = await f.options();
    vi.spyOn(f.accounts, 'markDeleted').mockImplementationOnce(() => { throw new Error('disk'); });
    const payload = { challenge: o.challenge, confirmed: true, provider: 'email', email: address, code: '123456' };
    expect((await f.post(payload)).json().code).toBe('delete_failed');
    f.tick(1); f.accounts.markDeleted(P, f.now()); f.accounts.remove(P);
    expect((await f.post(payload)).json().code).toBe('bad_token'); expect(f.store.peek(P)).toBeDefined();
  });

  it('its own tombstone does not authorize deleting a target rebound or rebuilt after the failed remove', async () => {
    const f = await setup(), address = 'owner@example.test'; f.accounts.link(P, 'email', { sub: f.accounts.emailId(address) });
    f.email.codes.put(address, '123456'); const o = await f.options();
    const remove = f.accounts.remove.bind(f.accounts);
    vi.spyOn(f.accounts, 'remove').mockImplementationOnce(player => { mkdirSync(f.file + '.tmp'); remove(player); });
    const payload = { challenge: o.challenge, confirmed: true, provider: 'email', email: address, code: '123456' };
    expect((await f.post(payload)).json().code).toBe('delete_failed');
    rmSync(f.file + '.tmp', { recursive: true }); f.tick(1);
    f.accounts.ensure(P); f.accounts.link(P, 'email', { sub: f.accounts.emailId('new-owner@example.test') });
    const before = readFileSync(f.file, 'utf8');
    expect((await f.post(payload)).json().code).toBe('bad_token');
    expect(readFileSync(f.file, 'utf8')).toBe(before); expect(f.store.peek(P)).toBeDefined();
  });

  it('shares PR1077 revocation floor: revoked Apple proof cannot delete via web, including a cached retry', async () => {
    const f = await setup(); f.accounts.link(P, 'apple', { sub: 'apple-subject', aud: APP, refresh: 'fake-refresh' });
    const o = await f.options(), payload = { challenge: o.challenge, confirmed: true, provider: 'apple', id_token: f.token(o) };
    vi.spyOn(f.accounts, 'markDeleted').mockImplementationOnce(() => { throw new Error('disk'); });
    expect((await f.post(payload)).json().code).toBe('delete_failed');
    f.tick(2000); expect((await f.revoke()).json()).toEqual({ ok: true });
    expect(f.accounts.find(P)?.apple?.sub).toBe('apple-subject'); // Revocation intentionally keeps binding/farm.
    expect((await f.post(payload)).json().code).toBe('bad_token'); expect(f.store.peek(P)).toBeDefined();
    const another = await f.options();
    expect((await f.post({ ...payload, challenge: another.challenge, id_token: f.token(another, 'apple', { iat: Math.floor(T / 1000) - 1 }) })).json().code).toBe('bad_token');
    const reloaded = new AppleNotificationJournal(f.journalFile, f.now);
    expect(() => reloaded.authorized('apple-subject', T - 1000)).toThrow('AUTHORIZATION_REVOKED');
    f.tick(3000); const fresh = await f.options();
    expect((await f.post({ ...payload, challenge: fresh.challenge, id_token: f.token(fresh) })).json()).toEqual({ ok: true });
    expect(f.store.peek(P)).toBeUndefined();
  });

  it.each(['apple', 'google'])('%s proof deletes only its bound farm and every repeat returns success without new sign-in tokens', async provider => {
    const f = await setup();
    if (provider === 'apple') f.accounts.link(P, 'apple', { sub: 'apple-subject', aud: APP, refresh: 'fake-refresh' });
    else f.accounts.link(P, 'google', { sub: 'google-subject' });
    const other = structuredClone(f.store.peek(Q)), o = await f.options();
    const payload = { challenge: o.challenge, confirmed: true, provider, id_token: f.token(o, provider) };
    expect((await f.post(payload)).json()).toEqual({ ok: true });
    expect(new P0Store(C, f.save).peek(P)).toBeUndefined(); expect(f.accounts.isDeleted(P)).toBe(true);
    expect(f.accounts.byToken('1'.repeat(64))).toBeUndefined(); expect(f.accounts.byToken('2'.repeat(64))?.player).toBe(Q);
    expect(f.store.peek(Q)).toEqual(other); expect(f.hub.kick).toHaveBeenCalledTimes(1);
    expect((await f.post(payload)).json()).toEqual({ ok: true }); expect(f.hub.kick).toHaveBeenCalledTimes(1);
    expect(readFileSync(f.file, 'utf8')).not.toMatch(/private-provider|PRIVATE_NAME/);
    if (provider === 'apple') expect(f.revokeApple).toHaveBeenCalledWith(APP, 'fake-refresh');
  });

  it('email uses the shared App code service and HMAC identity, without x-p0-key, plaintext persistence or session issuance', async () => {
    const f = await setup(), address = 'owner@example.test'; f.accounts.link(P, 'email', { sub: f.accounts.emailId(address) });
    const o = await f.options(); expect(o.email).toBe(true);
    expect((await f.start(address)).json()).toEqual({ ok: true, resend_in: 60 });
    const code = f.mails[0].text.match(/\n\n(\d{6})\n\n/)![1];
    const appRepeat = await f.app.inject({ method: 'POST', url: '/v1/p0/session/email/start', headers: { 'x-p0-key': 'fake-game-key' }, payload: { email: address } });
    expect(appRepeat.statusCode).toBe(429); // Same per-address / global quota; web did not get a second pool.
    const result = await f.post({ challenge: o.challenge, confirmed: true, provider: 'email', email: address.toUpperCase(), code });
    expect(result.json()).toEqual({ ok: true }); expect(f.store.peek(P)).toBeUndefined();
    expect(readFileSync(f.file, 'utf8')).not.toContain(address); expect(readFileSync(f.file, 'utf8')).not.toContain(code);
    expect(f.accounts.userTokenCount(P)).toBe(0);
    const another = await f.options();
    expect((await f.post({ challenge: another.challenge, confirmed: true, provider: 'email', email: address, code })).json().code).toBe('code_expired');
  });

  it('requires Origin, confirmation, a live IP-bound challenge and correct signature/audience/nonce before deleting', async () => {
    const f = await setup(); f.accounts.link(P, 'apple', { sub: 'apple-subject', aud: APP }); const o = await f.options();
    const payload = { challenge: o.challenge, confirmed: true, provider: 'apple', id_token: f.token(o) };
    expect((await f.app.inject({ method: 'POST', url: '/v1/web/delete', payload })).statusCode).toBe(403);
    expect((await f.app.inject({ method: 'POST', url: '/v1/web/delete', headers: { origin: 'https://attacker.test' }, payload })).statusCode).toBe(403);
    expect((await f.post({ ...payload, confirmed: false })).statusCode).toBe(400);
    expect((await f.post({ ...payload, player: Q })).statusCode).toBe(400);
    expect((await f.app.inject({ method: 'POST', url: '/v1/web/delete', headers: { origin: ORIGIN }, remoteAddress: '192.0.2.7', payload })).statusCode).toBe(410);
    for (const id_token of [f.token(o, 'apple', { aud: APP }), f.token(o, 'apple', { nonce: 'wrong' }),
      f.token(o, 'apple', { exp: Math.floor(T / 1000) - 120 }), f.token(o).slice(0, -16) + 'AAAAAAAAAAAAAAAA'])
      expect((await f.post({ ...payload, id_token })).json().code).toBe('bad_token');
    expect(f.store.peek(P)).toBeDefined(); f.tick(600_000);
    expect((await f.post(payload)).statusCode).toBe(410); expect(f.store.peek(P)).toBeDefined();
  });

  it('never creates a farm or account for a valid but unbound provider', async () => {
    const f = await setup(), o = await f.options(), before = readFileSync(f.file, 'utf8');
    const result = await f.post({ challenge: o.challenge, confirmed: true, provider: 'google', id_token: f.token(o, 'google') });
    expect([result.statusCode, result.json()]).toEqual([404, { ok: false, code: 'no_farm' }]);
    expect(f.store.size()).toBe(2); expect(readFileSync(f.file, 'utf8')).toBe(before);
  });

  it('email-off hides the option and refuses both sending and deleting with email', async () => {
    const f = await setup(false), o = await f.options(); expect(o.email).toBe(false);
    expect((await f.start('a@example.test')).json().code).toBe('provider_unavailable');
    expect((await f.post({ challenge: o.challenge, provider: 'email', confirmed: true, email: 'a@example.test', code: '123456' })).json().code).toBe('provider_unavailable');
    expect(f.mails).toEqual([]);
  });

  it('spends a proof once but allows retry after a local failure; later cleanup failure follows App success semantics', async () => {
    const f = await setup(), address = 'owner@example.test'; f.accounts.link(P, 'email', { sub: f.accounts.emailId(address) });
    const o = await f.options(); await f.start(address); const code = f.mails[0].text.match(/\n\n(\d{6})\n\n/)![1];
    vi.spyOn(f.accounts, 'markDeleted').mockImplementationOnce(() => { throw new Error('PRIVATE_DISK_ERROR'); });
    const payload = { challenge: o.challenge, confirmed: true, provider: 'email', email: address, code };
    const failed = await f.post(payload); expect([failed.statusCode, failed.json().code]).toEqual([500, 'delete_failed']);
    vi.spyOn(f.store, 'remove').mockImplementationOnce(() => { throw new Error('PRIVATE_DISK_ERROR'); });
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    expect((await f.post(payload)).json()).toEqual({ ok: true }); expect(f.accounts.isDeleted(P)).toBe(true);
    expect(f.store.peek(P)).toBeDefined(); // Residual is intentionally for authenticated admin recovery.
    expect(JSON.stringify(f.warn.mock.calls)).not.toMatch(/PRIVATE_DISK_ERROR|owner@example/);
  });

  it('coalesces concurrent requests, still permits deleting suspended accounts, and never uses an App session', async () => {
    const f = await setup(); f.accounts.link(P, 'apple', { sub: 'apple-subject', aud: APP, refresh: 'fake-refresh' });
    f.store.peek(P)!.sanctions = { suspended: { until: null, at: T } };
    const o = await f.options(), payload = { challenge: o.challenge, confirmed: true, provider: 'apple', id_token: f.token(o) };
    const results = await Promise.all([f.post(payload), f.post(payload)]);
    expect(results.map(r => r.json())).toEqual([{ ok: true }, { ok: true }]); expect(f.hub.kick).toHaveBeenCalledTimes(1);
    expect(f.revokeApple).toHaveBeenCalledTimes(1);
  });

  it('a verified retry cannot silently switch to another identity under the same challenge', async () => {
    const f = await setup(), address = 'owner@example.test', other = 'other@example.test';
    f.accounts.link(P, 'email', { sub: f.accounts.emailId(address) }); f.accounts.link(Q, 'email', { sub: f.accounts.emailId(other) });
    const o = await f.options(); f.email.codes.put(address, '123456'); f.email.codes.put(other, '654321');
    vi.spyOn(f.accounts, 'markDeleted').mockImplementationOnce(() => { throw new Error('disk'); });
    const payload = { challenge: o.challenge, confirmed: true, provider: 'email', email: address, code: '123456' };
    expect((await f.post(payload)).json().code).toBe('delete_failed');
    expect((await f.post({ ...payload, email: other, code: '654321' })).json().code).toBe('bad_token');
    expect(f.store.peek(P)).toBeDefined(); expect(f.store.peek(Q)).toBeDefined();
    expect((await f.post(payload)).json()).toEqual({ ok: true }); expect(f.store.peek(Q)).toBeDefined();
  });

  it('serves a real deletion form without credentials and uses bounded IP limits and precise CORS', async () => {
    const f = await setup(), page = await f.app.inject({ method: 'GET', url: '/v1/web/delete/page' });
    expect(page.statusCode).toBe(200); expect(page.headers['content-security-policy']).toContain("frame-ancestors 'none'");
    expect(page.body).toContain('If you signed in with a test code'); expect(page.body).toContain('Delete my account');
    expect(page.body).not.toMatch(/fake-game-key|SMTP_PASS|Playing as a guest/);
    const cors = await f.app.inject({ method: 'OPTIONS', url: '/v1/web/delete', headers: { origin: ORIGIN } });
    expect(cors.statusCode).toBe(204); expect(cors.headers['access-control-allow-origin']).toBe(ORIGIN);
    let last = 0; for (let n = 0; n < 32; n++) last = (await f.app.inject({ method: 'GET', url: '/v1/web/delete/options' })).statusCode;
    expect(last).toBe(429); expect(f.store.size()).toBe(2);
  });
});
