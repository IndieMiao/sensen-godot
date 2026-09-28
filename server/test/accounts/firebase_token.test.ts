import { describe, expect, it } from 'vitest';
import type { KeyObject } from 'node:crypto';
import {
  CachedJwks, IdTokenError, JWKS_DEFAULT_TTL_S, JWKS_REFRESH_COOLDOWN_MS, jwksToKeys, parseMaxAge,
  verifyFirebaseIdToken,
} from '../../src/accounts/firebase_token.js';
import { PROJECT, idToken, makeKeys, signToken } from '../fixtures/firebase_tokens.js';

const NOW = Date.UTC(2026, 8, 7, 8, 0, 0);
const k = makeKeys();
const opts = { projectId: PROJECT, keys: k.keys, now: () => NOW };

const codeOf = async (p: Promise<unknown>): Promise<string> => {
  try { await p; return 'OK'; } catch (e) { return e instanceof IdTokenError ? e.code : `THROW:${String(e)}`; }
};

describe('verifyFirebaseIdToken', () => {
  it('合法 token 给出 uid / 邮箱 / 登录方式', async () => {
    const id = await verifyFirebaseIdToken(idToken(k, NOW, { email_verified: true }), opts);
    expect(id.uid).toBe('uid-1');
    expect(id.email).toBe('uid-1@example.test');
    expect(id.emailVerified).toBe(true);
    expect(id.signInProvider).toBe('password');
    expect(id.expiresAt).toBe(Math.floor(NOW / 1000) + 3600);
  });

  it('alg 不是 RS256 一律拒——none / HS256 是 JWT 史上最经典的洞', async () => {
    const claims = { iss: `https://securetoken.google.com/${PROJECT}`, aud: PROJECT, sub: 'u', iat: 1, exp: 9e9, auth_time: 1 };
    expect(await codeOf(verifyFirebaseIdToken(signToken(k, claims, { alg: 'none', kid: k.kid }, true), opts))).toBe('BAD_ALG');
    expect(await codeOf(verifyFirebaseIdToken(signToken(k, claims, { alg: 'HS256', kid: k.kid }), opts))).toBe('BAD_ALG');
    expect(await codeOf(verifyFirebaseIdToken(signToken(k, claims, { alg: 'RS256' }), opts))).toBe('BAD_ALG'); // 没 kid
  });

  it('kid 不在钥匙串里：先问 refreshKeys 一次，还没有才拒', async () => {
    const other = makeKeys('k2');
    expect(await codeOf(verifyFirebaseIdToken(idToken(other, NOW), opts))).toBe('UNKNOWN_KID');
    let refreshed = 0;
    const id = await verifyFirebaseIdToken(idToken(other, NOW), {
      ...opts, refreshKeys: async () => { refreshed += 1; return other.keys(); },
    });
    expect(id.uid).toBe('uid-1');
    expect(refreshed).toBe(1);
  });

  it('改过 payload 的 token 验签失败', async () => {
    const t = idToken(k, NOW);
    const [h, , s] = t.split('.');
    const forged = Buffer.from(JSON.stringify({ ...JSON.parse(Buffer.from(t.split('.')[1], 'base64url').toString()), sub: 'admin' })).toString('base64url');
    expect(await codeOf(verifyFirebaseIdToken(`${h}.${forged}.${s}`, opts))).toBe('BAD_SIGNATURE');
  });

  it('时间：过期拒、60 s 偏差内放行、iat / auth_time 在未来拒', async () => {
    const s = Math.floor(NOW / 1000);
    expect(await codeOf(verifyFirebaseIdToken(idToken(k, NOW, { exp: s - 61 }), opts))).toBe('EXPIRED');
    expect(await codeOf(verifyFirebaseIdToken(idToken(k, NOW, { exp: s - 30 }), opts))).toBe('OK');
    expect(await codeOf(verifyFirebaseIdToken(idToken(k, NOW, { iat: s + 120 }), opts))).toBe('ISSUED_IN_FUTURE');
    expect(await codeOf(verifyFirebaseIdToken(idToken(k, NOW, { auth_time: s + 120 }), opts))).toBe('ISSUED_IN_FUTURE');
    expect(await codeOf(verifyFirebaseIdToken(idToken(k, NOW, { exp: 'soon' }), opts))).toBe('EXPIRED');
  });

  it('aud / iss 必须是本项目；sub 非空且 ≤128', async () => {
    expect(await codeOf(verifyFirebaseIdToken(idToken(k, NOW, { aud: 'other-project' }), opts))).toBe('BAD_AUDIENCE');
    expect(await codeOf(verifyFirebaseIdToken(idToken(k, NOW, { iss: 'https://securetoken.google.com/other' }), opts))).toBe('BAD_ISSUER');
    expect(await codeOf(verifyFirebaseIdToken(idToken(k, NOW, { sub: '' }), opts))).toBe('BAD_SUBJECT');
    expect(await codeOf(verifyFirebaseIdToken(idToken(k, NOW, { sub: 'x'.repeat(129) }), opts))).toBe('BAD_SUBJECT');
  });

  it('不是三段 base64url JSON 的东西一律 MALFORMED，包括超长串', async () => {
    for (const bad of ['', 'abc', 'a.b', 'a.b.c', null, 42, 'x'.repeat(5000)])
      expect(await codeOf(verifyFirebaseIdToken(bad, opts))).toBe('MALFORMED');
  });
});

