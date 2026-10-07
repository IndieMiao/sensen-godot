/** SGODOT-232 D1: the demo key, request limit and save snapshots a deployed P0 server runs with. */
import Fastify from 'fastify';
import { mkdtempSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { guardOptionsFromEnv, registerP0Guard, snapshotState } from '../../src/p0/guard.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { P0Store } from '../../src/p0/store.js';

const c = loadP0Content();
const player = { 'x-p0-player': 'guard-test-player' };

async function server(env: NodeJS.ProcessEnv, dev = false) {
  const app = Fastify({ bodyLimit: 32 * 1024 });
  await registerP0Guard(app, guardOptionsFromEnv(env));
  registerP0Routes(app, { content: c, store: new P0Store(c), now: () => Date.UTC(2026, 9, 8, 2), dev });
  app.get('/v1/healthz', async () => ({ ok: true }));
  return app;
}

describe('P0 server guard (SGODOT-232 D1)', () => {
  it('asks every /v1/p0 request for a demo key when keys are set; the health check stays open', async () => {
    const app = await server({ P0_ACCESS_KEYS: 'alpha, beta' });
    try {
      expect((await app.inject({ method: 'GET', url: '/v1/p0/state', headers: player })).json()).toEqual({ ok: false, code: 'bad_key' });
      expect((await app.inject({ method: 'GET', url: '/v1/p0/state', headers: { ...player, 'x-p0-key': 'nope' } })).statusCode).toBe(401);
      expect((await app.inject({ method: 'GET', url: '/v1/p0/state', headers: { ...player, 'x-p0-key': 'beta' } })).json()).toMatchObject({ ok: true });
      expect((await app.inject({ method: 'POST', url: '/v1/p0/commands', headers: player, payload: { type: 'rest' } })).statusCode).toBe(401);
      expect((await app.inject({ method: 'GET', url: '/v1/healthz' })).statusCode).toBe(200);
    } finally { await app.close(); }
  });

  it('needs no key without P0_ACCESS_KEYS (local playtests), and dev routes exist only with dev on', async () => {
    const open = await server({});
    const prod = await server({ P0_ACCESS_KEYS: 'k' });
    try {
      expect((await open.inject({ method: 'GET', url: '/v1/p0/state', headers: player })).statusCode).toBe(200);
      expect((await prod.inject({ method: 'POST', url: '/v1/p0/dev/skip', headers: { ...player, 'x-p0-key': 'k' }, payload: { minutes: 60 } })).statusCode).toBe(404);
    } finally { await open.close(); await prod.close(); }
  });

  it('limits requests per player per minute and refuses large bodies', async () => {
    const app = await server({ P0_RATE_PER_MINUTE: '5' });
    try {
      const codes: number[] = [];
      for (let i = 0; i < 7; i++) codes.push((await app.inject({ method: 'GET', url: '/v1/p0/state', headers: player })).statusCode);
      expect(codes).toEqual([200, 200, 200, 200, 200, 429, 429]);
      // another player has their own budget
      expect((await app.inject({ method: 'GET', url: '/v1/p0/state', headers: { 'x-p0-player': 'guard-test-other' } })).statusCode).toBe(200);
      const big = await app.inject({ method: 'POST', url: '/v1/p0/commands', headers: { 'x-p0-player': 'guard-test-third' },
        payload: { type: 'rest', pad: 'x'.repeat(40 * 1024) } });
      expect(big.statusCode).toBe(413);
    } finally { await app.close(); }
  });

  it('snapshots the save once per hour and keeps the newest copies', () => {
    const dir = mkdtempSync(path.join(tmpdir(), 'p0-snap-'));
    try {
      const file = path.join(dir, 'p0-state.json');
      expect(snapshotState(file, path.join(dir, 'snaps'), 3)).toBeNull();
      writeFileSync(file, '{}');
      for (let h = 0; h < 5; h++) snapshotState(file, path.join(dir, 'snaps'), 3, Date.UTC(2026, 9, 8, h));
      expect(readdirSync(path.join(dir, 'snaps')).sort()).toEqual(['p0-state-2026100802.json', 'p0-state-2026100803.json', 'p0-state-2026100804.json']);
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });
});
