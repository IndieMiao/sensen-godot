/**
 * C-100：匿名建号每个网络每小时 10 次（C-95#2）。只有第一次登录（新建玩家）占额度，已有安装再次登录不占；
 * IPv4 按地址、IPv6 按 /64 算同一个网络；伪造的转发头不能换网络。
 */
import { afterEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import path from 'node:path';
import { ANONYMOUS_SIGNUPS_PER_NETWORK_HOUR, buildApp, plotFor } from '../../src/http/app.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { networkKey } from '../../src/http/network.js';
import { DEFAULT_CONTENT_DIR, contentVersion, loadContent } from '../../src/domain/content.js';

const content = loadContent(DEFAULT_CONTENT_DIR);
const CV = contentVersion(DEFAULT_CONTENT_DIR);
let clock = Date.UTC(2026, 10, 25, 4);
let app: FastifyInstance | undefined;
let store: MemoryStore;
afterEach(async () => { await app?.close(); app = undefined; });

async function start(trustedProxies?: string[]) {
  store = new MemoryStore({ content, contentVersion: CV, timezone: 'America/Los_Angeles', plot: plotFor(content), now: () => clock });
  app = await buildApp({ store, content, contentVersion: CV, blueprintDir: path.resolve(DEFAULT_CONTENT_DIR, '../../blueprints'),
    regionsFile: path.join(DEFAULT_CONTENT_DIR, 'regions.json'), pepper: 'test-only', now: () => clock, realtimeEnabled: false, trustedProxies });
}
let next = 0;
const freshKey = () => (++next).toString(16).padStart(32, 'a');
const signIn = (key: string, remoteAddress = '198.51.100.7', headers: Record<string, string> = {}) =>
  app!.inject({ method: 'POST', url: '/v1/auth/anonymous', remoteAddress, headers, payload: { install_key: key } });

describe('anonymous sign-ups per network', () => {
  it('creates at most 10 new players per network per hour; returning installations are not counted', async () => {
    await start();
    expect(ANONYMOUS_SIGNUPS_PER_NETWORK_HOUR).toBe(10);
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