describe('CachedJwks', () => {
  const fetcherOf = (keys = [k.jwk], maxAgeS = 3600) => {
    const calls = { n: 0, fail: false };
    const f = async () => { calls.n += 1; if (calls.fail) throw new Error('down'); return { keys, maxAgeS }; };
    return { f, calls };
  };

  it('max-age 内复用缓存，过期后重新拉', async () => {
    let now = NOW;
    const { f, calls } = fetcherOf([k.jwk], 100);
    const c = new CachedJwks(f, () => now);
    expect((await c.keys()).has('k1')).toBe(true);
    await c.keys();
    expect(calls.n).toBe(1);
    now += 101_000;
    await c.keys();
    expect(calls.n).toBe(2);
  });

  it('没带 max-age 按默认 TTL；拉失败时沿用旧钥匙而不是全站 401', async () => {
    let now = NOW;
    const { f, calls } = fetcherOf([k.jwk], 0);
    const c = new CachedJwks(f, () => now);
    await c.keys();
    now += (JWKS_DEFAULT_TTL_S + 1) * 1000;
    calls.fail = true;
    expect((await c.keys()).has('k1')).toBe(true);
    expect(calls.n).toBe(2);
  });

  it('强制刷新有冷却：拿垃圾 kid 打我们的人不能借此打 Google', async () => {
    let now = NOW;
    const { f, calls } = fetcherOf();
    const c = new CachedJwks(f, () => now);
    await c.keys();
    await c.refresh();
    await c.refresh();
    expect(calls.n).toBe(2);
    now += JWKS_REFRESH_COOLDOWN_MS;
    await c.refresh();
    expect(calls.n).toBe(3);
  });

  it('并发首次拉取只发一次请求', async () => {
    const { f, calls } = fetcherOf();
    const c = new CachedJwks(f, () => NOW);
    const [a, b] = await Promise.all([c.keys(), c.keys()]);
    expect(a).toBe(b);
    expect(calls.n).toBe(1);
  });

  it('jwksToKeys 跳过非 RSA / 缺字段的条目；parseMaxAge 只认 max-age', () => {
    const m: Map<string, KeyObject> = jwksToKeys([k.jwk, { kid: 'ec', kty: 'EC' }, { kid: 'nope', kty: 'RSA' }]);
    expect([...m.keys()]).toEqual(['k1']);
    expect(parseMaxAge('public, max-age=22345, must-revalidate')).toBe(22345);
    expect(parseMaxAge('no-store')).toBe(0);
    expect(parseMaxAge(null)).toBe(0);
  });
});
