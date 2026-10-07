/** P0 HTTP surface: GET state, POST command, plus dev-only time skip and reset (local playtests only). */
import type { FastifyInstance } from 'fastify';
import type { P0Content } from './content.js';
import { applyP0, type P0Command } from './reducer.js';
import type { P0Store } from './store.js';
import { viewOf } from './view.js';
import type { P0State } from './state.js';
import { add } from './bag.js';
import { itemName } from './content.js';
import { putInStorage } from './storage.js';

/** presence: players in the outpost rooms right now (SGODOT-227 OutpostRooms.total()); optional. */
export interface P0RouteDeps { content: P0Content; store: P0Store; now: () => number; dev: boolean; presence?: () => number }

const PLAYER_RE = /^[A-Za-z0-9_-]{8,64}$/;

export function registerP0Routes(app: FastifyInstance, deps: P0RouteDeps): void {
  const { content: c, store } = deps;
  const playerOf = (headers: Record<string, unknown>): string | null => {
    const id = String(headers['x-p0-player'] ?? '');
    return PLAYER_RE.test(id) ? id : null;
  };
  const clock = (offset: number) => deps.now() + offset;
  const view = (st: P0State, at: number) => viewOf(c, st, at, { online: deps.presence ? deps.presence() : null });

  app.get('/v1/p0/state', async (req, reply) => {
    const player = playerOf(req.headers);
    if (!player) return reply.code(400).send({ ok: false, code: 'bad_player' });
    const s = store.get(player, deps.now());
    return reply.send({ ok: true, state: view(s, clock(s.clock_ms)) });
  });

  app.post('/v1/p0/commands', async (req, reply) => {
    const player = playerOf(req.headers);
    if (!player) return reply.code(400).send({ ok: false, code: 'bad_player' });
    const s = store.get(player, deps.now());
    const now = clock(s.clock_ms);
    const result = applyP0(c, s, (req.body ?? {}) as P0Command, now);
    if (!result.ok) return reply.send({ ok: false, code: result.code, detail: result.detail ?? {}, state: view(s, now) });
    store.put(result.state);
    return reply.send({ ok: true, events: result.events, state: view(result.state, now) });
  });

  if (!deps.dev) return;
  app.post('/v1/p0/dev/skip', async (req, reply) => {
    const player = playerOf(req.headers);
    if (!player) return reply.code(400).send({ ok: false, code: 'bad_player' });
    const minutes = Number((req.body as { minutes?: number } | undefined)?.minutes ?? 0);
    if (!Number.isFinite(minutes) || minutes <= 0 || minutes > 7 * 24 * 60) return reply.code(400).send({ ok: false, code: 'bad_minutes' });
    const s = store.get(player, deps.now());
    s.clock_ms += minutes * 60_000;
    store.put(s);
    return reply.send({ ok: true, state: view(s, clock(s.clock_ms)) });
  });
  /** Playtests only: set the stored energy (eating, Energy Card and zero-energy states need a low bar). */
  app.post('/v1/p0/dev/energy', async (req, reply) => {
    const player = playerOf(req.headers);
    if (!player) return reply.code(400).send({ ok: false, code: 'bad_player' });
    const value = Number((req.body as { value?: number } | undefined)?.value);
    if (!Number.isInteger(value) || value < 0 || value > 1000) return reply.code(400).send({ ok: false, code: 'bad_value' });
    const s = store.get(player, deps.now());
    const now = clock(s.clock_ms);
    s.energy = { value, tick_ms: now };
    store.put(s);
    return reply.send({ ok: true, state: view(s, now) });
  });
  /** Playtests only: fill every free bag slot with one item (the creel-full state, FISH-4). */
  app.post('/v1/p0/dev/fill', async (req, reply) => {
    const player = playerOf(req.headers);
    if (!player) return reply.code(400).send({ ok: false, code: 'bad_player' });
    const id = String((req.body as { id?: string } | undefined)?.id ?? 'fish_crucian');
    if (!c.fish.some(f => f.id === id)) return reply.code(400).send({ ok: false, code: 'bad_item' });
    const s = store.get(player, deps.now());
    add(c, s, id, 1_000_000);
    store.put(s);
    return reply.send({ ok: true, state: view(s, clock(s.clock_ms)) });
  });
  /** Playtests only: put items in the bag or the farm storage (materials have no P0 source until the mine / gathering land). */
  app.post('/v1/p0/dev/grant', async (req, reply) => {
    const player = playerOf(req.headers);
    if (!player) return reply.code(400).send({ ok: false, code: 'bad_player' });
    const body = (req.body ?? {}) as { id?: string; qty?: number; to?: string };
    const id = String(body.id ?? ''), qty = Number(body.qty ?? 1), to = body.to === 'storage' ? 'storage' : 'bag';
    if (!/^[a-z0-9_@]{2,48}$/.test(id) || itemName(c, id) === id) return reply.code(400).send({ ok: false, code: 'bad_item' });
    if (!Number.isInteger(qty) || qty < 1 || qty > 999) return reply.code(400).send({ ok: false, code: 'bad_qty' });
    const s = store.get(player, deps.now());
    if (to === 'storage') putInStorage(s, id, qty);
    else add(c, s, id, qty);
    store.put(s);
    return reply.send({ ok: true, state: view(s, clock(s.clock_ms)) });
  });
  app.post('/v1/p0/dev/reset', async (req, reply) => {
    const player = playerOf(req.headers);
    if (!player) return reply.code(400).send({ ok: false, code: 'bad_player' });
    const s = store.reset(player, deps.now());
    return reply.send({ ok: true, state: view(s, clock(s.clock_ms)) });
  });
}
