/** SGODOT-150 observer tools (q(53)): admin routes on their own loopback listener with their own key. */
import Fastify from 'fastify';
import { describe, expect, it } from 'vitest';
import { registerP0Admin } from '../../src/p0/admin.js';
import { loadP0Content } from '../../src/p0/content.js';
import { guardOptionsFromEnv, registerP0Guard } from '../../src/p0/guard.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { P0Store } from '../../src/p0/store.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 8, 2);
const KEY = 'admin-test-key';

function setup() {
  const store = new P0Store(c);
  const lines: string[] = [];
  const admin = Fastify();
  registerP0Admin(admin, { content: c, store, now: () => T0, key: KEY, log: l => lines.push(l) });
  return { store, admin, lines };
}

describe('P0 admin tools (SGODOT-150, q(53))', () => {
  it('sets an existing player\'s Energy once with the admin key, and logs it', async () => {
    const { store, admin, lines } = setup();
    store.get('admin-player-01', T0);
    try {
      const r = await admin.inject({ method: 'POST', url: '/admin/energy', headers: { 'x-p0-admin': KEY }, payload: { player: 'admin-player-01', value: 80 } });
      expect(r.json()).toEqual({ ok: true, player: 'admin-player-01', from: 200, to: 80, max: 200 });
      expect(store.peek('admin-player-01')!.energy).toEqual({ value: 80, tick_ms: T0 });
      expect(JSON.parse(lines[0])).toMatchObject({ admin: 'energy', player: 'admin-player-01', from: 200, to: 80 });
    } finally { await admin.close(); }
  });

  it('refuses without the key, for an unknown player (never creates one) and out-of-range values', async () => {
    const { store, admin } = setup();
    store.get('admin-player-02', T0);
    try {
      expect((await admin.inject({ method: 'POST', url: '/admin/energy', payload: { player: 'admin-player-02', value: 80 } })).statusCode).toBe(401);
      expect((await admin.inject({ method: 'POST', url: '/admin/energy', headers: { 'x-p0-admin': 'wrong' }, payload: { player: 'admin-player-02', value: 80 } })).statusCode).toBe(401);
      expect((await admin.inject({ method: 'POST', url: '/admin/energy', headers: { 'x-p0-admin': KEY }, payload: { player: 'nobody-here', value: 80 } })).json()).toEqual({ ok: false, code: 'no_such_player' });
      expect(store.peek('nobody-here')).toBeUndefined();
      expect((await admin.inject({ method: 'POST', url: '/admin/energy', headers: { 'x-p0-admin': KEY }, payload: { player: 'admin-player-02', value: 999 } })).statusCode).toBe(400);
    } finally { await admin.close(); }
  });

  it('lists players by when they joined, for the name ↔ id table', async () => {
    const { store, admin } = setup();
    store.get('admin-player-late', T0 + 60_000);
    store.get('admin-player-early', T0);
    try {
      const r = (await admin.inject({ method: 'GET', url: '/admin/players', headers: { 'x-p0-admin': KEY } })).json();
      expect(r.players.map((p: { player: string }) => p.player)).toEqual(['admin-player-early', 'admin-player-late']);
    } finally { await admin.close(); }
  });

  it('is not part of the game app: the public listener has no /admin route', async () => {
    const app = Fastify();
    await registerP0Guard(app, guardOptionsFromEnv({ P0_ACCESS_KEYS: 'k' }));
    registerP0Routes(app, { content: c, store: new P0Store(c), now: () => T0, dev: false });
    try {
      expect((await app.inject({ method: 'POST', url: '/admin/energy', headers: { 'x-p0-admin': KEY }, payload: { player: 'x', value: 1 } })).statusCode).toBe(404);
    } finally { await app.close(); }
  });

  it('cannot start without a key', () => {
    expect(() => registerP0Admin(Fastify(), { content: c, store: new P0Store(c), now: () => T0, key: '' })).toThrow();
  });
});
