import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import path from 'node:path';
import { buildApp, blueprintSets, loadBlueprint } from '../../src/http/app.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { MemoryAccountStore } from '../../src/http/memory_accounts.js';
import { MemorySocialStore } from '../../src/http/memory_social.js';
import { MemoryFeedStore } from '../../src/http/memory_feed.js';
import { socialAccountModule } from '../../src/http/social.js';
import { feedAccountModule, validatePost } from '../../src/http/feed.js';
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
let feed: MemoryFeedStore;
let clock = at('2026-09-07T18:00:00+08:00');

beforeEach(async () => {
  clock = at('2026-09-07T18:00:00+08:00');
  accounts = new MemoryAccountStore();
  social = new MemorySocialStore(async id => (await accounts.userById(id)) !== null);
  feed = new MemoryFeedStore(async viewer => (await social.following(viewer, null, 1000)).items.map(f => f.followee_id));
  const store = new MemoryStore({ content, timezone: SH, blueprint: blueprintSets(bp), now: () => clock, contentVersion: CV });
  app = await buildApp({
    store, content, contentVersion: CV, blueprintDir: BLUEPRINTS, regionsFile: REGIONS,
    pepper: 'test-pepper', now: () => clock,
    accounts, firebase: { projectId: PROJECT, keys: k.keys }, social, feed,
    accountModules: [socialAccountModule(social), feedAccountModule(feed)],
    uploads: { endpoint: 'https://acct.r2.cloudflarestorage.com', region: 'auto', bucket: 'ugc', accessKeyId: 'AK', secretAccessKey: 'SK', publicBase: 'https://img.example.test' },
  });
});
afterEach(async () => { await app.close(); });

const tok = (uid: string) => idToken(k, clock, {}, uid);
const authed = (uid: string) => ({ authorization: `Bearer ${tok(uid)}` });
const signIn = async (uid: string): Promise<string> =>
  (await app.inject({ method: 'POST', url: '/v1/auth/firebase', payload: { id_token: tok(uid) } })).json().user_id as string;
const get = (uid: string, url: string) => app.inject({ method: 'GET', url, headers: authed(uid) });
const post = (uid: string, url: string, payload?: object) => app.inject({ method: 'POST', url, headers: authed(uid), payload });
const put = (uid: string, url: string, payload?: object) => app.inject({ method: 'PUT', url, headers: authed(uid), payload });
const del = (uid: string, url: string) => app.inject({ method: 'DELETE', url, headers: authed(uid) });
const publish = async (uid: string, text: string, key = text): Promise<string> => {
  const r = await post(uid, '/v1/posts', { idempotency_key: key, text });
  expect(r.statusCode, r.body).toBe(201);
  return r.json().id as string;
};
const ids = (r: { json: () => { items: { id: string }[] } }) => r.json().items.map(i => i.id);

