/** P0 HTTP surface: GET state, POST command, plus dev-only time skip and reset (local playtests only). */
import type { FastifyInstance } from 'fastify';
import type { P0Content } from './content.js';
import { applyP0, type P0Command } from './reducer.js';
import type { P0Store } from './store.js';
import { viewOf } from './view.js';

export interface P0RouteDeps { content: P0Content; store: P0Store; now: () => number; dev: boolean }

const PLAYER_RE = /^[A-Za-z0-9_-]{8,64}$/;

export function registerP0Routes(app: FastifyInstance, deps: P0RouteDeps): void {
  const { content: c, store } = deps;
  const playerOf = (headers: Record<string, unknown>): string | null => {
    const id = String(headers['x-p0-player'] ?? '');
    return PLAYER_RE.test(id) ? id : null;
  };
  const clock = (offset: number) => deps.now() + offset;

  app.get('/v1/p0/state', async (req, reply) => {
    const player = playerOf(req.headers);
    if (!player) return reply.code(400).send({ ok: false, code: 'bad_player' });
    const s = store.get(player, deps.now());
    return reply.send({ ok: true, state: viewOf(c, s, clock(s.clock_ms)) });
  });

  app.post('/v1/p0/commands', async (req, reply) => {
    const player = playerOf(req.headers);
    if (!player) return reply.code(400).send({ ok: false, code: 'bad_player' });
    const s = store.get(player, deps.now());
    const now = clock(s.clock_ms);
    const result = applyP0(c, s, (req.body ?? {}) as P0Command, now);
    if (!result.ok) return reply.send({ ok: false, code: result.code, detail: result.detail ?? {}, state: viewOf(c, s, now) });
    store.put(result.state);
    return reply.send({ ok: true, events: result.events, state: viewOf(c, result.state, now) });
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
    return reply.send({ ok: true, state: viewOf(c, s, clock(s.clock_ms)) });
  });
  app.post('/v1/p0/dev/reset', async (req, reply) => {
    const player = playerOf(req.headers);
    if (!player) return reply.code(400).send({ ok: false, code: 'bad_player' });
    const s = store.reset(player, deps.now());
    return reply.send({ ok: true, state: viewOf(c, s, clock(s.clock_ms)) });
  });
}
