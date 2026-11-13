/** Sign-in's shared parts (SGODOT-489; contract-accounts.md §2, §4). */
import { describe, expect, it } from 'vitest';
import { conflictFarm, liveOwner, PENDING_MS, PendingSignIns, signIn } from '../../src/p0/accounts/link.js';
import { P0Accounts } from '../../src/p0/accounts/store.js';
import { loadP0Content } from '../../src/p0/content.js';
import { P0Store } from '../../src/p0/store.js';

const c = loadP0Content();
const T = (n: number) => n.toString(16).padStart(64, '0');

describe('PendingSignIns', () => {
  it('gives a pending sign-in back once, within 10 minutes; one past its time goes to expired', () => {
    let now = 0;
    const gone: string[] = [];
    const p = new PendingSignIns(() => now, i => gone.push(i.link.sub));
    const a = p.create('apple', { sub: 'a1', aud: 'app.gensen.maps', refresh: 'r' });
    expect(a).toMatch(/^[0-9a-f]{64}$/);
    expect(p.take(a)?.link.sub).toBe('a1');
    expect(p.take(a)).toBeUndefined();
    const b = p.create('google', { sub: 'g1' });
    now = PENDING_MS;
    expect(p.take(b)).toBeUndefined();
    expect(gone).toEqual(['g1']);
    expect(p.take(42)).toBeUndefined();
  });
});

describe('conflictFarm', () => {
  it('says the other farm\'s name, home level and last play', () => {
    const store = new P0Store(c);
    const s = store.get('p0-other0001', 1_000);
    s.profile = { name: 'Mia' }; s.homestead.level = 7; s.presence.last_at = 5_000; store.put(s);
    expect(conflictFarm(store, 'p0-other0001', 6_000)).toEqual({ name: 'Mia', home_level: 7, last_played_at: 5_000 });
  });
});

describe('signIn', () => {
  it('revokes the account\'s other user tokens, keeps admin ones, kicks its socket and issues the new token', () => {
    const accounts = new P0Accounts();
    accounts.issue('p0-a0000001', T(1)); accounts.issue('p0-a0000001', T(3), 'admin', Date.now() + 1e6);
    accounts.link('p0-a0000001', 'google', { sub: 'g' });
    const kicked: string[] = [];
    expect(signIn({ accounts, kick: p => kicked.push(p) }, 'p0-a0000001', T(2))).toEqual({ ok: true, player: 'p0-a0000001', linked: ['google'] });
    expect(accounts.byToken(T(1))).toBeUndefined();
    expect(accounts.byToken(T(2))?.player).toBe('p0-a0000001');
    expect(accounts.byToken(T(3))?.kind).toBe('admin');
    expect(kicked).toEqual(['p0-a0000001']);
  });
});

describe('liveOwner', () => {
  it('is the linked farm while it is there; a link left on a farm gone is dropped as found', () => {
    const store = new P0Store(c), accounts = new P0Accounts();
    store.get('p0-live00001', 0);
    accounts.link('p0-live00001', 'google', { sub: 'g-live' });
    accounts.link('p0-gone00001', 'google', { sub: 'g-gone' });   // no save: lost
    expect(liveOwner(store, accounts, 'google', 'g-live', 0)).toBe('p0-live00001');
    expect(liveOwner(store, accounts, 'google', 'g-gone', 0)).toBeUndefined();
    expect(accounts.byIdentity('google', 'g-gone')).toBeUndefined();   // free to link again
    expect(liveOwner(store, accounts, 'google', 'nobody', 0)).toBeUndefined();
  });
});
