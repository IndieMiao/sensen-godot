import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import path from 'node:path';
import { buildApp, blueprintSets, loadBlueprint } from '../../src/http/app.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { MemoryAccountStore } from '../../src/http/memory_accounts.js';
import { MemorySocialStore } from '../../src/http/memory_social.js';
import { MemoryModerationStore } from '../../src/http/memory_moderation.js';
import { MemoryImStore } from '../../src/http/memory_im.js';
import { socialAccountModule } from '../../src/http/social.js';
import { moderationAccountModule, type ModerationVerdict, type TextModerator } from '../../src/http/moderation.js';
import { RecordingHub, greetingBlocked, imAccountModule, validateMessage } from '../../src/http/im.js';
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

class FakeModerator implements TextModerator {
  async check(text: string): Promise<ModerationVerdict> { return text.includes('BAD') ? { flagged: true, categories: ['harassment'] } : { flagged: false, categories: [] }; }
}

let app: FastifyInstance;
let accounts: MemoryAccountStore;
let social: MemorySocialStore;
let moderation: MemoryModerationStore;
let im: MemoryImStore;
let hub: RecordingHub;
let clock = at('2026-09-07T20:00:00+08:00');

beforeEach(async () => {
  clock = at('2026-09-07T20:00:00+08:00');
  accounts = new MemoryAccountStore();
  social = new MemorySocialStore(async id => (await accounts.userById(id)) !== null);
  moderation = new MemoryModerationStore();
  im = new MemoryImStore();
  hub = new RecordingHub();
  const store = new MemoryStore({ content, timezone: SH, blueprint: blueprintSets(bp), now: () => clock, contentVersion: CV });
  app = await buildApp({
    store, content, contentVersion: CV, blueprintDir: BLUEPRINTS, regionsFile: REGIONS, pepper: 'p', now: () => clock,
    accounts, firebase: { projectId: PROJECT, keys: k.keys }, social, moderation, im, liveHub: hub, textModerator: new FakeModerator(),
    accountModules: [socialAccountModule(social), moderationAccountModule(moderation), imAccountModule(im)],
  });
});
afterEach(async () => { await app.close(); });

const tok = (uid: string) => idToken(k, clock, {}, uid);
const authed = (uid: string) => ({ authorization: `Bearer ${tok(uid)}` });
const signIn = async (uid: string): Promise<string> =>
  (await app.inject({ method: 'POST', url: '/v1/auth/firebase', payload: { id_token: tok(uid) } })).json().user_id as string;
const get = (uid: string, url: string) => app.inject({ method: 'GET', url, headers: authed(uid) });
const post = (uid: string, url: string, payload?: object) => app.inject({ method: 'POST', url, headers: authed(uid), payload });
const put = (uid: string, url: string) => app.inject({ method: 'PUT', url, headers: authed(uid) });
const del = (uid: string, url: string) => app.inject({ method: 'DELETE', url, headers: authed(uid) });
const dm = async (uid: string, other: string) => (await post(uid, '/v1/im/dm', { user_id: other })).json().id as string;
const send = (uid: string, conv: string, text: string, clientId = text) => post(uid, `/v1/im/conversations/${conv}/messages`, { client_id: clientId, text });

