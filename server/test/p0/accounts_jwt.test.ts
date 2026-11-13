/** P0's own ID token checks (SGODOT-489 PR-B; SGODOT-304: none of Journey's code): the JWKS cache, the RS256 header and
 *  signature (jwt.ts), and Google's claims (google.ts) — its account number and aud read, nothing else. */
import { describe, expect, it } from 'vitest';
import { verifyGoogleIdToken } from '../../src/p0/accounts/google.js';
import { CachedJwks, JWKS_DEFAULT_TTL_S, JWKS_REFRESH_COOLDOWN_MS, jwksToKeys, parseMaxAge, sha256Hex, verifyRs256 } from '../../src/p0/accounts/jwt.js';
import { makeKeys, signToken } from '../fixtures/firebase_tokens.js';

const NOW = Date.UTC(2026, 10, 13, 6);
const NONCE = 'g'.repeat(43);
const WEB = 'web-client.apps.googleusercontent.com';
const k = makeKeys('google-1');
const claims = (over: Record<string, unknown> = {}) => {
  const s = Math.floor(NOW / 1000);
  return { iss: 'https://accounts.google.com', aud: WEB, sub: '1234567890', iat: s - 5, exp: s + 3600, nonce: sha256Hex(NONCE),
    email: 'ada@gmail.com', email_verified: true, name: 'Ada L', picture: 'https://lh3.example/a.jpg', ...over };
};
const opts = { audiences: [WEB], keys: k.keys, now: () => NOW };
const code = (token: unknown, nonce: unknown = NONCE, o = opts) => verifyGoogleIdToken(token, nonce, o).then(() => 'ok', (e: { code: string }) => e.code);

describe("Google's ID token (google.ts)", () => {
  it('both issuer spellings; the account number and aud back, nothing else of it', async () => {
    expect(await verifyGoogleIdToken(signToken(k, claims()), NONCE, opts)).toEqual({ sub: '1234567890', aud: WEB });
    expect(await code(signToken(k, claims({ iss: 'accounts.google.com' })))).toBe('ok');
  });
  it('refuses another audience or issuer, another nonce, a short raw nonce, out of date, no subject', async () => {
    const s = Math.floor(NOW / 1000);
    expect(await code(signToken(k, claims({ aud: 'someone-else' })))).toBe('BAD_AUDIENCE');
    expect(await code(signToken(k, claims({ iss: 'https://evil.example' })))).toBe('BAD_ISSUER');
    expect(await code(signToken(k, claims()), 'h'.repeat(43))).toBe('BAD_NONCE');
    expect(await code(signToken(k, claims()), 'short')).toBe('BAD_NONCE');
    expect(await code(signToken(k, claims({ exp: s - 120 })))).toBe('EXPIRED');
    expect(await code(signToken(k, claims({ exp: s - 30 })))).toBe('ok');   // 60 s of clock skew
    expect(await code(signToken(k, claims({ iat: s + 120 })))).toBe('ISSUED_IN_FUTURE');
    expect(await code(signToken(k, claims({ sub: '' })))).toBe('BAD_SUBJECT');
  });
});

describe('an RS256 JWT (jwt.ts)', () => {
  it('only RS256 with a kid: none and HS256 are refused', async () => {
    const r = (t: string) => verifyRs256(t, k.keys).then(() => 'ok', (e: { code: string }) => e.code);
    expect(await r(signToken(k, claims(), { alg: 'none', kid: k.kid }, true))).toBe('BAD_ALG');
    expect(await r(signToken(k, claims(), { alg: 'HS256', kid: k.kid }))).toBe('BAD_ALG');
    expect(await r(signToken(k, claims(), { alg: 'RS256' }))).toBe('BAD_ALG');
  });
  it('a kid not held: refreshKeys asked once, then UNKNOWN_KID', async () => {
    const other = makeKeys('rolled');
    let asked = 0;
    const refresh = async () => { asked += 1; return new Map([[other.kid, other.publicKey]]); };
    expect(await verifyRs256(signToken(other, claims()), k.keys, refresh)).toMatchObject({ sub: '1234567890' });
    expect(asked).toBe(1);
    await expect(verifyRs256(signToken(makeKeys('nobody'), claims()), k.keys, refresh)).rejects.toMatchObject({ code: 'UNKNOWN_KID' });
  });
  it('a changed payload fails the signature; anything not three base64url JSON parts is MALFORMED', async () => {
    const t = signToken(k, claims());
    const [h, , s] = t.split('.');
    const forged = Buffer.from(JSON.stringify({ ...claims(), sub: 'someone' })).toString('base64url');
    await expect(verifyRs256(`${h}.${forged}.${s}`, k.keys)).rejects.toMatchObject({ code: 'BAD_SIGNATURE' });
    for (const bad of ['a.b', 'a.b.c', 7, undefined, 'x'.repeat(5000)]) await expect(verifyRs256(bad, k.keys)).rejects.toMatchObject({ code: 'MALFORMED' });
  });
});

describe('the JWKS cache (jwt.ts)', () => {
  const fetcherOf = (keys = [k.jwk], maxAgeS = 300) => {
    const calls = { n: 0, fail: false };
    const f = async () => { calls.n += 1; if (calls.fail) throw new Error('down'); return { keys, maxAgeS }; };
    return { f, calls };
  };
  it('kept for max-age, then fetched again', async () => {
    let now = NOW;
    const { f, calls } = fetcherOf([k.jwk], 100);
    const c = new CachedJwks(f, () => now);
    expect((await c.keys()).has('google-1')).toBe(true);
    await c.keys();
    expect(calls.n).toBe(1);
    now += 101_000;
    await c.keys();
    expect(calls.n).toBe(2);
  });
  it('no max-age: the default; a failed fetch keeps the old keys; none at all: the error goes up', async () => {
    let now = NOW;
    const { f, calls } = fetcherOf([k.jwk], 0);
    const c = new CachedJwks(f, () => now);
    await c.keys();
    now += (JWKS_DEFAULT_TTL_S + 1) * 1000;
    calls.fail = true;
    expect((await c.keys()).has('google-1')).toBe(true);
    const cold = fetcherOf();
    cold.calls.fail = true;
    await expect(new CachedJwks(cold.f, () => NOW).keys()).rejects.toThrow('down');
  });
  it('a forced refresh at most once a minute, and one fetch for two at once', async () => {
    let now = NOW;
    const { f, calls } = fetcherOf();
    const c = new CachedJwks(f, () => now);
    const [a, b] = await Promise.all([c.keys(), c.keys()]);
    expect(a).toBe(b);
    await c.refresh();
    await c.refresh();
    expect(calls.n).toBe(2);
    now += JWKS_REFRESH_COOLDOWN_MS;
    await c.refresh();
    expect(calls.n).toBe(3);
  });
  it('jwksToKeys skips what is not an RSA key; parseMaxAge reads max-age only', () => {
    expect([...jwksToKeys([k.jwk, { kid: 'ec', kty: 'EC' }, { kid: 'half', kty: 'RSA', n: 'AQAB' }]).keys()]).toEqual(['google-1']);
    expect(parseMaxAge('public, max-age=21325, must-revalidate')).toBe(21325);
    expect(parseMaxAge('no-store')).toBe(0);
    expect(parseMaxAge(null)).toBe(0);
  });
});
