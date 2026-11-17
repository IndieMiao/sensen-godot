/** edb9eaf8 §1.2: test real management/notice routes against temporary persisted state. No production data. */
import Fastify from 'fastify';
import { mkdtempSync, mkdirSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { registerP0Admin } from '../../src/p0/admin.js';
import { registerAccountNoticeRoutes, nameResetWatermark } from '../../src/p0/accounts/notices.js';
import { P0Accounts } from '../../src/p0/accounts/store.js';
import { identify, inForce } from '../../src/p0/accounts/identify.js';
import { loadP0Content } from '../../src/p0/content.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { registerP0Voice, P0Voice } from '../../src/p0/online/voice.js';
import { OutpostRooms } from '../../src/p0/online/rooms.js';
import { loadOutposts } from '../../src/p0/online/outposts.js';
import { P0Store } from '../../src/p0/store.js';
import { guardOptionsFromEnv, registerP0Guard } from '../../src/p0/guard.js';
import { deleteAccount } from '../../src/p0/accounts/delete.js';

const C = loadP0Content(), T0 = Date.UTC(2026, 10, 17), P = 'notice-player-main', Q = 'notice-player-other';
const TOKEN = '1'.repeat(64), ADMIN = '2'.repeat(64), OTHER = '3'.repeat(64);
const cleanups: (() => Promise<void>)[] = [];
afterEach(async () => { vi.restoreAllMocks(); for (const fn of cleanups.splice(0)) await fn(); });

async function setup() {
  const dir = mkdtempSync(path.join(tmpdir(), 'account-notices-'));
  const file = path.join(dir, 'state.json'), accountFile = path.join(dir, 'accounts.json');
  let now = T0;
  const store = new P0Store(C, file), accounts = new P0Accounts(accountFile, null, () => now);
  for (const p of [P, Q]) { store.get(p, now); accounts.ensure(p); }
  accounts.issue(P, TOKEN); accounts.issue(P, ADMIN, 'admin', T0 + 30 * 86_400_000); accounts.issue(Q, OTHER);
  const app = Fastify(), admin = Fastify();
  await registerP0Guard(app, guardOptionsFromEnv({ P0_ACCESS_KEYS: 'fake-game-key' }));
  const identity = { accounts, legacyId: true, warn: () => {}, suspended: (p: string) => inForce(store.peek(p)?.sanctions?.suspended, now) };
  registerAccountNoticeRoutes(app, { store, identify: identity });
  registerP0Routes(app, { content: C, store, identify: identity, now: () => now, dev: false });
  const voice = new P0Voice(null, new OutpostRooms(loadOutposts()), null, () => now);
  registerP0Voice(app, voice, headers => identify(headers, identity));
  const actions = { renamed: vi.fn(), kick: vi.fn(), dropVoice: vi.fn(async () => {}) }, log = vi.fn();
  registerP0Admin(admin, { content: C, store, accounts, now: () => now, key: 'fake-admin-key', moderation: actions, log });
  cleanups.push(async () => { await app.close(); await admin.close(); rmSync(dir, { recursive: true, force: true }); });
  const headers = (token: string) => ({ 'x-p0-key': 'fake-game-key', authorization: `Bearer ${token}` });
  const get = (token = TOKEN) => app.inject({ method: 'GET', url: '/v1/p0/account/notices', headers: headers(token) });
  const ack = (version: unknown, token = TOKEN, extra: object = {}) => app.inject({ method: 'POST', url: '/v1/p0/account/notices/ack',
    headers: headers(token), payload: { kind: 'name_reset', version, ...extra } });
  const reset = () => admin.inject({ method: 'POST', url: '/admin/moderate', headers: { 'x-p0-admin': 'fake-admin-key' }, payload: { player: P, action: 'reset_name' } });
  return { app, admin, store, accounts, identity, voice, file, accountFile, actions, log, headers, get, ack, reset,
    now: () => now, tick: (ms: number) => { now += ms; } };
}

describe('v1.6.10 account-level name-reset notices', () => {
  it('GET is read-only and never calls find/get or exposes name/admin data; no new field for no event', async () => {
    const f = await setup(), before = readFileSync(f.file, 'utf8'), accountBefore = readFileSync(f.accountFile, 'utf8');
    const find = vi.spyOn(f.store, 'find').mockImplementation(() => { throw new Error('settled save'); });
    const create = vi.spyOn(f.store, 'get').mockImplementation(() => { throw new Error('created save'); });
    const put = vi.spyOn(f.store, 'put');
    expect((await f.get()).json()).toEqual({ ok: true, name_reset: null });
    expect((await f.get()).headers['cache-control']).toBe('no-store');
    expect(put).not.toHaveBeenCalled(); expect(find).not.toHaveBeenCalled(); expect(create).not.toHaveBeenCalled();
    expect(readFileSync(f.file, 'utf8')).toBe(before); expect(readFileSync(f.accountFile, 'utf8')).toBe(accountBefore);
    expect(f.store.peek(P)).not.toHaveProperty('account_notices');
  });

  it('management reset atomically increments notice version through equal/backwards time, preserving normal lock and seq rules', async () => {
    const f = await setup(), other = structuredClone(f.store.peek(Q));
    const state = f.store.peek(P)!; state.profile = { name: 'PRIVATE_NAME' }; f.store.put(state);
    const bag = structuredClone(state.bag), seq = state.seq;
    expect((await f.reset()).json().ok).toBe(true);
    expect((await f.reset()).json().ok).toBe(true); // Same millisecond, separate management command.
    f.tick(-1000); expect((await f.reset()).json().ok).toBe(true);
    const saved = new P0Store(C, f.file).peek(P)!;
    expect(saved.account_notices?.name_reset).toEqual({ version: 3, ack_version: 0 });
    expect(saved.profile?.name).toBeUndefined(); expect(saved.profile?.name_locked_until).toBe(f.now() + 7 * 86_400_000);
    expect(saved.sanctions?.name_reset_at).toBe(f.now()); expect(saved.seq).toBe(seq + 3);
    expect(saved.bag).toEqual(bag); expect(f.store.peek(Q)).toEqual(other); expect(f.actions.renamed).toHaveBeenCalledTimes(3);
    expect((await f.get()).json()).toEqual({ ok: true, name_reset: { version: 3 } });
  });

  it('only advances the precise ACK version, with no seq/broadcast/asset/lock change; duplicate ACK has no write', async () => {
    const f = await setup(); await f.reset(); await f.reset();
    const before = structuredClone(f.store.peek(P)!);
    const puts = vi.spyOn(f.store, 'put'); f.actions.renamed.mockClear();
    expect((await f.ack(1)).json()).toEqual({ ok: true });
    const expected = structuredClone(before); expected.account_notices!.name_reset.ack_version = 1;
    expect(f.store.peek(P)).toEqual(expected); expect((await f.get()).json()).toEqual({ ok: true, name_reset: { version: 2 } });
    expect(puts).toHaveBeenCalledTimes(1); expect(f.actions.renamed).not.toHaveBeenCalled();
    expect((await f.ack(1)).json()).toEqual({ ok: true }); expect(puts).toHaveBeenCalledTimes(1);
    expect((await f.ack(2)).json()).toEqual({ ok: true }); expect((await f.get()).json()).toEqual({ ok: true, name_reset: null });
    expect(f.store.peek(P)!.seq).toBe(before.seq);
  });

  it('serializes concurrent reset/old ACK without swallowing the new event, and parallel same-version ACK is idempotent', async () => {
    const f = await setup(); await f.reset();
    const [reset, old] = await Promise.all([f.reset(), f.ack(1)]);
    expect(reset.json().ok).toBe(true); expect(old.json()).toEqual({ ok: true });
    expect(f.store.peek(P)?.account_notices?.name_reset).toEqual({ version: 2, ack_version: 1 });
    const put = vi.spyOn(f.store, 'put');
    const responses = await Promise.all([f.ack(2), f.ack(2, ADMIN)]);
    expect(responses.map(r => r.json())).toEqual([{ ok: true }, { ok: true }]); expect(put).toHaveBeenCalledTimes(1);
    await f.reset(); await f.ack(2);
    expect((await f.get(ADMIN)).json()).toEqual({ ok: true, name_reset: { version: 3 } });
  });

  it('ACK survives restart/lost response; historical timestamp never recreates an acknowledged event', async () => {
    const f = await setup(); const s = f.store.peek(P)!; s.sanctions = { name_reset_at: 0 }; f.store.put(s);
    const before = readFileSync(f.file, 'utf8');
    expect((await f.get()).json()).toEqual({ ok: true, name_reset: { version: 1 } });
    expect(readFileSync(f.file, 'utf8')).toBe(before); expect(f.store.peek(P)?.account_notices).toBeUndefined();
    await f.ack(1); // Treat its response as lost.
    const reloaded = new P0Store(C, f.file), app = Fastify();
    registerAccountNoticeRoutes(app, { store: reloaded, identify: f.identity });
    try {
      const put = vi.spyOn(reloaded, 'put');
      const ack = await app.inject({ method: 'POST', url: '/v1/p0/account/notices/ack', headers: f.headers(ADMIN), payload: { kind: 'name_reset', version: 1 } });
      expect(ack.json()).toEqual({ ok: true }); expect(put).not.toHaveBeenCalled();
      expect((await app.inject({ method: 'GET', url: '/v1/p0/account/notices', headers: f.headers(ADMIN) })).json()).toEqual({ ok: true, name_reset: null });
      expect(reloaded.peek(P)?.sanctions?.name_reset_at).toBe(0);
    } finally { await app.close(); }
  });

  it('a new reset after an unread historical event starts at 2, without changing SAVE_VERSION or other data', async () => {
    const f = await setup(), s = f.store.peek(P)!;
    s.sanctions = { name_reset_at: T0 - 1000 }; f.store.put(s); const version = s.v;
    await f.reset();
    expect(f.store.peek(P)?.account_notices?.name_reset).toEqual({ version: 2, ack_version: 0 });
    expect(f.store.peek(P)?.v).toBe(version);
    await f.ack(1); expect((await f.get()).json().name_reset).toEqual({ version: 2 });
  });

  it('cooldown expiry and voluntary rename do not acknowledge or suppress an unread reset', async () => {
    const f = await setup(); await f.reset(); f.tick(8 * 86_400_000);
    const s = structuredClone(f.store.peek(P)!); s.profile!.name = 'New Name'; s.profile!.name_set_at = f.now(); f.store.put(s);
    expect((await f.get()).json()).toEqual({ ok: true, name_reset: { version: 1 } });
    const before = structuredClone(f.store.peek(P)!); await f.ack(1);
    expect(f.store.peek(P)?.profile).toEqual(before.profile); expect(f.store.peek(P)?.seq).toBe(before.seq);
  });

  it('unknown/legacy identity, absent save, suspension and deletion never gain access or create a save', async () => {
    const f = await setup(); await f.reset();
    for (const method of ['GET', 'POST'] as const) {
      const url = '/v1/p0/account/notices' + (method === 'POST' ? '/ack' : '');
      const payload = method === 'POST' ? { kind: 'name_reset', version: 1 } : undefined;
      const r = await f.app.inject({ method, url, payload, headers: { 'x-p0-key': 'fake-game-key', 'x-p0-player': P } });
      expect([r.statusCode, r.json().code]).toEqual([401, 'unauthenticated']); expect(r.headers['cache-control']).toBe('no-store');
    }
    expect((await f.get('9'.repeat(64))).statusCode).toBe(401);
    const noKey = await f.app.inject({ method: 'GET', url: '/v1/p0/account/notices', headers: { authorization: `Bearer ${TOKEN}` } });
    expect(noKey.statusCode).toBe(401); expect(noKey.headers['cache-control']).toBe('no-store');
    f.store.peek(P)!.sanctions!.suspended = { until: null, at: T0 };
    expect((await f.get()).json()).toEqual({ ok: false, code: 'suspended', until: null });
    expect((await f.ack(1)).statusCode).toBe(403);
    delete f.store.peek(P)!.sanctions!.suspended;
    f.accounts.markDeleted(P, T0);
    expect((await f.get(ADMIN)).json()).toEqual({ ok: false, code: 'account_deleted' });
    expect((await f.ack(1, ADMIN)).statusCode).toBe(401); // A partial deletion must not be bypassed by a leftover admin token.
    f.accounts.markDeleted(P, T0 - 31 * 86_400_000); // Expired marker only for the separate missing-save case below.
    f.store.remove(P); expect((await f.get()).json()).toEqual({ ok: false, code: 'unauthenticated' }); expect((await f.ack(1)).statusCode).toBe(401);
    expect(f.store.peek(P)).toBeUndefined();
    f.accounts.revokeAll(P, undefined, { admin: true }); f.accounts.markDeleted(P, T0);
    const deleted = await f.app.inject({ method: 'GET', url: '/v1/p0/account/notices', headers: { ...f.headers(TOKEN), 'x-p0-player': P } });
    expect(deleted.json().code).toBe('account_deleted');
  });

  it('token owns the target; extra ACK fields are rejected, and public views/status do not leak the notice or admin data', async () => {
    const f = await setup(); await f.reset();
    const own = await f.app.inject({ method: 'GET', url: '/v1/p0/account/notices?player=' + Q, headers: { ...f.headers(TOKEN), 'x-p0-player': Q } });
    expect(own.json()).toEqual({ ok: true, name_reset: { version: 1 } });
    expect((await f.get(OTHER)).json()).toEqual({ ok: true, name_reset: null });
    expect((await f.ack(1, TOKEN, { player: Q })).statusCode).toBe(400);
    const view = (await f.app.inject({ method: 'GET', url: '/v1/p0/state', headers: f.headers(TOKEN) })).json().state;
    expect(view).not.toHaveProperty('account_notices'); expect(view.account).not.toHaveProperty('name_reset'); expect(view.account).not.toHaveProperty('name_reset_at');
    const voice = (await f.app.inject({ method: 'GET', url: '/v1/p0/voice/status', headers: f.headers(TOKEN) })).json();
    expect(voice).not.toHaveProperty('name_reset'); expect(voice).not.toHaveProperty('name_reset_at');
  });

  it('rejects bad ACK shapes and future versions with no mutation, including no-event conflict', async () => {
    const f = await setup(), before = readFileSync(f.file, 'utf8');
    expect((await f.ack(1)).json()).toEqual({ ok: false, code: 'notice_version_conflict' });
    for (const value of [0, -1, 1.5, '1', null, Number.MAX_SAFE_INTEGER + 1]) expect((await f.ack(value)).statusCode).toBe(400);
    expect((await f.ack(1, TOKEN, { kind: 'other' })).statusCode).toBe(400);
    expect(readFileSync(f.file, 'utf8')).toBe(before);
    await f.reset(); const puts = vi.spyOn(f.store, 'put');
    expect((await f.ack(2)).statusCode).toBe(409); expect(puts).not.toHaveBeenCalled();
  });

  it.each([null, {}, { name_reset: null }, { name_reset: { version: 0, ack_version: 0 } },
    { name_reset: { version: 1, ack_version: 2 } }, { name_reset: { version: '1', ack_version: 0 } },
    { name_reset: { version: 1 } }])('malformed new watermark is never treated as confirmed or replaced from history: %j', bad => {
    const state = new P0Store(C).get(P, T0);
    Object.assign(state, { sanctions: { name_reset_at: T0 }, account_notices: bad });
    expect(() => nameResetWatermark(state)).toThrow('NOTICE_FAILED');
  });

  it('corruption and maximum-version overflow fail management atomically; GET/ACK corruption is notice_failed', async () => {
    const f = await setup(), state = f.store.peek(P)!; state.profile = { name: 'Keep Name' };
    Object.assign(state, { account_notices: { name_reset: { version: 1, ack_version: 2 } } }); f.store.put(state);
    const before = readFileSync(f.file, 'utf8'), put = vi.spyOn(f.store, 'put');
    for (const r of [await f.get(), await f.ack(1), await f.reset()]) expect([r.statusCode, r.json()]).toEqual([500, { ok: false, code: 'notice_failed' }]);
    expect(put).not.toHaveBeenCalled(); expect(readFileSync(f.file, 'utf8')).toBe(before); expect(f.actions.renamed).not.toHaveBeenCalled();
    state.account_notices = { name_reset: { version: Number.MAX_SAFE_INTEGER, ack_version: Number.MAX_SAFE_INTEGER - 1 } };
    f.store.put(state); put.mockClear(); const maxBefore = structuredClone(state);
    expect((await f.reset()).json().code).toBe('notice_failed'); expect(put).not.toHaveBeenCalled(); expect(f.store.peek(P)).toEqual(maxBefore);
    expect((await f.ack(Number.MAX_SAFE_INTEGER)).json()).toEqual({ ok: true });
    expect((await f.get()).json()).toEqual({ ok: true, name_reset: null });
  });

  it('failed ACK/reset persistence retains the live object and disk, and retries without consuming an event version', async () => {
    const f = await setup(); await f.reset();
    const before = readFileSync(f.file, 'utf8'), live = f.store.peek(P); f.actions.renamed.mockClear();
    mkdirSync(f.file + '.tmp');
    expect((await f.ack(1)).json()).toEqual({ ok: false, code: 'notice_failed' });
    expect(f.store.peek(P)).toBe(live); expect(readFileSync(f.file, 'utf8')).toBe(before);
    expect((await f.reset()).json().code).toBe('moderation_write_failed');
    expect(f.store.peek(P)).toBe(live); expect(readFileSync(f.file, 'utf8')).toBe(before); expect(f.actions.renamed).not.toHaveBeenCalled();
    rmSync(f.file + '.tmp', { recursive: true }); await f.ack(1); await f.reset();
    expect(f.store.peek(P)?.account_notices?.name_reset).toEqual({ version: 2, ack_version: 1 });
    expect(f.actions.renamed).toHaveBeenCalledTimes(1);
  });

  it('malformed old timestamps fail closed, but a valid new watermark remains authoritative over legacy time', () => {
    const state = new P0Store(C).get(P, T0);
    for (const at of [null, -1, 0.5, 'today', Number.MAX_SAFE_INTEGER + 1]) {
      Object.assign(state, { sanctions: { name_reset_at: at } });
      expect(() => nameResetWatermark(state)).toThrow('NOTICE_FAILED');
    }
    for (const sanctions of [null, [], 'bad']) {
      Object.assign(state, { sanctions }); expect(() => nameResetWatermark(state)).toThrow('NOTICE_FAILED');
    }
    state.account_notices = { name_reset: { version: 1, ack_version: 1 } };
    expect(nameResetWatermark(state)).toEqual({ version: 1, ack_version: 1 });
    const copy = nameResetWatermark(state); copy.ack_version = 0;
    expect(state.account_notices.name_reset.ack_version).toBe(1);
  });

  it('account deletion removes notices with the save and a subsequent notice request never recreates it', async () => {
    const f = await setup(); await f.reset();
    await deleteAccount({ store: f.store, accounts: f.accounts, voice: f.voice, hub: { kick() {} }, now: f.now }, P);
    expect(f.store.peek(P)).toBeUndefined(); expect((await f.get()).statusCode).toBe(401);
    expect(f.store.peek(P)).toBeUndefined(); expect(f.store.peek(Q)).toBeDefined();
  });
});