describe('单聊', () => {
  it('找或建：两个方向同一会话；自己 400；不存在 404；拉黑 403', async () => {
    const a = await signIn('alice'); const b = await signIn('bob'); const c = await signIn('carol');
    const r1 = await post('alice', '/v1/im/dm', { user_id: b });
    expect(r1.statusCode).toBe(201);
    expect(r1.json()).toMatchObject({ kind: 'dm', peer: { user_id: b, display_name: 'bob' }, member_count: 2, unread: 0, last_message: null, created: true });
    const r2 = await post('bob', '/v1/im/dm', { user_id: a });
    expect(r2.statusCode).toBe(200);
    expect(r2.json().id).toBe(r1.json().id);
    expect(r2.json().peer.user_id).toBe(a);
    expect((await post('alice', '/v1/im/dm', { user_id: a })).json().code).toBe('SELF_DM');
    expect((await post('alice', '/v1/im/dm', { user_id: '00000000-0000-4000-8000-000000000000' })).statusCode).toBe(404);
    expect((await post('alice', '/v1/im/dm', { user_id: 'nope' })).statusCode).toBe(400);
    await put('carol', `/v1/users/${a}/block`);
    expect((await post('alice', '/v1/im/dm', { user_id: c })).json().code).toBe('BLOCKED');
  });

  it('发消息 → 双方 inbox 各一条事件（用户级 seq）→ 会话列表未读 → 已读推回执；历史倒序分页；client_id 重放', async () => {
    const a = await signIn('alice'); const b = await signIn('bob');
    await put('alice', `/v1/users/${b}/follow`);
    const conv = await dm('alice', b);
    const m1 = await send('alice', conv, 'hi');
    expect(m1.statusCode).toBe(201);
    expect(m1.json()).toMatchObject({ seq: 1, sender_id: a, kind: 'text', body: { text: 'hi' }, created: true, deleted: false });
    expect((await send('alice', conv, 'hi')).json()).toMatchObject({ seq: 1, created: false });
    clock += 1000;
    expect((await send('alice', conv, 'again', 'c2')).json().seq).toBe(2);
    expect(hub.published.filter(e => e.type === 'message')).toHaveLength(4); // 2 条消息 × 2 个成员
    const bobSync = await get('bob', '/v1/im/sync');
    expect(bobSync.json().latest_seq).toBe(2);
    expect(bobSync.json().events.map((e: { seq: number; type: string; seq_conv?: number }) => [e.seq, e.type])).toEqual([[1, 'message'], [2, 'message']]);
    expect(bobSync.json().events[0]).toMatchObject({ conversation_id: conv, sender_id: a, body: { text: 'hi' }, message_seq: 1 });
    expect((await get('bob', '/v1/im/sync?since=1')).json().events).toHaveLength(1);
    const list = await get('bob', '/v1/im/conversations');
    expect(list.json().items[0]).toMatchObject({ id: conv, unread: 2, last_seq: 2, last_read_seq: 0, last_message: { body: { text: 'again' } }, peer: { user_id: a } });
    const read = await post('bob', `/v1/im/conversations/${conv}/read`, { seq: 99 });
    expect(read.json().last_read_seq).toBe(2); // 夹到 last_seq
    expect((await get('bob', '/v1/im/conversations')).json().items[0].unread).toBe(0);
    const aliceSync = await get('alice', '/v1/im/sync?since=2');
    expect(aliceSync.json().events).toEqual([expect.objectContaining({ seq: 3, type: 'read', conversation_id: conv, user_id: b, read_seq: 2 })]);
    expect((await post('bob', `/v1/im/conversations/${conv}/read`, { seq: 1 })).json().last_read_seq).toBe(2); // 不倒退
    const hist = await get('alice', `/v1/im/conversations/${conv}/messages?limit=1`);
    expect(hist.json().items.map((m: { seq: number }) => m.seq)).toEqual([2]);
    expect((await get('alice', `/v1/im/conversations/${conv}/messages?limit=5&before_seq=2`)).json().items.map((m: { seq: number }) => m.seq)).toEqual([1]);
    expect((await get('carol', `/v1/im/conversations/${conv}/messages`)).statusCode).toBe(404); // 非成员
  });

  it('陌生人规则：先开口只能发一条，对方回复后解除；有关注关系不受限；拉黑后 403', async () => {
    const a = await signIn('alice'); const b = await signIn('bob');
    const conv = await dm('alice', b);
    expect((await send('alice', conv, 'hello')).statusCode).toBe(201);
    expect((await send('alice', conv, 'hello?')).json().code).toBe('GREETING_LIMIT');
    expect((await send('bob', conv, 'hey')).statusCode).toBe(201);
    expect((await send('alice', conv, 'now ok')).statusCode).toBe(201);
    expect(greetingBlocked({ following: false, followed_by: false, close_friends: false }, { a_count: 1, b_count: 0 })).toBe(true);
    expect(greetingBlocked({ following: true, followed_by: false, close_friends: false }, { a_count: 5, b_count: 0 })).toBe(false);
    const c = await signIn('carol');
    await put('alice', `/v1/users/${c}/follow`);
    const conv2 = await dm('alice', c);
    expect((await send('alice', conv2, '1')).statusCode).toBe(201);
    expect((await send('alice', conv2, '2')).statusCode).toBe(201);
    await put('carol', `/v1/users/${a}/block`);
    expect((await send('alice', conv2, '3')).json().code).toBe('BLOCKED');
    expect((await send('carol', conv2, 'x')).json().code).toBe('BLOCKED');
  });

  it('校验与审核：文字长度 / 图片 key 归属 / 命中拒发；撤回只有发送者能做并推事件', async () => {
    const a = await signIn('alice'); const b = await signIn('bob');
    await put('alice', `/v1/users/${b}/follow`);
    const conv = await dm('alice', b);
    expect((await post('alice', `/v1/im/conversations/${conv}/messages`, { client_id: 'x', text: '' })).json().field).toBe('text');
    expect((await post('alice', `/v1/im/conversations/${conv}/messages`, { client_id: 'x', kind: 'image', image: { key: 'u/other/1.jpg' } })).json().reason).toBe('NOT_OWNED');
    const img = await post('alice', `/v1/im/conversations/${conv}/messages`, { client_id: 'img', kind: 'image', image: { key: `u/${a}/20260907/1.jpg`, w: 10, h: 10 }, text: 'cap' });
    expect(img.json()).toMatchObject({ kind: 'image', body: { key: `u/${a}/20260907/1.jpg`, w: 10, h: 10, text: 'cap' } });
    expect((await send('alice', conv, 'BAD words')).json().code).toBe('MODERATION_REJECTED');
    expect(validateMessage({ client_id: 'c', kind: 'audio' })).toMatchObject({ ok: false, field: 'kind' });
    expect((await del('bob', `/v1/im/messages/${img.json().id}`)).statusCode).toBe(403);
    expect((await del('alice', `/v1/im/messages/${img.json().id}`)).json().deleted).toBe(true);
    const hist = await get('bob', `/v1/im/conversations/${conv}/messages`);
    expect(hist.json().items[0]).toMatchObject({ deleted: true, kind: 'system', body: { deleted: true } });
    expect((await get('bob', '/v1/im/sync')).json().events.at(-1)).toMatchObject({ type: 'message_deleted', message_id: img.json().id });
    expect((await del('carol', `/v1/im/messages/${img.json().id}`)).statusCode).toBe(404);
  });
});

