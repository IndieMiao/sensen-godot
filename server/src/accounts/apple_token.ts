/**
 * Sign in with Apple：校验 iOS 端 ASAuthorizationAppleIDCredential.identityToken（SGODOT-135）。
 *
 * 与 Firebase ID token 同一套 RS256 + JWKS 路子，只是签发方换成 Apple：
 * iss = https://appleid.apple.com、aud = App 的 bundle id、JWKS 在 /auth/keys。
 * 客户端把原始 nonce 发给我们，Apple 的 token 里装的是它的 SHA-256 十六进制；对得上才说明
 * 这个 token 是为这次请求取的，而不是别处截来的。
 */
import { createHash, verify as cryptoVerify } from 'node:crypto';
import { IdTokenError, googleJwksFetcher, type KeySource } from './firebase_token.js';

export const APPLE_ISSUER = 'https://appleid.apple.com';
export const APPLE_JWKS_URL = 'https://appleid.apple.com/auth/keys';
export const appleJwksFetcher = () => googleJwksFetcher(APPLE_JWKS_URL);

export interface AppleIdentity {
  sub: string;
  email?: string;
  emailVerified: boolean;
  /** Hide My Email 中继地址（privaterelay.appleid.com）。 */
  privateEmail: boolean;
  expiresAt: number;
}

export interface AppleVerifyOptions {
  /** 允许的 aud：iOS App 的 bundle id（多个包各自一个）。 */
  audiences: string[];
  keys: KeySource;
  refreshKeys?: KeySource;
  now: () => number;
  clockSkewS?: number;
  /** token 签发后多久内可用来登录，秒；默认 600。Apple 的 exp 是 10 分钟，这里再兜一层。 */
  maxAgeS?: number;
}

export const sha256Hex = (s: string) => createHash('sha256').update(s, 'utf8').digest('hex');
const b64urlJson = (s: string): unknown => JSON.parse(Buffer.from(s, 'base64url').toString('utf8'));
const isRecord = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null;
/** Apple 早期把布尔字段下发成字符串 "true"。 */
const truthy = (v: unknown) => v === true || v === 'true';

export async function verifyAppleIdToken(token: unknown, rawNonce: unknown, o: AppleVerifyOptions): Promise<AppleIdentity> {
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
  if (!cryptoVerify('sha256', Buffer.from(`${h}.${p}`, 'utf8'), key, Buffer.from(s, 'base64url')))
    throw new IdTokenError('BAD_SIGNATURE');

  const nowS = Math.floor(o.now() / 1000);
  const skew = o.clockSkewS ?? 60;
  const exp = typeof payload.exp === 'number' ? payload.exp : null;
  const iat = typeof payload.iat === 'number' ? payload.iat : null;
  if (exp === null || exp <= nowS - skew) throw new IdTokenError('EXPIRED');
  if (iat === null || iat > nowS + skew) throw new IdTokenError('ISSUED_IN_FUTURE');
  if (nowS - iat > (o.maxAgeS ?? 600) + skew) throw new IdTokenError('EXPIRED');
  if (payload.iss !== APPLE_ISSUER) throw new IdTokenError('BAD_ISSUER');
  if (typeof payload.aud !== 'string' || !o.audiences.includes(payload.aud)) throw new IdTokenError('BAD_AUDIENCE');
  if (payload.nonce !== sha256Hex(rawNonce)) throw new IdTokenError('BAD_NONCE');
  const sub = payload.sub;
  if (typeof sub !== 'string' || sub.length === 0 || sub.length > 128) throw new IdTokenError('BAD_SUBJECT');
  return {
    sub,
    email: typeof payload.email === 'string' ? payload.email : undefined,
    emailVerified: truthy(payload.email_verified),
    privateEmail: truthy(payload.is_private_email),
    expiresAt: exp,
  };
}
