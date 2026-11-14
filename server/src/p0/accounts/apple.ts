/**
 * Sign in with Apple for P0 accounts (SGODOT-489 PR-B; contract-accounts.md §2, 后裔): session/apple finds the farm an
 * Apple ID is linked to (or a pending sign-in for NAME's new farm). The ID token is checked on P0's own JWT code
 * (jwt.ts, SGODOT-304): RS256 on Apple's keys, iss https://appleid.apple.com, aud one of APPLE_BUNDLE_IDS (the app's;
 * the web page's Services ID only for web-delete), in date, its nonce the SHA-256 hex of the raw one sent beside it.
 * The authorization code is spent once for a refresh token (kept sealed, for revoking at deletion: tech-plan §1.2),
 * with a client secret signed by the team's key (ES256, APPLE_KEY_ID / APPLE_PRIVATE_KEY_FILE).
 *
 * Only the account number is kept; the email and name Apple may put in its first token are never read nor written.
 */
import { createPrivateKey, sign as cryptoSign, type KeyObject } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import type { P0Store } from '../store.js';
import type { AppleConfig } from './config.js';
import { IdTokenError, sha256Hex, verifyRs256, type KeySource } from './jwt.js';
import { liveOwner, signIn, type PendingSignIns } from './link.js';
import { tokenShapeOk, type AppleLink, type P0Accounts } from './store.js';

export const APPLE_JWKS_URL = 'https://appleid.apple.com/auth/keys';
export const APPLE_ISSUER = 'https://appleid.apple.com';
export const APPLE_TOKEN_URL = 'https://appleid.apple.com/auth/token';
export const APPLE_REVOKE_URL = 'https://appleid.apple.com/auth/revoke';

export interface AppleVerifyOptions { audiences: string[]; keys: KeySource; refreshKeys?: KeySource; now: () => number; clockSkewS?: number }

/** An Apple ID token's account number and aud, once Apple signed it for one of `audiences`, it is in date and its
 *  nonce is this raw one's hash. Nothing else in it is read. IdTokenError otherwise. */
export async function verifyAppleIdToken(token: unknown, rawNonce: unknown, o: AppleVerifyOptions): Promise<{ sub: string; aud: string }> {
  if (typeof rawNonce !== 'string' || rawNonce.length < 16 || rawNonce.length > 128) throw new IdTokenError('BAD_NONCE');
  const t = await verifyRs256(token, o.keys, o.refreshKeys);
  const nowS = Math.floor(o.now() / 1000), skew = o.clockSkewS ?? 60;
  if (typeof t.exp !== 'number' || t.exp <= nowS - skew) throw new IdTokenError('EXPIRED');
  if (typeof t.iat !== 'number' || t.iat > nowS + skew) throw new IdTokenError('ISSUED_IN_FUTURE');
  if (t.iss !== APPLE_ISSUER) throw new IdTokenError('BAD_ISSUER');
  if (typeof t.aud !== 'string' || !o.audiences.includes(t.aud)) throw new IdTokenError('BAD_AUDIENCE');
  if (typeof t.nonce !== 'string' || t.nonce.toLowerCase() !== sha256Hex(rawNonce)) throw new IdTokenError('BAD_NONCE');
  if (typeof t.sub !== 'string' || t.sub.length === 0 || t.sub.length > 255) throw new IdTokenError('BAD_SUBJECT');
  return { sub: t.sub, aud: t.aud };
}

/** The client secret Apple's token and revoke endpoints take: a JWT the team's key signs (ES256), five minutes long. */
export function appleClientSecret(c: Pick<AppleConfig, 'teamId' | 'keyId'>, key: KeyObject, clientId: string, now: number): string {
  const b64 = (v: object) => Buffer.from(JSON.stringify(v)).toString('base64url');
  const iat = Math.floor(now / 1000);
  const body = `${b64({ alg: 'ES256', kid: c.keyId })}.${b64({ iss: c.teamId, iat, exp: iat + 300, aud: APPLE_ISSUER, sub: clientId })}`;
  const sig = cryptoSign('sha256', Buffer.from(body), { key, dsaEncoding: 'ieee-p1363' });
  return `${body}.${sig.toString('base64url')}`;
}

/** A form POST to Apple (Node's fetch; a test's stand-in), its JSON or null. */
export type ApplePost = (url: string, form: Record<string, string>) => Promise<{ status: number; json: Record<string, unknown> | null }>;
export const applePost: ApplePost = async (url, form) => {
  // 10 s at most (周瑜 on #1048): a sign-in's code exchange or a deletion's revoke never hangs its request on Apple
  const res = await fetch(url, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams(form),
    signal: AbortSignal.timeout(10_000) });
  const text = await res.text();
  let json: Record<string, unknown> | null = null;
  try { json = text ? JSON.parse(text) as Record<string, unknown> : null; } catch { json = null; }
  return { status: res.status, json };
};

