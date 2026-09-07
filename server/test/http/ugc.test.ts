/** UGC 四件套的服务端：前置过滤、举报、拉黑、封禁、管理队列——都走 HTTP。 */
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import path from 'node:path';
import { buildApp, blueprintSets, loadBlueprint } from '../../src/http/app.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { MemoryAccountStore } from '../../src/http/memory_accounts.js';
import { MemorySocialStore } from '../../src/http/memory_social.js';
import { MemoryFeedStore } from '../../src/http/memory_feed.js';
import { MemoryModerationStore } from '../../src/http/memory_moderation.js';
import { socialAccountModule } from '../../src/http/social.js';
import { feedAccountModule } from '../../src/http/feed.js';
import { moderationAccountModule, type ModerationVerdict, type TextModerator } from '../../src/http/moderation.js';
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

/** 含 BAD 的文字命中；含 DOWN 的文字模拟审核服务挂了。 */
class FakeModerator implements TextModerator {
  calls: string[] = [];
  async check(text: string): Promise<ModerationVerdict> {
    this.calls.push(text);
    if (text.includes('DOWN')) return { flagged: false, categories: [], error: 'HTTP_503' };
    return text.includes('BAD') ? { flagged: true, categories: ['harassment'] } : { flagged: false, categories: [] };
  }
}

let app: FastifyInstance;
let accounts: MemoryAccountStore;
let social: MemorySocialStore;
let feed: MemoryFeedStore;
let moderation: MemoryModerationStore;
let moderator: FakeModerator;
let admins: Set<string>;
let clock = at('2026-09-07T19:00:00+08:00');

