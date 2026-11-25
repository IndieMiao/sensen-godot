/**
 * C-100：匿名建号每个网络每小时 10 次（C-95#2）。只有第一次登录（新建玩家）占额度，已有安装再次登录不占；
 * IPv4 按地址、IPv6 按 /64 算同一个网络；伪造的转发头不能换网络。
 * C-120：再加两层，IPv6 每个 /48 每小时 50 个、整个进程每小时 1000 个；三层都可用环境变量调。
 */
import { afterEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import path from 'node:path';
import { buildApp, plotFor } from '../../src/http/app.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { blockKey, networkKey } from '../../src/http/network.js';
import { DEFAULT_ANONYMOUS_SIGNUP_LIMITS, anonymousSignupLimitsFromEnv, type AnonymousSignupLimits } from '../../src/http/signup_limits.js';
import { DEFAULT_CONTENT_DIR, contentVersion, loadContent } from '../../src/domain/content.js';

const content = loadContent(DEFAULT_CONTENT_DIR);
const CV = contentVersion(DEFAULT_CONTENT_DIR);
let clock = Date.UTC(2026, 10, 25, 4);
let app: FastifyInstance | undefined;
let store: MemoryStore;
afterEach(async () => { await app?.close(); app = undefined; });

async function start(trustedProxies?: string[], anonymousSignupLimits?: Partial<AnonymousSignupLimits>) {
  store = new MemoryStore({ content, contentVersion: CV, timezone: 'America/Los_Angeles', plot: plotFor(content), now: () => clock });
  app = await buildApp({ store, content, contentVersion: CV, blueprintDir: path.resolve(DEFAULT_CONTENT_DIR, '../../blueprints'),
    regionsFile: path.join(DEFAULT_CONTENT_DIR, 'regions.json'), pepper: 'test-only', now: () => clock, realtimeEnabled: false, trustedProxies,
    anonymousSignupLimits });
}
let next = 0;
const freshKey = () => (++next).toString(16).padStart(32, 'a');
const signIn = (key: string, remoteAddress = '198.51.100.7', headers: Record<string, string> = {}) =>
  app!.inject({ method: 'POST', url: '/v1/auth/anonymous', remoteAddress, headers, payload: { install_key: key } });

describe('anonymous sign-ups per network', () => {
  it('creates at most 10 new players per network per hour; returning installations are not counted', async () => {
    await start();
    expect(DEFAULT_ANONYMOUS_SIGNUP_LIMITS).toEqual({ perNetwork: 10, perBlock: 50, total: 1000 });
    const keys = Array.from({ length: 10 }, freshKey);
    const players = new Set<string>();
    for (const key of keys) {
      const res = await signIn(key);
      expect(res.statusCode).toBe(200);
      players.add(res.json().player_id);
    }
    expect(players.size).toBe(10);
    const refused = await signIn(freshKey());
    expect(refused.statusCode).toBe(429);
    expect(refused.json().code).toBe('RATE_LIMITED');
    expect(Number(refused.headers['retry-after'])).toBeGreaterThan(0);
    // The refused installation was not created; an existing one still signs in, as the same player.
    const back = await signIn(keys[0]);
    expect(back.statusCode).toBe(200);
    expect(players.has(back.json().player_id)).toBe(true);
    // Another network has its own quota.
    expect((await signIn(freshKey(), '203.0.113.9')).statusCode).toBe(200);
  });

  it('concurrent first sign-ins from one network never create more than the limit', async () => {
    await start();
    const results = await Promise.all(Array.from({ length: 25 }, () => signIn(freshKey())));
    expect(results.filter(r => r.statusCode === 200)).toHaveLength(10);
    expect(results.filter(r => r.statusCode === 429)).toHaveLength(15);
  });

  it('treats every address in one IPv6 /64 as one network, and an IPv4-mapped address as its IPv4 address', async () => {
    await start();
    for (let i = 0; i < 10; i++) expect((await signIn(freshKey(), `2001:db8:1:2::${(i + 1).toString(16)}`)).statusCode).toBe(200);
    expect((await signIn(freshKey(), '2001:db8:1:2:ffff:ffff:ffff:ffff')).statusCode).toBe(429);
    expect((await signIn(freshKey(), '2001:db8:1:3::1')).statusCode).toBe(200);
    for (let i = 0; i < 10; i++) expect((await signIn(freshKey(), '192.0.2.44')).statusCode).toBe(200);
    expect((await signIn(freshKey(), '::ffff:192.0.2.44')).statusCode).toBe(429);
  });

  it('a forwarding header from an untrusted peer does not change the network', async () => {
    await start(['172.20.0.0/16']);
    for (let i = 0; i < 10; i++)
      expect((await signIn(freshKey(), '198.51.100.1', { 'x-forwarded-for': `203.0.113.${i + 1}` })).statusCode).toBe(200);
    expect((await signIn(freshKey(), '198.51.100.1', { 'x-forwarded-for': '203.0.113.99' })).statusCode).toBe(429);
    // Through the trusted proxy each client network has its own quota.
    expect((await signIn(freshKey(), '172.20.0.2', { 'x-forwarded-for': '203.0.113.99' })).statusCode).toBe(200);
  });

  it('a new hour gives a new quota', async () => {
    await start();
    for (let i = 0; i < 10; i++) expect((await signIn(freshKey())).statusCode).toBe(200);
    expect((await signIn(freshKey())).statusCode).toBe(429);
    // @fastify/rate-limit windows run on the real clock, not the app's injected one.
    const { vi } = await import('vitest');
    vi.useFakeTimers({ now: Date.now(), toFake: ['Date'] });
    try {
      vi.setSystemTime(Date.now() + 3600_000 + 1000);
      expect((await signIn(freshKey())).statusCode).toBe(200);
    } finally { vi.useRealTimers(); }
  });
});

describe('wider quotas: IPv6 /48 and the whole server (C-120)', () => {
  const ok = (rs: { statusCode: number }[]) => rs.filter(r => r.statusCode === 200).length;

  it('switching /64s inside one /48 (or a /56) does not add quota: 50 new players per /48 per hour', async () => {
    await start();
    const results = [];
    // A /56 holder has 256 /64s; ten of them would give 100 new players with only the /64 quota.
    for (let net = 0; net < 10; net++)
      for (let i = 0; i < 10; i++) results.push(await signIn(freshKey(), `2001:db8:7:${(0x100 + net).toString(16)}::${(i + 1).toString(16)}`));
    expect(ok(results)).toBe(50);
    expect(results.slice(50).every(r => r.statusCode === 429 && r.json().code === 'RATE_LIMITED')).toBe(true);
    expect((await signIn(freshKey(), '2001:db8:7:ffff::1')).statusCode).toBe(429); // any other /64 of the /48
    expect((await signIn(freshKey(), '2001:db8:8:100::1')).statusCode).toBe(200); // the next /48 has its own quota
    expect((await signIn(freshKey(), '198.51.100.7')).statusCode).toBe(200);
  });

  it('caps new players per hour in total, however scattered the sources are', async () => {
    await start(undefined, { total: 25 });
    const first = freshKey();
    const results = [await signIn(first, '2001:db8:100::1')];
    for (let i = 1; i < 30; i++) results.push(await signIn(freshKey(), `2001:db8:${(0x100 + i).toString(16)}::1`));
    for (let i = 0; i < 5; i++) results.push(await signIn(freshKey(), `203.0.113.${i + 1}`));
    expect(ok(results)).toBe(25);
    expect(results.slice(25).every(r => r.statusCode === 429)).toBe(true);
    // Returning installations are never counted.
    expect((await signIn(first, '2001:db8:100::1')).statusCode).toBe(200);
  });

  it('concurrent first sign-ins never exceed the /48 or the total quota', async () => {
    await start(undefined, { perBlock: 30 });
    const block = await Promise.all(Array.from({ length: 60 }, (_, i) => signIn(freshKey(), `2001:db8:9:${i % 6}::${i + 1}`)));
    expect(ok(block)).toBe(30);
    await app!.close();
    await start(undefined, { total: 20 });
    const total = await Promise.all(Array.from({ length: 60 }, (_, i) => signIn(freshKey(), `2001:db8:${(0x200 + i).toString(16)}::1`)));
    expect(ok(total)).toBe(20);
  });

  it('a network over its own quota uses none of the wider ones', async () => {
    await start(undefined, { total: 15 });
    const noisy = [];
    for (let i = 0; i < 30; i++) noisy.push(await signIn(freshKey(), '198.51.100.9'));
    expect(ok(noisy)).toBe(10);
    for (let i = 0; i < 5; i++) expect((await signIn(freshKey(), `203.0.113.${i + 1}`)).statusCode).toBe(200);
    expect((await signIn(freshKey(), '203.0.113.99')).statusCode).toBe(429);
  });

  it('forwarding headers from an untrusted peer cannot spread sign-ups over other /48s', async () => {
    await start(['172.20.0.0/16']);
    const results = [];
    for (let i = 0; i < 60; i++)
      results.push(await signIn(freshKey(), `2001:db8:5:${i % 6}::1`, { 'x-forwarded-for': `2001:db8:${(0x300 + i).toString(16)}::1` }));
    expect(ok(results)).toBe(50);
  });

  it('environment: each quota defaults, takes a whole number 1–1000000, and anything else refuses to start', () => {
    expect(anonymousSignupLimitsFromEnv({})).toEqual(DEFAULT_ANONYMOUS_SIGNUP_LIMITS);
    expect(anonymousSignupLimitsFromEnv({ ANONYMOUS_SIGNUPS_PER_NETWORK_HOUR: '', ANONYMOUS_SIGNUPS_PER_BLOCK_HOUR: '', ANONYMOUS_SIGNUPS_PER_HOUR: '' }))
      .toEqual(DEFAULT_ANONYMOUS_SIGNUP_LIMITS);
    expect(anonymousSignupLimitsFromEnv({ ANONYMOUS_SIGNUPS_PER_NETWORK_HOUR: '20', ANONYMOUS_SIGNUPS_PER_BLOCK_HOUR: '200', ANONYMOUS_SIGNUPS_PER_HOUR: '1000000' }))
      .toEqual({ perNetwork: 20, perBlock: 200, total: 1_000_000 });
    for (const bad of ['0', '-1', '1.5', 'ten', ' 10', '1000001', '00000000'])
      for (const name of ['ANONYMOUS_SIGNUPS_PER_NETWORK_HOUR', 'ANONYMOUS_SIGNUPS_PER_BLOCK_HOUR', 'ANONYMOUS_SIGNUPS_PER_HOUR'])
        expect(anonymousSignupLimitsFromEnv({ [name]: bad })).toEqual({ invalid: name });
  });
});

describe('networkKey', () => {
  it.each([
    ['198.51.100.7', '198.51.100.7'],
    ['::ffff:198.51.100.7', '198.51.100.7'],
    ['::FFFF:c633:6407', '198.51.100.7'],
    ['2001:db8:1:2::1', '2001:db8:1:2::/64'],
    ['2001:0DB8:0001:0002:aaaa:bbbb:cccc:dddd', '2001:db8:1:2::/64'],
    ['2001:db8::1', '2001:db8:0:0::/64'],
    ['::1', '0:0:0:0::/64'],
    ['fe80::1%eth0', 'fe80:0:0:0::/64'],
    ['2001:db8:1:2:3:4:192.0.2.1', '2001:db8:1:2::/64'],
    ['not-an-ip', 'other:not-an-ip'],
  ])('%s → %s', (ip, key) => { expect(networkKey(ip)).toBe(key); });
});

describe('blockKey', () => {
  it.each([
    ['198.51.100.7', '198.51.100.7'],
    ['::ffff:198.51.100.7', '198.51.100.7'],
    ['2001:db8:1:2::1', '2001:db8:1::/48'],
    ['2001:db8:1:ff00:aaaa::1', '2001:db8:1::/48'],
    ['2001:0DB8:0001:0002:aaaa:bbbb:cccc:dddd', '2001:db8:1::/48'],
    ['2001:db8::1', '2001:db8:0::/48'],
    ['not-an-ip', 'other:not-an-ip'],
  ])('%s → %s', (ip, key) => { expect(blockKey(ip)).toBe(key); });
});
