import { describe, expect, it } from 'vitest';
import { makeKeys, signToken } from '../fixtures/firebase_tokens.js';
import { sha256Hex, verifyAppleIdToken } from '../../src/accounts/apple_token.js';

const NOW = Date.UTC(2026, 8, 28, 2);
const NONCE = 'n'.repeat(32);
const k = makeKeys('apple-1');
const claims = (over: Record<string, unknown> = {}) => {
  const s = Math.floor(NOW / 1000);
  return { iss: 'https://appleid.apple.com', aud: 'app.gensen.maps', sub: '001234.abcd', iat: s - 5, exp: s + 600,
    nonce: sha256Hex(NONCE), email: 'x@privaterelay.appleid.com', email_verified: 'true', is_private_email: 'true', ...over };
};
const opts = { audiences: ['app.gensen.maps'], keys: k.keys, now: () => NOW };
const code = async (token: string, nonce: unknown = NONCE, o = opts) =>
  verifyAppleIdToken(token, nonce, o).then(() => 'ok', (e: { code: string }) => e.code);

describe('verifyAppleIdToken', () => {
  it('accepts a fresh token and reads string booleans', async () => {
    const id = await verifyAppleIdToken(signToken(k, claims()), NONCE, opts);
    expect(id).toMatchObject({ sub: '001234.abcd', emailVerified: true, privateEmail: true });
  });
  it('rejects a mismatched nonce, audience, issuer or algorithm', async () => {
    expect(await code(signToken(k, claims()), 'm'.repeat(32))).toBe('BAD_NONCE');
    expect(await code(signToken(k, claims()), 'short')).toBe('BAD_NONCE');
    expect(await code(signToken(k, claims({ aud: 'com.other.app' })))).toBe('BAD_AUDIENCE');
    expect(await code(signToken(k, claims({ iss: 'https://evil.example' })))).toBe('BAD_ISSUER');
    expect(await code(signToken(k, claims(), { alg: 'HS256', kid: k.kid }))).toBe('BAD_ALG');
    expect(await code(signToken(k, claims(), { alg: 'RS256', kid: 'nope' }))).toBe('UNKNOWN_KID');
  });
  it('rejects forged, expired and stale tokens', async () => {
    const other = makeKeys('apple-1');
    expect(await code(signToken(other, claims()))).toBe('BAD_SIGNATURE');
    const s = Math.floor(NOW / 1000);
    expect(await code(signToken(k, claims({ exp: s - 120 })))).toBe('EXPIRED');
    expect(await code(signToken(k, claims({ iat: s - 3600, exp: s + 600 })))).toBe('EXPIRED');
    expect(await code(signToken(k, claims({ iat: s + 600 })))).toBe('ISSUED_IN_FUTURE');
  });
  it('treats an unverified email as unverified', async () => {
    const id = await verifyAppleIdToken(signToken(k, claims({ email_verified: false, is_private_email: undefined })), NONCE, opts);
    expect(id.emailVerified).toBe(false);
    expect(id.privateEmail).toBe(false);
  });
});
