/** SGODOT-484, contract v1.6.9: real HTTP projection of the account's own voice ban. No client UI or extra wire fields. */
import Fastify from 'fastify';
import { AccessToken } from 'livekit-server-sdk';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { P0Voice, registerP0Voice } from '../../src/p0/online/voice.js';
import { loadOutposts } from '../../src/p0/online/outposts.js';
import { OutpostRooms } from '../../src/p0/online/rooms.js';
import { P0Store } from '../../src/p0/store.js';
import { P0Accounts } from '../../src/p0/accounts/store.js';
import { identify, inForce } from '../../src/p0/accounts/identify.js';
import { registerAccountDeleteRoute } from '../../src/p0/accounts/delete.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { loadP0Content } from '../../src/p0/content.js';
import type { Sanction } from '../../src/p0/state.js';

const T0 = Date.UTC(2026, 10, 15, 23, 59, 59), PLAYER = 'player-ban-test', OTHER = 'player-ban-other';
const TOKEN = '1'.repeat(64), OTHER_TOKEN = '2'.repeat(64);
const apps: ReturnType<typeof Fastify>[] = [];
afterEach(async () => { vi.restoreAllMocks(); for (const app of apps.splice(0)) await app.close(); });
function setup(on = true) {
  let now = T0;
  const content = loadP0Content(), store = new P0Store(content), accounts = new P0Accounts();
  for (const p of [PLAYER, OTHER]) { store.get(p, now); accounts.ensure(p); }
  accounts.issue(PLAYER, TOKEN); accounts.issue(OTHER, OTHER_TOKEN);
  const rooms = new OutpostRooms(loadOutposts());
  const voice = new P0Voice(on ? { url: 'ws://fake.test', apiKey: 'fake', apiSecret: 'fake-voice-secret-at-least-32-characters', namespace: 'contract-test' } : null,
    rooms, null, () => now, { getParticipant: async () => { throw Object.assign(new Error('gone'), { status: 404 }); }, removeParticipant: async () => {} });
  voice.voiceBan = p => store.peek(p)?.sanctions?.voice;
  const deps = { accounts, legacyId: false, suspended: (p: string) => inForce(store.peek(p)?.sanctions?.suspended, now) };
  const who = (headers: Record<string, unknown>) => identify(headers, deps);
  const app = Fastify(); apps.push(app);
  registerP0Voice(app, voice, who);
  registerP0Routes(app, { content, store, now: () => now, dev: false, identify: deps });
  registerAccountDeleteRoute(app, { store, accounts, voice, hub: { kick() {} }, now: () => now, identify: deps });
  const request = (url: string, method: 'GET' | 'POST' | 'DELETE' = 'GET', token = TOKEN) => app.inject({ method, url,
    headers: { authorization: `Bearer ${token}`, 'x-p0-player': token === OTHER_TOKEN ? OTHER : PLAYER },
    ...(method === 'POST' ? { payload: {} } : {}) });
  const set = (ban: unknown) => {
    const s = store.peek(PLAYER)!;
    s.sanctions = ban === undefined ? undefined : { voice: ban as Sanction };
  };
  return { app, voice, store, rooms, accounts, request, set, tick: (ms: number) => { now += ms; } };
}

