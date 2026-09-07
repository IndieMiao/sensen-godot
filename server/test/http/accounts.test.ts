import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import path from 'node:path';
import { buildApp, blueprintSets, loadBlueprint, type AppDeps } from '../../src/http/app.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { MemoryAccountStore } from '../../src/http/memory_accounts.js';
import type { AccountModule } from '../../src/http/accounts.js';
import { DEFAULT_CONTENT_DIR, contentVersion, loadContent } from '../../src/domain/content.js';
import { at, SH } from '../domain/helpers.js';
import { PROJECT, idToken, makeKeys } from '../fixtures/firebase_tokens.js';

const ROOT = path.resolve(DEFAULT_CONTENT_DIR, '..', '..', '..');
const BLUEPRINTS = path.join(ROOT, 'assets', 'blueprints');
const REGIONS = path.join(DEFAULT_CONTENT_DIR, 'regions.json');
const content = loadContent(DEFAULT_CONTENT_DIR);
const CV = contentVersion(DEFAULT_CONTENT_DIR);
const bp = loadBlueprint(BLUEPRINTS, 'sh_a', 2)!;
const k = makeKeys();

let app: FastifyInstance;
let accounts: MemoryAccountStore;
let clock = at('2026-09-07T16:00:00+08:00');
let modules: AccountModule[];

async function build(extra: Partial<AppDeps> = {}) {
  const store = new MemoryStore({ content, timezone: SH, blueprint: blueprintSets(bp), now: () => clock, contentVersion: CV });
  return buildApp({
    store, content, contentVersion: CV, blueprintDir: BLUEPRINTS, regionsFile: REGIONS,
    pepper: 'test-pepper', now: () => clock,
    accounts, firebase: { projectId: PROJECT, keys: k.keys }, accountModules: modules,
    ...extra,
  });
}

beforeEach(async () => {
  clock = at('2026-09-07T16:00:00+08:00');
  accounts = new MemoryAccountStore();
  modules = [];
  app = await build();
});
afterEach(async () => { await app.close(); });

const tok = (over: Record<string, unknown> = {}, uid = 'uid-1') => idToken(k, clock, over, uid);
const authed = (t: string) => ({ authorization: `Bearer ${t}` });
const signIn = (t = tok()) => app.inject({ method: 'POST', url: '/v1/auth/firebase', payload: { id_token: t } });
const me = (t = tok()) => app.inject({ method: 'GET', url: '/v1/users/me', headers: authed(t) });

describe('登录 → 自有 user id', () => {
  it('首次 201 建用户，再次 200 复用同一 user_id 并刷新 last_seen_at', async () => {
    const a = await signIn();
    expect(a.statusCode).toBe(201);
    expect(a.json().created).toBe(true);
    expect(a.json().user_id).toMatch(/^[0-9a-f-]{36}$/);
    expect(a.json().email).toBe('uid-1@example.test');
    clock += 60_000;
    const b = await signIn();
    expect(b.statusCode).toBe(200);
    expect(b.json().created).toBe(false);
    expect(b.json().user_id).toBe(a.json().user_id);
    expect(b.json().last_seen_at).toBe(clock);
    expect(b.json().created_at).toBe(a.json().created_at);
  });

  it('不同 Firebase uid 是不同用户；邮箱验证状态以最新 token 为准', async () => {
    const a = await signIn(tok({}, 'uid-a'));
    const b = await signIn(tok({}, 'uid-b'));
    expect(a.json().user_id).not.toBe(b.json().user_id);
    expect((await signIn(tok({ email_verified: true }, 'uid-a'))).json().email_verified).toBe(true);
  });

  it('id_token 也可以放 Authorization: Bearer；JSON content-type 带空 body 当 {}', async () => {
    const r = await app.inject({ method: 'POST', url: '/v1/auth/firebase', headers: authed(tok()) });
    expect(r.statusCode).toBe(201);
    const empty = await app.inject({ method: 'POST', url: '/v1/auth/firebase', headers: { ...authed(tok()), 'content-type': 'application/json' }, payload: '' });
    expect(empty.statusCode).toBe(200);
    const bad = await app.inject({ method: 'POST', url: '/v1/auth/firebase', headers: { ...authed(tok()), 'content-type': 'application/json' }, payload: '{not json' });
    expect(bad.statusCode).toBe(400);
  });

  it('坏 token 401 INVALID_ID_TOKEN 并带原因', async () => {
    const s = Math.floor(clock / 1000);
    const r = await signIn(tok({ exp: s - 3600 }));
    expect(r.statusCode).toBe(401);
    expect(r.json()).toMatchObject({ code: 'INVALID_ID_TOKEN', reason: 'EXPIRED' });
    expect((await signIn('garbage')).json().reason).toBe('MALFORMED');
    expect((await app.inject({ method: 'POST', url: '/v1/auth/firebase', payload: {} })).statusCode).toBe(401);
  });

  it('GET /v1/users/me：没登录过 404 NO_ACCOUNT，没 token 401，登录后 200', async () => {
    expect((await me()).statusCode).toBe(404);
    expect((await me()).json().code).toBe('NO_ACCOUNT');
    const noTok = await app.inject({ method: 'GET', url: '/v1/users/me' });
    expect(noTok.statusCode).toBe(401);
    expect(noTok.json()).toMatchObject({ code: 'UNAUTHENTICATED', reason: 'MALFORMED' });
    const { user_id } = (await signIn()).json();
    const r = await me();
    expect(r.statusCode).toBe(200);
    expect(r.json().user_id).toBe(user_id);
  });

  it('没配账号服务时账号路由 503，农场路由不受影响', async () => {
    await app.close();
    app = await build({ accounts: undefined, firebase: undefined });
    expect((await signIn()).statusCode).toBe(503);
    expect((await signIn()).json().code).toBe('ACCOUNTS_NOT_CONFIGURED');
    expect((await me()).statusCode).toBe(503);
    expect((await app.inject({ method: 'GET', url: '/v1/healthz' })).json().accounts).toBe(false);
    expect((await app.inject({ method: 'GET', url: '/v1/regions' })).statusCode).toBe(200);
  });

  it('healthz 报告账号服务已启用', async () => {
    expect((await app.inject({ method: 'GET', url: '/v1/healthz' })).json().accounts).toBe(true);
  });
});

