/**
 * Sign in with Apple 令牌撤销（App Store 5.1.1(v)：删号时要撤销用户的 Apple 授权）。
 *
 * 登录时客户端带上一次性的 authorization code，我们用 .p8 私钥签的 client secret 换回
 * refresh token 存起来；删号时拿它调 /auth/revoke。换码或撤销失败都不挡登录与删号，
 * 只在墓碑里记 failed / pending 以便补做。
 */
import { createPrivateKey, sign, type KeyObject } from 'node:crypto';
import { readFileSync } from 'node:fs';

export const APPLE_TOKEN_URL = 'https://appleid.apple.com/auth/token';
export const APPLE_REVOKE_URL = 'https://appleid.apple.com/auth/revoke';

export interface AppleRevoker {
  /** 用 authorization code 换 refresh token；失败返回 null。 */
  exchange(code: string, clientId: string): Promise<string | null>;
  /** 撤销 refresh token；Apple 回 200 即成功。 */
  revoke(refreshToken: string, clientId: string): Promise<boolean>;
}

export interface AppleKeyConfig { teamId: string; keyId: string; privateKey: KeyObject }

const b64 = (o: unknown) => Buffer.from(JSON.stringify(o)).toString('base64url');

/** Apple 要求的 client secret：ES256 JWT，最长 6 个月；这里每次现签、5 分钟有效。 */
export function clientSecret(config: AppleKeyConfig, clientId: string, nowMs: number): string {
  const iat = Math.floor(nowMs / 1000);
  const head = b64({ alg: 'ES256', kid: config.keyId, typ: 'JWT' });
  const body = b64({ iss: config.teamId, iat, exp: iat + 300, aud: 'https://appleid.apple.com', sub: clientId });
  const signature = sign('sha256', Buffer.from(`${head}.${body}`), { key: config.privateKey, dsaEncoding: 'ieee-p1363' });
  return `${head}.${body}.${signature.toString('base64url')}`;
}

type Post = (url: string, form: Record<string, string>) => Promise<{ status: number; json: Record<string, unknown> }>;

const httpPost: Post = async (url, form) => {
  const res = await fetch(url, { method: 'POST', body: new URLSearchParams(form), signal: AbortSignal.timeout(15000),
    headers: { 'content-type': 'application/x-www-form-urlencoded' } });
  let json: Record<string, unknown> = {};
  try { json = await res.json() as Record<string, unknown>; } catch { /* revoke answers with an empty body */ }
  return { status: res.status, json };
};

export function createAppleRevoker(config: AppleKeyConfig, now: () => number, post: Post = httpPost): AppleRevoker {
  return {
    async exchange(code, clientId) {
      const r = await post(APPLE_TOKEN_URL, { client_id: clientId, client_secret: clientSecret(config, clientId, now()),
        code, grant_type: 'authorization_code' });
      return r.status === 200 && typeof r.json.refresh_token === 'string' ? r.json.refresh_token : null;
    },
    async revoke(refreshToken, clientId) {
      const r = await post(APPLE_REVOKE_URL, { client_id: clientId, client_secret: clientSecret(config, clientId, now()),
        token: refreshToken, token_type_hint: 'refresh_token' });
      return r.status === 200;
    },
  };
}

/** APPLE_KEY_ID + APPLE_PRIVATE_KEY_FILE（.p8）都配了才启用；APPLE_TEAM_ID 默认 Gensen。 */
export function appleRevokerFromEnv(env: NodeJS.ProcessEnv, now: () => number): AppleRevoker | undefined {
  if (!env.APPLE_KEY_ID || !env.APPLE_PRIVATE_KEY_FILE) return undefined;
  const privateKey = createPrivateKey(readFileSync(env.APPLE_PRIVATE_KEY_FILE, 'utf8'));
  return createAppleRevoker({ teamId: env.APPLE_TEAM_ID ?? 'XN4Z77ZX73', keyId: env.APPLE_KEY_ID, privateKey }, now);
}
