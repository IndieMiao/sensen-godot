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
import { NameLimiter, nameForGuest, registerNameRoutes, setName, type NameList } from './name.js';
import { tokenShapeOk, type P0Accounts } from './store.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../..');
/** The terms' and privacy's versions: the one place they are written, the client's own copy of the same file. */
export function legalVersions(file = path.join(ROOT, 'assets/p0/legal/versions.json')): { terms: string; privacy: string } {
  const v = JSON.parse(readFileSync(file, 'utf8')) as { terms: string; privacy: string };
  return { terms: String(v.terms), privacy: String(v.privacy) };
}

export interface AccountRouteDeps {
  store: P0Store; accounts: P0Accounts; identify: IdentifyDeps; now: () => number;
  versions?: { terms: string; privacy: string };
  /** The 13+ answer the voice gate kept (voice_ages.json): true, false, or null when never asked. */
  voiceAge?: (player: string) => boolean | null;
  /** A new save's options from the request (choose_home / guide_v3, as routes.ts newSave). */
  newSave?: (headers: Record<string, unknown>) => { pending?: boolean; guide?: boolean };
  /** The names' bucket (周瑜's name.ts), shared by name/check, account/name and a guest with a name; one made here when none. */
  limiter?: NameLimiter;
  /** The word list (tests); server/data/name_blocklist.json when absent. */
  nameList?: () => NameList;
  /** Saves made per address per hour, at most (a script making saves; 后裔 on contract v1.2). */
  guestsPerHour?: number;
}

const bad = (code: string, status: number, extra: Record<string, unknown> = {}) => ({ status, body: { ok: false as const, code, ...extra } });

export function registerAccountRoutes(app: FastifyInstance, deps: AccountRouteDeps): void {
  const { store, accounts } = deps;
  const versions = deps.versions ?? legalVersions();
  const limiter = deps.limiter ?? new NameLimiter();
  registerNameRoutes(app, { store, now: deps.now, limiter, list: deps.nameList,
    identify: (req, reply) => { const w = identify(req.headers, deps.identify); if (isRefusal(w)) { reply.code(w.status).send(w.body); return null; } return w.player; } });
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
    const now = deps.now();
    // §2.5: a test account (Test options, the OSS build) is made by its phone's main account — its token in authorization
    // — and takes that account's consent; no name (the default). Anyone else's test:true is refused: a test account is a
    // plain guest with no rights, but its consent must be a real one.
    let main: ReturnType<typeof store.find> | undefined;
    if (b.test === true) {
      const w = identify(req.headers, deps.identify);
      if (isRefusal(w)) return reply.code(w.status).send(w.body);
      main = w.via === 'token' ? store.find(w.player, now) : undefined;
      if (!main?.consent) return send(bad('unauthenticated', 401));
    } else {
      if (b.age_ok !== true) return send(bad('schema', 400));
      if (!consentOk(b)) return send(outdated());
    }
    const named = main ? { ok: true as const } : nameForGuest(b, { limiter, ip: req.ip, now, list: deps.nameList?.() });
    if (!named.ok) return reply.code(named.status).send(named.body);
    if (b.pending !== undefined) return send(bad('pending_expired', 410));   // PR-B: the pending sign-in is taken here
    const h = Math.floor(now / 3_600_000);
    if (h !== hour) { made.clear(); hour = h; }
    const n = made.get(req.ip) ?? 0;
    if (n >= (deps.guestsPerHour ?? 10)) return send(bad('rate_limited', 429));
    made.set(req.ip, n + 1);
    let player = '';
    const make = () => (main ? 'g3test-' + randomBytes(16).toString('hex') : 'p0-' + randomBytes(10).toString('hex'));   // the test ids as P0TestAccounts writes them
    do player = make(); while (store.peek(player) || accounts.find(player) || accounts.isDeleted(player));
    const s = store.get(player, now, deps.newSave?.(req.headers) ?? {});
    s.consent = main?.consent ? { ...main.consent } : { terms: versions.terms, privacy: versions.privacy, at: now };
    s.age_ok = true;
    if (main) s.test = true;
    if ('name' in named && named.name !== undefined) setName(s, named.name, named.name_set_at ?? now);
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
