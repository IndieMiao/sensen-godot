/** SYS-UPDATE / SYS-MAINT on the server (SGODOT-232; contract with 刘邦's two full-screen cards, §10.7.1). */
import Fastify from 'fastify';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import WebSocket from 'ws';
import { registerP0Admin } from '../../src/p0/admin.js';
import { loadP0Content } from '../../src/p0/content.js';
import { P0Gate, isoMinute } from '../../src/p0/gate.js';
import { guardOptionsFromEnv, registerP0Guard } from '../../src/p0/guard.js';
import { registerP0Online } from '../../src/p0/online/hub.js';
import { loadOutposts } from '../../src/p0/online/outposts.js';
import { OutpostRooms } from '../../src/p0/online/rooms.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { P0Store } from '../../src/p0/store.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 9, 2);
const KEY = 'gate-demo-key';
const ADMIN = 'gate-admin-key';
const H = { 'x-p0-player': 'gate-player-01', 'x-p0-key': KEY };
const dirs: string[] = [];
const closers: (() => Promise<unknown>)[] = [];
afterEach(async () => {
  for (const close of closers.splice(0)) await close();
  for (const d of dirs.splice(0)) rmSync(d, { recursive: true, force: true });
});
const tmp = () => { const d = mkdtempSync(path.join(tmpdir(), 'p0-gate-')); dirs.push(d); return d; };

async function server(gate: P0Gate) {
  const app = Fastify({ bodyLimit: 32 * 1024 });
  await registerP0Guard(app, guardOptionsFromEnv({ P0_ACCESS_KEYS: KEY }), gate);
  registerP0Routes(app, { content: c, store: new P0Store(c), now: () => T0, dev: false });
  registerP0Online(app, { rooms: new OutpostRooms(loadOutposts()), keys: [KEY], gate });
  app.get('/v1/healthz', async () => ({ ok: true, ...gate.state() }));
  closers.push(() => app.close());
  return app;
}

describe('the gate rules', () => {
  it('lets everything through by default', () => {
    const g = new P0Gate(undefined, {});
    expect(g.state()).toEqual({ maintenance: { on: false }, min_version: 0, update_url: '' });
    expect(g.check({ 'x-p0-version': '1' })).toBeNull();
  });

  it('426 below the minimum; no header always passes; an unreadable version counts as too old', () => {
    const g = new P0Gate(undefined, { P0_MIN_VERSION: '2026100901', P0_UPDATE_URL: 'https://example.test/p0.apk' });
    expect(g.check({ 'x-p0-version': '2026100900' })).toEqual({ status: 426, body: { ok: false, code: 'update_required', url: 'https://example.test/p0.apk' } });
    expect(g.check({ 'x-p0-version': '2026100901' })).toBeNull();
    expect(g.check({ 'x-p0-version': '2026100902' })).toBeNull();
    expect(g.check({})).toBeNull();
    expect(g.check({ 'x-p0-version': '' })).toBeNull();
    expect(g.check({ 'x-p0-version': 'p0-0.1.1' })?.status).toBe(426);
  });

  it('503 while in maintenance, back_at in UTC ISO to the second, absent when unknown', () => {
    expect(new P0Gate(undefined, { P0_MAINT: '1' }).check({})).toEqual({ status: 503, body: { ok: false, code: 'maintenance' } });
    const g = new P0Gate(undefined, { P0_MAINT: '1', P0_MAINT_UNTIL: '2026-10-09T14:30:00+08:00' });
    expect(g.check({})).toEqual({ status: 503, body: { ok: false, code: 'maintenance', back_at: '2026-10-09T06:30:00Z' } });
    expect(isoMinute('not a time')).toBeUndefined();
  });

  it('Update wins over Maintenance (§10.7.1): an old client sees Update once', () => {
    const g = new P0Gate(undefined, { P0_MAINT: '1', P0_MIN_VERSION: '5' });
    expect(g.check({ 'x-p0-version': '4' })?.status).toBe(426);
    expect(g.check({ 'x-p0-version': '5' })?.status).toBe(503);
    expect(g.check({})?.status).toBe(503);
  });

  it('run-time changes persist and survive a restart; the environment can only make it stricter', () => {
    const file = path.join(tmp(), 'gate.json');
    const g = new P0Gate(file, { P0_MIN_VERSION: '3' });
    g.setMaintenance(true, '2026-10-09T06:30:00Z');
    g.setMinVersion(7, 'https://example.test/new.apk');
    expect(JSON.parse(readFileSync(file, 'utf8'))).toMatchObject({ maintenance: { on: true, back_at: '2026-10-09T06:30:00Z' }, min_version: 7 });
    const again = new P0Gate(file, { P0_MIN_VERSION: '3' });
    expect(again.state()).toEqual({ maintenance: { on: true, back_at: '2026-10-09T06:30:00Z' }, min_version: 7, update_url: 'https://example.test/new.apk' });
    again.setMinVersion(1);
    expect(again.state().min_version).toBe(3);                                // the environment's floor stays
    again.setMaintenance(false);
    expect(new P0Gate(file, { P0_MAINT: '1' }).state().maintenance.on).toBe(true);   // P0_MAINT=1 keeps it on
    expect(new P0Gate(file, {}).state().maintenance).toEqual({ on: false });
  });
});

