/**
 * Observer tools for the real-player playtest (SGODOT-150 observer manual, q(53)). A second Fastify app that listens
 * on 127.0.0.1 inside the P0 container only (P0_ADMIN_PORT): Caddy and the internet reach the game port, never this
 * one, and every call also needs P0_ADMIN_KEY in `x-p0-admin`. Use it from the host through server/deploy/p0/deploy-hk.sh
 * (players / energy): it pipes a small script into `docker exec -i p0-p0-1 node`, which reads the key from its own
 * environment, so the key is in no process's arguments (host ps sees container processes too).
 * Each change is printed as one JSON line ({admin, player, from, to, at}) to the container log.
 */
import { randomBytes } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { newCode, noteOk } from './accounts/codes.js';
import type { P0Accounts } from './accounts/store.js';
import type { P0Content } from './content.js';
import { isoMinute, type P0Gate } from './gate.js';
import { maxEnergy, settleEnergy } from './rules.js';
import type { P0Store } from './store.js';
import { registerModerationRoutes, type ModerationActions } from './admin_moderation.js';
import { registerAdminDelete } from './admin_delete.js';
import type { DeleteDeps } from './accounts/delete.js';

/** accounts (SGODOT-488): the tokens, for a test device's admin token and a claim reset (contract-accounts §4.1). */
export interface P0AdminDeps { content: P0Content; store: P0Store; now: () => number; key: string; log?: (line: string) => void; gate?: P0Gate;
  accounts?: P0Accounts;
  /** The room hub's kick (SGODOT-488): a claim reset closes the player's open socket at once. */
  kick?: (player: string) => void;
  moderation?: ModerationActions;
  deletion?: Pick<DeleteDeps, 'voice' | 'hub' | 'revokeApple'> }

/** An admin token lasts 30 days (tech-plan §2.5): a test device's, kept through other devices' sign-ins, never forgotten. */
export const ADMIN_TOKEN_MS = 30 * 86_400_000;
/** The deploy's smoke account (SGODOT-488, 奕星 11-13): one fixed id, never a player's, and its token's hour. */
export const SMOKE_PLAYER = 'p0-smoke-check';
export const SMOKE_TOKEN_MS = 3_600_000;
const PLAYER_RE = /^[A-Za-z0-9_-]{8,64}$/;

