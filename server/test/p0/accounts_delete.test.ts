/** SGODOT-484 PR1: isolated files only; no real provider or production deletion. */
import Fastify from 'fastify';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it, vi } from 'vitest';
import WebSocket from 'ws';
import { deleteAccount, previewAccountDeletion, registerAccountDeleteRoute } from '../../src/p0/accounts/delete.js';
import { identify } from '../../src/p0/accounts/identify.js';
import { registerAccountRoutes } from '../../src/p0/accounts/routes.js';
import { P0Accounts } from '../../src/p0/accounts/store.js';
import { loadP0Content } from '../../src/p0/content.js';
import { loadOutposts } from '../../src/p0/online/outposts.js';
import { registerP0Online } from '../../src/p0/online/hub.js';
import { OutpostRooms } from '../../src/p0/online/rooms.js';
import { P0Voice, registerP0Voice } from '../../src/p0/online/voice.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { P0Store } from '../../src/p0/store.js';
import { supportCode } from '../../src/p0/support.js';

const content = loadP0Content(), dirs: string[] = [];
const PLAYER = 'p0-delete-target', OTHER = 'p0-delete-kept', THIRD = 'p0-delete-third';
const KEY = Buffer.alloc(32, 7), USER_TOKEN = '1'.repeat(64), ADMIN_TOKEN = '2'.repeat(64), OTHER_TOKEN = '3'.repeat(64);
const T0 = Date.UTC(2026, 10, 13);
afterEach(() => { vi.restoreAllMocks(); for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true }); });

function setup() {
  const dir = mkdtempSync(path.join(tmpdir(), 'p0-delete-')); dirs.push(dir);
  const files = { save: path.join(dir, 'save.json'), accounts: path.join(dir, 'accounts.json'),
    ages: path.join(dir, 'ages.json'), blocks: path.join(dir, 'blocks.json'), reports: path.join(dir, 'reports.jsonl') };
  let time = T0;
  const now = () => time;
  const store = new P0Store(content, files.save), accounts = new P0Accounts(files.accounts, KEY, now);
  for (const p of [PLAYER, OTHER, THIRD]) { store.get(p, now()); accounts.ensure(p); }
  accounts.issue(PLAYER, USER_TOKEN);
  accounts.issue(PLAYER, ADMIN_TOKEN, 'admin', T0 + 86_400_000);
  accounts.issue(OTHER, OTHER_TOKEN);
  accounts.link(PLAYER, 'apple', { sub: 'apple-test-sub', aud: 'app.gensen.maps.web', refresh: 'fake-refresh-private' });
  accounts.link(PLAYER, 'google', { sub: 'google-test-sub' });
  writeFileSync(files.ages, JSON.stringify({ [PLAYER]: true, [OTHER]: false }));
  writeFileSync(files.blocks, JSON.stringify({ [PLAYER]: [OTHER], [OTHER]: [PLAYER, THIRD], [THIRD]: [PLAYER] }));
  writeFileSync(files.reports, JSON.stringify({ reporter: PLAYER, target: OTHER, at: T0 }) + '\n');
  const voice = new P0Voice(null, new OutpostRooms(loadOutposts()), files, now);
  const hub = { kick: vi.fn() }, revokeApple = vi.fn(async (_aud: string, _refresh: string) => {});
  const deps = { store, accounts, voice, hub, revokeApple, now };
  return { ...deps, deps, files, tick: (ms: number) => { time += ms; } };
}
const json = (file: string) => JSON.parse(readFileSync(file, 'utf8'));

