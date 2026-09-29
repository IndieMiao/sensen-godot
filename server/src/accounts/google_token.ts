/**
 * Sign in with Google：校验 Android Credential Manager 拿到的 Google ID token（2026-09-29）。
 *
 * RS256 + Google JWKS；iss 为 accounts.google.com（两种写法都合法），aud 为我们的 Web 客户端 ID
 * （Android 端用它请求 token，服务端据此认"是给我们签的"）。客户端把原始 nonce 发来，token 里
 * 的 nonce 是它的 SHA-256 十六进制（与 Apple 同一约定）。
 */
import { verify as cryptoVerify } from 'node:crypto';
import { IdTokenError, googleJwksFetcher, type KeySource } from './firebase_token.js';
import { sha256Hex } from './apple_token.js';

export const GOOGLE_JWKS_URL = 'https://www.googleapis.com/oauth2/v3/certs';
export const GOOGLE_ISSUERS = ['accounts.google.com', 'https://accounts.google.com'];
export const googleIdJwksFetcher = () => googleJwksFetcher(GOOGLE_JWKS_URL);

export interface GoogleIdentity { sub: string; aud: string; email?: string; emailVerified: boolean; givenName?: string; familyName?: string }

export interface GoogleVerifyOptions {
  audiences: string[];
  keys: KeySource;
  refreshKeys?: KeySource;
  now: () => number;
  clockSkewS?: number;
}

const b64urlJson = (s: string): unknown => JSON.parse(Buffer.from(s, 'base64url').toString('utf8'));
const isRecord = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null;

export async function verifyGoogleIdToken(token: unknown, rawNonce: unknown, o: GoogleVerifyOptions): Promise<GoogleIdentity> {
  if (typeof token !== 'string' || token.length > 4096) throw new IdTokenError('MALFORMED');
  if (typeof rawNonce !== 'string' || rawNonce.length < 16 || rawNonce.length > 128) throw new IdTokenError('BAD_NONCE');
  const parts = token.split('.');
  if (parts.length !== 3) throw new IdTokenError('MALFORMED');
  const [h, p, s] = parts;
  let header: unknown, payload: unknown;
  try { header = b64urlJson(h); payload = b64urlJson(p); } catch { throw new IdTokenError('MALFORMED'); }
  if (!isRecord(header) || !isRecord(payload)) throw new IdTokenError('MALFORMED');
  if (header.alg !== 'RS256' || typeof header.kid !== 'string') throw new IdTokenError('BAD_ALG');
  let key = (await o.keys()).get(header.kid);
  if (!key && o.refreshKeys) key = (await o.refreshKeys()).get(header.kid);
  if (!key) throw new IdTokenError('UNKNOWN_KID');
  if (!cryptoVerify('sha256', Buffer.from(`${h}.${p}`, 'utf8'), key, Buffer.from(s, 'base64url'))) throw new IdTokenError('BAD_SIGNATURE');
  const nowS = Math.floor(o.now() / 1000), skew = o.clockSkewS ?? 60;
  const exp = typeof payload.exp === 'number' ? payload.exp : null;
  const iat = typeof payload.iat === 'number' ? payload.iat : null;
  if (exp === null || exp <= nowS - skew) throw new IdTokenError('EXPIRED');
  if (iat === null || iat > nowS + skew) throw new IdTokenError('ISSUED_IN_FUTURE');
  if (typeof payload.iss !== 'string' || !GOOGLE_ISSUERS.includes(payload.iss)) throw new IdTokenError('BAD_ISSUER');
  if (typeof payload.aud !== 'string' || !o.audiences.includes(payload.aud)) throw new IdTokenError('BAD_AUDIENCE');
  if (payload.nonce !== sha256Hex(rawNonce)) throw new IdTokenError('BAD_NONCE');
  const sub = payload.sub;
  if (typeof sub !== 'string' || sub.length === 0 || sub.length > 255) throw new IdTokenError('BAD_SUBJECT');
  const str = (k: string) => (typeof payload[k] === 'string' ? payload[k] as string : undefined);
  return { sub, aud: payload.aud, email: str('email'), emailVerified: payload.email_verified === true || payload.email_verified === 'true',
    givenName: str('given_name'), familyName: str('family_name') };
}
