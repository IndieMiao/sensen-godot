import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import path from 'node:path';
import { buildApp, blueprintSets, loadBlueprint } from '../../src/http/app.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { MemoryAccountStore } from '../../src/http/memory_accounts.js';
import { MemorySocialStore } from '../../src/http/memory_social.js';
import { MemoryModerationStore } from '../../src/http/memory_moderation.js';
import { MemoryImStore } from '../../src/http/memory_im.js';
import { MemoryDeviceStore } from '../../src/http/memory_push.js';
import { socialAccountModule } from '../../src/http/social.js';
import { moderationAccountModule } from '../../src/http/moderation.js';
import { imAccountModule, type LiveHub, type UserEvent } from '../../src/http/im.js';
import { messageNotification, offlineRecipients, pushAccountModule, validateRegister,
  type DeviceRow, type Notification, type PushSender } from '../../src/http/push.js';
import { fcmSender, parseServiceAccount, signAssertion } from '../../src/http/fcm.js';
import { DEFAULT_CONTENT_DIR, contentVersion, loadContent } from '../../src/domain/content.js';
import { at, SH } from '../domain/helpers.js';
import { PROJECT, idToken, makeKeys } from '../fixtures/firebase_tokens.js';
import { generateKeyPairSync, createVerify } from 'node:crypto';

const ROOT = path.resolve(DEFAULT_CONTENT_DIR, '..', '..', '..');
const BLUEPRINTS = path.join(ROOT, 'assets', 'blueprints');
const REGIONS = path.join(DEFAULT_CONTENT_DIR, 'regions.json');
const content = loadContent(DEFAULT_CONTENT_DIR);
const CV = contentVersion(DEFAULT_CONTENT_DIR);
const bp = loadBlueprint(BLUEPRINTS, 'sh_a', 2)!;
const k = makeKeys();

/** 在线名单可控的假 hub：谁在线由测试说了算。 */
class FakeHub implements LiveHub {
  onlineIds = new Set<string>();
  publish(_events: UserEvent[]): void {}
  has(userId: string): boolean { return this.onlineIds.has(userId); }
}
class RecordingSender implements PushSender {
  calls: { tokens: DeviceRow[]; n: Notification }[] = [];
  invalid: string[] = [];
  async send(tokens: DeviceRow[], n: Notification) {
    this.calls.push({ tokens, n });
    return { sent: tokens.length - this.invalid.length, invalid: this.invalid };
  }
}

let app: FastifyInstance;
let accounts: MemoryAccountStore;
let devices: MemoryDeviceStore;
let sender: RecordingSender;
let hub: FakeHub;
let clock = at('2026-09-08T10:00:00+08:00');

beforeEach(async () => {
  clock = at('2026-09-08T10:00:00+08:00');
  accounts = new MemoryAccountStore();
  const social = new MemorySocialStore(async id => (await accounts.userById(id)) !== null);
  devices = new MemoryDeviceStore();
  sender = new RecordingSender();
  hub = new FakeHub();
  const im = new MemoryImStore();
  const store = new MemoryStore({ content, timezone: SH, blueprint: blueprintSets(bp), now: () => clock, contentVersion: CV });
  app = await buildApp({
    store, content, contentVersion: CV, blueprintDir: BLUEPRINTS, regionsFile: REGIONS, pepper: 'p', now: () => clock,
    accounts, firebase: { projectId: PROJECT, keys: k.keys }, social, im, liveHub: hub,
    moderation: new MemoryModerationStore(), devices, pushSender: sender,
    accountModules: [socialAccountModule(social), moderationAccountModule(new MemoryModerationStore()), imAccountModule(im), pushAccountModule(devices)],
  });
});
afterEach(async () => { await app.close(); });

const tok = (uid: string) => idToken(k, clock, {}, uid);
const authed = (uid: string) => ({ authorization: `Bearer ${tok(uid)}` });
const signIn = async (uid: string): Promise<string> =>
  (await app.inject({ method: 'POST', url: '/v1/auth/firebase', payload: { id_token: tok(uid) } })).json().user_id as string;
const put = (uid: string, url: string, payload?: object) => app.inject({ method: 'PUT', url, headers: authed(uid), payload });
const del = (uid: string, url: string, payload?: object) => app.inject({ method: 'DELETE', url, headers: authed(uid), payload });
const post = (uid: string, url: string, payload?: object) => app.inject({ method: 'POST', url, headers: authed(uid), payload });

