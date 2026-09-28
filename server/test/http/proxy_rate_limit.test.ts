import { afterEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import path from 'node:path';
import { buildApp, plotFor, loadBlueprint } from '../../src/http/app.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { DEFAULT_CONTENT_DIR, contentVersion, loadContent } from '../../src/domain/content.js';

const content = loadContent(DEFAULT_CONTENT_DIR);
const blueprintDir = path.resolve(DEFAULT_CONTENT_DIR, '../../blueprints');
const now = () => Date.parse('2026-09-08T10:00:00Z');
let app: FastifyInstance | undefined;
afterEach(async () => { await app?.close(); app = undefined; });

async function start(trustedProxies?: string[]) {
  const version = contentVersion(DEFAULT_CONTENT_DIR);
  const store = new MemoryStore({ content, contentVersion: version, timezone: 'Asia/Shanghai',
    plot: plotFor(content), now });
  app = await buildApp({ guestWrites: true, store, content, contentVersion: version, blueprintDir,
    regionsFile: path.join(DEFAULT_CONTENT_DIR, 'regions.json'), pepper: 'test-only', now, trustedProxies });
}
function attempt(remoteAddress: string, forwarded: string) {
  return app!.inject({ method: 'POST', url: '/v1/auth/anonymous', remoteAddress,
    headers: { 'x-forwarded-for': forwarded }, payload: { install_key: 'invalid' } });
}

describe('login rate limits behind a reverse proxy', () => {
  it('allows 300 distinct installations on one NAT to authenticate and form a party, while bounding repeat logins', async () => {
    await start();
    const tokens: string[] = [];
    for (let i = 1; i <= 300; i++) {
      const result = await app!.inject({ method: 'POST', url: '/v1/auth/anonymous',
        payload: { install_key: i.toString(16).padStart(32, '0') } });
      expect(result.statusCode).toBe(200);
      tokens.push(result.json().token);
    }
    const created = await app!.inject({ method: 'POST', url: '/v1/online/party',
      headers: { authorization: 'Bearer ' + tokens[0] }, payload: { action: 'create' } });
    expect(created.statusCode).toBe(200);
    for (const token of tokens.slice(1)) {
      const joined = await app!.inject({ method: 'POST', url: '/v1/online/party',
        headers: { authorization: 'Bearer ' + token }, payload: { action: 'join', value: created.json().party.code } });
      expect(joined.statusCode).toBe(200);
    }
    for (let i = 0; i < 9; i++) expect((await app!.inject({ method: 'POST', url: '/v1/auth/anonymous',
      payload: { install_key: '1'.padStart(32, '0') } })).statusCode).toBe(200);
    expect((await app!.inject({ method: 'POST', url: '/v1/auth/anonymous',
      payload: { install_key: '1'.padStart(32, '0') } })).statusCode).toBe(429);
  });
  it('keeps separate client quotas through the trusted proxy and still limits repeat requests', async () => {
    await start(['172.20.0.0/16']);
    for (let i = 0; i < 10; i++) expect((await attempt('172.20.0.2', '198.51.100.1')).statusCode).toBe(400);
    expect((await attempt('172.20.0.2', '198.51.100.1')).statusCode).toBe(429);
    expect((await attempt('172.20.0.2', '198.51.100.2')).statusCode).toBe(400);
  });

  it.each([undefined, ['172.20.0.0/16']])('ignores forged forwarding headers from an untrusted peer: %j', async trusted => {
    await start(trusted);
    for (let i = 0; i < 10; i++) expect((await attempt('198.51.100.1', `203.0.113.${i + 1}`)).statusCode).toBe(400);
    expect((await attempt('198.51.100.1', '203.0.113.99')).statusCode).toBe(429);
  });

  it('stops at the first untrusted client in a forwarded chain', async () => {
    await start(['172.20.0.0/16']);
    for (let i = 0; i < 10; i++) expect((await attempt('172.20.0.2', `203.0.113.${i + 1}, 198.51.100.1`)).statusCode).toBe(400);
    expect((await attempt('172.20.0.2', '203.0.113.99, 198.51.100.1')).statusCode).toBe(429);
  });
});
