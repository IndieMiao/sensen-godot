/**
 * The first launch's routes (SGODOT-488 A1; contract-accounts.md §1): hello, session/guest, session/claim, account/consent.
 * hello and guest need no player; claim takes the old x-p0-player once, with the client's new token; consent needs the
 * token. Only guest makes a save (§1.3: the save first, then accounts.json — a crash between leaves a save no token
 * reaches, which the 12-month clean-up takes).
 */
import { randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { FastifyInstance } from 'fastify';
import type { P0Store } from '../store.js';
import { identify, isRefusal, type IdentifyDeps } from './identify.js';
import { tokenShapeOk, type P0Accounts } from './store.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../..');
/** The terms' and privacy's versions: the one place they are written, the client's own copy of the same file. */
export function legalVersions(file = path.join(ROOT, 'assets/p0/legal/versions.json')): { terms: string; privacy: string } {
  const v = JSON.parse(readFileSync(file, 'utf8')) as { terms: string; privacy: string };
  return { terms: String(v.terms), privacy: String(v.privacy) };
}

/** A name for a new save: {name, name_set_at?} or the refusal's reason (周瑜's nameForGuest plugs in here). */
export type GuestName = (body: Record<string, unknown>, now: number) => { name?: string; name_set_at?: number } | { reason: string };
/** Until 周瑜's rules are in: skip keeps no name, a name is taken trimmed if 1–16 characters. */
const plainName: GuestName = (body, now) => {
  if (body.skip === true) return {};
  const name = typeof body.name === 'string' ? body.name.trim() : '';
  if (name === '') return { reason: 'empty' };
  if ([...name].length > 16) return { reason: 'length' };
  return { name, name_set_at: now };
};

export interface AccountRouteDeps {
  store: P0Store; accounts: P0Accounts; identify: IdentifyDeps; now: () => number;
  versions?: { terms: string; privacy: string };
  /** The 13+ answer the voice gate kept (voice_ages.json): true, false, or null when never asked. */
  voiceAge?: (player: string) => boolean | null;
  /** A new save's options from the request (choose_home / guide_v3, as routes.ts newSave). */
  newSave?: (headers: Record<string, unknown>) => { pending?: boolean; guide?: boolean };
  guestName?: GuestName;
  /** Saves made per address per hour, at most (a script making saves; 后裔 on contract v1.2). */
  guestsPerHour?: number;
}

const bad = (code: string, status: number, extra: Record<string, unknown> = {}) => ({ status, body: { ok: false as const, code, ...extra } });

export function registerAccountRoutes(app: FastifyInstance, deps: AccountRouteDeps): void {
  const { store, accounts } = deps;
  const versions = deps.versions ?? legalVersions();
  const nameOf = deps.guestName ?? plainName;
  const made = new Map<string, number>();   // address → saves made this hour
  let hour = -1;
  const body = (b: unknown) => (b && typeof b === 'object' && !Array.isArray(b) ? b : {}) as Record<string, unknown>;
  const consentOk = (b: Record<string, unknown>) => b.terms === versions.terms && b.privacy === versions.privacy;
  const outdated = () => bad('consent_outdated', 409, { terms_version: versions.terms, privacy_version: versions.privacy });

  app.get('/v1/p0/hello', async () => ({ ok: true, terms_version: versions.terms, privacy_version: versions.privacy, legacy_id: deps.identify.legacyId }));

  app.post('/v1/p0/session/guest', async (req, reply) => {
    const b = body(req.body);
    const send = (r: ReturnType<typeof bad>) => reply.code(r.status).send(r.body);
    if (!tokenShapeOk(b.token)) return send(bad(typeof b.token === 'string' ? 'token_too_short' : 'schema', 400));
    const token = String(b.token).toLowerCase();
    const mine = accounts.tokenOwner(token);
    if (mine) return { ok: true, player: mine };   // the same token again: a retry after a lost answer, the same save
    if (b.age_ok !== true) return send(bad('schema', 400));
    if (!consentOk(b)) return send(outdated());
    const now = deps.now();
    const named = nameOf(b, now);
    if ('reason' in named) return send(bad('name_rejected', 400, { reason: named.reason }));
    if (b.pending !== undefined) return send(bad('pending_expired', 410));   // PR-B: the pending sign-in is taken here
    const h = Math.floor(now / 3_600_000);
    if (h !== hour) { made.clear(); hour = h; }
    const n = made.get(req.ip) ?? 0;
    if (n >= (deps.guestsPerHour ?? 10)) return send(bad('rate_limited', 429));
    made.set(req.ip, n + 1);
    let player = '';
    do player = 'p0-' + randomBytes(10).toString('hex'); while (store.peek(player) || accounts.find(player) || accounts.isDeleted(player));
    const s = store.get(player, now, deps.newSave?.(req.headers) ?? {});
    s.consent = { terms: versions.terms, privacy: versions.privacy, at: now };
    s.age_ok = true;
    if (named.name !== undefined) s.profile = { ...s.profile, name: named.name, ...(named.name_set_at !== undefined ? { name_set_at: named.name_set_at } : {}) };
    store.put(s);                    // the save first (§1.3) …
    accounts.ensure(player);
    accounts.issue(player, token);   // … then who holds it
    return { ok: true, player };
  });

  app.post('/v1/p0/session/claim', async (req, reply) => {
    const b = body(req.body);
    const send = (r: ReturnType<typeof bad>) => reply.code(r.status).send(r.body);
    const id = String(req.headers['x-p0-player'] ?? '');
    if (!/^[A-Za-z0-9_-]{8,64}$/.test(id)) return send(bad('bad_player', 400));
    if (!tokenShapeOk(b.token)) return send(bad(typeof b.token === 'string' ? 'token_too_short' : 'schema', 400));
    const token = String(b.token).toLowerCase();
    const owner = accounts.tokenOwner(token);
    if (owner && owner !== id) return send(bad('schema', 400));   // a token is one player's only
    if (accounts.isDeleted(id) || !store.find(id, deps.now())) return send(bad('unknown_player', 404));
    if (owner !== id) {
      if (accounts.find(id)?.claimed_at !== undefined || accounts.userTokenCount(id) > 0) return send(bad('claimed', 409, { linked: accounts.linked(id) }));
      accounts.markClaimed(id);
      accounts.issue(id, token);
    }
    const s = store.find(id, deps.now())!;
    return { ok: true, player: id, age: deps.voiceAge?.(id) ?? null, consent: s.consent ?? null };
  });

  app.post('/v1/p0/account/consent', async (req, reply) => {
    const w = identify(req.headers, deps.identify);
    if (isRefusal(w)) return reply.code(w.status).send(w.body);
    const b = body(req.body);
    if (b.age_ok !== true) return reply.code(400).send({ ok: false, code: 'schema' });   // q(312) ⑨ C: 「没过」 is never sent
    if (!consentOk(b)) { const r = outdated(); return reply.code(r.status).send(r.body); }
    const s = store.find(w.player, deps.now());
    if (!s) return reply.code(401).send({ ok: false, code: 'unauthenticated' });
    s.consent = { terms: versions.terms, privacy: versions.privacy, at: deps.now() };
    s.age_ok = true;
    store.put(s);
    return { ok: true };
  });
}