export function registerP0Admin(app: FastifyInstance, deps: P0AdminDeps): void {
  if (!deps.key) throw new Error('P0 admin needs P0_ADMIN_KEY');
  const { content: c, store } = deps;
  const log = deps.log ?? ((line: string) => console.log(line));
  app.addHook('onRequest', async (req, reply) => {
    if (req.headers['x-p0-admin'] !== deps.key) return reply.code(401).send({ ok: false, code: 'bad_admin_key' });
  });
  if (deps.moderation) registerModerationRoutes(app, { store, actions: deps.moderation, now: deps.now, log });
  if (deps.deletion && deps.accounts) registerAdminDelete(app, { ...deps.deletion, store, accounts: deps.accounts, now: deps.now }, log);

  /** Players with when they joined and were last seen: the observer matches them to names by install time. */
  /** With accounts, each player's admin tokens still in force ({tail, expires_at}), so one given to a test device is not
   *  forgotten there (tech-plan §2.5). */
  app.get('/admin/players', async () => {
    const admin = new Map<string, { tail: string; token_tail: string; expires_at: number }[]>();
    for (const t of deps.accounts?.adminTokens() ?? []) admin.set(t.player, [...(admin.get(t.player) ?? []), { tail: t.tail, token_tail: t.token_tail, expires_at: t.expires_at }]);
    return {
      ok: true,
      players: store.all().map(s => ({ player: s.player, created_at: s.created_at, last_at: s.presence.last_at, seq: s.seq,
        energy: s.energy.value, skills: s.skills, homestead: s.homestead.level,
        ...(deps.accounts ? { admin_tokens: admin.get(s.player) ?? [] } : {}),
        ...(deps.accounts?.codesOn() ? { code: deps.accounts.codeOf(s.player) ?? null } : {}) })).sort((a, b) => a.created_at - b.created_at),
    };
  });

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

  const accounts = deps.accounts;
  if (accounts) {
    const playerOf = (body: unknown) => {
      const p = (body && typeof body === 'object' ? (body as { player?: unknown }).player : undefined);
      return typeof p === 'string' && PLAYER_RE.test(p) ? p : null;
    };

    /** A test account on a test device (tech-plan §2.5, contract §4.1): a token the server makes, 32 bytes, its plain text
     *  in this answer only; kind admin, 30 days, kept through other devices' sign-ins. Not a claim: an unclaimed test
     *  account still takes its x-p0-player. The log line has no token. */
    app.post('/admin/session', async (req, reply) => {
      const player = playerOf(req.body);
      if (!player || !store.peek(player) || accounts.isDeleted(player)) return reply.code(404).send({ ok: false, code: 'unknown_player' });
      const token = randomBytes(32).toString('hex');
      const expires_at = deps.now() + ADMIN_TOKEN_MS;
      accounts.ensure(player);
      accounts.issue(player, token, 'admin', expires_at);
      log(JSON.stringify({ admin: 'session', player: player.slice(-6), expires_at, at: deps.now() }));   // the id's tail: the log outlives a deletion
      return { ok: true, player, token, expires_at };
    });

    /** The deploy's smoke (smoke.sh through deploy-hk.sh smoke): the fixed smoke account made afresh — a new save marked
     *  test, left out of the counts, so the same check runs each time — and a token of its own for an hour, its earlier
     *  ones revoked. No other save is touched; no id made up per run (a forced update leaves no id-only client to make
     *  one). The token is in this answer only, never in the log. */
    app.post('/admin/smoke', async (req, reply) => {
      // that one account only (奕星 11-13: the reset runs with every deploy, so no id may be passed to it — any other
      // is refused, never reset)
      const asked = (req.body && typeof req.body === 'object' ? (req.body as { player?: unknown }).player : undefined);
      if (asked !== undefined && asked !== SMOKE_PLAYER) return reply.code(400).send({ ok: false, code: 'smoke_only', player: SMOKE_PLAYER });
      const now = deps.now();
      const s = store.reset(SMOKE_PLAYER, now);
      s.test = true;
      store.put(s);
      accounts.ensure(SMOKE_PLAYER);
      accounts.revokeAll(SMOKE_PLAYER, undefined, { admin: true });
      const token = randomBytes(32).toString('hex'), expires_at = now + SMOKE_TOKEN_MS;
      accounts.issue(SMOKE_PLAYER, token, 'admin', expires_at);
      log(JSON.stringify({ admin: 'smoke', expires_at, at: now }));
      return { ok: true, player: SMOKE_PLAYER, token, expires_at };
    });

    /** A test code (contract v1.4 §4, v1.6 ④): for `player`, or for an account made here — a new player's fresh save (its
     *  home to pick, the guide), as any new player's: a reviewer goes the real way — the save marked login: code, and test
     *  when the note is a store review's (q(322) ②, 奕星 11-13 A: the counts leave it out; test changes no way in the
     *  game, nothing reads it but the counts, and it is not the OSS test page's accounts). One code an
     *  account: a new one replaces the old, whose tokens go. Not for an account linked to Apple or Google: their sign-in
     *  would sign every code device out. A code makes its account claimed (isClaimed): its old id alone gets 426. The code
     *  is in this answer only, never in the log. */
    app.post('/admin/code', async (req, reply) => {
      if (!accounts.codesOn()) return reply.code(503).send({ ok: false, code: 'codes_off' });
      const b = (req.body && typeof req.body === 'object' ? req.body : {}) as { player?: unknown; note?: unknown };
      if (!noteOk(b.note)) return reply.code(400).send({ ok: false, code: 'bad_note' });
      const now = deps.now();
      let player: string, s;
      if (b.player === undefined) {
        do player = 'p0-' + randomBytes(10).toString('hex'); while (store.peek(player) || accounts.find(player) || accounts.isDeleted(player));
        s = store.get(player, now, { pending: true, guide: true });
      } else {
        const p = playerOf(b);
        if (!p || !store.peek(p) || accounts.isDeleted(p)) return reply.code(404).send({ ok: false, code: 'unknown_player' });
        if (accounts.linked(p).length) return reply.code(409).send({ ok: false, code: 'linked', linked: accounts.linked(p) });
        player = p; s = store.peek(p)!;
      }
      s.login = 'code';
      if (/(^|[-_.])review([-_.]|$)/i.test(b.note)) s.test = true;   // q(322) ②: left out of the counts, nothing else; review a word of its own (not preview-…)
      store.put(s);
      // claimed for good (亚瑟 11-13): an old account a code is handed to, a Google-less tester's own farm, turns its old
      // build's id-only requests away (426) from now, and still once the code is withdrawn — the code's presence alone
      // (isClaimed) would lapse with it, letting the old build back in beside the code's phones
      accounts.markClaimed(player);
      const code = newCode();
      accounts.setCode(player, code, b.note);
      log(JSON.stringify({ admin: 'code', player: player.slice(-6), note: b.note, made: b.player === undefined, at: now }));
      return { ok: true, player, code, note: b.note };
    });

    /** A test code withdrawn: exactly the tokens it gave go, and the account's open room socket (its Apple / Google
     *  sign-in, had it one, would stay). */
    app.post('/admin/code/revoke', async (req, reply) => {
      if (!accounts.codesOn()) return reply.code(503).send({ ok: false, code: 'codes_off' });
      const player = playerOf(req.body);
      const revoked = player ? accounts.revokeCode(player) : -1;
      if (!player || revoked < 0) return reply.code(404).send({ ok: false, code: 'no_code' });
      deps.kick?.(player);
      log(JSON.stringify({ admin: 'code_revoke', player: player.slice(-6), revoked, at: deps.now() }));
      return { ok: true, revoked };
    });

    /** The claim undone (contract §4.1): claimed_at cleared and every token revoked, admin ones too — the account's old id
     *  can claim again, on a reinstalled test phone say. */
    app.post('/admin/claim/reset', async (req, reply) => {
      const player = playerOf(req.body);
      if (!player || (!store.peek(player) && !accounts.find(player))) return reply.code(404).send({ ok: false, code: 'unknown_player' });
      accounts.clearClaimed(player);
      const revoked = accounts.revokeAll(player, undefined, { admin: true }).length;
      deps.kick?.(player);   // its open room socket goes now (4001), not at its next reconnect
      log(JSON.stringify({ admin: 'claim_reset', player: player.slice(-6), revoked, at: deps.now() }));
      return { ok: true, revoked };
    });
  }

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