describe('account deletion (contract-accounts §4)', () => {
  it('integrates A1: revoked tokens and legacy ids cannot read, claim or rejoin, nor can queued WS messages recreate presence', async () => {
    const { deps, files } = setup();
    const app = Fastify(), rooms = new OutpostRooms(loadOutposts());
    const voice = new P0Voice(null, rooms, files, deps.now);
    const identity = { accounts: deps.accounts, legacyId: false, warn: () => {} };
    const who = (headers: Record<string, unknown>) => identify(headers, identity);
    const hub = registerP0Online(app, { rooms, identify: who, departed: o => voice.departed(o) });
    registerP0Voice(app, voice, who);
    registerP0Routes(app, { content, store: deps.store, now: deps.now, dev: false, identify: identity });
    registerAccountRoutes(app, { ...deps, identify: identity, versions: { terms: 'test', privacy: 'test' },
      verify: async () => ({ link: { sub: 'g-deleted' } }), pending: { take: () => undefined, create: () => 'pend' } });
    await app.listen({ port: 0, host: '127.0.0.1' });
    const url = `ws://127.0.0.1:${(app.server.address() as { port: number }).port}/v1/p0/online`;
    const headers = { authorization: `Bearer ${USER_TOKEN}`, 'x-p0-player': PLAYER };
    const ws = new WebSocket(url, { headers });
    try {
      await new Promise<void>((resolve, reject) => { ws.once('open', resolve); ws.once('error', reject); });
      const joined = new Promise<void>(resolve => ws.on('message', data => {
        if (String(data).startsWith('{') && JSON.parse(String(data)).t === 'joined') resolve();
      }));
      ws.send(JSON.stringify({ t: 'join', outpost: 'sh_tea_1' }));
      await joined;
      const old = [...hub.conns][0];
      const closed = new Promise<number>(resolve => ws.once('close', resolve));
      const deleting = deleteAccount({ ...deps, voice, hub }, PLAYER);
      old.ws.emit('message', Buffer.from(JSON.stringify({ t: 'join', outpost: 'sh_tea_1' })), false);
      await deleting;
      expect(await closed).toBe(4001);
      expect(rooms.total()).toBe(0);
      expect(hub.conns.size).toBe(0);
      for (const auth of [headers, { 'x-p0-player': PLAYER }, { authorization: `Bearer ${ADMIN_TOKEN}`, 'x-p0-player': PLAYER }]) {
        const r = await app.inject({ method: 'GET', url: '/v1/p0/state', headers: auth });
        expect([r.statusCode, r.json().code]).toEqual([401, 'account_deleted']);
      }
      const claim = await app.inject({ method: 'POST', url: '/v1/p0/session/claim', headers: { 'x-p0-player': PLAYER }, payload: { provider: 'google', id_token: 'x', nonce: 'n', token: '4'.repeat(64) } });
      expect([claim.statusCode, claim.json().code]).toEqual([404, 'unknown_player']);
      const voiceRead = await app.inject({ method: 'GET', url: '/v1/p0/voice/status', headers });
      expect(voiceRead.statusCode).toBe(401);
      const refused = await new Promise<number>((resolve, reject) => {
        const again = new WebSocket(url, { headers });
        again.once('unexpected-response', (_req, res) => { res.resume(); res.once('end', () => resolve(res.statusCode!)); });
        again.once('open', () => { again.terminate(); reject(new Error('deleted account rejoined')); });
        again.once('error', reject);
      });
      expect(refused).toBe(401);
      expect(deps.store.peek(PLAYER)).toBeUndefined();
      expect(deps.store.size()).toBe(2);
      expect((await app.inject({ method: 'GET', url: '/v1/p0/state', headers: { authorization: `Bearer ${OTHER_TOKEN}` } })).statusCode).toBe(200);
    } finally { ws.terminate(); await app.close(); }
  });

  it('matches the client support code vectors without exposing the player id', () => {
    expect(supportCode('p0-shot-nezha')).toBe('WKRW4-9CH60');
    expect(supportCode('test-1')).toBe('55YF1-3C0J8');
    expect(supportCode('')).toBe('');
  });

  it('preview does not create, settle or write, and contains no identity, token or name', () => {
    const { deps, files, store } = setup();
    const before = Object.values(files).map(f => readFileSync(f, 'utf8'));
    vi.spyOn(store, 'find').mockImplementation(() => { throw new Error('preview must not settle'); });
    vi.spyOn(store, 'get').mockImplementation(() => { throw new Error('preview must not create'); });
    const preview = previewAccountDeletion(deps, PLAYER);
    expect(preview).toMatchObject({ support_code: supportCode(PLAYER), found: true, deleted: false, linked: ['apple', 'google'], save: { level: 1 } });
    expect(previewAccountDeletion(deps, 'p0-nobody')).toMatchObject({ found: false, save: null, linked: [] });
    expect(Object.values(files).map(f => readFileSync(f, 'utf8'))).toEqual(before);
    for (const secret of [PLAYER, 'apple-test-sub', 'google-test-sub', 'fake-refresh-private', USER_TOKEN, ADMIN_TOKEN]) {
      expect(JSON.stringify(preview)).not.toContain(secret);
    }
  });

  it('deletes the save, all token kinds, links, age and both sides of blocks; preserves others and reports after reload', async () => {
    const { deps, files, now, revokeApple, hub } = setup();
    const otherSave = structuredClone(deps.store.peek(OTHER)), otherAccount = deps.accounts.find(OTHER);
    const reports = readFileSync(files.reports, 'utf8');
    await deleteAccount(deps, PLAYER);
    const store = new P0Store(content, files.save), accounts = new P0Accounts(files.accounts, KEY, now);
    expect(store.peek(PLAYER)).toBeUndefined();
    expect(store.peek(OTHER)).toEqual(otherSave);
    expect(accounts.find(PLAYER)).toBeUndefined();
    expect(accounts.find(OTHER)).toEqual(otherAccount);
    expect(accounts.byToken(USER_TOKEN)).toBeUndefined();
    expect(accounts.byToken(ADMIN_TOKEN)).toBeUndefined();
    expect(accounts.byToken(OTHER_TOKEN)?.player).toBe(OTHER);
    expect(accounts.byIdentity('apple', 'apple-test-sub')).toBeUndefined();
    expect(accounts.byIdentity('google', 'google-test-sub')).toBeUndefined();
    expect(accounts.isDeleted(PLAYER)).toBe(true);
    expect(json(files.ages)).toEqual({ [OTHER]: false });
    expect(json(files.blocks)).toEqual({ [OTHER]: [THIRD] });
    expect(readFileSync(files.reports, 'utf8')).toBe(reports);
    expect(hub.kick).toHaveBeenCalledTimes(1);
    expect(hub.kick).toHaveBeenCalledWith(PLAYER);
    expect(revokeApple).toHaveBeenCalledTimes(1);
    expect(revokeApple).toHaveBeenCalledWith('app.gensen.maps.web', 'fake-refresh-private');
  });

  it('follows accounts → save → voice/hub → Apple with a fake accounts port', async () => {
    const { deps } = setup(), events: string[] = [];
    const accounts = { find: () => ({ apple: { aud: 'web-aud', refresh: 'fake-refresh' } }), isDeleted: () => false,
      revokeAll: () => events.push('revoke'), markDeleted: () => events.push('deleted'), remove: () => events.push('accounts') };
    vi.spyOn(deps.store, 'remove').mockImplementation(() => { events.push('save'); return true; });
    vi.spyOn(deps.voice, 'removePlayer').mockImplementation(async () => { events.push('voice'); });
    deps.hub.kick.mockImplementation(() => { events.push('hub'); });
    deps.revokeApple.mockImplementation(async () => { events.push('apple'); });
    await deleteAccount({ ...deps, accounts: accounts as unknown as P0Accounts }, PLAYER);
    expect(events).toEqual(['revoke', 'deleted', 'accounts', 'save', 'voice', 'hub', 'apple']);
  });

  it('is idempotent without extending the tombstone, and an unknown player is a no-op', async () => {
    const { deps, files, tick } = setup();
    await deleteAccount(deps, PLAYER);
    tick(86_400_000);
    await deleteAccount(deps, PLAYER);
    expect(json(files.accounts).deleted[PLAYER]).toBe(T0);
    expect(deps.revokeApple).toHaveBeenCalledTimes(1);
    const before = Object.values(files).map(f => readFileSync(f, 'utf8'));
    await deleteAccount(deps, 'p0-nobody');
    expect(Object.values(files).map(f => readFileSync(f, 'utf8'))).toEqual(before);
    expect(deps.hub.kick).toHaveBeenCalledTimes(2);
  });

  it('coalesces concurrent deletion while the provider is pending', async () => {
    const { deps } = setup();
    let release!: () => void;
    const provider = new Promise<void>(resolve => { release = resolve; });
    deps.revokeApple.mockImplementation(() => provider);
    const first = deleteAccount(deps, PLAYER), second = deleteAccount(deps, PLAYER);
    await vi.waitFor(() => expect(deps.revokeApple).toHaveBeenCalledTimes(1));
    expect(deps.hub.kick).toHaveBeenCalledTimes(1);
    release();
    await Promise.all([first, second]);
  });

  it('does not delete the save if the accounts phase cannot persist', async () => {
    const { deps, files } = setup();
    const before = readFileSync(files.save, 'utf8');
    mkdirSync(files.accounts + '.tmp');
    await expect(deleteAccount(deps, PLAYER)).rejects.toThrow();
    expect(readFileSync(files.save, 'utf8')).toBe(before);
    expect(deps.store.peek(PLAYER)).toBeDefined();
    expect(deps.hub.kick).not.toHaveBeenCalled();
    rmSync(files.accounts + '.tmp', { recursive: true });
    await deleteAccount(deps, PLAYER);
    expect(new P0Accounts(files.accounts, KEY, deps.now).isDeleted(PLAYER)).toBe(true);
    expect(new P0Store(content, files.save).peek(PLAYER)).toBeUndefined();
  });

  it.each([false, true])('retries only accounts.remove failing after token revocation and tombstone persisted (restart=%s)', async restart => {
    const { deps, files } = setup();
    const saved = readFileSync(files.save, 'utf8'), ages = readFileSync(files.ages, 'utf8');
    const remove = deps.accounts.remove.bind(deps.accounts);
    const spy = vi.spyOn(deps.accounts, 'remove').mockImplementationOnce(player => {
      const persisted = new P0Accounts(files.accounts, KEY, deps.now);
      expect(persisted.byToken(USER_TOKEN)).toBeUndefined();
      expect(persisted.isDeleted(PLAYER)).toBe(true);
      mkdirSync(files.accounts + '.tmp'); // Only the final remove write fails, not revokeAll or markDeleted.
      remove(player);
    });
    await expect(deleteAccount(deps, PLAYER)).rejects.toThrow();
    expect(readFileSync(files.save, 'utf8')).toBe(saved);
    expect(readFileSync(files.ages, 'utf8')).toBe(ages);
    expect(deps.hub.kick).not.toHaveBeenCalled();
    expect(deps.revokeApple).not.toHaveBeenCalled();
    rmSync(files.accounts + '.tmp', { recursive: true });
    spy.mockRestore();
    const next = restart ? { ...deps, accounts: new P0Accounts(files.accounts, KEY, deps.now) } : deps;
    await deleteAccount(next, PLAYER);
    const persisted = new P0Accounts(files.accounts, KEY, deps.now);
    expect(persisted.find(PLAYER)).toBeUndefined();
    expect(persisted.byToken(ADMIN_TOKEN)).toBeUndefined();
    expect(persisted.byToken(OTHER_TOKEN)?.player).toBe(OTHER);
    expect(persisted.byIdentity('apple', 'apple-test-sub')).toBeUndefined();
    expect(json(files.accounts).deleted[PLAYER]).toBe(T0);
    expect(new P0Store(content, files.save).peek(PLAYER)).toBeUndefined();
    expect(json(files.ages)).toEqual({ [OTHER]: false });
  });

  it.each([false, true])('retries a failed save write (restart=%s) while still removing voice and WS', async restart => {
    const { deps, files } = setup();
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    const before = readFileSync(files.save, 'utf8');
    mkdirSync(files.save + '.tmp');
    await expect(deleteAccount(deps, PLAYER)).rejects.toThrow('ACCOUNT_DELETE_INCOMPLETE');
    expect(deps.store.peek(PLAYER)).toBeDefined();
    expect(readFileSync(files.save, 'utf8')).toBe(before);
    expect(deps.hub.kick).toHaveBeenCalledWith(PLAYER);
    expect(json(files.ages)[PLAYER]).toBeUndefined();
    expect(json(files.accounts).deleted[PLAYER]).toBe(T0);
    rmSync(files.save + '.tmp', { recursive: true });
    const next = restart ? { ...deps, store: new P0Store(content, files.save), accounts: new P0Accounts(files.accounts, KEY, deps.now) } : deps;
    await deleteAccount(next, PLAYER);
    expect(new P0Store(content, files.save).peek(PLAYER)).toBeUndefined();
  });

  it('retries partial voice-file failure without losing unrelated blocks', async () => {
    const { deps, files } = setup();
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    mkdirSync(files.blocks + '.tmp');
    await expect(deleteAccount(deps, PLAYER)).rejects.toThrow('ACCOUNT_DELETE_INCOMPLETE');
    expect(json(files.ages)[PLAYER]).toBeUndefined();
    expect(json(files.blocks)[OTHER]).toContain(PLAYER);
    expect(deps.hub.kick).toHaveBeenCalledWith(PLAYER);
    rmSync(files.blocks + '.tmp', { recursive: true });
    await deleteAccount(deps, PLAYER);
    expect(json(files.blocks)).toEqual({ [OTHER]: [THIRD] });
    expect(json(files.ages)).toEqual({ [OTHER]: false });
  });

  it('Apple failure is best effort and logs only a support code, never provider error text or credentials', async () => {
    const { deps } = setup();
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    deps.revokeApple.mockRejectedValue(new Error('fake-refresh-private ' + PLAYER));
    await expect(deleteAccount(deps, PLAYER)).resolves.toBeUndefined();
    expect(warn.mock.calls).toEqual([[JSON.stringify({ account: 'apple_revoke_failed', support_code: supportCode(PLAYER) })]]);
    expect(deps.store.peek(PLAYER)).toBeUndefined();
  });

  it.each(['callback', 'refresh'])('local deletion succeeds without Apple %s, recording the skip', async missing => {
    const { deps } = setup();
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    if (missing === 'refresh') deps.accounts.link(PLAYER, 'apple', { sub: 'apple-test-sub', aud: 'app.gensen.maps.web' });
    await deleteAccount({ ...deps, ...(missing === 'callback' ? { revokeApple: undefined } : {}) }, PLAYER);
    expect(deps.store.peek(PLAYER)).toBeUndefined();
    expect(warn.mock.calls).toEqual([[JSON.stringify({ account: 'apple_revoke_skipped', support_code: supportCode(PLAYER) })]]);
  });
});

