import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import path from 'node:path';
import { buildApp, blueprintSets, loadBlueprint } from '../../src/http/app.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { MemoryAccountStore } from '../../src/http/memory_accounts.js';
import { MemorySocialStore } from '../../src/http/memory_social.js';
import { socialAccountModule, validatePatch, defaultDisplayName, decodeCursor, encodeCursor } from '../../src/http/social.js';
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
let social: MemorySocialStore;
let clock = at('2026-09-07T17:00:00+08:00');

beforeEach(async () => {
  clock = at('2026-09-07T17:00:00+08:00');
  accounts = new MemoryAccountStore();
  social = new MemorySocialStore(async id => (await accounts.userById(id)) !== null);
  const store = new MemoryStore({ content, timezone: SH, blueprint: blueprintSets(bp), now: () => clock, contentVersion: CV });
  app = await buildApp({
    store, content, contentVersion: CV, blueprintDir: BLUEPRINTS, regionsFile: REGIONS,
    pepper: 'test-pepper', now: () => clock,
    accounts, firebase: { projectId: PROJECT, keys: k.keys }, social, accountModules: [socialAccountModule(social)],
  });
});
afterEach(async () => { await app.close(); });

const tok = (uid: string) => idToken(k, clock, {}, uid);
const authed = (uid: string) => ({ authorization: `Bearer ${tok(uid)}` });
const signIn = async (uid: string): Promise<string> => {
  const r = await app.inject({ method: 'POST', url: '/v1/auth/firebase', payload: { id_token: tok(uid) } });
  return r.json().user_id as string;
};
const get = (uid: string, url: string) => app.inject({ method: 'GET', url, headers: authed(uid) });
const put = (uid: string, url: string, payload?: object) => app.inject({ method: 'PUT', url, headers: authed(uid), payload });
const del = (uid: string, url: string) => app.inject({ method: 'DELETE', url, headers: authed(uid) });

