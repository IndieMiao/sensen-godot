/**
 * The sign-in providers' ID tokens, P0's own (SGODOT-489 PR-B): the P0 server leans on none of Journey's code
 * (SGODOT-304, p0_own_imports.test.ts), so this is its copy of what Journey's src/accounts token checks share — the
 * providers' keys fetched and cached (JWKS), and an RS256 JWT's header and signature checked. Each provider then checks
 * its own claims: Google's in google.ts, Apple's in 后裔's apple.ts. Nothing here logs or keeps a token.
 */
import { createHash, createPublicKey, verify as cryptoVerify, type KeyObject } from 'node:crypto';

/** Why a token was refused, for tests and a log's reason; the client is told only bad_token (contract §0). */
export class IdTokenError extends Error {
  constructor(public readonly code: string) { super(code); this.name = 'IdTokenError'; }
}

export type KeySource = () => Promise<Map<string, KeyObject>>;
export interface Jwk { kid: string; kty: string; n?: string; e?: string; alg?: string; use?: string }
export interface JwksFetchResult { keys: Jwk[]; maxAgeS: number }
export type JwksFetcher = () => Promise<JwksFetchResult>;

export const JWKS_DEFAULT_TTL_S = 300;
export const JWKS_REFRESH_COOLDOWN_MS = 60_000;

export const sha256Hex = (s: string): string => createHash('sha256').update(s, 'utf8').digest('hex');

/**
 * A provider's keys, kept as long as its Cache-Control max-age says. `keys` for each check; `refresh` when a token
 * names a kid not held (the provider rolled its keys), at most once a minute. Keys that cannot be fetched again leave
 * the old ones in use (a provider's rollover overlaps): only with none at all does the fetch's error reach the caller.
 */
export class CachedJwks {
  private cache?: { keys: Map<string, KeyObject>; expiresAt: number };
  private inflight?: Promise<Map<string, KeyObject>>;
  private lastForcedRefresh = -Infinity;
  fetches = 0;

  constructor(private readonly fetcher: JwksFetcher, private readonly now: () => number = Date.now) {}

  keys: KeySource = async () => {
    if (this.cache && this.cache.expiresAt > this.now()) return this.cache.keys;
    return this.load();
  };

  refresh: KeySource = async () => {
    if (this.now() - this.lastForcedRefresh < JWKS_REFRESH_COOLDOWN_MS) return this.cache?.keys ?? new Map();
    this.lastForcedRefresh = this.now();
    return this.load();
  };

  private load(): Promise<Map<string, KeyObject>> {
    if (this.inflight) return this.inflight;
    this.inflight = (async () => {
      try {
        this.fetches += 1;
        const r = await this.fetcher();
        const keys = jwksToKeys(r.keys);
        this.cache = { keys, expiresAt: this.now() + (r.maxAgeS > 0 ? r.maxAgeS : JWKS_DEFAULT_TTL_S) * 1000 };
        return keys;
      } catch (e) {
        if (this.cache) return this.cache.keys;
        throw e;
      } finally {
        this.inflight = undefined;
      }
    })();
    return this.inflight;
  }
}

/** The RSA keys of a JWKS by kid; an entry that is not one is skipped, never the set. */
export function jwksToKeys(jwks: Jwk[]): Map<string, KeyObject> {
  const out = new Map<string, KeyObject>();
  for (const k of jwks) {
    if (k.kty !== 'RSA' || typeof k.kid !== 'string' || !k.n || !k.e) continue;
    try { out.set(k.kid, createPublicKey({ key: { kty: 'RSA', n: k.n, e: k.e }, format: 'jwk' })); } catch { /* skip it */ }
  }
  return out;
}

export function parseMaxAge(cacheControl: string | null | undefined): number {
  const m = /max-age=(\d+)/i.exec(cacheControl ?? '');
  return m ? Number(m[1]) : 0;
}

/** A provider's JWKS over Node's fetch (Google: https://www.googleapis.com/oauth2/v3/certs). */
export const jwksFetcher = (url: string): JwksFetcher => async () => {
  const res = await fetch(url, { headers: { accept: 'application/json' } });
  if (!res.ok) throw new Error(`JWKS ${url}: ${res.status}`);
  const body = await res.json() as { keys?: Jwk[] };
  return { keys: Array.isArray(body.keys) ? body.keys : [], maxAgeS: parseMaxAge(res.headers.get('cache-control')) };
};

const b64urlJson = (s: string): unknown => JSON.parse(Buffer.from(s, 'base64url').toString('utf8'));
const isRecord = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null;

/**
 * An RS256 JWT's claims once its header (alg RS256, a kid) and signature hold, on `keys` or, for a kid not held,
 * `refreshKeys`. The claims themselves (iss, aud, exp, nonce …) are the provider's to check. IdTokenError when it
 * fails; a key fetch's own error when there are no keys to check with (provider_unavailable to the caller).
 */
export async function verifyRs256(token: unknown, keys: KeySource, refreshKeys?: KeySource): Promise<Record<string, unknown>> {
  if (typeof token !== 'string' || token.length > 4096) throw new IdTokenError('MALFORMED');
  const parts = token.split('.');
  if (parts.length !== 3) throw new IdTokenError('MALFORMED');
  const [h, p, s] = parts;
  let header: unknown, payload: unknown;
  try { header = b64urlJson(h); payload = b64urlJson(p); } catch { throw new IdTokenError('MALFORMED'); }
  if (!isRecord(header) || !isRecord(payload)) throw new IdTokenError('MALFORMED');
  if (header.alg !== 'RS256' || typeof header.kid !== 'string') throw new IdTokenError('BAD_ALG');
  let key = (await keys()).get(header.kid);
  if (!key && refreshKeys) key = (await refreshKeys()).get(header.kid);
  if (!key) throw new IdTokenError('UNKNOWN_KID');
  if (!cryptoVerify('sha256', Buffer.from(`${h}.${p}`, 'utf8'), key, Buffer.from(s, 'base64url'))) throw new IdTokenError('BAD_SIGNATURE');
  return payload;
}
