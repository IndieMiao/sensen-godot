/**
 * 接口里的上报（C-203）：没配置时不发任何外部请求；配置后注册、登录、认领、进入、地块命令、卖出、领蓝图按清单进队列并批量发出，
 * 只带内部用户 ID；Mixpanel 超时或报错时玩家请求照常返回。Mixpanel 一律用桩。
 */
import { afterEach, describe, expect, it, vi } from 'vitest';
import type { FastifyInstance } from 'fastify';
import path from 'node:path';
import { buildApp, plotFor } from '../../src/http/app.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { DEFAULT_CONTENT_DIR, contentVersion, loadContent } from '../../src/domain/content.js';
import { loadParcelRules } from '../../src/parcels/rules.js';
import { MemoryParcelStore } from '../../src/parcels/store.js';
import { MixpanelAnalytics, type Analytics } from '../../src/analytics/mixpanel.js';
import { makeKeys, signToken } from '../fixtures/firebase_tokens.js';
import { sha256Hex } from '../../src/accounts/apple_token.js';
import type { Mailer } from '../../src/accounts/mailer.js';

const content = loadContent(DEFAULT_CONTENT_DIR);
const CV = contentVersion(DEFAULT_CONTENT_DIR);
const ROOT = path.resolve(DEFAULT_CONTENT_DIR, '..', '..', '..');
const base = loadParcelRules(DEFAULT_CONTENT_DIR);
/** 好卖一次：让开局赠送的胡萝卜种子也能卖，卖一次就够领鸡舍蓝图。 */
const rules = { ...base, economy: { ...base.economy, sell_prices: { ...base.economy.sell_prices, seed_carrot: 3 } } };
const DATASET = 'sf-dynamic-farm-20261118-r4';
const PARCEL = { parcel_id: 'p-3512001', center: [-122.4194, 37.7749] };
const T0 = Date.UTC(2026, 10, 27, 4);
const GOOGLE_KEYS = makeKeys('google-analytics');
const GOOGLE_AUD = 'web-client.apps.googleusercontent.com';
const EMAIL = 'ada@example.com';
const IP = '203.0.113.7';

const opened: { app: FastifyInstance; analytics?: Analytics }[] = [];
async function appWith(analytics?: Analytics, mailer?: Mailer) {
  const store = new MemoryStore({ content, timezone: 'America/Los_Angeles', plot: plotFor(content), now: () => T0, contentVersion: CV });
  const app = await buildApp({
    store, content, contentVersion: CV, blueprintDir: path.join(ROOT, 'assets', 'blueprints'), regionsFile: path.join(DEFAULT_CONTENT_DIR, 'regions.json'),
    pepper: 'test-pepper', now: () => T0, realtimeEnabled: false, google: { audiences: [GOOGLE_AUD], keys: GOOGLE_KEYS.keys },
    parcels: { store: new MemoryParcelStore(id => store.displayNameOf(id)), rules, reselect: false }, analytics, mailer,
  });
  opened.push({ app, analytics });
  return app;
}
afterEach(async () => {
  for (const o of opened.splice(0)) { await o.app.close(); await o.analytics?.close(); }
  vi.restoreAllMocks();
});

const bearer = (token: string) => ({ authorization: `Bearer ${token}` });
let nonces = 0;
const google = (app: FastifyInstance, sub: string) => {
  const s = Math.floor(T0 / 1000), nonce = `nonce-0123456789abcdef-${++nonces}`;
  return app.inject({ method: 'POST', url: '/v1/auth/google', remoteAddress: IP, payload: { nonce, id_token: signToken(GOOGLE_KEYS, {
    iss: 'https://accounts.google.com', aud: GOOGLE_AUD, sub, iat: s, exp: s + 3600, nonce: sha256Hex(nonce), email: 'grace@gmail.com', email_verified: true }) } });
};
const command = (app: FastifyInstance, token: string, base_version: number, commands: object[]) =>
  app.inject({ method: 'POST', url: '/v1/parcels/mine/commands', headers: bearer(token), remoteAddress: IP, payload: { base_version, commands } });

