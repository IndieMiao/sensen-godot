/**
 * Observer tools for the real-player playtest (SGODOT-150 observer manual, q(53)). A second Fastify app that listens
 * on 127.0.0.1 inside the P0 container only (P0_ADMIN_PORT): Caddy and the internet reach the game port, never this
 * one, and every call also needs P0_ADMIN_KEY in `x-p0-admin`. Use it from the host with docker exec, e.g.
 *   docker exec p0-p0-1 wget -qO- --header "x-p0-admin: $KEY" --header 'content-type: application/json' \
 *     --post-data '{"player":"p0-…","value":80}' http://127.0.0.1:3111/admin/energy
 * Each change is printed as one JSON line ({admin, player, from, to, at}) to the container log.
 */
import type { FastifyInstance } from 'fastify';
import type { P0Content } from './content.js';
import { maxEnergy, settleEnergy } from './rules.js';
import type { P0Store } from './store.js';

export interface P0AdminDeps { content: P0Content; store: P0Store; now: () => number; key: string; log?: (line: string) => void }

export function registerP0Admin(app: FastifyInstance, deps: P0AdminDeps): void {
  if (!deps.key) throw new Error('P0 admin needs P0_ADMIN_KEY');
  const { content: c, store } = deps;
  const log = deps.log ?? ((line: string) => console.log(line));
  app.addHook('onRequest', async (req, reply) => {
    if (req.headers['x-p0-admin'] !== deps.key) return reply.code(401).send({ ok: false, code: 'bad_admin_key' });
  });

  /** Players with when they joined and were last seen: the observer matches them to names by install time. */
  app.get('/admin/players', async () => ({
    ok: true,
    players: store.all().map(s => ({ player: s.player, created_at: s.created_at, last_at: s.presence.last_at, seq: s.seq,
      energy: s.energy.value, skills: s.skills, homestead: s.homestead.level })).sort((a, b) => a.created_at - b.created_at),
  }));

  /** F1: set a player's Energy once (day-4 revisit at about 80 / max). Only an existing player; the clock offset counts. */
  app.post('/admin/energy', async (req, reply) => {
    const body = (req.body ?? {}) as { player?: unknown; value?: unknown };
    const s = typeof body.player === 'string' ? store.peek(body.player) : undefined;
    if (!s) return reply.code(404).send({ ok: false, code: 'no_such_player' });
    const value = Number(body.value);
    if (!Number.isInteger(value) || value < 0 || value > maxEnergy(c, s) + c.energy.bonus_zone) {
      return reply.code(400).send({ ok: false, code: 'bad_value', detail: { max: maxEnergy(c, s) } });
    }
    const now = deps.now() + s.clock_ms;
    settleEnergy(c, s, now);
    const from = s.energy.value;
    s.energy = { value, tick_ms: now };
    store.put(s);
    log(JSON.stringify({ admin: 'energy', player: s.player, from, to: value, max: maxEnergy(c, s), at: deps.now() }));
    return { ok: true, player: s.player, from, to: value, max: maxEnergy(c, s) };
  });
}