describe('群聊', () => {
  it('建群 / 拉人 / 退群，事件扇出到全部成员；非成员发消息 404；成员校验', async () => {
    const a = await signIn('alice'); const b = await signIn('bob'); const c = await signIn('carol'); await signIn('dave');
    const g = await post('alice', '/v1/im/groups', { title: ' Team ', member_ids: [b] });
    expect(g.statusCode).toBe(201);
    expect(g.json()).toMatchObject({ kind: 'group', title: 'Team', member_count: 2, peer: null });
    const gid = g.json().id as string;
    expect((await get('bob', '/v1/im/sync')).json().events[0]).toMatchObject({ type: 'conversation_created', conversation_id: gid, by: a });
    expect((await post('carol', `/v1/im/conversations/${gid}/messages`, { client_id: 'x', text: 'let me in' })).statusCode).toBe(404);
    expect((await post('alice', `/v1/im/groups/${gid}/members`, { user_ids: [c] })).json().added).toEqual([c]);
    expect((await post('alice', `/v1/im/groups/${gid}/members`, { user_ids: [c] })).json().added).toEqual([]);
    expect((await get('carol', '/v1/im/sync')).json().events[0]).toMatchObject({ type: 'members_added', user_ids: [c] });
    const m = await post('carol', `/v1/im/conversations/${gid}/messages`, { client_id: 'm1', text: 'hello all' });
    expect(m.statusCode).toBe(201);
    for (const u of ['alice', 'bob', 'carol']) expect((await get(u, '/v1/im/sync')).json().events.at(-1)).toMatchObject({ type: 'message', body: { text: 'hello all' } });
    expect((await del('bob', `/v1/im/groups/${gid}/members/me`)).json().removed).toBe(true);
    expect((await get('alice', '/v1/im/sync')).json().events.at(-1)).toMatchObject({ type: 'member_left', user_id: b });
    expect((await get('bob', `/v1/im/conversations/${gid}/messages`)).statusCode).toBe(404);
    expect((await get('alice', '/v1/im/conversations')).json().items[0].member_count).toBe(2);
    expect((await post('alice', '/v1/im/groups', { title: 'x', member_ids: ['00000000-0000-4000-8000-000000000000'] })).json()).toMatchObject({ code: 'SCHEMA', reason: 'UNKNOWN_USER' });
    expect((await post('alice', '/v1/im/groups', { title: '', member_ids: [b] })).json().field).toBe('title');
    const dmConv = await dm('alice', b);
    expect((await post('alice', `/v1/im/groups/${dmConv}/members`, { user_ids: [c] })).json().code).toBe('NOT_GROUP');
    await put('dave', `/v1/users/${a}/block`);
    const d = (await get('alice', '/v1/users/@dave/profile')).statusCode; // 404：拉黑双向
    expect(d).toBe(404);
  });
});

