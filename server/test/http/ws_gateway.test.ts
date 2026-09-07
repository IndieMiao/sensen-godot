/** WS 网关：握手鉴权、hello、事件实时推送、多连接、ping/pong、关闭清理。用 @fastify/websocket 的 injectWS。 */
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { once } from 'node:events';
import path from 'node:path';
import { buildApp, blueprintSets, loadBlueprint } from '../../src/http/app.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { MemoryAccountStore } from '../../src/http/memory_accounts.js';
import { MemorySocialStore } from '../../src/http/memory_social.js';
import { MemoryModerationStore } from '../../src/http/memory_moderation.js';
import { MemoryImStore } from '../../src/http/memory_im.js';
import { SocketHub, WS_CLOSE_FORBIDDEN, WS_CLOSE_NOT_FOUND, WS_CLOSE_UNAUTHENTICATED, eventFrame } from '../../src/http/ws_gateway.js';
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
let moderation: MemoryModerationStore;
let hub: SocketHub;
let clock = at('2026-09-07T21:00:00+08:00');

beforeEach(async () => {
  clock = at('2026-09-07T21:00:00+08:00');
  accounts = new MemoryAccountStore();
  const social = new MemorySocialStore(async id => (await accounts.userById(id)) !== null);
  moderation = new MemoryModerationStore();
  hub = new SocketHub();
  const store = new MemoryStore({ content, timezone: SH, blueprint: blueprintSets(bp), now: () => clock, contentVersion: CV });
  app = await buildApp({ store, content, contentVersion: CV, blueprintDir: BLUEPRINTS, regionsFile: REGIONS, pepper: 'p', now: () => clock,
    // 注入型 socket 关闭时不触发服务端 close 事件，靠 ping 兜底清理；测试把心跳缩到 50 ms。
    accounts, firebase: { projectId: PROJECT, keys: k.keys }, social, moderation, im: new MemoryImStore(), wsHub: hub, wsPingIntervalMs: 50 });
  await app.ready();
});
afterEach(async () => { await app.close(); });

const tok = (uid: string) => idToken(k, clock, {}, uid);
const authed = (uid: string) => ({ authorization: `Bearer ${tok(uid)}` });
const signIn = async (uid: string): Promise<string> =>
  (await app.inject({ method: 'POST', url: '/v1/auth/firebase', payload: { id_token: tok(uid) } })).json().user_id as string;
/** 帧在 injectWS 返回前就可能到了：用 injectWS 的 onInit 在握手前挂监听并排队，next() 按序取。 */
type InjectedWs = Awaited<ReturnType<FastifyInstance['injectWS']>>;
class Inbox {
  ws!: InjectedWs;
  private queue: Record<string, unknown>[] = [];
  private waiters: ((v: Record<string, unknown>) => void)[] = [];
  attach(ws: InjectedWs): void {
    this.ws = ws;
    ws.on('message', (raw: unknown) => {
      const v = JSON.parse(String(raw)) as Record<string, unknown>;
      const w = this.waiters.shift();
      if (w) w(v); else this.queue.push(v);
    });
  }
  next(): Promise<Record<string, unknown>> {
    const q = this.queue.shift();
    if (q) return Promise.resolve(q);
    return new Promise(resolve => this.waiters.push(resolve));
  }
  close(): Promise<unknown> { this.ws.close(); return once(this.ws, 'close'); }
}
const connect = async (uid: string): Promise<Inbox> => {
  const inbox = new Inbox();
  await app.injectWS('/v1/im/ws', { headers: authed(uid) }, { onInit: (ws: InjectedWs) => inbox.attach(ws) });
  return inbox;
};

describe('WS 网关', () => {
  it('合法 token 连上收 hello；发消息后双方连接实时收到事件；两条连接都收；关闭后计数归零', async () => {
    const a = await signIn('alice'); const b = await signIn('bob');
    await app.inject({ method: 'PUT', url: `/v1/users/${b}/follow`, headers: authed('alice') });
    const wsA = await connect('alice'); const wsB1 = await connect('bob'); const wsB2 = await connect('bob');
    expect(await wsA.next()).toMatchObject({ type: 'hello', user_id: a });
    await wsB1.next(); await wsB2.next();
    expect(hub.connections(b)).toBe(2);
    expect(hub.online()).toBe(2);
    const conv = (await app.inject({ method: 'POST', url: '/v1/im/dm', headers: authed('alice'), payload: { user_id: b } })).json().id as string;
    const pending = [wsA.next(), wsB1.next(), wsB2.next()];
    const sent = await app.inject({ method: 'POST', url: `/v1/im/conversations/${conv}/messages`, headers: authed('alice'), payload: { client_id: 'c1', text: 'hi there' } });
    expect(sent.statusCode).toBe(201);
    const frames = await Promise.all(pending);
    for (const f of frames) expect(f).toMatchObject({ type: 'message', seq: 1, conversation_id: conv, message_seq: 1, sender_id: a, body: { text: 'hi there' }, event_at: clock });
    expect(hub.sent).toBe(3);
    // 已读回执只推给对方
    const readPending = wsA.next();
    await app.inject({ method: 'POST', url: `/v1/im/conversations/${conv}/read`, headers: authed('bob'), payload: { seq: 1 } });
    expect(await readPending).toMatchObject({ type: 'read', seq: 2, user_id: b, read_seq: 1 });
    await Promise.all([wsA.close(), wsB1.close(), wsB2.close()]);
    // 服务端的 close 回调在关闭握手之后才跑：轮询等，不猜毫秒数。
    const deadline = Date.now() + 2000;
    while (hub.online() > 0 && Date.now() < deadline) await new Promise(r => setTimeout(r, 10));
    expect(hub.online()).toBe(0);
  });

  it('上行 ping 回 pong；其他上行忽略', async () => {
    await signIn('alice');
    const ws = await connect('alice');
    await ws.next();
    ws.ws.send('not json');
    ws.ws.send(JSON.stringify({ type: 'send', text: 'nope' }));
    ws.ws.send(JSON.stringify({ type: 'ping' }));
    expect(await ws.next()).toMatchObject({ type: 'pong', server_time: clock });
    await ws.close();
  });

  it('坏 token 4401；没账号 4404；封禁 4403', async () => {
    const bad = await app.injectWS('/v1/im/ws', { headers: { authorization: 'Bearer garbage' } });
    expect((await once(bad, 'close'))[0]).toBe(WS_CLOSE_UNAUTHENTICATED);
    const noAccount = await app.injectWS('/v1/im/ws', { headers: authed('ghost') });
    expect((await once(noAccount, 'close'))[0]).toBe(WS_CLOSE_NOT_FOUND);
    const b = await signIn('banned');
    await moderation.ban(b, 'test', 'admin', clock);
    const banned = await app.injectWS('/v1/im/ws', { headers: authed('banned') });
    expect((await once(banned, 'close'))[0]).toBe(WS_CLOSE_FORBIDDEN);
    expect(hub.online()).toBe(0);
    expect((await app.inject({ method: 'GET', url: '/v1/healthz' })).json().ws).toBe(true);
  });

  it('eventFrame 把事件 seq 放在顶层，payload 平铺', () => {
    expect(JSON.parse(eventFrame({ user_id: 'u', seq: 7, type: 'message', payload: { conversation_id: 'c', message_seq: 3 }, created_at: 5 })))
      .toEqual({ type: 'message', seq: 7, conversation_id: 'c', message_seq: 3, event_at: 5 });
  });
});