describe('发布', () => {
  it('发帖 201 带作者卡；同 idempotency_key 重放 200 同一条', async () => {
    await signIn('alice');
    await put('alice', '/v1/users/me/profile', { handle: 'ali' });
    const me = (await get('alice', '/v1/users/me')).json().user_id as string;
    const r = await post('alice', '/v1/posts', { idempotency_key: 'k1', text: '  hello  ', images: [{ key: `u/${me}/20260907/a.jpg`, w: 100, h: 50 }] });
    expect(r.statusCode).toBe(201);
    expect(r.json()).toMatchObject({ text: 'hello', images: [{ key: `u/${me}/20260907/a.jpg`, w: 100, h: 50 }], like_count: 0, comment_count: 0, liked: false, created: true,
      author: { display_name: 'alice', handle: 'ali' }, created_at: clock });
    const again = await post('alice', '/v1/posts', { idempotency_key: 'k1', text: 'different' });
    expect(again.statusCode).toBe(200);
    expect(again.json().id).toBe(r.json().id);
    expect(again.json().text).toBe('hello');
  });

  it('校验：空帖、超长、图片数量与 key 格式、缺 idempotency_key', async () => {
    await signIn('alice');
    const bad = async (body: object, field: string) => {
      const r = await post('alice', '/v1/posts', body);
      expect(r.statusCode, JSON.stringify(body)).toBe(400);
      expect(r.json()).toMatchObject({ code: 'SCHEMA', field });
    };
    await bad({ idempotency_key: 'k', text: '   ' }, 'text');
    await bad({ idempotency_key: 'k', text: 'x'.repeat(2001) }, 'text');
    await bad({ idempotency_key: 'k', text: 'ok', images: Array.from({ length: 10 }, (_, i) => ({ key: `i${i}` })) }, 'images');
    await bad({ idempotency_key: 'k', text: 'ok', images: [{ key: '../etc' }] }, 'images');
    await bad({ idempotency_key: 'k', text: 'ok', images: [{ key: 'a', w: -1 }] }, 'images');
    // 别人前缀下的 key 不能引用
    const other = await post('alice', '/v1/posts', { idempotency_key: 'k9', text: 'ok', images: [{ key: 'u/someone-else/20260907/x.jpg' }] });
    expect(other.statusCode).toBe(400);
    expect(other.json()).toMatchObject({ field: 'images', reason: 'NOT_OWNED' });
    await bad({ text: 'ok' }, 'idempotency_key');
    expect(validatePost({ idempotency_key: 'k', images: [{ key: 'only-image' }] })).toMatchObject({ ok: true, text: '' });
    expect((await post('alice', '/v1/posts', { idempotency_key: 'k', text: 'a\nb' })).statusCode).toBe(201); // 换行允许
  });

  it('没配 feed 503；没账号 404', async () => {
    expect((await get('alice', '/v1/feed')).statusCode).toBe(404);
    await app.close();
    const store = new MemoryStore({ content, timezone: SH, blueprint: blueprintSets(bp), now: () => clock, contentVersion: CV });
    app = await buildApp({ store, content, contentVersion: CV, blueprintDir: BLUEPRINTS, regionsFile: REGIONS, pepper: 'p', now: () => clock,
      accounts, firebase: { projectId: PROJECT, keys: k.keys }, social });
    await signIn('alice');
    expect((await get('alice', '/v1/feed')).json().code).toBe('FEED_NOT_CONFIGURED');
    expect((await app.inject({ method: 'GET', url: '/v1/healthz' })).json().feed).toBe(false);
  });
});

describe('可见性与时间线', () => {
  it('关注了作者才看得到；作者自己总能看；不可见答 404，列表 403 FOLLOW_REQUIRED', async () => {
    const a = await signIn('alice'); await signIn('bob'); await signIn('carol');
    const p = await publish('alice', 'from alice');
    await put('bob', `/v1/users/${a}/follow`);
    expect((await get('bob', `/v1/posts/${p}`)).statusCode).toBe(200);
    expect((await get('carol', `/v1/posts/${p}`)).statusCode).toBe(404);
    expect((await get('alice', `/v1/posts/${p}`)).statusCode).toBe(200);
    expect(ids(await get('bob', `/v1/users/${a}/posts`))).toEqual([p]);
    expect((await get('carol', `/v1/users/${a}/posts`)).json().code).toBe('FOLLOW_REQUIRED');
    expect(ids(await get('alice', '/v1/users/me/posts'))).toEqual([p]);
    // alice 关注 carol 不会让 carol 看到 alice：只看 viewer → author 这一个方向
    await put('alice', `/v1/users/${(await get('alice', '/v1/users/@carol/profile')).json().user_id ?? ''}/follow`).catch(() => undefined);
    expect((await get('carol', `/v1/posts/${p}`)).statusCode).toBe(404);
  });

  it('时间线 = 我 + 我关注的人，倒序，游标分页，带 liked', async () => {
    const a = await signIn('alice'); const b = await signIn('bob'); await signIn('carol');
    await put('alice', `/v1/users/${b}/follow`);
    const p1 = await publish('bob', 'b1'); clock += 1000;
    const p2 = await publish('alice', 'a1'); clock += 1000;
    await publish('carol', 'c1'); clock += 1000;
    const p3 = await publish('bob', 'b2');
    await put('alice', `/v1/posts/${p1}/like`);
    const page1 = await get('alice', '/v1/feed?limit=2');
    expect(ids(page1)).toEqual([p3, p2]);
    expect(page1.json().next_cursor).toBeTruthy();
    const page2 = await get('alice', `/v1/feed?limit=2&cursor=${page1.json().next_cursor}`);
    expect(ids(page2)).toEqual([p1]);
    expect(page2.json().items[0].liked).toBe(true);
    expect(page2.json().next_cursor).toBeNull();
    expect(ids(await get('carol', '/v1/feed'))).toHaveLength(1);
    expect(a).not.toBe(b);
  });
});