/** 注册、再登录、Google 首登和再登、认领、进入两次、一批成功的命令（含卖出和领蓝图）、一批被拒、一批版本不符。返回 Ada 的 user_id。 */
async function play(app: FastifyInstance): Promise<string> {
  const reg = await app.inject({ method: 'POST', url: '/v1/auth/email/register', remoteAddress: IP,
    payload: { email: EMAIL, password: 'correct horse', display_name: 'Ada' } });
  expect(reg.statusCode).toBe(201);
  const login = await app.inject({ method: 'POST', url: '/v1/auth/email/login', remoteAddress: IP, payload: { email: EMAIL, password: 'correct horse' } });
  expect(login.statusCode).toBe(200);
  expect((await google(app, 'g-1')).statusCode).toBe(201);
  expect((await google(app, 'g-1')).statusCode).toBe(200);
  const token = login.json().token as string;
  const claim = await app.inject({ method: 'POST', url: '/v1/parcels/claim', headers: bearer(token), remoteAddress: IP, payload: { dataset_version: DATASET, ...PARCEL } });
  expect(claim.statusCode).toBe(201);
  expect((await app.inject({ method: 'POST', url: '/v1/parcels/mine/enter', headers: bearer(token), remoteAddress: IP })).json().granted).toBe(true);
  expect((await app.inject({ method: 'POST', url: '/v1/parcels/mine/enter', headers: bearer(token), remoteAddress: IP })).json().granted).toBe(false);
  expect((await command(app, token, 1, [{ type: 'till', cell: '1,1' }, { type: 'till', cell: '2,1' }, { type: 'sell', item: 'seed_carrot', count: 2 },
    { type: 'claim_blueprint', blueprint: 'coop' }])).statusCode).toBe(200);
  const refused = await command(app, token, 2, [{ type: 'till', cell: '3,1' }, { type: 'sell', item: 'blueprint_cottage', count: 1 }]);
  expect(refused.json()).toMatchObject({ code: 'NOT_SELLABLE', index: 1 });
  expect((await command(app, token, 1, [{ type: 'till', cell: '3,1' }])).statusCode).toBe(409);
  return reg.json().user_id;
}

/** Mixpanel 桩：记下每批事件，按 answer 回答。 */
function mixpanel(answer: 'ok' | 'error' | 'hang' = 'ok') {
  const batches: { event: string; properties: Record<string, unknown> }[][] = [];
  const bodies: string[] = [];
  const fetch = vi.fn(async (_url: string | URL | Request, init?: RequestInit) => {
    bodies.push(String(init!.body));
    batches.push(JSON.parse(String(init!.body)));
    if (answer === 'hang') return new Promise<Response>((_, reject) => init!.signal!.addEventListener('abort', () => reject(init!.signal!.reason)));
    return new Response('{}', { status: answer === 'ok' ? 200 : 500 });
  });
  const logs: string[] = [];
  const analytics = new MixpanelAnalytics({ token: 'test-token', host: 'https://api.mixpanel.com', fetch: fetch as unknown as typeof globalThis.fetch,
    batchSize: 5, flushMs: 60_000, timeoutMs: 100, retryDelayMs: 0, log: line => logs.push(line) });
  return { analytics, batches, bodies, fetch, logs };
}

