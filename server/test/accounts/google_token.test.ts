import { describe, expect, it } from 'vitest';
import { makeKeys, signToken } from '../fixtures/firebase_tokens.js';
import { sha256Hex } from '../../src/accounts/apple_token.js';
import { verifyGoogleIdToken } from '../../src/accounts/google_token.js';

const NOW = Date.UTC(2026, 8, 29, 5);
const NONCE = 'g'.repeat(32);
const AUD = 'web-client.apps.googleusercontent.com';
const k = makeKeys('google-1');
const claims = (over: Record<string, unknown> = {}) => {
  const s = Math.floor(NOW / 1000);
  return { iss: 'https://accounts.google.com', aud: AUD, sub: '1234567890', iat: s - 5, exp: s + 3600,
    nonce: sha256Hex(NONCE), email: 'ada@gmail.com', email_verified: true, given_name: 'Ada', family_name: 'L', ...over };
};
const opts = { audiences: [AUD], keys: k.keys, now: () => NOW };
const code = (token: string, nonce: unknown = NONCE) => verifyGoogleIdToken(token, nonce, opts).then(() => 'ok', (e: { code: string }) => e.code);

describe('verifyGoogleIdToken', () => {
  it('accepts both issuer spellings and reads the profile', async () => {
    expect(await verifyGoogleIdToken(signToken(k, claims()), NONCE, opts)).toMatchObject({ sub: '1234567890', aud: AUD, emailVerified: true, givenName: 'Ada' });
    expect(await code(signToken(k, claims({ iss: 'accounts.google.com' })))).toBe('ok');
  });
  it('rejects wrong audience, issuer, nonce and expired tokens', async () => {
    expect(await code(signToken(k, claims({ aud: 'someone-else' })))).toBe('BAD_AUDIENCE');
    expect(await code(signToken(k, claims({ iss: 'https://evil.example' })))).toBe('BAD_ISSUER');
    expect(await code(signToken(k, claims()), 'h'.repeat(32))).toBe('BAD_NONCE');
    expect(await code(signToken(k, claims({ exp: Math.floor(NOW / 1000) - 120 })))).toBe('EXPIRED');
    expect(await code(signToken(makeKeys('google-1'), claims()))).toBe('BAD_SIGNATURE');
  });
});
