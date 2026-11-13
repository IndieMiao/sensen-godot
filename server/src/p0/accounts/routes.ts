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
import { tokenShapeOk, type AppleLink, type GoogleLink, type P0Accounts, type Provider } from './store.js';

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
  /** The AGE page passed (claim's or consent's age_ok: true) written to the voice gate too, so the mic is not held back
   * later (q(312) ⑪; a code account's reviewer, 奕星 on v3.2 ⑤). Never a 「没过」: that is never sent. */
  voiceAgeOk?: (player: string) => void;
  /** A new save's options from the request (choose_home / guide_v3, as routes.ts newSave). */
  newSave?: (headers: Record<string, unknown>) => { pending?: boolean; guide?: boolean };
  /** The names' bucket (周瑜's name.ts), shared by name/check, account/name and a guest with a name; one made here when none. */
  limiter?: NameLimiter;
  /** The word list (tests); server/data/name_blocklist.json when absent. */
  nameList?: () => NameList;
  /** Saves made per address per hour, at most (a script making saves; 后裔 on contract v1.2). */
  guestsPerHour?: number;
  /** v1.4 (必须注册): a new farm needs a sign-in — guest takes the pending one (PR-B's PendingSignIns) and links it;
   * without one, sign_in_required, unless P0_GUEST_OK (devserver, shots) or a test account. */
  pending?: { take(id: unknown): { provider: Provider; link: AppleLink | GoogleLink } | undefined;
    create?(provider: Provider, link: AppleLink | GoogleLink): string };
  guestOk?: boolean;
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

  /** hello (v1.4 ⑦b): with an x-p0-player the server has, that old account's way before any sign-in — unclaimed, its
   * voice gate's answer and its consent; claimed, which sign-in it has. Read only: no token, no save. */
  app.get('/v1/p0/hello', async req => {
    const id = String(req.headers['x-p0-player'] ?? '');
    let legacy: Record<string, unknown> | undefined;
    if (/^[A-Za-z0-9_-]{8,64}$/.test(id) && !accounts.isDeleted(id)) {
      const s = store.find(id, deps.now());
      if (accounts.isClaimed(id)) legacy = { claimed: true, linked: accounts.linked(id) };
      else if (s) legacy = { age: deps.voiceAge?.(id) ?? null, consent: s.consent ? { terms: s.consent.terms, privacy: s.consent.privacy } : null };
    }
    return { ok: true, terms_version: versions.terms, privacy_version: versions.privacy, legacy_id: deps.identify.legacyId,
      guest_ok: !!deps.guestOk, ...(legacy ? { legacy } : {}) };
  });

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
    if (!main && b.pending === undefined && !deps.guestOk) return send(bad('sign_in_required', 400));
    const named = main ? { ok: true as const } : nameForGuest(b, { limiter, ip: req.ip, now, list: deps.nameList?.() });
    if (!named.ok) return reply.code(named.status).send(named.body);
    const signedIn = b.pending !== undefined ? deps.pending?.take(b.pending) : undefined;
    if (b.pending !== undefined && !signedIn) return send(bad('pending_expired', 410));
    if (signedIn) {
      // the account linked meanwhile to a farm that is there (another phone made one): never taken from it
      const was = accounts.byIdentity(signedIn.provider, signedIn.link.sub);
      // v1.6 ②: the sign-in handed back as a new pending one, so 「进那个农场」 needs no second system sign-in
      if (was && !accounts.isDeleted(was) && store.find(was, now)) {
        const again = deps.pending?.create?.(signedIn.provider, signedIn.link);
        return send(bad('conflict', 409, again ? { pending: again } : {}));
      }
    }
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
    if (signedIn) {
      // a link left on a farm gone goes first, so the sign-in is this farm's alone (liveOwner's rule)
      const was = accounts.byIdentity(signedIn.provider, signedIn.link.sub);
      if (was) accounts.unlink(was, signedIn.provider);
      accounts.link(player, signedIn.provider, signedIn.link);
    }
    accounts.issue(player, token);   // … then who holds it
    return { ok: true, player, ...(signedIn ? { linked: signedIn.provider } : {}) };
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
      if (accounts.isClaimed(id)) return send(bad('claimed', 409, { linked: accounts.linked(id) }));
      accounts.markClaimed(id);
      accounts.issue(id, token);
    }
    const s = store.find(id, deps.now())!;
    // v1.4 ⑦b: the consent given on the pages before sign-in comes with the claim (no token then for account/consent)
    const c = body(b.consent);
    if (owner !== id && c.terms === versions.terms && c.privacy === versions.privacy) {
      s.consent = { terms: versions.terms, privacy: versions.privacy, at: deps.now() };
      s.age_ok = true;
      store.put(s);
    }
    if (owner !== id && b.age_ok === true && deps.voiceAge?.(id) === null) deps.voiceAgeOk?.(id);   // v1.4 ⑬: never asked, now passed
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
    if (deps.voiceAge?.(w.player) === null) deps.voiceAgeOk?.(w.player);
    return { ok: true };
  });
}
