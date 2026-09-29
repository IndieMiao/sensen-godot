import { describe, expect, it } from 'vitest';
import { generateKeyPairSync, verify } from 'node:crypto';
import { APPLE_REVOKE_URL, APPLE_TOKEN_URL, clientSecret, createAppleRevoker } from '../../src/accounts/apple_revoke.js';

const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
const config = { teamId: 'XN4Z77ZX73', keyId: 'ABC123DEFG', privateKey };
const NOW = Date.UTC(2026, 8, 29, 2);

describe('Apple client secret and revocation', () => {
  it('signs an ES256 client secret Apple can verify', () => {
    const jwt = clientSecret(config, 'app.gensen.maps', NOW);
    const [h, p, s] = jwt.split('.');
    expect(JSON.parse(Buffer.from(h, 'base64url').toString())).toEqual({ alg: 'ES256', kid: 'ABC123DEFG', typ: 'JWT' });
    const claims = JSON.parse(Buffer.from(p, 'base64url').toString());
    expect(claims).toMatchObject({ iss: 'XN4Z77ZX73', aud: 'https://appleid.apple.com', sub: 'app.gensen.maps' });
    expect(claims.exp - claims.iat).toBe(300);
    expect(verify('sha256', Buffer.from(`${h}.${p}`), { key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(s, 'base64url'))).toBe(true);
  });

  it('exchanges a code and revokes the refresh token with form posts', async () => {
    const calls: { url: string; form: Record<string, string> }[] = [];
    const revoker = createAppleRevoker(config, () => NOW, async (url, form) => {
      calls.push({ url, form });
      return url === APPLE_TOKEN_URL ? { status: 200, json: { refresh_token: 'r.1' } } : { status: 200, json: {} };
    });
    expect(await revoker.exchange('c.1', 'app.gensen.maps')).toBe('r.1');
    expect(await revoker.revoke('r.1', 'app.gensen.maps')).toBe(true);
    expect(calls[0]).toMatchObject({ url: APPLE_TOKEN_URL, form: { code: 'c.1', grant_type: 'authorization_code', client_id: 'app.gensen.maps' } });
    expect(calls[1]).toMatchObject({ url: APPLE_REVOKE_URL, form: { token: 'r.1', token_type_hint: 'refresh_token' } });
  });

  it('reports failures instead of throwing on bad answers', async () => {
    const revoker = createAppleRevoker(config, () => NOW, async () => ({ status: 400, json: { error: 'invalid_grant' } }));
    expect(await revoker.exchange('bad', 'app.gensen.maps')).toBeNull();
    expect(await revoker.revoke('bad', 'app.gensen.maps')).toBe(false);
  });
});