describe('点赞与评论', () => {
  it('点赞幂等、计数正确；取消后归零；看不到的帖不能赞', async () => {
    const a = await signIn('alice'); await signIn('bob'); await signIn('carol');
    const p = await publish('alice', 'x');
    await put('bob', `/v1/users/${a}/follow`);
    expect((await put('bob', `/v1/posts/${p}/like`)).json()).toMatchObject({ liked: true, created: true, like_count: 1 });
    expect((await put('bob', `/v1/posts/${p}/like`)).json()).toMatchObject({ created: false, like_count: 1 });
    expect((await put('alice', `/v1/posts/${p}/like`)).json().like_count).toBe(2);
    expect((await get('bob', `/v1/posts/${p}`)).json()).toMatchObject({ liked: true, like_count: 2 });
    expect((await del('bob', `/v1/posts/${p}/like`)).json()).toMatchObject({ liked: false, removed: true, like_count: 1 });
    expect((await del('bob', `/v1/posts/${p}/like`)).json().removed).toBe(false);
    expect((await put('carol', `/v1/posts/${p}/like`)).statusCode).toBe(404);
  });

  it('评论正序分页、计数；评论作者或帖主可删，他人 403；校验 text', async () => {
    const a = await signIn('alice'); await signIn('bob'); await signIn('carol');
    const p = await publish('alice', 'x');
    await put('bob', `/v1/users/${a}/follow`); await put('carol', `/v1/users/${a}/follow`);
    const c1 = await post('bob', `/v1/posts/${p}/comments`, { text: ' first ' });
    expect(c1.statusCode).toBe(201);
    expect(c1.json()).toMatchObject({ post_id: p, text: 'first', author: { display_name: 'bob' } });
    clock += 1000;
    const c2 = (await post('carol', `/v1/posts/${p}/comments`, { text: 'second' })).json();
    clock += 1000;
    const c3 = (await post('alice', `/v1/posts/${p}/comments`, { text: 'third' })).json();
    expect((await get('alice', `/v1/posts/${p}`)).json().comment_count).toBe(3);
    const l1 = await get('bob', `/v1/posts/${p}/comments?limit=2`);
    expect(ids(l1)).toEqual([c1.json().id, c2.id]);
    const l2 = await get('bob', `/v1/posts/${p}/comments?limit=2&cursor=${l1.json().next_cursor}`);
    expect(ids(l2)).toEqual([c3.id]);
    expect((await del('carol', `/v1/comments/${c1.json().id}`)).statusCode).toBe(403);
    expect((await del('bob', `/v1/comments/${c1.json().id}`)).json().deleted).toBe(true);
    expect((await del('alice', `/v1/comments/${c2.id}`)).json().deleted).toBe(true); // 帖主
    expect((await get('alice', `/v1/posts/${p}`)).json().comment_count).toBe(1);
    expect((await del('alice', `/v1/comments/${c2.id}`)).statusCode).toBe(404);
    expect((await post('bob', `/v1/posts/${p}/comments`, { text: '' })).statusCode).toBe(400);
    expect((await post('bob', `/v1/posts/${p}/comments`, { text: 'x'.repeat(501) })).json().field).toBe('text');
  });
});

