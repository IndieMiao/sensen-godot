/**
 * Observer tools for the real-player playtest (SGODOT-150 observer manual, q(53)). A second Fastify app that listens
 * on 127.0.0.1 inside the P0 container only (P0_ADMIN_PORT): Caddy and the internet reach the game port, never this
 * one, and every call also needs P0_ADMIN_KEY in `x-p0-admin`. Use it from the host through server/deploy/p0/deploy-hk.sh
 * (players / energy): it pipes a small script into `docker exec -i p0-p0-1 node`, which reads the key from its own
 * environment, so the key is in no process's arguments (host ps sees container processes too).
 * Each change is printed as one JSON line ({admin, player, from, to, at}) to the container log.
 */
import type { FastifyInstance } from 'fastify';
import type { P0Content } from './content.js';
import { isoMinute, type P0Gate } from './gate.js';
import { maxEnergy, settleEnergy } from './rules.js';
import type { P0Store } from './store.js';

export interface P0AdminDeps { content: P0Content; store: P0Store; now: () => number; key: string; log?: (line: string) => void; gate?: P0Gate }

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
    s.seq += 1;   // like every other change: a client holding the old view is refused stale_state and refreshes
    store.put(s);
    log(JSON.stringify({ admin: 'energy', player: s.player, from, to: value, max: maxEnergy(c, s), at: deps.now() }));
    return { ok: true, player: s.player, from, to: value, max: maxEnergy(c, s) };
  });

  const gate = deps.gate;
  if (!gate) return;
  /** SYS-UPDATE / SYS-MAINT settings now in force (gate.ts). */
  app.get('/admin/gate', async () => ({ ok: true, ...gate.state(), env: gate.envFloor() }));

  /** Maintenance on ({on:true, back_at?: ISO}) or off ({on:false}); persists across restarts (deploy-hk.sh maint-on / maint-off). */
  app.post('/admin/maintenance', async (req, reply) => {
    const body = (req.body ?? {}) as { on?: unknown; back_at?: unknown };
    if (typeof body.on !== 'boolean') return reply.code(400).send({ ok: false, code: 'bad_value' });
    if (body.back_at !== undefined && body.back_at !== null && body.back_at !== '' && !isoMinute(body.back_at)) {
      return reply.code(400).send({ ok: false, code: 'bad_back_at' });
    }
    const st = gate.setMaintenance(body.on, typeof body.back_at === 'string' ? body.back_at : undefined);
    log(JSON.stringify({ admin: 'maintenance', ...st.maintenance, at: deps.now() }));
    return { ok: true, ...st, env: gate.envFloor() };
  });

  /** The lowest client versionCode served ({version: 0 = no minimum, url?: download page}). */
  app.post('/admin/min-version', async (req, reply) => {
    const body = (req.body ?? {}) as { version?: unknown; url?: unknown };
    const version = Number(body.version);
    if (!Number.isInteger(version) || version < 0) return reply.code(400).send({ ok: false, code: 'bad_value' });
    if (body.url !== undefined && typeof body.url !== 'string') return reply.code(400).send({ ok: false, code: 'bad_url' });
    // No minimum without somewhere to update from (李白 / 苏烈 on #85): the Update card's button would do nothing.
    const url = body.url !== undefined ? String(body.url) : gate.state().update_url;
    if (version > 0 && url === '') return reply.code(400).send({ ok: false, code: 'need_url' });
    const st = gate.setMinVersion(version, body.url as string | undefined);
    log(JSON.stringify({ admin: 'min_version', min_version: st.min_version, update_url: st.update_url, update_on: st.update_on, at: deps.now() }));
    return { ok: true, ...st, env: gate.envFloor() };
  });
}
