/** accounts.json (SGODOT-488; contract-accounts.md §4): tokens by hash, links one-to-one, deleted ids for 30 days, the
 * Apple refresh token sealed on disk. */
import { mkdtempSync, readFileSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import { DELETED_KEEP_MS, P0Accounts, hashToken, tokenShapeOk } from '../../src/p0/accounts/store.js';

const KEY = Buffer.alloc(32, 7);
const T = (n: number) => n.toString(16).padStart(64, '0');
const dirs: string[] = [];
afterEach(() => { for (const d of dirs.splice(0)) rmSync(d, { recursive: true, force: true }); });
const file = () => { const d = mkdtempSync(path.join(tmpdir(), 'acc-')); dirs.push(d); return path.join(d, 'accounts.json'); };

describe('P0Accounts', () => {
  it('knows a player by a token, keeps only its hash, and keeps it across a restart', () => {
    const f = file();
    const a = new P0Accounts(f, KEY);
    a.ensure('p0-a');
    a.issue('p0-a', T(1));
    expect(a.byToken(T(1))).toEqual({ player: 'p0-a', kind: 'user' });
    expect(a.byToken(T(2))).toBeUndefined();
    const raw = readFileSync(f, 'utf8');
    expect(raw).not.toContain(T(1));
    expect(raw).toContain(hashToken(T(1)));
    expect(new P0Accounts(f, KEY).byToken(T(1))?.player).toBe('p0-a');
  });

  it('revokes every user token but the one kept, an admin one only when asked', () => {
    const a = new P0Accounts(undefined, KEY);
    a.issue('p0-a', T(1)); a.issue('p0-a', T(2)); a.issue('p0-a', T(3), 'admin', Date.now() + 1e6); a.issue('p0-b', T(4));
    expect(a.revokeAll('p0-a', T(2))).toHaveLength(1);
    expect(a.byToken(T(1))).toBeUndefined();
    expect(a.byToken(T(2))?.player).toBe('p0-a');
    expect(a.byToken(T(3))?.kind).toBe('admin');   // sign-in elsewhere leaves a test phone's admin token
    expect(a.byToken(T(4))?.player).toBe('p0-b');
    a.revokeAll('p0-a', undefined, { admin: true });
    expect(a.byToken(T(2))).toBeUndefined();
    expect(a.byToken(T(3))).toBeUndefined();
  });

  it('lets an admin token lapse on its day and lists the live ones by tail', () => {
    let now = 1_000;
    const a = new P0Accounts(undefined, KEY, () => now);
    a.issue('p0-tester-9a3f', T(5), 'admin', 2_000);
    expect(a.adminTokens()).toEqual([{ player: 'p0-tester-9a3f', tail: '9a3f', token_tail: hashToken(T(5)).slice(-6), expires_at: 2_000 }]);
    now = 2_000;
    expect(a.byToken(T(5))).toBeUndefined();
    expect(a.adminTokens()).toEqual([]);
  });

  it('links an Apple or Google account to one player, and seals the refresh token on disk', () => {
    const f = file();
    const a = new P0Accounts(f, KEY);
    a.link('p0-a', 'apple', { sub: 'apple-sub-1', aud: 'app.gensen.maps', refresh: 'r.secret' });
    expect(a.byIdentity('apple', 'apple-sub-1')).toBe('p0-a');
    expect(a.find('p0-a')?.apple).toEqual({ sub: 'apple-sub-1', aud: 'app.gensen.maps', refresh: 'r.secret' });
    expect(readFileSync(f, 'utf8')).not.toContain('r.secret');
    expect(new P0Accounts(f, KEY).find('p0-a')?.apple?.refresh).toBe('r.secret');
    expect(new P0Accounts(f, Buffer.alloc(32, 8)).find('p0-a')?.apple?.refresh).toBeUndefined();   // another key opens nothing
    expect(a.linked('p0-a')).toEqual(['apple']);
    a.unlink('p0-a', 'apple');
    expect(a.byIdentity('apple', 'apple-sub-1')).toBeUndefined();
    expect(a.linked('p0-a')).toEqual([]);
  });

  it('keeps no refresh token without a key', () => {
    const a = new P0Accounts(undefined, null);
    a.link('p0-a', 'apple', { sub: 's', aud: 'app.gensen.maps', refresh: 'r' });
    expect(a.find('p0-a')?.apple).toEqual({ sub: 's', aud: 'app.gensen.maps', refresh: undefined });
  });

  it('removes a player whole and refuses the id for 30 days', () => {
    let now = 10_000;
    const f = file();
    const a = new P0Accounts(f, KEY, () => now);
    a.issue('p0-a', T(1)); a.link('p0-a', 'google', { sub: 'g-1' });
    a.markDeleted('p0-a', now);
    a.remove('p0-a');
    expect(a.find('p0-a')).toBeUndefined();
    expect(a.byToken(T(1))).toBeUndefined();
    expect(a.byIdentity('google', 'g-1')).toBeUndefined();
    expect(a.isDeleted('p0-a')).toBe(true);
    now += DELETED_KEEP_MS;
    expect(a.isDeleted('p0-a')).toBe(false);
    expect(JSON.parse(readFileSync(f, 'utf8')).deleted['p0-a']).toBe(10_000);
    new P0Accounts(f, KEY, () => now);   // a start past the 30 days drops it from the file
    expect(JSON.parse(readFileSync(f, 'utf8')).deleted['p0-a']).toBeUndefined();
  });

  it('takes tokens of 32 bytes or more, in hex', () => {
    expect(tokenShapeOk(T(1))).toBe(true);
    expect(tokenShapeOk('ab'.repeat(31))).toBe(false);
    expect(tokenShapeOk('zz'.repeat(32))).toBe(false);
    expect(tokenShapeOk(42)).toBe(false);
  });
});

describe('P0Accounts files and case', () => {
  it('reads a token in either case as the same, and keeps accounts.json to the server alone', () => {
    const f = file();
    const a = new P0Accounts(f, KEY);
    a.issue('p0-a', T(10).toUpperCase());
    expect(a.byToken(T(10))?.player).toBe('p0-a');
    expect(statSync(f).mode & 0o777).toBe(0o600);
  });
});

describe('test codes (contract v1.4 §4)', () => {
  it('keeps a code as HMAC under the key, finds it as typed in any form, one code per player', () => {
    const f = file();
    const a = new P0Accounts(f, KEY);
    a.setCode('p0-review001', 'AB12-CD34-EF56', 'review-play');
    expect(readFileSync(f, 'utf8')).not.toContain('AB12CD34EF56');
    expect(a.codeOwner('ab12 cd34 ef56')?.player).toBe('p0-review001');
    expect(a.codeOwner('AB12CD34EF56')?.player).toBe('p0-review001');
    expect(a.codeOwner('AB12-CD34-EF57')).toBeUndefined();
    expect(new P0Accounts(f, Buffer.alloc(32, 9)).codeOwner('AB12-CD34-EF56')).toBeUndefined();   // another key: not found
    expect(a.codeOf('p0-review001')).toEqual({ note: 'review-play', at: expect.any(Number) });
    a.setCode('p0-review001', 'ZZ99-ZZ99-ZZ99', 'review-play');
    expect(a.codeOwner('AB12-CD34-EF56')).toBeUndefined();   // the old one replaced
  });
  it('reads I / L as 1 and O as 0', () => {
    const a = new P0Accounts(undefined, KEY);
    a.setCode('p0-tester001', '1100-0000-1111', 'cn-tester-01');
    expect(a.codeOwner('ILOO-oooo-lIl1')?.player).toBe('p0-tester001');
  });
  it('revoking the code revokes exactly the tokens it gave; a deletion takes the code too', () => {
    const a = new P0Accounts(undefined, KEY);
    const key = a.setCode('p0-review001', 'AB12-CD34-EF56', 'review-play');
    a.issue('p0-review001', T(1), 'user', undefined, key);
    a.issue('p0-review001', T(2), 'user', undefined, key);
    a.issue('p0-review001', T(3));   // an Apple sign-in of the same player
    expect(a.revokeCode('p0-review001')).toBe(2);
    expect([a.byToken(T(1)), a.byToken(T(2)), a.byToken(T(3))?.player]).toEqual([undefined, undefined, 'p0-review001']);
    expect(a.revokeCode('p0-review001')).toBe(-1);
    a.setCode('p0-review001', 'AB12-CD34-EF56', 'x');
    a.remove('p0-review001');
    expect(a.codeOwner('AB12-CD34-EF56')).toBeUndefined();
  });
  it('without a key, no codes: off, found nowhere', () => {
    const a = new P0Accounts(undefined, null);
    expect(a.codesOn()).toBe(false);
    expect(a.codeOwner('AB12-CD34-EF56')).toBeUndefined();
    expect(() => a.setCode('p', 'AB12-CD34-EF56', 'x')).toThrow();
  });
});
