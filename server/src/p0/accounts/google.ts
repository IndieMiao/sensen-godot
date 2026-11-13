/**
 * Sign in with Google for P0 accounts (SGODOT-489 PR-B; contract-accounts.md §2, 周瑜): session/google finds the farm a
 * Google account is linked to, account/link/google links one to the farm in hand. The ID token is checked as Journey's
 * was (P0's own copy, jwt.ts: SGODOT-304): RS256 on Google's keys, the issuer, aud one of config.google.audiences (the
 * Web client, which Android's Credential Manager asks for; the iOS client), not expired, and its nonce the SHA-256 hex
 * of the raw one the client sends beside it.
 *
 * Only the account number is kept (李白's store forms ◆E: on Play the email is processed, never stored): google: {sub}
 * in accounts.json and in a pending sign-in. An Android token carries the email, name and picture besides; nothing here
 * reads them and nothing writes them — not accounts.json, not the save, not a log. A refusal says bad_token and nothing
 * of the token; Google's keys out of reach is provider_unavailable, logged without the token.
 */
import type { FastifyInstance } from 'fastify';
import type { P0Store } from '../store.js';
import { identify, isRefusal, type IdentifyDeps } from './identify.js';
import { conflictFarm, liveOwner, signIn, type PendingSignIns } from './link.js';
import { IdTokenError, sha256Hex, verifyRs256, type KeySource } from './jwt.js';
import { tokenShapeOk, type GoogleLink, type P0Accounts } from './store.js';

export const GOOGLE_JWKS_URL = 'https://www.googleapis.com/oauth2/v3/certs';
const GOOGLE_ISSUERS = ['accounts.google.com', 'https://accounts.google.com'];

export interface GoogleVerifyOptions { audiences: string[]; keys: KeySource; refreshKeys?: KeySource; now: () => number; clockSkewS?: number }

/** A Google ID token's account number and aud, once Google signed it for one of our clients, it is in date and its
 *  nonce is this raw one's hash. Nothing else in it is read: not its email, name or picture. IdTokenError otherwise. */
export async function verifyGoogleIdToken(token: unknown, rawNonce: unknown, o: GoogleVerifyOptions): Promise<{ sub: string; aud: string }> {
  if (typeof rawNonce !== 'string' || rawNonce.length < 16 || rawNonce.length > 128) throw new IdTokenError('BAD_NONCE');
  const t = await verifyRs256(token, o.keys, o.refreshKeys);
  const nowS = Math.floor(o.now() / 1000), skew = o.clockSkewS ?? 60;
  if (typeof t.exp !== 'number' || t.exp <= nowS - skew) throw new IdTokenError('EXPIRED');
  if (typeof t.iat !== 'number' || t.iat > nowS + skew) throw new IdTokenError('ISSUED_IN_FUTURE');
  if (typeof t.iss !== 'string' || !GOOGLE_ISSUERS.includes(t.iss)) throw new IdTokenError('BAD_ISSUER');
  if (typeof t.aud !== 'string' || !o.audiences.includes(t.aud)) throw new IdTokenError('BAD_AUDIENCE');
  if (t.nonce !== sha256Hex(rawNonce)) throw new IdTokenError('BAD_NONCE');
  if (typeof t.sub !== 'string' || t.sub.length === 0 || t.sub.length > 255) throw new IdTokenError('BAD_SUBJECT');
  return { sub: t.sub, aud: t.aud };
}

export interface GoogleRouteDeps {
  store: P0Store; accounts: P0Accounts; identify: IdentifyDeps; now: () => number;
  /** The one PendingSignIns of p0_server (后裔's link.ts): no_farm's and conflict's pending sign-ins. */
  pending: PendingSignIns;
  /** config.google.audiences (GOOGLE_CLIENT_IDS): none, and Google sign-in answers provider_unavailable. */
  audiences: string[];
  /** Google's keys (a CachedJwks over googleIdJwksFetcher): `keys`, and `refreshKeys` for a kid not seen yet. */
  keys: KeySource; refreshKeys?: KeySource;
  /** The room hub's kick: a sign-in elsewhere closes the account's open socket (signIn). */
  kick?: (player: string) => void;
  warn?: (line: string) => void;
}

