/**
 * Mixpanel 上报模块（C-203）：开关、批量、失败重试一次后丢弃、队列上限。网络一律用桩，不连真实 Mixpanel。
 */
import { afterEach, describe, expect, it, vi } from 'vitest';
import pg from 'pg';
import { migrate, truncateAll } from '../../src/db/migrate.js';
import { PgStore } from '../../src/db/pg_store.js';
import { createInvites } from '../../src/accounts/invites.js';
import { DEFAULT_CONTENT_DIR, contentVersion, loadContent } from '../../src/domain/content.js';
import { plotFor } from '../../src/http/app.js';
import { MIXPANEL_HOSTS, MixpanelAnalytics, NO_ANALYTICS, createAnalytics, mixpanelConfigFromEnv } from '../../src/analytics/mixpanel.js';
import { SIGNUPS_SQL, backfillSignups, type SignupRow } from '../../src/analytics/backfill.js';

const DSN = process.env.TEST_DATABASE_URL;

type Call = { url: string; init: RequestInit; events: { event: string; properties: Record<string, unknown> }[] };
/** 按顺序回答的 fetch 桩：数字是 HTTP 状态，'throw' 是网络错误，'hang' 一直不回（直到超时取消）。 */
function stubFetch(...answers: (number | 'throw' | 'hang')[]) {
  const calls: Call[] = [];
  const fetch = vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: String(url), init: init!, events: JSON.parse(String(init!.body)) });
    const a = answers.length ? answers.shift()! : 200;
    if (a === 'throw') throw new Error('connect ECONNREFUSED');
    if (a === 'hang') return new Promise<Response>((_, reject) => init!.signal!.addEventListener('abort', () => reject(init!.signal!.reason)));
    return new Response(a === 200 ? '{"code":200,"status":"OK"}' : '{"error":"nope"}', { status: a });
  });
  return { fetch: fetch as unknown as typeof globalThis.fetch, calls, spy: fetch };
}

const made: MixpanelAnalytics[] = [];
const client = (over: Partial<ConstructorParameters<typeof MixpanelAnalytics>[0]> = {}) => {
  const logs: string[] = [];
  const a = new MixpanelAnalytics({ token: 's3cret', host: 'https://api-eu.mixpanel.com', retryDelayMs: 0, timeoutMs: 50, flushMs: 60_000,
    log: line => logs.push(line), now: () => 1_700_000_000_000, ...over });
  made.push(a);
  return { a, logs };
};
afterEach(async () => { for (const a of made.splice(0)) await a.close(); vi.restoreAllMocks(); });

describe('mixpanelConfigFromEnv', () => {
  it('is off when neither setting is present, so nothing is created and nothing is sent', async () => {
    const spy = vi.spyOn(globalThis, 'fetch');
    expect(mixpanelConfigFromEnv({})).toBeNull();
    expect(mixpanelConfigFromEnv({ MIXPANEL_PROJECT_TOKEN: '', MIXPANEL_API_HOST: ' ' })).toBeNull();
    const off = createAnalytics(mixpanelConfigFromEnv({}) as null);
    expect(off).toBe(NO_ANALYTICS);
    off.track('login', 'u-1', { method: 'email' });
    await off.close();
    expect(spy).not.toHaveBeenCalled();
  });

  it('needs both settings and one of the three Mixpanel region hosts', () => {
    expect(mixpanelConfigFromEnv({ MIXPANEL_PROJECT_TOKEN: 'x' })).toHaveProperty('invalid');
    expect(mixpanelConfigFromEnv({ MIXPANEL_API_HOST: 'https://api.mixpanel.com' })).toHaveProperty('invalid');
    expect(mixpanelConfigFromEnv({ MIXPANEL_PROJECT_TOKEN: 'x', MIXPANEL_API_HOST: 'https://evil.example.com' })).toHaveProperty('invalid');
    expect(mixpanelConfigFromEnv({ MIXPANEL_PROJECT_TOKEN: 'x', MIXPANEL_API_HOST: 'http://api.mixpanel.com' })).toHaveProperty('invalid');
    for (const host of MIXPANEL_HOSTS)
      expect(mixpanelConfigFromEnv({ MIXPANEL_PROJECT_TOKEN: ' x ', MIXPANEL_API_HOST: host + '/' })).toEqual({ token: 'x', host });
  });
});