describe('DELETE /v1/p0/account (SGODOT-488; contract §4, v1.6.6)', () => {
  const route = (over: { suspended?: (p: string) => { until: number | null } | null } = {}) => {
    const { deps } = setup();
    const app = Fastify();
    const identity = { accounts: deps.accounts, legacyId: false, warn: () => {}, ...over };
    registerAccountDeleteRoute(app, { ...deps, identify: identity });
    registerP0Routes(app, { content, store: deps.store, now: deps.now, dev: false, identify: identity });
    const del = (headers: Record<string, string>) => app.inject({ method: 'DELETE', url: '/v1/p0/account', headers });
    return { deps, app, del };
  };
  it("deletes the token's own account (Apple's authorization withdrawn with it); its token then reads account_deleted", async () => {
    const { deps, app, del } = route();
    expect((await del({ authorization: `Bearer ${USER_TOKEN}` })).json()).toEqual({ ok: true });
    expect(deps.store.peek(PLAYER)).toBeUndefined();
    expect(deps.accounts.isDeleted(PLAYER)).toBe(true);
    expect(deps.revokeApple).toHaveBeenCalledWith('app.gensen.maps.web', 'fake-refresh-private');
    const r = await app.inject({ method: 'GET', url: '/v1/p0/state', headers: { authorization: `Bearer ${USER_TOKEN}`, 'x-p0-player': PLAYER } });
    expect([r.statusCode, r.json().code]).toEqual([401, 'account_deleted']);
    expect(deps.store.peek(OTHER)).toBeDefined();
  });
  it('a suspended account can still delete itself; every other route still turns it away', async () => {
    const { deps, app, del } = route({ suspended: p => (p === PLAYER ? { until: null } : null) });
    const read = await app.inject({ method: 'GET', url: '/v1/p0/state', headers: { authorization: `Bearer ${USER_TOKEN}` } });
    expect([read.statusCode, read.json().code]).toEqual([403, 'suspended']);
    expect((await del({ authorization: `Bearer ${USER_TOKEN}` })).json()).toEqual({ ok: true });
    expect(deps.accounts.isDeleted(PLAYER)).toBe(true);
  });
  it('an id alone cannot delete (an old build, or anyone who knows an id); an unknown token is unauthenticated', async () => {
    const { deps, del } = route();
    const legacy = await del({ 'x-p0-player': THIRD });
    expect([legacy.statusCode, legacy.json().code]).toEqual([401, 'unauthenticated']);
    expect(deps.store.peek(THIRD)).toBeDefined();
    const unknown = await del({ authorization: `Bearer ${'9'.repeat(64)}` });
    expect([unknown.statusCode, unknown.json().code]).toEqual([401, 'unauthenticated']);
  });
  it('a later step that fails still answers ok — the account is gone for every request; the log asks the admin to finish', async () => {
    const { deps, del } = route();
    vi.spyOn(deps.store, 'remove').mockImplementationOnce(() => { throw new Error('disk'); });
    const warned: string[] = [];
    vi.spyOn(console, 'warn').mockImplementation((l: string) => { warned.push(l); });
    expect((await del({ authorization: `Bearer ${USER_TOKEN}` })).json()).toEqual({ ok: true });
    expect(deps.accounts.isDeleted(PLAYER)).toBe(true);
    expect(deps.accounts.tokenOwner(USER_TOKEN)).toBeUndefined();
    expect(warned).toContain(JSON.stringify({ account: 'delete_incomplete_app', support_code: supportCode(PLAYER) }));
    expect(deps.store.peek(PLAYER)).toBeDefined();   // left for the admin's run on the tombstone
    await deleteAccount(deps, PLAYER);
    expect(deps.store.peek(PLAYER)).toBeUndefined();
  });
  it('the first stretch failing to write is 500 delete_failed — nothing deleted, never told it was (周瑜 on #1048)', async () => {
    const { deps, del } = route();
    vi.spyOn(deps.accounts, 'markDeleted').mockImplementation(() => { throw new Error('EIO'); });   // both tries
    const warned: string[] = [];
    vi.spyOn(console, 'warn').mockImplementation((l: string) => { warned.push(l); });
    const r = await del({ authorization: `Bearer ${USER_TOKEN}` });
    expect([r.statusCode, r.json()]).toEqual([500, { ok: false, code: 'delete_failed' }]);
    expect(deps.accounts.isDeleted(PLAYER)).toBe(false);
    expect(deps.store.peek(PLAYER)).toBeDefined();
    expect(warned).toContain(JSON.stringify({ account: 'delete_failed_app', support_code: supportCode(PLAYER) }));
  });
  it('a passing write error is tried once more at once: the second try deletes and answers ok', async () => {
    const { deps, del } = route();
    vi.spyOn(deps.accounts, 'markDeleted').mockImplementationOnce(() => { throw new Error('EIO'); });
    expect((await del({ authorization: `Bearer ${USER_TOKEN}` })).json()).toEqual({ ok: true });
    expect(deps.accounts.isDeleted(PLAYER)).toBe(true);
    expect(deps.store.peek(PLAYER)).toBeUndefined();
  });
});