describe('资料', () => {
  it('首次登录随账号建默认资料：昵称 = 邮箱本地部分，计数为零', async () => {
    const id = await signIn('alice');
    const r = await get('alice', '/v1/users/me/profile');
    expect(r.statusCode).toBe(200);
    expect(r.json()).toMatchObject({
      user_id: id, display_name: 'alice', handle: null, bio: '', avatar: null, following_visible: true,
      followers_count: 0, following_count: 0, new_followers_unread: 0,
    });
    expect(defaultDisplayName(undefined, 'AbC-123xyz')).toBe('user_AbC123');
    expect(defaultDisplayName('x'.repeat(40) + '@e.test', 'u')).toHaveLength(30);
  });

  it('PUT 只改给了的字段；handle 小写化且唯一；清空用 null', async () => {
    await signIn('alice'); await signIn('bob');
    const r = await put('alice', '/v1/users/me/profile', { display_name: '  Sen  ', handle: 'Sen_01', bio: 'hi', avatar: { hair: 'h1' } });
    expect(r.statusCode).toBe(200);
    expect(r.json()).toMatchObject({ display_name: 'Sen', handle: 'sen_01', bio: 'hi', avatar: { hair: 'h1' }, updated_at: clock });
    expect((await put('alice', '/v1/users/me/profile', { bio: 'only bio' })).json()).toMatchObject({ display_name: 'Sen', bio: 'only bio' });
    const taken = await put('bob', '/v1/users/me/profile', { handle: 'SEN_01' });
    expect(taken.statusCode).toBe(409);
    expect(taken.json().code).toBe('HANDLE_TAKEN');
    expect((await put('alice', '/v1/users/me/profile', { handle: 'sen_01' })).statusCode).toBe(200); // 自己保留自己的
    expect((await put('alice', '/v1/users/me/profile', { handle: null })).json().handle).toBeNull();
    expect((await put('bob', '/v1/users/me/profile', { handle: 'sen_01' })).statusCode).toBe(200);
  });

  it('字段校验：长度 / 格式 / 控制字符 / avatar 大小，400 带 field', async () => {
    await signIn('alice');
    const bad = async (body: object, field: string) => {
      const r = await put('alice', '/v1/users/me/profile', body);
      expect(r.statusCode, JSON.stringify(body)).toBe(400);
      expect(r.json()).toMatchObject({ code: 'SCHEMA', field });
    };
    await bad({ display_name: '' }, 'display_name');
    await bad({ display_name: 'x'.repeat(31) }, 'display_name');
    await bad({ display_name: 'a\nb' }, 'display_name');
    await bad({ handle: 'ab' }, 'handle');
    await bad({ handle: 'has space' }, 'handle');
    await bad({ handle: 'x'.repeat(21) }, 'handle');
    await bad({ bio: 'x'.repeat(161) }, 'bio');
    await bad({ avatar: [] }, 'avatar');
    await bad({ avatar: { big: 'x'.repeat(5000) } }, 'avatar');
    await bad({ following_visible: 'yes' }, 'following_visible');
    expect(validatePatch(null)).toMatchObject({ ok: false, field: 'body' });
    expect((await put('alice', '/v1/users/me/profile', { bio: 'line1\nline2' })).statusCode).toBe(200); // 简介允许换行
  });

  it('别人看资料：按 uuid 或 @handle；关注计数受隐私开关，自己总能看', async () => {
    const a = await signIn('alice'); const b = await signIn('bob'); await signIn('carol');
    await put('bob', '/v1/users/me/profile', { handle: 'bobby', following_visible: false });
    await put('bob', `/v1/users/${a}/follow`);
    const viaHandle = await get('alice', '/v1/users/@Bobby/profile');
    expect(viaHandle.statusCode).toBe(200);
    expect(viaHandle.json()).toMatchObject({ user_id: b, handle: 'bobby', followers_count: 0, following_visible: false,
      relation: { following: false, followed_by: true, close_friends: false } });
    expect(viaHandle.json()).not.toHaveProperty('following_count');
    expect((await get('bob', '/v1/users/me/profile')).json().following_count).toBe(1);
    expect((await get('bob', `/v1/users/${b}/profile`)).json().following_count).toBe(1);
    expect((await get('alice', '/v1/users/@nobody/profile')).statusCode).toBe(404);
    expect((await get('alice', '/v1/users/not-a-uuid/profile')).statusCode).toBe(404);
  });

  it('没配 social 时 503；没登录过服务端 404 NO_ACCOUNT；没 token 401', async () => {
    expect((await get('alice', '/v1/users/me/profile')).statusCode).toBe(404);
    expect((await app.inject({ method: 'GET', url: '/v1/users/me/profile' })).statusCode).toBe(401);
    await app.close();
    const store = new MemoryStore({ content, timezone: SH, blueprint: blueprintSets(bp), now: () => clock, contentVersion: CV });
    app = await buildApp({ store, content, contentVersion: CV, blueprintDir: BLUEPRINTS, regionsFile: REGIONS,
      pepper: 'p', now: () => clock, accounts, firebase: { projectId: PROJECT, keys: k.keys } });
    await signIn('alice');
    const r = await get('alice', '/v1/users/me/profile');
    expect(r.statusCode).toBe(503);
    expect(r.json().code).toBe('SOCIAL_NOT_CONFIGURED');
    expect((await app.inject({ method: 'GET', url: '/v1/healthz' })).json().social).toBe(false);
  });
});