/** Apple's code exchange and revoke, for one aud (the app's or the web page's): the team's key read once. */
export class AppleClient {
  private key?: KeyObject;
  constructor(private c: AppleConfig, private keyText: () => string, private post: ApplePost = applePost, private now: () => number = Date.now) {}
  private secret(clientId: string): string {
    this.key ??= createPrivateKey(this.keyText());
    return appleClientSecret(this.c, this.key, clientId, this.now());
  }
  /** The refresh token for an authorization code (spent once, about five minutes long); null when Apple says no. */
  async refreshFor(code: string, clientId: string): Promise<string | null> {
    const r = await this.post(APPLE_TOKEN_URL, { client_id: clientId, client_secret: this.secret(clientId), code, grant_type: 'authorization_code' });
    return r.status === 200 && typeof r.json?.refresh_token === 'string' ? r.json.refresh_token : null;
  }
  /** The app's authorization on that Apple ID withdrawn (deletion, a pending sign-in left unused). */
  async revoke(clientId: string, refresh: string): Promise<void> {
    const r = await this.post(APPLE_REVOKE_URL, { client_id: clientId, client_secret: this.secret(clientId), token: refresh, token_type_hint: 'refresh_token' });
    if (r.status !== 200) throw new Error(`APPLE_REVOKE_${r.status}`);
  }
}

export interface AppleRouteDeps {
  store: P0Store; accounts: P0Accounts; now: () => number;
  pending: PendingSignIns;
  /** config.apple (null: Apple sign-in off, provider_unavailable). */
  apple: AppleConfig | null;
  client: Pick<AppleClient, 'refreshFor'> | null;
  keys: KeySource; refreshKeys?: KeySource;
  kick?: (player: string) => void;
  warn?: (line: string) => void;
}

export type Refused = { status: number; body: { ok: false; code: string } };
const refused = (status: number, code: string): Refused => ({ status, body: { ok: false, code } });
export const bodyOf = (b: unknown) => (b && typeof b === 'object' && !Array.isArray(b) ? b : {}) as Record<string, unknown>;

/** The Apple link a sign-in brings — the account number, its aud, and a refresh token when a code came and was good —
 *  or the refusal. session/apple's, and claim's for provider apple (v1.4). */
export function appleVerifier(deps: Pick<AppleRouteDeps, 'apple' | 'client' | 'keys' | 'refreshKeys' | 'now' | 'warn'>):
    (b: Record<string, unknown>) => Promise<AppleLink | Refused> {
  const warn = deps.warn ?? ((line: string) => console.warn(line));
  return async b => {
    if (!deps.apple) return refused(503, 'provider_unavailable');
    let id: { sub: string; aud: string };
    try {
      id = await verifyAppleIdToken(b.id_token, b.nonce, { audiences: deps.apple.bundleIds, keys: deps.keys, refreshKeys: deps.refreshKeys, now: deps.now });
    } catch (e) {
      if (e instanceof IdTokenError) return refused(401, 'bad_token');
      warn(JSON.stringify({ apple: 'provider_unavailable', error: e instanceof Error ? e.name : typeof e }));
      return refused(503, 'provider_unavailable');
    }
    let refresh: string | undefined;
    if (typeof b.auth_code === 'string' && b.auth_code.length > 0 && b.auth_code.length < 1024 && deps.client) {
      try { refresh = (await deps.client.refreshFor(b.auth_code, id.aud)) ?? undefined; }
      catch (e) { warn(JSON.stringify({ apple: 'code_exchange_failed', error: e instanceof Error ? e.name : typeof e })); }
    }
    return { sub: id.sub, aud: id.aud, ...(refresh ? { refresh } : {}) };
  };
}

export function registerAppleRoutes(app: FastifyInstance, deps: AppleRouteDeps): void {
  const { store, accounts } = deps;
  const verify = appleVerifier(deps);

  /** POST /v1/p0/session/apple {id_token, nonce, auth_code?, token}, no identity: the linked farm signed in on this phone
   *  (its other phones' tokens revoked), or no_farm {pending} for NAME's new farm. A new refresh token replaces the kept
   *  one (the last authorization is the one deletion revokes). */
  app.post('/v1/p0/session/apple', async (req, reply) => {
    const b = bodyOf(req.body);
    if (!tokenShapeOk(b.token)) {
      const r = refused(400, typeof b.token === 'string' ? 'token_too_short' : 'schema');
      return reply.code(r.status).send(r.body);
    }
    const token = String(b.token).toLowerCase();
    const v = await verify(b);
    if ('status' in v) return reply.code(v.status).send(v.body);
    // after the last await: the check and the writes below in one stretch (§1.3)
    const player = liveOwner(store, accounts, 'apple', v.sub, deps.now());
    if (player) {
      const owner = accounts.tokenOwner(token);
      if (owner && owner !== player) return reply.code(400).send({ ok: false, code: 'schema' });   // a token is one player's only
      if (v.refresh) accounts.link(player, 'apple', v);
      return signIn({ accounts, kick: deps.kick }, player, token);
    }
    return reply.code(404).send({ ok: false, code: 'no_farm', pending: deps.pending.create('apple', v) });
  });
}
