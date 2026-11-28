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
import { spawn } from 'node:child_process';
import { createServer, type Server } from 'node:http';
import { fileURLToPath } from 'node:url';
import { MIXPANEL_HOSTS, MixpanelAnalytics, NO_ANALYTICS, SHUTDOWN_MS, createAnalytics, mixpanelConfigFromEnv } from '../../src/analytics/mixpanel.js';
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

  it('takes the optional GDPR token for deletions only together with the two settings (C-205)', () => {
    const on = { MIXPANEL_PROJECT_TOKEN: 'x', MIXPANEL_API_HOST: 'https://api.mixpanel.com' };
    expect(mixpanelConfigFromEnv({ ...on, MIXPANEL_GDPR_TOKEN: ' g ' })).toEqual({ token: 'x', host: 'https://api.mixpanel.com', gdprToken: 'g' });
    expect(mixpanelConfigFromEnv({ ...on, MIXPANEL_GDPR_TOKEN: ' ' })).toEqual({ token: 'x', host: 'https://api.mixpanel.com' });
    expect(mixpanelConfigFromEnv({ MIXPANEL_GDPR_TOKEN: 'g' })).toHaveProperty('invalid');
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

/** 删除接口的 fetch 桩：按顺序回答；记下 URL、认证和请求体。'hang' 一直不回，直到被取消。 */
function stubDeletionFetch(...answers: (number | 'throw' | 'hang')[]) {
  const calls: { url: string; auth: string; body: unknown }[] = [];
  const fetch = vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: String(url), auth: (init!.headers as Record<string, string>).authorization, body: JSON.parse(String(init!.body)) });
    const a = answers.length ? answers.shift()! : 200;
    if (a === 'throw') throw new Error('connect ECONNREFUSED');
    if (a === 'hang') return new Promise<Response>((_, reject) => init!.signal!.addEventListener('abort', () => reject(init!.signal!.reason)));
    const body = String(url).includes('/data-deletions/')
      ? '{"status":"ok","results":[{"status":"PENDING","tracking_id":"1583792934719392965","distinct_id_count":1}]}' : '{}';
    return new Response(a === 200 ? body : '{"error":"nope"}', { status: a });
  });
  return { fetch: fetch as unknown as typeof globalThis.fetch, calls };
}

describe('deleting a user (C-205)', () => {
  it.each([
    ['https://api.mixpanel.com', 'https://mixpanel.com'], ['https://api-eu.mixpanel.com', 'https://eu.mixpanel.com'], ['https://api-in.mixpanel.com', 'https://in.mixpanel.com'],
  ])('asks the GDPR API of the same region (%s) to delete the user, after dropping their unsent events', async (host, gdprHost) => {
    const { fetch, calls } = stubDeletionFetch();
    const { a, logs } = client({ fetch, host, gdprToken: 'oauth-1', batchSize: 10 });
    a.track('login', 'u-1');
    a.track('login', 'u-2');
    a.track('parcel_enter', 'u-1');
    a.deleteUser('u-1');
    await a.close();
    const deletion = calls.find(c => c.url.includes('/data-deletions/'))!;
    expect(deletion).toEqual({ url: `${gdprHost}/api/app/data-deletions/v3.0/?token=s3cret`, auth: 'Bearer oauth-1',
      body: { distinct_ids: ['u-1'], compliance_type: 'GDPR' } });
    // u-1's queued events never leave; u-2's still do.
    const imported = calls.filter(c => c.url.endsWith('/import?strict=1')).flatMap(c => c.body as { properties: { distinct_id: string } }[]);
    expect(imported.map(e => e.properties.distinct_id)).toEqual(['u-2']);
    expect(logs).toEqual(['[analytics] Mixpanel deletion requested for user u-1, task 1583792934719392965']);
  });

  it('waits for a batch already on its way before asking for the deletion', async () => {
    const order: string[] = [];
    let answer!: () => void;
    const fetch = vi.fn(async (url: string | URL | Request) => {
      order.push(String(url).includes('/data-deletions/') ? 'delete' : 'import');
      if (order.length === 1) await new Promise<void>(resolve => { answer = resolve; });
      return new Response('{}', { status: 200 });
    }) as unknown as typeof globalThis.fetch;
    const { a } = client({ fetch, gdprToken: 'oauth-1', batchSize: 1, timeoutMs: 60_000 });
    a.track('login', 'u-1');
    a.deleteUser('u-1');
    await new Promise(resolve => setImmediate(resolve));
    expect(order).toEqual(['import']);
    answer();
    await a.close();
    expect(order).toEqual(['import', 'delete']);
  });

  it('skips the deletion with a log line when no GDPR token is configured, and sends nothing for that user', async () => {
    const { fetch, calls } = stubDeletionFetch();
    const { a, logs } = client({ fetch });
    a.track('login', 'u-1');
    a.deleteUser('u-1');
    await a.close();
    expect(calls).toHaveLength(0);
    expect(logs).toEqual(['[analytics] MIXPANEL_GDPR_TOKEN not set, Mixpanel data of deleted user u-1 was not deleted; delete it in Mixpanel by hand']);
  });

  it.each([
    ['a server error', [503, 503], 2], ['rate limiting', [429, 429], 2], ['a network error', ['throw', 'throw'], 2], ['a rejected token', [401], 1],
  ] as const)('only logs after %s, never throwing into account deletion', async (_, answers, tries) => {
    const { fetch, calls } = stubDeletionFetch(...answers);
    const { a, logs } = client({ fetch, gdprToken: 'oauth-1' });
    expect(() => a.deleteUser('u-1')).not.toThrow();
    await a.close();
    expect(calls).toHaveLength(tries);
    expect(logs.at(-1)).toBe('[analytics] Mixpanel deletion for user u-1 not requested; delete it in Mixpanel by hand');
  });

  it('keeps deletions one at a time (the GDPR API allows one request a second)', async () => {
    let inFlight = 0, most = 0;
    const fetch = vi.fn(async () => {
      most = Math.max(most, ++inFlight);
      await new Promise(resolve => setTimeout(resolve, 5));
      inFlight--;
      return new Response('{}', { status: 200 });
    }) as unknown as typeof globalThis.fetch;
    const { a } = client({ fetch, gdprToken: 'oauth-1' });
    for (const id of ['u-1', 'u-2', 'u-3']) a.deleteUser(id);
    await a.close();
    expect(fetch).toHaveBeenCalledTimes(3);
    expect(most).toBe(1);
  });

  it('does nothing when Mixpanel is off', () => {
    expect(() => NO_ANALYTICS.deleteUser('u-1')).not.toThrow();
  });
});