describe('the gated server', () => {
  it('answers every /v1/p0 route with 503 in maintenance; the health check stays open; the key is checked first', async () => {
    const gate = new P0Gate(undefined, {});
    const app = await server(gate);
    expect((await app.inject({ method: 'GET', url: '/v1/p0/state', headers: H })).statusCode).toBe(200);
    gate.setMaintenance(true, '2026-10-09T06:30:00Z');
    for (const [method, url] of [['GET', '/v1/p0/state'], ['GET', '/v1/p0/presence'], ['POST', '/v1/p0/commands'], ['POST', '/v1/p0/telemetry']] as const) {
      const r = await app.inject({ method, url, headers: H, ...(method === 'POST' ? { payload: { type: 'rest' } } : {}) });
      expect(r.statusCode).toBe(503);
      expect(r.json()).toEqual({ ok: false, code: 'maintenance', back_at: '2026-10-09T06:30:00Z' });
    }
    expect((await app.inject({ method: 'GET', url: '/v1/p0/state', headers: { 'x-p0-player': 'gate-player-01' } })).statusCode).toBe(401);
    const health = await app.inject({ method: 'GET', url: '/v1/healthz' });
    expect(health.statusCode).toBe(200);
    expect(health.json().maintenance).toEqual({ on: true, back_at: '2026-10-09T06:30:00Z' });
    gate.setMaintenance(false);
    expect((await app.inject({ method: 'GET', url: '/v1/p0/state', headers: H })).statusCode).toBe(200);
  });

  it('answers an old client with 426 and its download url; a current one or one without the header plays', async () => {
    const app = await server(new P0Gate(undefined, { P0_MIN_VERSION: '2026100901', P0_UPDATE_URL: 'https://example.test/p0.apk' }));
    const old = await app.inject({ method: 'GET', url: '/v1/p0/state', headers: { ...H, 'x-p0-version': '2' } });
    expect(old.statusCode).toBe(426);
    expect(old.json()).toEqual({ ok: false, code: 'update_required', url: 'https://example.test/p0.apk' });
    expect((await app.inject({ method: 'GET', url: '/v1/p0/state', headers: { ...H, 'x-p0-version': '2026100901' } })).statusCode).toBe(200);
    expect((await app.inject({ method: 'GET', url: '/v1/p0/state', headers: H })).statusCode).toBe(200);
  });

  it('refuses the outpost WebSocket upgrade with the same 503 / 426 and JSON body', async () => {
    const gate = new P0Gate(undefined, {});
    const app = await server(gate);
    await app.listen({ port: 0, host: '127.0.0.1' });
    const port = (app.server.address() as { port: number }).port;
    const attempt = (headers: Record<string, string>) => new Promise<{ status: number; body: string } | 'open'>(resolve => {
      const ws = new WebSocket(`ws://127.0.0.1:${port}/v1/p0/online`, { headers });
      ws.once('open', () => { ws.close(); resolve('open'); });
      ws.once('unexpected-response', (_req, res) => {
        let body = '';
        res.on('data', d => body += d);
        res.on('end', () => resolve({ status: res.statusCode ?? 0, body }));
      });
      ws.once('error', () => undefined);
    });
    gate.setMaintenance(true);
    expect(await attempt({ 'x-p0-player': 'gate-ws-player', 'x-p0-key': KEY })).toEqual({ status: 503, body: JSON.stringify({ ok: false, code: 'maintenance' }) });
    gate.setMaintenance(false);
    gate.setMinVersion(9, 'https://example.test/p0.apk');
    expect(await attempt({ 'x-p0-player': 'gate-ws-player', 'x-p0-key': KEY, 'x-p0-version': '8' }))
      .toEqual({ status: 426, body: JSON.stringify({ ok: false, code: 'update_required', url: 'https://example.test/p0.apk' }) });
    expect(await attempt({ 'x-p0-player': 'gate-ws-player', 'x-p0-key': KEY, 'x-p0-version': '9' })).toBe('open');
  });
});

