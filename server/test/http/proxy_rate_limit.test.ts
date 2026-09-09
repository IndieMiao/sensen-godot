import { afterEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import path from 'node:path';
import { buildApp, blueprintSets, loadBlueprint } from '../../src/http/app.js';
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
    blueprint: blueprintSets(loadBlueprint(blueprintDir, 'sh_a', 2)!), now });
  app = await buildApp({ store, content, contentVersion: version, blueprintDir,
    regionsFile: path.join(DEFAULT_CONTENT_DIR, 'regions.json'), pepper: 'test-only', now, trustedProxies });
}
function attempt(remoteAddress: string, forwarded: string) {
  return app!.inject({ method: 'POST', url: '/v1/auth/anonymous', remoteAddress,
    headers: { 'x-forwarded-for': forwarded }, payload: { install_key: 'invalid' } });
}

describe('login rate limits behind a reverse proxy', () => {
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