describe('analytics in the routes (C-203)', () => {
  it('sends nothing anywhere when Mixpanel is not configured', async () => {
    const spy = vi.spyOn(globalThis, 'fetch');
    const app = await appWith();
    await play(app);
    expect(spy).not.toHaveBeenCalled();
  });

  it('queues the six events with only the internal user id and sends them in batches', async () => {
    const mp = mixpanel();
    const app = await appWith(mp.analytics);
    const userId = await play(app);
    await mp.analytics.flush();
    expect(mp.batches.length).toBeGreaterThan(1);
    expect(mp.batches.every(b => b.length <= 5)).toBe(true);
    const events = mp.batches.flat();
    const googleUser = events.find(e => e.event === 'account_created' && e.properties.method === 'google')!.properties.distinct_id;
    const strip = ({ time, $insert_id, ip, ...rest }: Record<string, unknown>) => {
      expect(time).toBe(T0);
      // ip=0 keeps Mixpanel from locating the event by this server's address.
      expect(ip).toBe(0);
      expect($insert_id).toEqual(expect.any(String));
      return rest;
    };
    const sf = { community_id: 'sf' };
    expect(events.map(e => ({ event: e.event, ...strip(e.properties) }))).toEqual([
      { event: 'account_created', distinct_id: userId, method: 'email' },
      { event: 'login', distinct_id: userId, method: 'email' },
      { event: 'account_created', distinct_id: googleUser, method: 'google' },
      { event: 'login', distinct_id: googleUser, method: 'google' },
      { event: 'parcel_claimed', distinct_id: userId, ...sf, dataset_version: DATASET, starter_zone: null },
      { event: 'parcel_enter', distinct_id: userId, ...sf, welcome_gift: true, rebased: false },
      { event: 'parcel_enter', distinct_id: userId, ...sf, welcome_gift: false, rebased: false },
      { event: 'farm_command', distinct_id: userId, ...sf, command: 'till', count: 2, outcome: 'applied' },
      { event: 'farm_command', distinct_id: userId, ...sf, command: 'sell', count: 1, outcome: 'applied' },
      { event: 'farm_command', distinct_id: userId, ...sf, command: 'claim_blueprint', count: 1, outcome: 'applied' },
      { event: 'market_sell', distinct_id: userId, ...sf, item: 'seed_carrot', count: 2, coins: 6 },
      { event: 'blueprint_claimed', distinct_id: userId, ...sf, blueprint: 'coop', item: 'blueprint_coop' },
      { event: 'farm_command', distinct_id: userId, ...sf, command: 'sell', count: 1, outcome: 'rejected', reject_code: 'NOT_SELLABLE' },
      { event: 'farm_command', distinct_id: userId, ...sf, command: 'till', count: 1, outcome: 'version_conflict' },
    ]);
    expect(googleUser).not.toBe(userId);
    // account_created's insert id is fixed per account, so the backfill script cannot count it twice.
    expect(events.filter(e => e.event === 'account_created').map(e => e.properties.$insert_id)).toEqual([`account_created:${userId}`, `account_created:${googleUser}`]);
    // No email, address, nickname, parcel id or coordinates leave the server.
    const sent = mp.bodies.join('\n');
    for (const secret of [EMAIL, 'grace@gmail.com', IP, '127.0.0.1', 'Ada', PARCEL.parcel_id, '37.77', '-122.41', 'lat', 'lng', 'center'])
      expect(sent).not.toContain(secret);
  });

  it.each(['error', 'hang'] as const)('keeps player requests working when Mixpanel answers with %s, retrying a batch once', async answer => {
    const mp = mixpanel(answer);
    const app = await appWith(mp.analytics);
    const started = Date.now();
    await play(app);
    await mp.analytics.flush();
    expect(Date.now() - started).toBeLessThan(5_000);
    // Every batch was tried twice, then dropped with a log line.
    const sent = mp.batches.length;
    expect(sent % 2).toBe(0);
    for (let i = 0; i < sent; i += 2) expect(mp.batches[i]).toEqual(mp.batches[i + 1]);
    expect(mp.logs.filter(l => l.startsWith('[analytics] dropped')).length).toBe(sent / 2);
  });

  it('answers players while a Mixpanel request is still outstanding', async () => {
    const pending: (() => void)[] = [];
    const fetch = vi.fn((_url: string | URL | Request, _init?: RequestInit) =>
      new Promise<Response>(resolve => pending.push(() => resolve(new Response('{}', { status: 200 })))));
    const analytics = new MixpanelAnalytics({ token: 'test-token', host: 'https://api.mixpanel.com', fetch: fetch as unknown as typeof globalThis.fetch,
      batchSize: 2, flushMs: 60_000, timeoutMs: 60_000, log: () => {} });
    const app = await appWith(analytics);
    await play(app);
    // The first batch is still unanswered: no request waited for it, and later events stay queued behind it.
    expect(fetch).toHaveBeenCalledTimes(1);
    const done = analytics.flush();
    while (pending.length) { pending.shift()!(); await new Promise(resolve => setImmediate(resolve)); }
    await done;
    expect(fetch.mock.calls.length).toBeGreaterThan(1);
  });

  // —— C-205 ——
  /** 收信桩：记下每个验证码。 */
  const inbox = () => {
    const mail: { email: string; code: string; purpose: string }[] = [];
    const mailer: Mailer = { async sendCode(email, code, purpose) { mail.push({ email, code, purpose }); } };
    return { mail, mailer };
  };
  const register = (app: FastifyInstance, email = EMAIL) => app.inject({ method: 'POST', url: '/v1/auth/email/register', remoteAddress: IP,
    payload: { email, password: 'correct horse', display_name: 'Ada' } });
  const gdprClient = (answer: number) => {
    const calls: { url: string; body: string }[] = [];
    const fetch = vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
      calls.push({ url: String(url), body: String(init!.body) });
      return new Response(String(url).includes('/data-deletions/') && answer === 200 ? '{"status":"ok","results":[{"tracking_id":"42"}]}' : '{}', { status: answer });
    });
    const logs: string[] = [];
    const analytics = new MixpanelAnalytics({ token: 'test-token', host: 'https://api.mixpanel.com', gdprToken: 'oauth', fetch: fetch as unknown as typeof globalThis.fetch,
      batchSize: 50, flushMs: 60_000, timeoutMs: 100, retryDelayMs: 0, log: line => logs.push(line) });
    return { analytics, calls, logs, deletions: () => calls.filter(c => c.url.includes('/data-deletions/')).map(c => JSON.parse(c.body)) };
  };

  it('reports a login with method password_reset after a successful email password reset', async () => {
    const mp = mixpanel();
    const { mail, mailer } = inbox();
    const app = await appWith(mp.analytics, mailer);
    const userId = (await register(app)).json().user_id;
    await app.inject({ method: 'POST', url: '/v1/auth/email/code', remoteAddress: IP, payload: { email: EMAIL, purpose: 'reset' } });
    const code = mail.filter(m => m.purpose === 'reset').at(-1)!.code;
    // A wrong code changes nothing and reports nothing.
    const wrong = await app.inject({ method: 'POST', url: '/v1/auth/email/reset', remoteAddress: IP,
      payload: { email: EMAIL, code: code === '000000' ? '111111' : '000000', password: 'brand new pass' } });
    expect(wrong.statusCode).toBe(422);
    const reset = await app.inject({ method: 'POST', url: '/v1/auth/email/reset', remoteAddress: IP, payload: { email: EMAIL, code, password: 'brand new pass' } });
    expect(reset.statusCode).toBe(200);
    await mp.analytics.flush();
    expect(mp.batches.flat().map(e => ({ event: e.event, id: e.properties.distinct_id, method: e.properties.method, time: e.properties.time }))).toEqual([
      { event: 'account_created', id: userId, method: 'email', time: T0 },
      { event: 'login', id: userId, method: 'password_reset', time: T0 },
    ]);
  });

  it.each(['app', 'web'] as const)('asks Mixpanel to delete the account\'s data when it is deleted (%s), dropping its unsent events', async source => {
    const mp = gdprClient(200);
    const app = await appWith(mp.analytics);
    const reg = (await register(app)).json();
    const other = (await register(app, 'bea@example.com')).json();
    const res = source === 'app'
      ? await app.inject({ method: 'DELETE', url: '/v1/users/me', headers: bearer(reg.token), remoteAddress: IP, payload: { password: 'correct horse' } })
      : await app.inject({ method: 'POST', url: '/v1/account/delete', remoteAddress: IP, payload: { email: EMAIL, password: 'correct horse' } });
    expect(res.statusCode).toBe(200);
    await mp.analytics.close();
    expect(mp.deletions()).toEqual([{ distinct_ids: [reg.user_id], compliance_type: 'GDPR' }]);
    const imported = mp.calls.filter(c => c.url.includes('/import')).flatMap(c => JSON.parse(c.body) as { properties: { distinct_id: string } }[]);
    expect(imported.map(e => e.properties.distinct_id)).toEqual([other.user_id]);
    expect(mp.logs).toEqual([`[analytics] Mixpanel deletion requested for user ${reg.user_id}, task 42`]);
  });

  it('still deletes the account when Mixpanel refuses the deletion, and only logs', async () => {
    const mp = gdprClient(500);
    const app = await appWith(mp.analytics);
    const reg = (await register(app)).json();
    const res = await app.inject({ method: 'DELETE', url: '/v1/users/me', headers: bearer(reg.token), remoteAddress: IP, payload: { password: 'correct horse' } });
    expect(res.statusCode).toBe(200);
    expect(res.json().ok).toBe(true);
    expect((await app.inject({ method: 'GET', url: '/v1/users/me', headers: bearer(reg.token) })).statusCode).toBe(401);
    await mp.analytics.close();
    expect(mp.deletions()).toHaveLength(2);
    expect(mp.logs.at(-1)).toBe(`[analytics] Mixpanel deletion for user ${reg.user_id} not requested; delete it in Mixpanel by hand`);
  });

  it('sends nothing on reset or deletion when Mixpanel is not configured', async () => {
    const spy = vi.spyOn(globalThis, 'fetch');
    const { mail, mailer } = inbox();
    const app = await appWith(undefined, mailer);
    expect((await register(app)).statusCode).toBe(201);
    await app.inject({ method: 'POST', url: '/v1/auth/email/code', remoteAddress: IP, payload: { email: EMAIL, purpose: 'reset' } });
    const reset = await app.inject({ method: 'POST', url: '/v1/auth/email/reset', remoteAddress: IP,
      payload: { email: EMAIL, code: mail.filter(m => m.purpose === 'reset').at(-1)!.code, password: 'brand new pass' } });
    expect(reset.statusCode).toBe(200);
    const del = await app.inject({ method: 'DELETE', url: '/v1/users/me', headers: bearer(reset.json().token), remoteAddress: IP, payload: { password: 'brand new pass' } });
    expect(del.statusCode).toBe(200);
    expect(spy).not.toHaveBeenCalled();
  });
});