describe('the admin routes', () => {
  async function adminApp(gate: P0Gate, lines: string[]) {
    const admin = Fastify({ bodyLimit: 4 * 1024 });
    registerP0Admin(admin, { content: c, store: new P0Store(c), now: () => T0, key: ADMIN, gate, log: l => lines.push(l) });
    closers.push(() => admin.close());
    return admin;
  }
  const A = { 'x-p0-admin': ADMIN };

  it('turn maintenance on and off, set the minimum, and log each change; the admin key is required', async () => {
    const lines: string[] = [];
    const gate = new P0Gate(undefined, {});
    const admin = await adminApp(gate, lines);
    expect((await admin.inject({ method: 'POST', url: '/admin/maintenance', payload: { on: true } })).statusCode).toBe(401);
    const on = await admin.inject({ method: 'POST', url: '/admin/maintenance', headers: A, payload: { on: true, back_at: '2026-10-09T14:30:00+08:00' } });
    expect(on.json()).toMatchObject({ ok: true, maintenance: { on: true, back_at: '2026-10-09T06:30:00Z' } });
    expect(gate.check({})?.status).toBe(503);
    expect((await admin.inject({ method: 'POST', url: '/admin/maintenance', headers: A, payload: { on: false } })).json().maintenance).toEqual({ on: false });
    expect((await admin.inject({ method: 'POST', url: '/admin/min-version', headers: A, payload: { version: 2026100901, url: 'https://example.test/p0.apk' } })).json())
      .toMatchObject({ ok: true, min_version: 2026100901, update_url: 'https://example.test/p0.apk' });
    expect((await admin.inject({ method: 'GET', url: '/admin/gate', headers: A })).json()).toEqual({ ok: true, maintenance: { on: false }, min_version: 2026100901, update_url: 'https://example.test/p0.apk' });
    expect(lines.map(l => JSON.parse(l).admin)).toEqual(['maintenance', 'maintenance', 'min_version']);
  });

  it('refuses unreadable values', async () => {
    const admin = await adminApp(new P0Gate(undefined, {}), []);
    expect((await admin.inject({ method: 'POST', url: '/admin/maintenance', headers: A, payload: { on: 'yes' } })).statusCode).toBe(400);
    expect((await admin.inject({ method: 'POST', url: '/admin/maintenance', headers: A, payload: { on: true, back_at: 'soon' } })).json().code).toBe('bad_back_at');
    expect((await admin.inject({ method: 'POST', url: '/admin/min-version', headers: A, payload: { version: -1 } })).statusCode).toBe(400);
    expect((await admin.inject({ method: 'POST', url: '/admin/min-version', headers: A, payload: { version: 3, url: 7 } })).json().code).toBe('bad_url');
  });
});
