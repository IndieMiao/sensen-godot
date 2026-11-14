/** identify (SGODOT-488; contract-accounts.md §0–§1): one answer for who a request is. */
import { describe, expect, it } from 'vitest';
import { identify, inForce, isRefusal, bearerOf } from '../../src/p0/accounts/identify.js';
import { P0Accounts } from '../../src/p0/accounts/store.js';

const T = (n: number) => n.toString(16).padStart(64, '0');
const bearer = (n: number) => ({ authorization: `Bearer ${T(n)}` });
const deps = (a: P0Accounts, more: Partial<Parameters<typeof identify>[1]> = {}) => ({ accounts: a, legacyId: false, warn: () => {}, ...more });

describe('identify', () => {
  it('takes a token for its player, the token winning over a different x-p0-player', () => {
    const a = new P0Accounts(); a.issue('p0-alpha001', T(1));
    let warned = '';
    expect(identify(bearer(1), deps(a))).toEqual({ player: 'p0-alpha001', via: 'token' });
    expect(identify({ ...bearer(1), 'x-p0-player': 'p0-other0001' }, deps(a, { warn: l => { warned = l; } })))
      .toEqual({ player: 'p0-alpha001', via: 'token' });
    expect(warned).toContain('player_header_mismatch');
    expect(warned).not.toContain('p0-alpha001');   // only the ids' tails go to the log
  });

  it('a token not known: session_replaced, account_deleted or unauthenticated', () => {
    const a = new P0Accounts();
    a.issue('p0-alpha001', T(2));   // signed in on another phone with token 2; this phone still sends token 1
    const r1 = identify({ ...bearer(1), 'x-p0-player': 'p0-alpha001' }, deps(a));
    expect(isRefusal(r1) && r1.body.code).toBe('session_replaced');
    a.markDeleted('p0-gone00001', Date.now());
    const r2 = identify({ ...bearer(1), 'x-p0-player': 'p0-gone00001' }, deps(a));
    expect(isRefusal(r2) && r2.body.code).toBe('account_deleted');
    const r3 = identify(bearer(1), deps(a));
    expect(isRefusal(r3) && [r3.status, r3.body.code]).toEqual([401, 'unauthenticated']);
  });

  it('x-p0-player alone: as before while unclaimed, update_required once claimed, refused once deleted', () => {
    const a = new P0Accounts();
    expect(identify({ 'x-p0-player': 'p0-old00001' }, deps(a))).toEqual({ player: 'p0-old00001', via: 'legacy' });
    a.markClaimed('p0-old00001'); a.issue('p0-old00001', T(3));
    const r = identify({ 'x-p0-player': 'p0-old00001' }, deps(a, { updateUrl: () => 'https://play.example/app' }));
    expect(isRefusal(r) && [r.status, r.body]).toEqual([426, { ok: false, code: 'update_required', url: 'https://play.example/app' }]);
    a.markDeleted('p0-old00002', Date.now());
    const d = identify({ 'x-p0-player': 'p0-old00002' }, deps(a));
    expect(isRefusal(d) && d.body.code).toBe('account_deleted');
    const none = identify({}, deps(a));
    expect(isRefusal(none) && [none.status, none.body.code]).toEqual([400, 'bad_player']);
  });

  it('a guest made with a token (never claimed) is not taken by its id alone either', () => {
    const a = new P0Accounts(); a.ensure('p0-new00001'); a.issue('p0-new00001', T(4));
    const r = identify({ 'x-p0-player': 'p0-new00001' }, deps(a));
    expect(isRefusal(r) && r.body.code).toBe('update_required');
  });

  it('a deleted id alone is refused even under P0_LEGACY_ID (a read would make its save anew)', () => {
    const a = new P0Accounts(); a.markDeleted('p0-gone00001', Date.now());
    const r = identify({ 'x-p0-player': 'p0-gone00001' }, deps(a, { legacyId: true }));
    expect(isRefusal(r) && [r.status, r.body.code]).toEqual([401, 'account_deleted']);
  });

  it('P0_LEGACY_ID takes any id alone, claimed or not (devserver, shots, tests)', () => {
    const a = new P0Accounts(); a.markClaimed('p0-old00001'); a.issue('p0-old00001', T(3));
    expect(identify({ 'x-p0-player': 'p0-old00001' }, deps(a, { legacyId: true }))).toEqual({ player: 'p0-old00001', via: 'legacy' });
  });

  it('reads a bearer token of 32 bytes or more in hex only', () => {
    expect(bearerOf({ authorization: `Bearer ${T(5).toUpperCase()}` })).toBe(T(5));
    expect(bearerOf({ authorization: `Bearer ${'ab'.repeat(31)}` })).toBe('');
    expect(bearerOf({ authorization: T(5) })).toBe('');
  });
});

describe('a suspension (SGODOT-484)', () => {
  it('turns its player away on every way in — token or id alone — with until; none past its time; a deleted id says deleted', () => {
    const a = new P0Accounts(); a.issue('p0-alpha001', T(1));
    const until = Date.UTC(2026, 11, 1);
    const sanctions: Record<string, { until: number | null }> = { 'p0-alpha001': { until }, 'p0-legacy01': { until: null } };
    const d = deps(a, { suspended: p => sanctions[p] ?? null });
    expect(identify(bearer(1), d)).toEqual({ status: 403, body: { ok: false, code: 'suspended', until: new Date(until).toISOString() } });
    expect(identify({ 'x-p0-player': 'p0-legacy01' }, d)).toEqual({ status: 403, body: { ok: false, code: 'suspended', until: null } });
    expect(identify({ 'x-p0-player': 'p0-other0001' }, d)).toEqual({ player: 'p0-other0001', via: 'legacy' });
    a.markDeleted('p0-legacy01', Date.now());
    expect((identify({ 'x-p0-player': 'p0-legacy01' }, d) as { body: { code: string } }).body.code).toBe('account_deleted');
  });
  it('inForce: for good, till a time to come; not past it, not absent', () => {
    expect(inForce({ until: null }, 5)).toEqual({ until: null });
    expect(inForce({ until: 10 }, 5)).toEqual({ until: 10 });
    expect(inForce({ until: 5 }, 5)).toBeNull();
    expect(inForce(undefined, 5)).toBeNull();
  });
});