describe('删号级联', () => {
  it('应用内删号：用户消失、墓碑记 app、再登录是全新 user_id、重复删返回 deleted=false', async () => {
    const { user_id } = (await signIn()).json();
    const d = await app.inject({ method: 'DELETE', url: '/v1/users/me', headers: authed(tok()) });
    expect(d.statusCode).toBe(200);
    expect(d.json()).toMatchObject({ ok: true, deleted: true, user_id });
    expect((await me()).statusCode).toBe(404);
    expect(await accounts.deletion(user_id)).toMatchObject({
      user_id, provider_uid: 'uid-1', source: 'app', apple_revocation: 'n/a', requested_at: clock,
    });
    const again = await app.inject({ method: 'DELETE', url: '/v1/users/me', headers: authed(tok()) });
    expect(again.json()).toMatchObject({ ok: true, deleted: false });
    const fresh = (await signIn()).json();
    expect(fresh.created).toBe(true);
    expect(fresh.user_id).not.toBe(user_id);
  });

  it('Apple 登录的用户删号时墓碑标 pending，等 revocation 队列处理', async () => {
    const t = tok({ firebase: { sign_in_provider: 'apple.com' } });
    const { user_id } = (await signIn(t)).json();
    await app.inject({ method: 'DELETE', url: '/v1/users/me', headers: authed(t) });
    expect((await accounts.deletion(user_id))?.apple_revocation).toBe('pending');
  });

  it('模块按登记顺序级联；任一模块失败整个删号 500 且用户保留', async () => {
    const order: string[] = [];
    modules.push(
      { name: 'profile', del: async id => { order.push(`profile:${id}`); } },
      { name: 'feed', del: async id => { order.push(`feed:${id}`); } },
    );
    await app.close(); app = await build();
    const { user_id } = (await signIn()).json();
    await app.inject({ method: 'DELETE', url: '/v1/users/me', headers: authed(tok()) });
    expect(order).toEqual([`profile:${user_id}`, `feed:${user_id}`]);

    modules.push({ name: 'im', del: async () => { throw new Error('im down'); } });
    await app.close(); app = await build();
    const { user_id: u2 } = (await signIn()).json();
    const r = await app.inject({ method: 'DELETE', url: '/v1/users/me', headers: authed(tok()) });
    expect(r.statusCode).toBe(500);
    expect(r.json().code).toBe('DELETE_FAILED');
    expect((await me()).json().user_id).toBe(u2);
    expect(await accounts.deletion(u2)).toBeNull();
  });

  it('站外 Web 删号：POST id_token，同一条级联，墓碑记 web；没 token 401', async () => {
    const { user_id } = (await signIn()).json();
    expect((await app.inject({ method: 'POST', url: '/v1/account/delete', payload: {} })).statusCode).toBe(401);
    const r = await app.inject({ method: 'POST', url: '/v1/account/delete', payload: { id_token: tok() } });
    expect(r.statusCode).toBe(200);
    expect(r.json()).toMatchObject({ ok: true, deleted: true, user_id });
    expect((await accounts.deletion(user_id))?.source).toBe('web');
  });
});

describe('数据导出', () => {
  it('一份 JSON 附件：账号 + 身份 + 各模块导出', async () => {
    modules.push({ name: 'profile', export: async id => ({ display_name: 'Sen', for: id }) });
    await app.close(); app = await build();
    const { user_id } = (await signIn()).json();
    const r = await app.inject({ method: 'GET', url: '/v1/users/me/export', headers: authed(tok()) });
    expect(r.statusCode).toBe(200);
    expect(r.headers['content-disposition']).toBe(`attachment; filename="sensen-account-${user_id}.json"`);
    const body = r.json();
    expect(body.account.user_id).toBe(user_id);
    expect(body.identities).toEqual([{ provider: 'firebase', provider_uid: 'uid-1', sign_in_provider: 'password', created_at: clock }]);
    expect(body.modules).toEqual({ profile: { display_name: 'Sen', for: user_id } });
    expect(body.exported_at).toBe(clock);
  });

  it('没账号 404，没 token 401', async () => {
    expect((await app.inject({ method: 'GET', url: '/v1/users/me/export', headers: authed(tok()) })).statusCode).toBe(404);
    expect((await app.inject({ method: 'GET', url: '/v1/users/me/export' })).statusCode).toBe(401);
  });
});
