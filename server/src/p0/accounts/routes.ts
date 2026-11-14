/**
 * The first launch's routes (SGODOT-488 A1, 489; contract-accounts v1.4–v1.6.3): hello, session/guest, session/claim,
 * session/pending, session/logout, account/consent. hello, guest and pending need no player; claim takes the old
 * x-p0-player once with a sign-in (the claim and the link in one step), and the client's new token; consent and logout
 * need the token. Only guest makes a save (§1.3: the save first, then accounts.json — a crash between leaves a save no token
 * reaches, which the 12-month clean-up takes).
 */
import { randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { FastifyInstance } from 'fastify';
import type { P0Store } from '../store.js';
import { identify, isRefusal, type IdentifyDeps } from './identify.js';
import { conflictFarm, liveOwner, signIn } from './link.js';
import { NameLimiter, nameForGuest, registerNameRoutes, setName, type NameList } from './name.js';
import { tokenShapeOk, type AnyLink, type AppleLink, type P0Accounts, type Provider } from './store.js';

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
  pending?: { take(id: unknown): { provider: Provider; link: AnyLink } | undefined;
    peek?(id: unknown): { provider: Provider; link: AnyLink } | undefined;
    create?(provider: Provider, link: AnyLink): string };
  guestOk?: boolean;
  /** A sign-in's credentials checked (PR-B: appleVerifier / googleVerifier by provider): its link, or the refusal
   * (bad_token, provider_unavailable). An unknown provider is undefined. claim needs it; none, and claim is off (503). */
  verify?: (provider: string, b: Record<string, unknown>) => Promise<{ link: AnyLink } | { status: number; body: { ok: false; code: string } } | undefined>;
  /** The room hub's kick: a sign-in closes the account's open socket elsewhere (link.ts signIn). */
  kick?: (player: string) => void;
  /** Email sign-in usable (contract v1.5: P0_EMAIL_LOGIN, P0_ACCOUNTS_KEY and the sign-in mail all there): hello says so,
   * and the client shows `Continue with email`. */
  email?: boolean;
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
      guest_ok: !!deps.guestOk, email: !!deps.email, ...(legacy ? { legacy } : {}) };
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

  /** POST /v1/p0/session/claim {provider, id_token, nonce, auth_code? | email, code, token, consent?, age_ok?} with the
   * old x-p0-player (v1.4): the sign-in checked first, then — after the last await — the old farm claimed and linked to
   * it, unless that account has another farm still there (conflict, its line) or this farm is claimed already (claimed,
   * its links). The same farm's own account signs in. Every refusal after the check carries the sign-in as a pending
   * one and has_farm (v1.6 ①: Apple's code and the email code are spent; the client never asks for a second sheet). */
  app.post('/v1/p0/session/claim', async (req, reply) => {
    const b = body(req.body);
    const send = (r: ReturnType<typeof bad>) => reply.code(r.status).send(r.body);
    const id = String(req.headers['x-p0-player'] ?? '');
    if (!/^[A-Za-z0-9_-]{8,64}$/.test(id)) return send(bad('bad_player', 400));
    if (!tokenShapeOk(b.token)) return send(bad(typeof b.token === 'string' ? 'token_too_short' : 'schema', 400));
    const token = String(b.token).toLowerCase();
    if (accounts.tokenOwner(token) === id) return claimed(id, b);   // the same claim again: a retry after a lost answer
    if (!deps.verify || !deps.pending?.create) return send(bad('provider_unavailable', 503));
    const checked = await deps.verify(String(b.provider ?? ''), b);
    if (!checked) return send(bad('schema', 400));
    if ('status' in checked) return reply.code(checked.status).send(checked.body);
    // after the last await: the checks and the writes below in one stretch (§1.3)
    const now = deps.now();
    const provider = b.provider as Provider;
    const owner = accounts.tokenOwner(token);
    if (owner && owner !== id) return send(bad('schema', 400));   // a token is one player's only
    const other = liveOwner(store, accounts, provider, checked.link.sub, now);
    const ticket = () => ({ pending: deps.pending!.create!(provider, checked.link), has_farm: other !== undefined });
    if (accounts.isDeleted(id) || !store.find(id, now)) return send(bad('unknown_player', 404, ticket()));
    if (other === id) {
      // this farm's own account (claimed on another phone before): signed in, as session/apple|google would
      if (provider === 'apple' && (checked.link as AppleLink).refresh) accounts.link(id, 'apple', checked.link);
      signIn({ accounts, kick: deps.kick }, id, token);
      return claimed(id, b);
    }
    if (accounts.isClaimed(id)) return send(bad('claimed', 409, { linked: accounts.linked(id), ...ticket() }));
    if (other) return send(bad('conflict', 409, { farm: conflictFarm(store, other, now), ...ticket() }));
    accounts.markClaimed(id);
    accounts.link(id, provider, checked.link);
    accounts.issue(id, token);
    // v1.4 ⑦b: the consent given on the pages before sign-in comes with the claim (no token then for account/consent)
    const s = store.find(id, now)!;
    const c = body(b.consent);
    if (c.terms === versions.terms && c.privacy === versions.privacy) {
      s.consent = { terms: versions.terms, privacy: versions.privacy, at: now };
      s.age_ok = true;
      store.put(s);
    }
    if (b.age_ok === true && deps.voiceAge?.(id) === null) deps.voiceAgeOk?.(id);   // v1.4 ⑬: never asked, now passed
    return claimed(id, b);
  });
  const claimed = (id: string, _b: Record<string, unknown>) => {
    const s = store.find(id, deps.now());
    return { ok: true, player: id, linked: accounts.linked(id), age: deps.voiceAge?.(id) ?? null, consent: s?.consent ?? null };
  };

  /** POST /v1/p0/session/pending {pending, token}, no identity (v1.6 ①): a sign-in a claim or guest already checked —
   * its farm signed in (its other phones' tokens revoked), or no_farm with a new pending one. */
  app.post('/v1/p0/session/pending', async (req, reply) => {
    const b = body(req.body);
    const send = (r: ReturnType<typeof bad>) => reply.code(r.status).send(r.body);
    if (!tokenShapeOk(b.token)) return send(bad(typeof b.token === 'string' ? 'token_too_short' : 'schema', 400));
    const token = String(b.token).toLowerCase();
    const p = deps.pending?.peek ? deps.pending.peek(b.pending) : undefined;
    if (!p) return send(bad('pending_expired', 410));
    const player = liveOwner(store, accounts, p.provider, p.link.sub, deps.now());
    const owner = accounts.tokenOwner(token);
    if (player && owner && owner !== player) return send(bad('schema', 400));   // a token is one player's only; the ticket kept
    deps.pending!.take(b.pending);
    if (!player) return send(bad('no_farm', 404, { pending: deps.pending!.create!(p.provider, p.link) }));
    if (p.provider === 'apple' && (p.link as AppleLink).refresh) accounts.link(player, 'apple', p.link);   // the newest authorization
    return signIn({ accounts, kick: deps.kick }, player, token);
  });

  /** POST /v1/p0/session/logout (v1.4): this phone's token alone withdrawn; the account's other phones keep theirs. */
  app.post('/v1/p0/session/logout', async (req, reply) => {
    const w = identify(req.headers, deps.identify);
    if (isRefusal(w)) return reply.code(w.status).send(w.body);
    if (w.via !== 'token') return reply.code(401).send({ ok: false, code: 'unauthenticated' });
    const auth = String(req.headers.authorization ?? '').replace(/^Bearer\s+/i, '').toLowerCase();
    accounts.revoke(auth);
    return { ok: true };
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