type Refused = { status: number; body: { ok: false; code: string } };
const refused = (status: number, code: string): Refused => ({ status, body: { ok: false, code } });
const bodyOf = (b: unknown) => (b && typeof b === 'object' && !Array.isArray(b) ? b : {}) as Record<string, unknown>;

/** The token's account number, or the refusal: the rest of what it carries goes no further than here. session/google's,
 *  and claim's for provider google (v1.4). */
export function googleVerifier(deps: Pick<GoogleRouteDeps, 'audiences' | 'keys' | 'refreshKeys' | 'now' | 'warn'>):
    (b: Record<string, unknown>) => Promise<GoogleLink | Refused> {
  const warn = deps.warn ?? ((line: string) => console.warn(line));
  return async b => {
    if (deps.audiences.length === 0) return refused(503, 'provider_unavailable');
    try {
      const id = await verifyGoogleIdToken(b.id_token, b.nonce,
        { audiences: deps.audiences, keys: deps.keys, refreshKeys: deps.refreshKeys, now: deps.now });
      return { sub: id.sub };
    } catch (e) {
      if (e instanceof IdTokenError) return refused(401, 'bad_token');
      warn(JSON.stringify({ google: 'provider_unavailable', error: e instanceof Error ? e.name : typeof e }));
      return refused(503, 'provider_unavailable');
    }
  };
}

export function registerGoogleRoutes(app: FastifyInstance, deps: GoogleRouteDeps): void {
  const { store, accounts } = deps;
  const verify = googleVerifier(deps);

  /** POST /v1/p0/session/google {id_token, nonce, token}, no identity: the linked farm signed in on this phone (its
   *  other phones' tokens revoked, contract §2), or no_farm {pending} for NAME's `Start a new farm` (guest takes it). */
  app.post('/v1/p0/session/google', async (req, reply) => {
    const b = bodyOf(req.body);
    if (!tokenShapeOk(b.token)) {
      const r = refused(400, typeof b.token === 'string' ? 'token_too_short' : 'schema');
      return reply.code(r.status).send(r.body);
    }
    const token = String(b.token).toLowerCase();
    const v = await verify(b);
    if ('status' in v) return reply.code(v.status).send(v.body);
    const player = liveOwner(store, accounts, 'google', v.sub, deps.now());
    if (player) {
      const owner = accounts.tokenOwner(token);
      if (owner && owner !== player) return reply.code(400).send({ ok: false, code: 'schema' });   // a token is one player's only
      return signIn({ accounts, kick: deps.kick }, player, token);
    }
    return reply.code(404).send({ ok: false, code: 'no_farm', pending: deps.pending.create('google', { sub: v.sub }) });
  });
}

/** Not registered in the first version (contract v1.4: switch and link cut — 「换个账号」 is sign out, sign in again); kept
 *  for a later one. */
export function registerGoogleLinkRoute(app: FastifyInstance, deps: GoogleRouteDeps): void {
  const { store, accounts } = deps;
  const verify = googleVerifier(deps);

  /** POST /v1/p0/account/link/google {id_token, nonce}: the farm in hand linked to this Google account; its token only
   *  (an old id alone could otherwise tie someone's farm to a stranger's Google for good). The same account again is
   *  done already; another Google account on this farm is already_linked; this one on another farm is conflict, with a
   *  pending for switch and that farm's line (q(306)). No unlink in the first version (q(314)). */
  app.post('/v1/p0/account/link/google', async (req, reply) => {
    const w = identify(req.headers, deps.identify);
    if (isRefusal(w)) return reply.code(w.status).send(w.body);
    if (w.via !== 'token') return reply.code(401).send({ ok: false, code: 'unauthenticated' });
    const v = await verify(bodyOf(req.body));
    if ('status' in v) return reply.code(v.status).send(v.body);
    const mine = accounts.find(w.player)?.google;
    if (mine) {
      if (mine.sub === v.sub) return { ok: true, linked: accounts.linked(w.player) };
      return reply.code(409).send({ ok: false, code: 'already_linked' });
    }
    const other = liveOwner(store, accounts, 'google', v.sub, deps.now());
    if (other && other !== w.player) {
      return reply.code(409).send({ ok: false, code: 'conflict', pending: deps.pending.create('google', { sub: v.sub }),
        farm: conflictFarm(store, other, deps.now()) });
    }
    accounts.link(w.player, 'google', { sub: v.sub });
    return { ok: true, linked: accounts.linked(w.player) };
  });
}