describe('shutting down (C-205)', () => {
  it('waits at most 5 seconds by default, inside docker stop\'s 10 second grace period', () => {
    expect(SHUTDOWN_MS).toBe(5_000);
  });

  it('sends everything when Mixpanel answers in time', async () => {
    const { fetch, calls } = stubFetch();
    const { a, logs } = client({ fetch, batchSize: 2, shutdownMs: 1_000 });
    for (const id of ['u-1', 'u-2', 'u-3']) a.track('login', id);
    await a.close();
    expect(calls.flatMap(c => c.events.map(e => e.properties.distinct_id))).toEqual(['u-1', 'u-2', 'u-3']);
    expect(logs).toEqual([]);
  });

  it('gives up at the limit when Mixpanel never answers, cancels the request and drops the rest', async () => {
    const { fetch, calls, spy } = stubFetch('hang', 'hang');
    const { a, logs } = client({ fetch, batchSize: 2, timeoutMs: 60_000, retryDelayMs: 60_000, shutdownMs: 100, gdprToken: 'oauth-1' });
    for (const id of ['u-1', 'u-2', 'u-3']) a.track('login', id);
    a.deleteUser('u-4');
    const started = Date.now();
    await a.close();
    expect(Date.now() - started).toBeLessThan(1_000);
    expect(logs).toContain('[analytics] shutdown limit 100ms reached, dropped 1 queued events and 1 pending deletions');
    // The outstanding request is cancelled, and nothing is retried or sent afterwards.
    const signal = spy.mock.calls[0][1]!.signal!;
    expect(signal.aborted).toBe(true);
    await new Promise(resolve => setTimeout(resolve, 20));
    expect(calls).toHaveLength(1);
    a.track('login', 'u-5');
    await a.flush();
    expect(calls).toHaveLength(1);
  });

  it('gives up at the limit even when the request ignores cancellation', async () => {
    const fetch = vi.fn(() => new Promise<Response>(() => {})) as unknown as typeof globalThis.fetch;
    const { a, logs } = client({ fetch, timeoutMs: 60_000, shutdownMs: 50 });
    a.track('login', 'u-1');
    const started = Date.now();
    await a.close();
    expect(Date.now() - started).toBeLessThan(1_000);
    expect(logs.some(l => l.startsWith('[analytics] shutdown limit 50ms reached'))).toBe(true);
  });

  describe('a real process against a Mixpanel that accepts the connection and never answers', () => {
    let server: Server;
    afterEach(() => new Promise<void>(resolve => { server?.closeAllConnections(); server?.close(() => resolve()); }));

    it('exits within the shutdown limit', async () => {
      let requests = 0;
      server = createServer(() => { requests++; /* never answers */ });
      await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve));
      const { port } = server.address() as { port: number };
      const module = fileURLToPath(new URL('../../src/analytics/mixpanel.ts', import.meta.url));
      // host is checked only by mixpanelConfigFromEnv; the class takes any address, here the silent local server.
      const script = `const { MixpanelAnalytics } = await import(${JSON.stringify(module)});
        const a = new MixpanelAnalytics({ token: 't', host: 'http://127.0.0.1:${port}', shutdownMs: 300, timeoutMs: 60000, retryDelayMs: 60000 });
        a.track('login', 'u-1'); a.track('login', 'u-2');
        await a.close(); console.log('closed');`;
      const started = Date.now();
      const child = spawn(process.execPath, ['--import', 'tsx', '--input-type=module', '-e', script],
        { cwd: fileURLToPath(new URL('../..', import.meta.url)), stdio: ['ignore', 'pipe', 'pipe'] });
      let out = '', err = '';
      child.stdout.on('data', d => { out += d; });
      child.stderr.on('data', d => { err += d; });
      const code = await new Promise<number | null>(resolve => child.on('exit', resolve));
      const took = Date.now() - started;
      expect({ code, out: out.trim(), requests }).toEqual({ code: 0, out: 'closed', requests: 1 });
      expect(err).toContain('[analytics] shutdown limit 300ms reached');
      // Startup of tsx included; far below the 10 s grace period and the 60 s request timeout.
      expect(took).toBeLessThan(5_000);
    }, 15_000);
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