describe('其他', () => {
  it('没配 im 503；导出带消息；删号后单聊对对方消失、消息内容清空', async () => {
    const a = await signIn('alice'); const b = await signIn('bob');
    await put('alice', `/v1/users/${b}/follow`); await put('bob', `/v1/users/${a}/follow`);
    const conv = await dm('alice', b);
    await send('alice', conv, 'secret'); await send('bob', conv, 'reply');
    expect((await get('alice', '/v1/users/me/export')).json().modules.im.messages.map((m: { body: { text: string } }) => m.body.text)).toEqual(['secret']);
    expect((await del('alice', '/v1/users/me')).json().deleted).toBe(true);
    expect((await get('bob', '/v1/im/conversations')).json().items).toEqual([]);
    expect(await im.conversation(conv)).toBeNull();
    await app.close();
    const store = new MemoryStore({ content, timezone: SH, blueprint: blueprintSets(bp), now: () => clock, contentVersion: CV });
    app = await buildApp({ store, content, contentVersion: CV, blueprintDir: BLUEPRINTS, regionsFile: REGIONS, pepper: 'p', now: () => clock,
      accounts, firebase: { projectId: PROJECT, keys: k.keys }, social });
    expect((await get('bob', '/v1/im/conversations')).json().code).toBe('IM_NOT_CONFIGURED');
    expect((await app.inject({ method: 'GET', url: '/v1/healthz' })).json().im).toBe(false);
  });
});

describe('成员列表、对方已读进度、举报消息（B2 第二刀的服务端）', () => {
  it('单聊带 peer_read_seq 并随对方已读推进；成员列表带昵称与已读进度；群聊 peer_read_seq 为 null；非成员 404', async () => {
    const a = await signIn('alice'); const b = await signIn('bob'); await signIn('carol');
    const conv = await dm('alice', b);
    await send('alice', conv, 'hi');
    expect((await get('alice', '/v1/im/conversations')).json().items[0].peer_read_seq).toBe(0);
    await post('bob', `/v1/im/conversations/${conv}/read`, { seq: 1 });
    expect((await get('alice', '/v1/im/conversations')).json().items[0].peer_read_seq).toBe(1);
    const ms = await get('alice', `/v1/im/conversations/${conv}/members`);
    expect(ms.statusCode).toBe(200);
    const byId = new Map(ms.json().items.map((m: { user_id: string }) => [m.user_id, m]));
    expect(byId.get(b)).toMatchObject({ last_read_seq: 1, display_name: 'bob' });
    expect(byId.get(a)).toMatchObject({ display_name: 'alice' });
    expect(typeof (byId.get(a) as { joined_at: number }).joined_at).toBe('number');
    expect((await get('carol', `/v1/im/conversations/${conv}/members`)).statusCode).toBe(404);
    const g = await post('alice', '/v1/im/groups', { title: 'T', member_ids: [b] });
    expect(g.json().peer_read_seq).toBeNull();
    expect((await get('bob', `/v1/im/conversations/${g.json().id}/members`)).json().items).toHaveLength(2);
  });

  it('举报消息：非成员 404；不能举报自己的；同一人去重；3 人举报自动撤回并推 message_deleted；撤回后不再受理', async () => {
    await signIn('alice'); const b = await signIn('bob'); const c = await signIn('carol'); const d = await signIn('dave'); await signIn('eve');
    const gid = (await post('alice', '/v1/im/groups', { title: 'T', member_ids: [b, c, d] })).json().id as string;
    const m = (await send('alice', gid, 'rude')).json();
    const report = (uid: string) => post(uid, '/v1/reports', { target_type: 'message', target_id: m.id, reason: 'harassment' });
    expect((await report('eve')).statusCode).toBe(404);
    expect((await report('alice')).json().code).toBe('SELF_REPORT');
    expect((await report('bob')).statusCode).toBe(201);
    expect((await report('bob')).statusCode).toBe(200);
    expect((await report('carol')).json().auto_hidden).toBe(false);
    const third = await report('dave');
    expect(third.statusCode).toBe(201);
    expect(third.json().auto_hidden).toBe(true);
    expect(hub.published.at(-1)).toMatchObject({ type: 'message_deleted', payload: { conversation_id: gid, message_id: m.id, message_seq: 1 } });
    expect((await get('bob', `/v1/im/conversations/${gid}/messages`)).json().items[0]).toMatchObject({ id: m.id, deleted: true, kind: 'system' });
    expect((await post('eve', '/v1/reports', { target_type: 'message', target_id: m.id, reason: 'spam' })).statusCode).toBe(404);
  });
});