describe('D7 推送', () => {
  it('token 校验；注册后同 token 换人登录归属跟着换；只能注销自己的', async () => {
    expect(validateRegister({ token: 'x', platform: 'ios' })).toMatchObject({ ok: false, field: 'token' });
    expect(validateRegister({ token: 'abcdefghij', platform: 'web' })).toMatchObject({ ok: false, field: 'platform' });
    const a = await signIn('alice'); const b = await signIn('bob');
    expect((await put('alice', '/v1/devices', { token: 'tok-shared-1', platform: 'ios' })).statusCode).toBe(200);
    expect((await put('alice', '/v1/devices', { token: 'bad', platform: 'ios' })).statusCode).toBe(400);
    expect((await devices.tokensFor([a]))[0]).toMatchObject({ token: 'tok-shared-1', platform: 'ios' });
    await put('bob', '/v1/devices', { token: 'tok-shared-1', platform: 'ios' });
    expect(await devices.tokensFor([a])).toEqual([]);
    expect((await devices.tokensFor([b]))[0].user_id).toBe(b);
    // alice 拿 bob 的 token 来注销：无效，不动别人的表。
    expect((await del('alice', '/v1/devices', { token: 'tok-shared-1' })).statusCode).toBe(200);
    expect(await devices.tokensFor([b])).toHaveLength(1);
    expect((await del('bob', '/v1/devices', { token: 'tok-shared-1' })).statusCode).toBe(200);
    expect(await devices.tokensFor([b])).toEqual([]);
  });

  it('只给不在线的成员推，正文不进通知，失效 token 顺手清掉', async () => {
    const a = await signIn('alice'); const b = await signIn('bob');
    await put('bob', '/v1/devices', { token: 'tok-bob-0001', platform: 'android' });
    await put('alice', '/v1/devices', { token: 'tok-alice-0001', platform: 'ios' });
    await put('alice', `/v1/users/${b}/follow`); await put('bob', `/v1/users/${a}/follow`);
    const conv = (await post('alice', '/v1/im/dm', { user_id: b })).json().id as string;

    hub.onlineIds.add(b); // bob 在线：不推
    await post('alice', `/v1/im/conversations/${conv}/messages`, { client_id: 'm1', text: '在吗' });
    expect(sender.calls).toHaveLength(0);

    hub.onlineIds.delete(b); // bob 离线：推给他，不推给发送者自己
    await post('alice', `/v1/im/conversations/${conv}/messages`, { client_id: 'm2', text: '秘密内容' });
    expect(sender.calls).toHaveLength(1);
    expect(sender.calls[0].tokens.map(t => t.token)).toEqual(['tok-bob-0001']);
    expect(JSON.stringify(sender.calls[0].n)).not.toContain('秘密内容');
    expect(sender.calls[0].n.data).toMatchObject({ type: 'im_message', conversation_id: conv });

    // 幂等重放不重复推送。
    await post('alice', `/v1/im/conversations/${conv}/messages`, { client_id: 'm2', text: '秘密内容' });
    expect(sender.calls).toHaveLength(1);

    // FCM 说 token 失效 → 从表里删掉。
    sender.invalid = ['tok-bob-0001'];
    await post('alice', `/v1/im/conversations/${conv}/messages`, { client_id: 'm3', text: 'hi' });
    expect(await devices.tokensFor([b])).toEqual([]);
  });

  it('通知文案不含正文；离线名单排除发送者与在线的人；删号清 token', async () => {
    expect(messageNotification('QA alice', 'c1', 'text')).toEqual({
      title: 'QA alice', body: 'Sent you a message', data: { type: 'im_message', conversation_id: 'c1' } });
    expect(messageNotification('', 'c1', 'image').title).toBe('Someone');
    expect(messageNotification('QA alice', 'c1', 'image').body).toBe('Sent you a photo');
    expect(offlineRecipients(['a', 'b', 'c'], 'a', id => id === 'b')).toEqual(['c']);
    const a = await signIn('alice');
    await put('alice', '/v1/devices', { token: 'tok-x-000001', platform: 'ios' });
    const mod = pushAccountModule(devices);
    expect(await mod.export!(a)).toEqual([{ platform: 'ios', updated_at: clock }]);
    await mod.del!(a);
    expect(await devices.tokensFor([a])).toEqual([]);
  });

  it('FCM 发送端：服务账号 JWT 可验签，失效 token 回报，access token 会缓存', async () => {
    const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
    const sa = { project_id: 'p1', client_email: 'svc@p1.iam', private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString() };
    const jwt = signAssertion(sa, 1_700_000_000_000);
    const [h, c, sig] = jwt.split('.');
    const v = createVerify('RSA-SHA256'); v.update(`${h}.${c}`);
    expect(v.verify(publicKey, Buffer.from(sig, 'base64url'))).toBe(true);
    expect(JSON.parse(Buffer.from(c, 'base64url').toString()).scope).toBe('https://www.googleapis.com/auth/firebase.messaging');
    expect(parseServiceAccount('{"project_id":"p"}')).toBeNull();

    const seen: string[] = [];
    let now = 1_700_000_000_000;
    const http = async (url: string, init: { body: string }) => {
      seen.push(url);
      if (url.includes('oauth2')) return { status: 200, json: { access_token: 'at-1', expires_in: 3600 } };
      const body = JSON.parse(init.body) as { message: { token: string } };
      return body.message.token === 'dead'
        ? { status: 404, json: { error: { status: 'UNREGISTERED' } } }
        : { status: 200, json: {} };
    };
    const s = fcmSender(sa, () => now, http);
    const rows: DeviceRow[] = [
      { user_id: 'u', token: 'live', platform: 'ios', updated_at: now },
      { user_id: 'u', token: 'dead', platform: 'android', updated_at: now },
    ];
    expect(await s.send(rows, messageNotification('A', 'c1', 'text'))).toEqual({ sent: 1, invalid: ['dead'] });
    expect(seen.filter(u => u.includes('oauth2'))).toHaveLength(1);
    now += 60_000;
    await s.send(rows.slice(0, 1), messageNotification('A', 'c1', 'text'));
    expect(seen.filter(u => u.includes('oauth2'))).toHaveLength(1); // 仍在有效期内：不再换 token
  });

  it('未配置设备表时注册路由 503', async () => {
    const bare = await buildApp({
      store: new MemoryStore({ content, timezone: SH, blueprint: blueprintSets(bp), now: () => clock, contentVersion: CV }),
      content, contentVersion: CV, blueprintDir: BLUEPRINTS, regionsFile: REGIONS, pepper: 'p', now: () => clock,
      accounts, firebase: { projectId: PROJECT, keys: k.keys },
    });
    expect((await bare.inject({ method: 'PUT', url: '/v1/devices', headers: authed('alice'), payload: { token: 'abcdefghij', platform: 'ios' } })).statusCode).toBe(503);
    await bare.close();
  });
});