describe('deleteAccount resumes from any step that failed to write (苏烈 on #1048, 484 8c4a62d5)', () => {
  for (const step of ['revokeAll', 'markDeleted', 'remove', 'store.remove'] as const) {
    it(`a failure at ${step}, then the same call again: the account deleted to the end`, async () => {
      const { deps } = setup();
      vi.spyOn(console, 'warn').mockImplementation(() => {});
      const target = step === 'store.remove' ? deps.store : deps.accounts;
      const name = step === 'store.remove' ? 'remove' : step;
      vi.spyOn(target as unknown as Record<string, () => unknown>, name).mockImplementationOnce(() => { throw new Error('EIO'); });
      await expect(deleteAccount(deps, PLAYER)).rejects.toThrow();
      await deleteAccount(deps, PLAYER);
      expect(deps.accounts.isDeleted(PLAYER)).toBe(true);
      expect(deps.accounts.find(PLAYER)).toBeUndefined();
      expect(deps.accounts.tokenOwner(USER_TOKEN)).toBeUndefined();
      expect(deps.store.peek(PLAYER)).toBeUndefined();
      expect(deps.store.peek(OTHER)).toBeDefined();
      expect(deps.revokeApple).toHaveBeenCalledTimes(1);   // once, never lost on the way
    });
  }
  it("the account row's write failing, retried in the same process: Apple's authorization still withdrawn", async () => {
    const { deps } = setup();
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    const real = deps.accounts.remove.bind(deps.accounts);
    // the row taken out of memory, then the write fails — what a disk error inside remove leaves
    vi.spyOn(deps.accounts, 'remove').mockImplementationOnce((p: string) => { real(p); throw new Error('EIO'); });
    await expect(deleteAccount(deps, PLAYER)).rejects.toThrow('EIO');
    expect(deps.revokeApple).toHaveBeenCalledTimes(1);
    await deleteAccount(deps, PLAYER);   // finds no row now: no second revoke, the rest done
    expect(deps.store.peek(PLAYER)).toBeUndefined();
    expect(deps.revokeApple).toHaveBeenCalledTimes(1);
  });
  it('markDeleted failing twice: 500, the farm there, and Apple not withdrawn (周瑜 on #1049)', async () => {
    const { deps } = setup();
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    const app = Fastify();
    registerAccountDeleteRoute(app, { ...deps, identify: { accounts: deps.accounts, legacyId: false, warn: () => {} } });
    vi.spyOn(deps.accounts, 'markDeleted').mockImplementation(() => { throw new Error('EIO'); });
    const r = await app.inject({ method: 'DELETE', url: '/v1/p0/account', headers: { authorization: `Bearer ${USER_TOKEN}` } });
    expect([r.statusCode, r.json().code]).toEqual([500, 'delete_failed']);
    expect(deps.store.peek(PLAYER)).toBeDefined();
    expect(deps.accounts.find(PLAYER)?.apple).toBeDefined();
    expect(deps.revokeApple).not.toHaveBeenCalled();
  });
});