describe('MixpanelAnalytics', () => {
  it('sends a full batch to /import with the project token, internal user id, time, insert id and no geolocation', async () => {
    const { fetch, calls } = stubFetch();
    const { a } = client({ fetch, batchSize: 2 });
    a.track('login', 'u-1', { method: 'email' });
    expect(calls).toHaveLength(0);
    a.track('parcel_enter', 'u-2', { welcome_gift: true }, { time: 5, insertId: 'fixed' });
    await a.flush();
    expect(calls).toHaveLength(1);
    expect(calls[0].url).toBe('https://api-eu.mixpanel.com/import?strict=1');
    expect(calls[0].init.method).toBe('POST');
    expect((calls[0].init.headers as Record<string, string>).authorization).toBe('Basic ' + Buffer.from('s3cret:').toString('base64'));
    expect(calls[0].events).toEqual([
      { event: 'login', properties: { method: 'email', time: 1_700_000_000_000, distinct_id: 'u-1', $insert_id: expect.any(String), ip: 0 } },
      { event: 'parcel_enter', properties: { welcome_gift: true, time: 5, distinct_id: 'u-2', $insert_id: 'fixed', ip: 0 } },
    ]);
  });

  it('sends what is queued on the timer and on close, in batches, and skips players without an account', async () => {
    const { fetch, calls } = stubFetch();
    const { a } = client({ fetch, batchSize: 2, flushMs: 20 });
    a.track('login', null);
    a.track('login', undefined);
    a.track('login', 'u-1');
    await vi.waitFor(() => expect(calls).toHaveLength(1), { timeout: 1000 });
    for (const id of ['u-2', 'u-3', 'u-4']) a.track('login', id);
    await a.close();
    expect(calls.map(c => c.events.map(e => e.properties.distinct_id))).toEqual([['u-1'], ['u-2', 'u-3'], ['u-4']]);
  });

  it.each([
    ['a server error', 503], ['rate limiting', 429], ['a network error', 'throw'], ['a timeout', 'hang'],
  ] as const)('retries once after %s, then drops the batch and only logs', async (_, answer) => {
    const { fetch, calls } = stubFetch(answer, answer);
    const { a, logs } = client({ fetch });
    a.track('login', 'u-1');
    await a.flush();
    expect(calls).toHaveLength(2);
    expect(logs.at(-1)).toBe('[analytics] dropped 1 events');
    a.track('login', 'u-2');
    await a.flush();
    expect(calls).toHaveLength(3);
    expect(calls[2].events[0].properties.distinct_id).toBe('u-2');
  });

  it('succeeds on the retry without dropping anything', async () => {
    const { fetch, calls } = stubFetch('throw', 200);
    const { a, logs } = client({ fetch });
    a.track('login', 'u-1');
    await a.flush();
    expect(calls).toHaveLength(2);
    expect(logs.some(l => l.includes('dropped'))).toBe(false);
  });

  it('does not retry a rejected batch (other 4xx)', async () => {
    const { fetch, calls } = stubFetch(400);
    const { a, logs } = client({ fetch });
    a.track('login', 'u-1');
    await a.flush();
    expect(calls).toHaveLength(1);
    expect(logs).toEqual(['[analytics] mixpanel import answered 400: {"error":"nope"}', '[analytics] dropped 1 events']);
  });

  it('drops new events once the queue is full and logs that once', async () => {
    const { fetch, calls } = stubFetch();
    const { a, logs } = client({ fetch, batchSize: 100, maxQueue: 3 });
    for (let i = 0; i < 6; i++) a.track('login', `u-${i}`);
    expect(logs).toEqual(['[analytics] queue full (3), dropping new events']);
    await a.flush();
    expect(calls[0].events.map(e => e.properties.distinct_id)).toEqual(['u-0', 'u-1', 'u-2']);
  });

  it('never throws into the caller, even when fetch itself throws synchronously', async () => {
    const { a, logs } = client({ fetch: (() => { throw new Error('boom'); }) as unknown as typeof fetch });
    expect(() => a.track('login', 'u-1')).not.toThrow();
    await expect(a.flush()).resolves.toBeUndefined();
    expect(logs.at(-1)).toBe('[analytics] dropped 1 events');
  });
});

describe('backfillSignups', () => {
  const rows: SignupRow[] = [
    { id: 'u-1', created_at: '1000', method: 'email' }, { id: 'u-2', created_at: '2000', method: 'invite' }, { id: 'u-3', created_at: '3000', method: 'google' },
  ];
  const db = { params: [] as unknown[], async query(_sql: string, params: unknown[]) { this.params = params; return { rows }; } };

  it('only counts without --send', async () => {
    const { fetch, calls } = stubFetch();
    const { a } = client({ fetch });
    expect(await backfillSignups(db, a, { since: 42, send: false })).toBe(3);
    expect(db.params).toEqual([42]);
    await a.flush();
    expect(calls).toHaveLength(0);
  });

  it('reports account_created at each account\'s creation time with the same insert id as live sign-ups', async () => {
    const { fetch, calls } = stubFetch();
    const { a } = client({ fetch, batchSize: 2 });
    expect(await backfillSignups(db, a, { since: 0, send: true, batch: 2 })).toBe(3);
    expect(calls.flatMap(c => c.events)).toEqual(rows.map(r => ({ event: 'account_created',
      properties: { method: r.method, backfill: true, time: Number(r.created_at), distinct_id: r.id, $insert_id: `account_created:${r.id}`, ip: 0 } })));
  });

  it.skipIf(!DSN)('reads every account since a day with how it signed up (PostgreSQL)', async () => {
    const pool = new pg.Pool({ connectionString: DSN, max: 2 });
    try {
      await migrate(pool);
      await truncateAll(pool);
      const content = loadContent(DEFAULT_CONTENT_DIR);
      const store = new PgStore({ pool, content, contentVersion: contentVersion(DEFAULT_CONTENT_DIR), timezone: () => 'UTC', plot: plotFor(content), now: () => 0 });
      const email = await store.createEmailUser('ada@example.com', 'hash', 1000);
      const google = await store.createIdentityUser('google', 'g-1', 'grace@gmail.com', 2000);
      const apple = await store.createIdentityUser('apple', 'a-1', null, 3000);
      await createInvites(pool, { count: 1, domain: 'invite.example.org', batch: 'b1' }, 4000);
      await createInvites(pool, { count: 1, domain: 'invite.example.org', batch: 'b2' }, 500);
      const ids = [email, google, apple].map(r => r.kind === 'created' ? r.user.id : '');
      const { rows } = await pool.query(SIGNUPS_SQL, [1000]);
      expect(rows.map(r => ({ ...r, created_at: Number(r.created_at) }))).toEqual([
        { id: ids[0], created_at: 1000, method: 'email' }, { id: ids[1], created_at: 2000, method: 'google' },
        { id: ids[2], created_at: 3000, method: 'apple' }, { id: expect.any(String), created_at: 4000, method: 'invite' },
      ]);
    } finally {
      await pool.end();
    }
  });
});