describe('关注', () => {
  it('单向关注 → 互关即密友 → 取关只降级；幂等；不能关注自己；不存在 404', async () => {
    const a = await signIn('alice'); const b = await signIn('bob');
    const f1 = await put('alice', `/v1/users/${b}/follow`);
    expect(f1.statusCode).toBe(200);
    expect(f1.json()).toMatchObject({ created: true, relation: { following: true, followed_by: false, close_friends: false } });
    expect((await put('alice', `/v1/users/${b}/follow`)).json().created).toBe(false);
    const f2 = await put('bob', `/v1/users/${a}/follow`);
    expect(f2.json().relation).toEqual({ following: true, followed_by: true, close_friends: true });
    expect((await get('alice', `/v1/users/${b}/profile`)).json().relation.close_friends).toBe(true);
    const u = await del('alice', `/v1/users/${b}/follow`);
    expect(u.json()).toMatchObject({ removed: true, relation: { following: false, followed_by: true, close_friends: false } });
    expect((await get('bob', `/v1/users/${a}/profile`)).json().relation).toEqual({ following: true, followed_by: false, close_friends: false });
    expect((await del('alice', `/v1/users/${b}/follow`)).json().removed).toBe(false);
    expect((await put('alice', `/v1/users/${a}/follow`)).json().code).toBe('SELF_FOLLOW');
    expect((await put('alice', '/v1/users/me/follow')).statusCode).toBe(400);
    expect((await put('alice', '/v1/users/00000000-0000-4000-8000-000000000000/follow')).statusCode).toBe(404);
  });

  it('列表：倒序、游标分页、卡片带关系；粉丝永远公开，「我关注的」受隐私开关', async () => {
    const a = await signIn('alice');
    const others: string[] = [];
    for (const uid of ['u1', 'u2', 'u3']) { others.push(await signIn(uid)); clock += 1000; await put(uid, `/v1/users/${a}/follow`); }
    await put('u3', '/v1/users/me/profile', { handle: 'three', display_name: 'Three' });
    await put('alice', `/v1/users/${others[2]}/follow`);
    const p1 = await get('u1', `/v1/users/${a}/followers?limit=2`);
    expect(p1.statusCode).toBe(200);
    expect(p1.json().items.map((i: { user_id: string }) => i.user_id)).toEqual([others[2], others[1]]);
    expect(p1.json().items[0]).toMatchObject({ display_name: 'Three', handle: 'three', relation: { following: false, followed_by: false, close_friends: false } });
    expect(p1.json().next_cursor).toBeTruthy();
    const p2 = await get('u1', `/v1/users/${a}/followers?limit=2&cursor=${p1.json().next_cursor}`);
    expect(p2.json().items.map((i: { user_id: string }) => i.user_id)).toEqual([others[0]]);
    expect(p2.json().next_cursor).toBeNull();
    // alice 看自己的粉丝：u3 是密友
    const mine = await get('alice', '/v1/users/me/followers');
    expect(mine.json().items[0].relation).toEqual({ following: true, followed_by: true, close_friends: true });
    // 我关注的：默认公开；关掉后别人 403，自己照看
    expect((await get('u1', `/v1/users/${a}/following`)).json().items).toHaveLength(1);
    await put('alice', '/v1/users/me/profile', { following_visible: false });
    expect((await get('u1', `/v1/users/${a}/following`)).statusCode).toBe(403);
    expect((await get('alice', '/v1/users/me/following')).json().items).toHaveLength(1);
    // limit 上限 50，坏游标当没有
    expect((await get('alice', `/v1/users/${a}/followers?limit=999&cursor=garbage`)).statusCode).toBe(200);
    expect(decodeCursor('garbage')).toBeNull();
    expect(decodeCursor(encodeCursor(5, others[0]))).toEqual({ createdAt: 5, id: others[0] });
  });

  it('新粉丝页：带未读数，读过即清，取关不产生通知', async () => {
    const a = await signIn('alice'); await signIn('bob'); await signIn('carol');
    await put('bob', `/v1/users/${a}/follow`);
    clock += 1000;
    await put('carol', `/v1/users/${a}/follow`);
    expect((await get('alice', '/v1/users/me/profile')).json().new_followers_unread).toBe(2);
    const page = await get('alice', '/v1/users/me/new-followers');
    expect(page.json().unread_count).toBe(2);
    expect(page.json().items.map((i: { display_name: string }) => i.display_name)).toEqual(['carol', 'bob']);
    expect((await get('alice', '/v1/users/me/new-followers')).json().unread_count).toBe(0);
    await del('bob', `/v1/users/${a}/follow`);
    expect((await get('alice', '/v1/users/me/profile')).json().new_followers_unread).toBe(0);
  });

  it('导出带资料与关注；删号后从别人的列表里消失', async () => {
    const a = await signIn('alice'); const b = await signIn('bob');
    await put('alice', `/v1/users/${b}/follow`);
    await put('bob', `/v1/users/${a}/follow`);
    const ex = await get('alice', '/v1/users/me/export');
    expect(ex.json().modules.social).toMatchObject({ profile: { user_id: a, display_name: 'alice' }, following: [b], followers: [b] });
    expect((await del('alice', '/v1/users/me')).json().deleted).toBe(true);
    expect((await get('bob', '/v1/users/me/followers')).json().items).toEqual([]);
    expect((await get('bob', '/v1/users/me/profile')).json().following_count).toBe(0);
    expect(await social.profile(a)).toBeNull();
  });
});
