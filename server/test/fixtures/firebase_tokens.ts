/** 测试用 Firebase ID token：本地 RSA 密钥对签发，公钥以 JWKS 形式喂给校验器。 */
import { generateKeyPairSync, sign, type KeyObject } from 'node:crypto';
import type { Jwk } from '../../src/http/firebase_token.js';

export const PROJECT = 'gensen-test';

export interface TestKeys {
  kid: string;
  privateKey: KeyObject;
  publicKey: KeyObject;
  jwk: Jwk;
  keys: () => Promise<Map<string, KeyObject>>;
}

export function makeKeys(kid = 'k1'): TestKeys {
  const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const j = publicKey.export({ format: 'jwk' }) as { n: string; e: string };
  const map = new Map([[kid, publicKey]]);
  return {
    kid, privateKey, publicKey,
    jwk: { kid, kty: 'RSA', n: j.n, e: j.e, alg: 'RS256', use: 'sig' },
    keys: async () => map,
  };
}

const b64 = (o: unknown): string => Buffer.from(JSON.stringify(o)).toString('base64url');

export function signToken(
  k: TestKeys, claims: Record<string, unknown>,
  header: Record<string, unknown> = { alg: 'RS256', kid: k.kid, typ: 'JWT' },
  unsigned = false,
): string {
  const h = b64(header), p = b64(claims);
  if (unsigned) return `${h}.${p}.`;
  const sig = sign('sha256', Buffer.from(`${h}.${p}`, 'utf8'), k.privateKey).toString('base64url');
  return `${h}.${p}.${sig}`;
}

export function idToken(k: TestKeys, nowMs: number, over: Record<string, unknown> = {}, uid = 'uid-1'): string {
  const nowS = Math.floor(nowMs / 1000);
  return signToken(k, {
    iss: `https://securetoken.google.com/${PROJECT}`, aud: PROJECT, sub: uid, user_id: uid,
    iat: nowS - 10, exp: nowS + 3600, auth_time: nowS - 10,
    email: `${uid}@example.test`, email_verified: false,
    firebase: { sign_in_provider: 'password', identities: {} },
    ...over,
  });
}
