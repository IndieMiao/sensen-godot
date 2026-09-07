/**
 * Firebase ID token 校验（D2 / SGODOT-76）。
 *
 * 不引 firebase-admin：它要服务账号私钥外加一大坨依赖，而校验一个 RS256 JWT 只需要
 * Node 自带的 crypto 和 Google 公开的 JWKS。规则照 Firebase 文档
 * 「Verify ID tokens using a third-party JWT library」逐条：alg 必须是 RS256、kid 必须在
 * JWKS 里、exp 未过、iat / auth_time 不在未来、aud 等于项目 id、iss 等于
 * https://securetoken.google.com/<项目 id>、sub 非空且不超过 128 字符。
 *
 * 服务端**每个请求**都校验 ID token，不另发自己的会话 token：RSA 验签在缓存了公钥之后
 * 只是几十微秒，换来的是没有第二套 token 生命周期要管，客户端也不用改 Bearer 的传法。
 * 撤销靠删号：用户行没了，再有效的 token 也查不到人。
 */
import { createPublicKey, verify as cryptoVerify, type KeyObject } from 'node:crypto';

export const FIREBASE_JWKS_URL =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';

export interface FirebaseIdentity {
  uid: string;
  email?: string;
  emailVerified: boolean;
  /** 'password' | 'google.com' | 'apple.com' | …，来自 `firebase.sign_in_provider`。 */
  signInProvider?: string;
  /** 秒。 */
  authTime: number;
  /** 秒。 */
  expiresAt: number;
}

export type KeySource = () => Promise<Map<string, KeyObject>>;

export interface VerifyOptions {
  projectId: string;
  keys: KeySource;
  /** kid 不认识时可要求刷新一次公钥（Google 轮换密钥后旧缓存会落后）。 */
  refreshKeys?: KeySource;
  /** 毫秒。 */
  now: () => number;
  /** 允许的时钟偏差，秒；默认 60。 */
  clockSkewS?: number;
}

export class IdTokenError extends Error {
  constructor(public readonly code: string, message?: string) {
    super(message ?? code);
    this.name = 'IdTokenError';
  }
}

const b64urlJson = (s: string): unknown => JSON.parse(Buffer.from(s, 'base64url').toString('utf8'));
const isRecord = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null;

export async function verifyFirebaseIdToken(token: unknown, o: VerifyOptions): Promise<FirebaseIdentity> {
  if (typeof token !== 'string' || token.length > 4096) throw new IdTokenError('MALFORMED');
  const parts = token.split('.');
  if (parts.length !== 3) throw new IdTokenError('MALFORMED');
  const [h, p, s] = parts;
  let header: unknown, payload: unknown;
  try { header = b64urlJson(h); payload = b64urlJson(p); } catch { throw new IdTokenError('MALFORMED'); }
  if (!isRecord(header) || !isRecord(payload)) throw new IdTokenError('MALFORMED');
  // alg 白名单在验签**之前**：接受 none / HS256 的校验器是 JWT 史上最经典的漏洞。
  if (header.alg !== 'RS256' || typeof header.kid !== 'string') throw new IdTokenError('BAD_ALG');

  let key = (await o.keys()).get(header.kid);
  if (!key && o.refreshKeys) key = (await o.refreshKeys()).get(header.kid);
  if (!key) throw new IdTokenError('UNKNOWN_KID');
  const ok = cryptoVerify('sha256', Buffer.from(`${h}.${p}`, 'utf8'), key, Buffer.from(s, 'base64url'));
  if (!ok) throw new IdTokenError('BAD_SIGNATURE');

  const nowS = Math.floor(o.now() / 1000);
  const skew = o.clockSkewS ?? 60;
  const num = (k: string): number | null => (typeof payload[k] === 'number' ? (payload[k] as number) : null);
  const exp = num('exp'), iat = num('iat'), authTime = num('auth_time');
  if (exp === null || exp <= nowS - skew) throw new IdTokenError('EXPIRED');
  if (iat === null || iat > nowS + skew) throw new IdTokenError('ISSUED_IN_FUTURE');
  if (authTime === null || authTime > nowS + skew) throw new IdTokenError('ISSUED_IN_FUTURE');
  if (payload.aud !== o.projectId) throw new IdTokenError('BAD_AUDIENCE');
  if (payload.iss !== `https://securetoken.google.com/${o.projectId}`) throw new IdTokenError('BAD_ISSUER');
  const sub = payload.sub;
  if (typeof sub !== 'string' || sub.length === 0 || sub.length > 128) throw new IdTokenError('BAD_SUBJECT');

  const fb = isRecord(payload.firebase) ? payload.firebase : {};
  return {
    uid: sub,
    email: typeof payload.email === 'string' ? payload.email : undefined,
    emailVerified: payload.email_verified === true,
    signInProvider: typeof fb.sign_in_provider === 'string' ? fb.sign_in_provider : undefined,
    authTime, expiresAt: exp,
  };
}