beforeEach(async () => {
  clock = at('2026-09-07T19:00:00+08:00');
  accounts = new MemoryAccountStore();
  social = new MemorySocialStore(async id => (await accounts.userById(id)) !== null);
  feed = new MemoryFeedStore(async v => (await social.following(v, null, 1000)).items.map(f => f.followee_id));
  moderation = new MemoryModerationStore();
  moderator = new FakeModerator();
  admins = new Set();
  const store = new MemoryStore({ content, timezone: SH, blueprint: blueprintSets(bp), now: () => clock, contentVersion: CV });
  app = await buildApp({
    store, content, contentVersion: CV, blueprintDir: BLUEPRINTS, regionsFile: REGIONS, pepper: 'p', now: () => clock,
    accounts, firebase: { projectId: PROJECT, keys: k.keys }, social, feed, moderation, textModerator: moderator, adminUserIds: admins,
    accountModules: [socialAccountModule(social), feedAccountModule(feed), moderationAccountModule(moderation)],
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
const publish = async (uid: string, text: string, key = text) => {
  const r = await post(uid, '/v1/posts', { idempotency_key: key, text });
  expect(r.statusCode, r.body).toBe(201);
  return r.json().id as string;
};
const ids = (r: { json: () => { items: { id: string }[] } }) => r.json().items.map(i => i.id);

describe('前置过滤', () => {
  it('命中拒发 422 带分类；干净放行 approved；审核挂了放行但 pending 进队列；带图 pending', async () => {
    const me = await signIn('alice'); admins.add(me);
    const bad = await post('alice', '/v1/posts', { idempotency_key: 'k1', text: 'you are BAD' });
    expect(bad.statusCode).toBe(422);
    expect(bad.json()).toMatchObject({ code: 'MODERATION_REJECTED', categories: ['harassment'] });
    expect((await post('alice', '/v1/posts', { idempotency_key: 'k2', text: 'nice' })).json().moderation_status).toBe('approved');
    const down = await post('alice', '/v1/posts', { idempotency_key: 'k3', text: 'service DOWN' });
    expect(down.json().moderation_status).toBe('pending');
    const img = await post('alice', '/v1/posts', { idempotency_key: 'k4', text: 'pic', images: [{ key: `u/${me}/20260907/a.jpg` }] });
    expect(img.json().moderation_status).toBe('pending');
    const q = await get('alice', '/v1/admin/review');
    expect(q.json().posts.map((p: { id: string }) => p.id).sort()).toEqual([down.json().id, img.json().id].sort());
    expect(moderator.calls).toEqual(['you are BAD', 'nice', 'service DOWN', 'pic']);
    // pending 对关注者可见
    await signIn('bob'); await put('bob', `/v1/users/${me}/follow`);
    expect(ids(await get('bob', '/v1/feed'))).toHaveLength(3);
    // 评论同一套
    const c = await post('bob', `/v1/posts/${down.json().id}/comments`, { text: 'BAD words' });
    expect(c.statusCode).toBe(422);
    expect((await post('bob', `/v1/posts/${down.json().id}/comments`, { text: 'fine' })).statusCode).toBe(201);
  });

  it('没配文本审核：不拦但全部 pending', async () => {
    await app.close();
    const store = new MemoryStore({ content, timezone: SH, blueprint: blueprintSets(bp), now: () => clock, contentVersion: CV });
    app = await buildApp({ store, content, contentVersion: CV, blueprintDir: BLUEPRINTS, regionsFile: REGIONS, pepper: 'p', now: () => clock,
      accounts, firebase: { projectId: PROJECT, keys: k.keys }, social, feed, moderation });
    await signIn('alice');
    expect((await post('alice', '/v1/posts', { idempotency_key: 'k', text: 'BAD but nobody checks' })).json().moderation_status).toBe('pending');
    expect((await app.inject({ method: 'GET', url: '/v1/healthz' })).json()).toMatchObject({ moderation: true, text_moderator: false });
  });
});

describe('拉黑', () => {
  it('双向不可见：资料 / 动态 / 时间线 / 评论都看不到；自动互相取关；关注被拉黑者 403；解除后恢复', async () => {
    const a = await signIn('alice'); const b = await signIn('bob'); await signIn('carol');
    await put('alice', `/v1/users/${b}/follow`); await put('bob', `/v1/users/${a}/follow`);
    const pa = await publish('alice', 'from a'); const pb = await publish('bob', 'from b');
    const cb = (await post('bob', `/v1/posts/${pa}/comments`, { text: 'hey' })).json().id;
    expect((await put('alice', `/v1/users/${b}/block`)).json()).toMatchObject({ ok: true, created: true });
    expect((await put('alice', `/v1/users/${b}/block`)).json().created).toBe(false);
    expect((await put('alice', `/v1/users/${a}/block`)).json().code).toBe('SELF_BLOCK');
    expect((await get('alice', `/v1/users/${b}/profile`)).statusCode).toBe(404);
    expect((await get('bob', `/v1/users/${a}/profile`)).statusCode).toBe(404);
    expect((await get('bob', `/v1/posts/${pa}`)).statusCode).toBe(404);
    expect((await get('alice', `/v1/posts/${pb}`)).statusCode).toBe(404);
    expect(ids(await get('alice', '/v1/feed'))).toEqual([pa]);
    expect(ids(await get('bob', '/v1/feed'))).toEqual([pb]);
    expect((await get('bob', `/v1/users/${a}/posts`)).statusCode).toBe(404);
    expect(ids(await get('alice', `/v1/posts/${pa}/comments`))).toEqual([]);
    expect((await get('alice', '/v1/users/me/profile')).json()).toMatchObject({ followers_count: 0, following_count: 0 });
    expect((await put('bob', `/v1/users/${a}/follow`)).json().code).toBe('BLOCKED');
    expect((await put('alice', `/v1/users/${b}/follow`)).json().code).toBe('BLOCKED');
    const list = await get('alice', '/v1/users/me/blocks');
    expect(list.json().items).toEqual([{ user_id: b, display_name: 'bob', handle: null, avatar: null, blocked_at: clock }]);
    expect((await del('alice', `/v1/users/${b}/block`)).json().removed).toBe(true);
    expect((await get('bob', `/v1/users/${a}/profile`)).statusCode).toBe(200);
    expect(ids(await get('alice', `/v1/posts/${pa}/comments`))).toEqual([cb]);
    expect((await put('bob', `/v1/users/${a}/follow`)).statusCode).toBe(200);
  });
});

describe('举报与处置', () => {
  it('举报去重；不同人达到 3 条自动隐藏（作者还能看到自己的）；不能举报自己；目标须存在', async () => {
    const a = await signIn('alice');
    const p = await publish('alice', 'spammy');
    const reporters: string[] = [];
    for (const u of ['u1', 'u2', 'u3']) { reporters.push(await signIn(u)); await put(u, `/v1/users/${a}/follow`); }
    const r1 = await post('u1', '/v1/reports', { target_type: 'post', target_id: p, reason: 'spam', detail: ' ads ' });
    expect(r1.statusCode).toBe(201);
    expect(r1.json()).toMatchObject({ created: true, auto_hidden: false, status: 'open', detail: 'ads' });
    expect((await post('u1', '/v1/reports', { target_type: 'post', target_id: p, reason: 'hate' })).json()).toMatchObject({ created: false, reason: 'spam' });
    await post('u2', '/v1/reports', { target_type: 'post', target_id: p, reason: 'spam' });
    expect((await get('u3', `/v1/posts/${p}`)).statusCode).toBe(200);
    const r3 = await post('u3', '/v1/reports', { target_type: 'post', target_id: p, reason: 'spam' });
    expect(r3.json().auto_hidden).toBe(true);
    expect((await get('u3', `/v1/posts/${p}`)).statusCode).toBe(404);
    expect(ids(await get('u1', '/v1/feed'))).toEqual([]);
    expect((await get('alice', `/v1/posts/${p}`)).json().moderation_status).toBe('hidden');
    expect((await post('alice', '/v1/reports', { target_type: 'post', target_id: p, reason: 'spam' })).json().code).toBe('SELF_REPORT');
    expect((await post('u1', '/v1/reports', { target_type: 'comment', target_id: '00000000-0000-4000-8000-000000000000', reason: 'spam' })).statusCode).toBe(404);
    expect((await post('u1', '/v1/reports', { target_type: 'user', target_id: a, reason: 'harassment' })).statusCode).toBe(201);
  });

  it('管理队列：非管理员 403；dismiss / remove_content / ban_user；封禁后所有登录路由 403 BANNED', async () => {
    const admin = await signIn('admin'); admins.add(admin);
    const a = await signIn('alice'); await signIn('bob'); await put('bob', `/v1/users/${a}/follow`);
    const p = await publish('alice', 'x');
    const rep = (await post('bob', '/v1/reports', { target_type: 'post', target_id: p, reason: 'hate' })).json().id;
    expect((await get('bob', '/v1/admin/reports')).statusCode).toBe(403);
    const open = await get('admin', '/v1/admin/reports');
    expect(open.json().items.map((r: { id: string }) => r.id)).toEqual([rep]);
    expect((await post('admin', `/v1/admin/reports/${rep}/resolve`, { action: 'nuke' })).statusCode).toBe(400);
    expect((await post('admin', `/v1/admin/reports/${rep}/resolve`, { action: 'dismiss' })).json()).toMatchObject({ ok: true, resolved: 1 });
    expect((await get('admin', '/v1/admin/reports')).json().items).toEqual([]);
    expect((await post('admin', `/v1/admin/reports/${rep}/resolve`, { action: 'dismiss' })).json().resolved).toBe(0);
    // 第二轮：下架
    const p2 = await publish('alice', 'y');
    const rep2 = (await post('bob', '/v1/reports', { target_type: 'post', target_id: p2, reason: 'hate' })).json().id;
    expect((await post('admin', `/v1/admin/reports/${rep2}/resolve`, { action: 'remove_content' })).json()).toMatchObject({ resolved: 1, banned: null });
    expect((await get('bob', `/v1/posts/${p2}`)).statusCode).toBe(404);
    // 第三轮：封人
    const p3 = await publish('alice', 'z');
    const rep3 = (await post('bob', '/v1/reports', { target_type: 'post', target_id: p3, reason: 'minor_safety' })).json().id;
    expect((await post('admin', `/v1/admin/reports/${rep3}/resolve`, { action: 'ban_user' })).json().banned).toBe(a);
    expect((await get('alice', '/v1/users/me')).json().code).toBe('BANNED');
    expect((await post('alice', '/v1/posts', { idempotency_key: 'k', text: 'still here?' })).statusCode).toBe(403);
    expect((await get('bob', `/v1/posts/${p3}`)).statusCode).toBe(404);
    // 复审队列
    const pend = (await post('bob', '/v1/posts', { idempotency_key: 'd', text: 'DOWN' })).json().id;
    expect((await get('admin', '/v1/admin/review')).json().posts.map((x: { id: string }) => x.id)).toEqual([pend]);
    expect((await post('admin', `/v1/admin/review/post/${pend}`, { decision: 'approve' })).json().status).toBe('approved');
    expect((await get('admin', '/v1/admin/review')).json().posts).toEqual([]);
    expect((await post('admin', '/v1/admin/review/post/00000000-0000-4000-8000-000000000000', { decision: 'hide' })).statusCode).toBe(404);
    expect((await post('admin', `/v1/admin/review/post/${pend}`, { decision: 'maybe' })).statusCode).toBe(400);
  });

  it('导出带举报与拉黑；删号级联；没配 moderation 时 503', async () => {
    const a = await signIn('alice'); const b = await signIn('bob');
    await put('alice', `/v1/users/${b}/block`);
    await post('alice', '/v1/reports', { target_type: 'user', target_id: b, reason: 'spam' });
    const ex = await get('alice', '/v1/users/me/export');
    expect(ex.json().modules.moderation.blocks).toHaveLength(1);
    expect(ex.json().modules.moderation.reports_filed).toHaveLength(1);
    expect((await del('alice', '/v1/users/me')).json().deleted).toBe(true);
    expect(await moderation.blockedIdsAround(b)).toEqual([]);
    expect(await moderation.openReports(10)).toEqual([]);
    expect(a).not.toBe(b);
    await app.close();
    const store = new MemoryStore({ content, timezone: SH, blueprint: blueprintSets(bp), now: () => clock, contentVersion: CV });
    app = await buildApp({ store, content, contentVersion: CV, blueprintDir: BLUEPRINTS, regionsFile: REGIONS, pepper: 'p', now: () => clock,
      accounts, firebase: { projectId: PROJECT, keys: k.keys }, social, feed });
    await signIn('bob');
    expect((await put('bob', `/v1/users/${a}/block`)).statusCode).toBe(503);
  });
});