describe('删除与级联', () => {
  it('作者删帖后对所有人 404、从时间线消失；他人删 403', async () => {
    const a = await signIn('alice'); await signIn('bob');
    const p = await publish('alice', 'x');
    await put('bob', `/v1/users/${a}/follow`);
    expect((await del('bob', `/v1/posts/${p}`)).statusCode).toBe(403);
    expect((await del('alice', `/v1/posts/${p}`)).json().deleted).toBe(true);
    expect((await get('alice', `/v1/posts/${p}`)).statusCode).toBe(404);
    expect(ids(await get('bob', '/v1/feed'))).toEqual([]);
    expect((await del('alice', `/v1/posts/${p}`)).statusCode).toBe(404);
  });

  it('导出带帖子与评论；删号后帖子消失、别人帖子上的点赞与评论计数回退', async () => {
    const a = await signIn('alice'); const b = await signIn('bob');
    await put('alice', `/v1/users/${b}/follow`); await put('bob', `/v1/users/${a}/follow`);
    const pa = await publish('alice', 'alice post');
    const pb = await publish('bob', 'bob post');
    await put('alice', `/v1/posts/${pb}/like`);
    await post('alice', `/v1/posts/${pb}/comments`, { text: 'nice' });
    const ex = await get('alice', '/v1/users/me/export');
    expect(ex.json().modules.feed.posts.map((p: { id: string }) => p.id)).toEqual([pa]);
    expect(ex.json().modules.feed.comments.map((c: { text: string }) => c.text)).toEqual(['nice']);
    expect((await del('alice', '/v1/users/me')).json().deleted).toBe(true);
    expect(ids(await get('bob', '/v1/feed'))).toEqual([pb]);
    expect((await get('bob', `/v1/posts/${pb}`)).json()).toMatchObject({ like_count: 0, comment_count: 0 });
    expect(await feed.post(pa)).toBeNull();
  });
});

describe('图片直传', () => {
  it('POST /v1/uploads 给预签名 PUT，key 在本人前缀下，能直接用于发帖', async () => {
    const me = await signIn('alice');
    const r = await post('alice', '/v1/uploads', { kind: 'post_image', content_type: 'image/jpeg', size: 1234 });
    expect(r.statusCode).toBe(201);
    expect(r.json()).toMatchObject({ method: 'PUT', headers: { 'content-type': 'image/jpeg' }, expires_at: clock + 600_000 });
    expect(r.json().key).toMatch(new RegExp(`^u/${me}/20260907/[0-9a-f]{24}\\.jpg$`));
    expect(r.json().url).toContain('X-Amz-Signature=');
    expect(r.json().public_url).toBe(`https://img.example.test/${r.json().key}`);
    const p = await post('alice', '/v1/posts', { idempotency_key: 'k', images: [{ key: r.json().key, w: 10, h: 10 }] });
    expect(p.statusCode).toBe(201);
    expect((await post('alice', '/v1/uploads', { kind: 'post_image', content_type: 'text/plain', size: 1 })).statusCode).toBe(400);
    expect((await app.inject({ method: 'POST', url: '/v1/uploads', payload: {} })).statusCode).toBe(401);
  });

  it('没配 R2 时 503', async () => {
    await signIn('alice');
    await app.close();
    const store = new MemoryStore({ content, timezone: SH, blueprint: blueprintSets(bp), now: () => clock, contentVersion: CV });
    app = await buildApp({ store, content, contentVersion: CV, blueprintDir: BLUEPRINTS, regionsFile: REGIONS, pepper: 'p', now: () => clock,
      accounts, firebase: { projectId: PROJECT, keys: k.keys }, social, feed });
    const r = await post('alice', '/v1/uploads', { kind: 'post_image', content_type: 'image/jpeg', size: 1 });
    expect(r.statusCode).toBe(503);
    expect(r.json().code).toBe('UPLOADS_NOT_CONFIGURED');
    expect((await app.inject({ method: 'GET', url: '/v1/healthz' })).json().uploads).toBe(false);
  });
});