// —— JWKS 缓存 ——

export interface Jwk { kid: string; kty: string; n?: string; e?: string; alg?: string; use?: string }
export interface JwksFetchResult { keys: Jwk[]; maxAgeS: number }
export type JwksFetcher = () => Promise<JwksFetchResult>;

/** 默认缓存时长：Google 的响应通常带 max-age（几小时）；没带就按 5 分钟。 */
export const JWKS_DEFAULT_TTL_S = 300;
/** 未知 kid 触发的强制刷新最少间隔：拿垃圾 kid 打我们的人不能借此打 Google。 */
export const JWKS_REFRESH_COOLDOWN_MS = 60_000;

export class CachedJwks {
  private cache?: { keys: Map<string, KeyObject>; expiresAt: number };
  private inflight?: Promise<Map<string, KeyObject>>;
  private lastForcedRefresh = -Infinity;
  fetches = 0;

  constructor(private readonly fetcher: JwksFetcher, private readonly now: () => number) {}

  keys: KeySource = async () => {
    if (this.cache && this.cache.expiresAt > this.now()) return this.cache.keys;
    return this.load();
  };

  /** 未知 kid 时的强制刷新；冷却期内直接返回现有缓存。 */
  refresh: KeySource = async () => {
    if (this.now() - this.lastForcedRefresh < JWKS_REFRESH_COOLDOWN_MS)
      return this.cache?.keys ?? new Map();
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
        const ttl = r.maxAgeS > 0 ? r.maxAgeS : JWKS_DEFAULT_TTL_S;
        this.cache = { keys, expiresAt: this.now() + ttl * 1000 };
        return keys;
      } catch (e) {
        // 拉不到新钥匙时宁可用过期的旧钥匙也不要让全站 401：Google 密钥轮换有重叠期。
        if (this.cache) return this.cache.keys;
        throw e;
      } finally {
        this.inflight = undefined;
      }
    })();
    return this.inflight;
  }
}

export function jwksToKeys(jwks: Jwk[]): Map<string, KeyObject> {
  const out = new Map<string, KeyObject>();
  for (const k of jwks) {
    if (k.kty !== 'RSA' || typeof k.kid !== 'string' || !k.n || !k.e) continue;
    try {
      out.set(k.kid, createPublicKey({ key: { kty: 'RSA', n: k.n, e: k.e }, format: 'jwk' }));
    } catch { /* 坏条目跳过，不让一把坏钥匙拖垮整组 */ }
  }
  return out;
}

export function parseMaxAge(cacheControl: string | null | undefined): number {
  const m = /max-age=(\d+)/i.exec(cacheControl ?? '');
  return m ? Number(m[1]) : 0;
}

/** 走 Node 22 的全局 fetch 拉 Google JWKS。 */
export const googleJwksFetcher = (url = FIREBASE_JWKS_URL): JwksFetcher => async () => {
  const res = await fetch(url, { headers: { accept: 'application/json' } });
  if (!res.ok) throw new Error(`JWKS ${url} 返回 ${res.status}`);
  const body = await res.json() as { keys?: Jwk[] };
  return { keys: Array.isArray(body.keys) ? body.keys : [], maxAgeS: parseMaxAge(res.headers.get('cache-control')) };
};