describe('v1.6.9 voice ban status and errors', () => {
  it('projects absent, timed, exact expiry, permanent and removed states consistently, with no internal fields', async () => {
    const f = setup();
    const status = () => f.request('/v1/p0/voice/status');
    expect((await status()).json()).toEqual({ ok: true, available: true, age: 'unknown', ban: null });
    const until = T0 + 2000, iso = new Date(until).toISOString();
    const record = { until, at: T0, report: 'R-20261115-0123ABCD', admin: 'PRIVATE_ADMIN' };
    f.set(record);
    f.store.peek(PLAYER)!.clock_ms = 30 * 86_400_000; // A game-time jump must not expire a real-time sanction.
    for (const url of ['/v1/p0/voice/join', '/v1/p0/voice/heartbeat']) {
      const r = await f.request(url, 'POST');
      expect([r.statusCode, r.json()]).toEqual([403, { ok: false, code: 'VOICE_BANNED', until: iso }]);
    }
    expect((await status()).json()).toEqual({ ok: true, available: true, age: 'unknown', ban: { until: iso } });
    expect(record.until).toBe(until); // Storage remains milliseconds, not the ISO projection.
    const view = (await f.request('/v1/p0/state')).json().state;
    expect(view.account).toBeDefined();
    expect(view.account).not.toHaveProperty('ban'); expect(view).not.toHaveProperty('sanctions');
    expect(JSON.stringify(view)).not.toMatch(/PRIVATE_ADMIN|R-20261115-0123ABCD/);
    expect((await f.request('/v1/p0/voice/status', 'GET', OTHER_TOKEN)).json().ban).toBeNull();
    f.tick(2000); expect((await status()).json().ban).toBeNull();
    expect((await f.request('/v1/p0/voice/join', 'POST')).json()).toEqual({ ok: false, code: 'AGE_GATE' });
    f.set({ until: null, at: T0 });
    expect((await status()).json().ban).toEqual({ until: null });
    const permanent = await f.request('/v1/p0/voice/join', 'POST');
    expect(permanent.json()).toEqual({ ok: false, code: 'VOICE_BANNED', until: null });
    f.set(undefined); expect((await status()).json().ban).toBeNull();
  });

  it('status keeps ban even when voice is off or age is no; available and age retain their original meaning', async () => {
    const f = setup(false); f.voice.setAge(PLAYER, false); f.set({ until: null, at: T0 });
    expect((await f.request('/v1/p0/voice/status')).json()).toEqual({ ok: true, available: false, age: 'no', ban: { until: null } });
    expect((await f.request('/v1/p0/voice/join', 'POST')).json()).toEqual({ ok: false, code: 'VOICE_BANNED', until: null });
  });

  it.each([{}, { until: undefined }, { until: '' }, { until: false }, { until: NaN }, { until: Infinity },
    { until: T0 + 0.5 }, { until: 8_640_000_000_000_001 }])('malformed stored deadline is not returned as absent or permanent: %j', value => {
    const f = setup(); f.set(value);
    expect(() => f.voice.status(PLAYER)).toThrow('VOICE_BAN_INVALID');
    expect(f.voice.heartbeat(PLAYER, '')).toEqual({ code: 'VOICE_UNAVAILABLE', status: 503 });
  });

  it('HTTP errors for corrupt deadlines are generic and have no misleading ban or until', async () => {
    const f = setup(); f.set({ at: T0, report: 'PRIVATE_REPORT' });
    for (const [url, method] of [['/v1/p0/voice/status', 'GET'], ['/v1/p0/voice/join', 'POST'], ['/v1/p0/voice/heartbeat', 'POST']] as const) {
      const r = await f.request(url, method);
      expect([r.statusCode, r.json()]).toEqual([503, { ok: false, code: 'VOICE_UNAVAILABLE' }]);
    }
  });

  it('HTTP answer preserves only VOICE_BANNED.until and refuses a missing deadline instead of making it permanent', async () => {
    const f = setup();
    vi.spyOn(f.voice, 'join').mockResolvedValueOnce({ code: 'VOICE_BANNED', status: 403, until: null,
      report: 'PRIVATE_REPORT', at: T0, name_reset_at: T0, admin: 'PRIVATE_ADMIN' });
    expect((await f.request('/v1/p0/voice/join', 'POST')).json()).toEqual({ ok: false, code: 'VOICE_BANNED', until: null });
    vi.mocked(f.voice.join).mockResolvedValueOnce({ code: 'VOICE_BANNED', status: 403 });
    expect((await f.request('/v1/p0/voice/join', 'POST')).json()).toEqual({ ok: false, code: 'VOICE_UNAVAILABLE' });
    vi.mocked(f.voice.join).mockResolvedValueOnce({ code: 'AGE_GATE', status: 403, until: null, secret: 'PRIVATE' });
    expect((await f.request('/v1/p0/voice/join', 'POST')).json()).toEqual({ ok: false, code: 'AGE_GATE' });
  });

  it('reads the current deadline after delayed JWT signing', async () => {
    const f = setup(); f.voice.setAge(PLAYER, true); f.rooms.join(PLAYER, 'sh_tea_1');
    let resolve!: (v: string) => void;
    const signed = vi.spyOn(AccessToken.prototype, 'toJwt').mockReturnValue(new Promise<string>(done => { resolve = done; }));
    const pending = f.request('/v1/p0/voice/join', 'POST').then(r => r);
    await vi.waitFor(() => expect(signed).toHaveBeenCalled());
    f.set({ until: T0 + 1234, at: T0 }); resolve('fake-signed-token');
    expect((await pending).json()).toEqual({ ok: false, code: 'VOICE_BANNED', until: new Date(T0 + 1234).toISOString() });
  });

  it('auth runs first: suspended status stays suspended, unknown identity cannot read ban, and suspended account may delete', async () => {
    const f = setup(); f.set({ until: null, at: T0 });
    f.store.peek(PLAYER)!.sanctions!.suspended = { until: T0 + 5000, at: T0 };
    const expected = { ok: false, code: 'suspended', until: new Date(T0 + 5000).toISOString() };
    for (const [url, method] of [['/v1/p0/voice/status', 'GET'], ['/v1/p0/voice/join', 'POST'], ['/v1/p0/voice/heartbeat', 'POST']] as const)
      expect((await f.request(url, method)).json()).toEqual(expected);
    expect((await f.request('/v1/p0/voice/status', 'GET', '9'.repeat(64))).statusCode).toBe(401);
    expect((await f.request('/v1/p0/account', 'DELETE')).json()).toEqual({ ok: true });
    expect(f.accounts.isDeleted(PLAYER)).toBe(true);
  });

  it('same-account status responses can arrive out of order but never overwrite the newer server ban snapshot', async () => {
    const f = setup();
    let release!: () => void, captured!: () => void;
    const hold = new Promise<void>(resolve => { release = resolve; });
    const ready = new Promise<void>(resolve => { captured = resolve; });
    let delayFirst = true;
    f.app.addHook('onSend', async (req, _reply, payload) => {
      if (req.url === '/v1/p0/voice/status' && delayFirst) { delayFirst = false; captured(); await hold; }
      return payload;
    });
    const order: string[] = [];
    const old = f.request('/v1/p0/voice/status').then(r => { order.push('old'); return r; });
    await ready;
    f.set({ until: T0 + 10_000, at: T0 });
    const recent = await f.request('/v1/p0/voice/status'); order.push('new');
    expect(recent.json().ban).toEqual({ until: new Date(T0 + 10_000).toISOString() });
    release(); expect((await old).json().ban).toBeNull(); expect(order).toEqual(['new', 'old']);
    expect((await f.request('/v1/p0/voice/heartbeat', 'POST')).json()).toEqual({ ok: false, code: 'VOICE_BANNED', until: new Date(T0 + 10_000).toISOString() });
    expect((await f.request('/v1/p0/voice/status')).json().ban).toEqual(recent.json().ban);
    // This is a server regression and a real HTTP ordering fixture, not a fake client claiming to fix its cache.
    // The client consumer must ignore an older request/generation after the newer response/ban error (separate client PR).
  });
});
