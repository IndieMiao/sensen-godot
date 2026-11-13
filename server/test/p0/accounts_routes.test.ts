/** The first launch's routes (SGODOT-488 A1; contract-accounts.md §1): hello, guest, claim, consent. */
import Fastify from 'fastify';
import { describe, expect, it } from 'vitest';
import { registerAccountRoutes } from '../../src/p0/accounts/routes.js';
import { P0Accounts } from '../../src/p0/accounts/store.js';
import { loadP0Content } from '../../src/p0/content.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { P0Store } from '../../src/p0/store.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 10, 13, 4);
const V = { terms: '2026-11-13', privacy: '2026-11-13' };
const T = (n: number) => n.toString(16).padStart(64, '0');

type Pend = { provider: 'apple' | 'google'; link: { sub: string; aud?: string } };
function setup(opts: { legacyId?: boolean; ages?: Record<string, boolean>; guestsPerHour?: number; guestOk?: boolean; pendings?: Record<string, Pend> } = {}) {
  const store = new P0Store(c), accounts = new P0Accounts();
  const identifyDeps = { accounts, legacyId: !!opts.legacyId, warn: () => {} };
  const app = Fastify();
  registerAccountRoutes(app, { store, accounts, identify: identifyDeps, now: () => T0, versions: V,
    voiceAge: p => (opts.ages && p in opts.ages ? opts.ages[p] : null), guestsPerHour: opts.guestsPerHour, guestOk: opts.guestOk ?? true,
    pending: { take: (id: unknown) => { const p = opts.pendings?.[String(id)]; if (p) delete opts.pendings![String(id)]; return p as never; },
      create: (_p: string, link: { sub: string }) => `again-${link.sub}` } });
  registerP0Routes(app, { content: c, store, now: () => T0, dev: false, identify: identifyDeps });
  return { app, store, accounts };
}
const guest = (extra: Record<string, unknown> = {}) => ({ age_ok: true, ...V, name: 'Mia', token: T(1), request_id: T(9), ...extra });

describe('hello', () => {
  it('says the versions and whether ids alone are taken', async () => {
    const { app } = setup({ legacyId: true });
    expect((await app.inject({ method: 'GET', url: '/v1/p0/hello' })).json()).toEqual({ ok: true, terms_version: V.terms, privacy_version: V.privacy, legacy_id: true, guest_ok: true });
  });
});

describe('session/guest', () => {
  it('makes a save with the consent, the age and the name, and the token reads it', async () => {
    const { app, store } = setup();
    const r = (await app.inject({ method: 'POST', url: '/v1/p0/session/guest', payload: guest() })).json();
    expect(r.ok).toBe(true);
    expect(r.player).toMatch(/^p0-[0-9a-f]{20}$/);
    const s = store.peek(r.player)!;
    expect(s.consent).toEqual({ ...V, at: T0 });
    expect(s.age_ok).toBe(true);
    expect(s.profile).toEqual({ name: 'Mia', name_set_at: T0 });
    const state = await app.inject({ method: 'GET', url: '/v1/p0/state', headers: { authorization: `Bearer ${T(1)}` } });
    expect([state.statusCode, state.json().ok]).toEqual([200, true]);   // the view carries no id: read by the token
    expect(store.size()).toBe(1);
  });
  it('the same token again is the same save (a lost answer retried), never a second one', async () => {
    const { app, store } = setup();
    const a = (await app.inject({ method: 'POST', url: '/v1/p0/session/guest', payload: guest() })).json();
    const b = (await app.inject({ method: 'POST', url: '/v1/p0/session/guest', payload: guest() })).json();
    expect(b).toEqual(a);
    expect(store.size()).toBe(1);
  });
  it('skip keeps no name and no name time', async () => {
    const { app, store } = setup();
    const r = (await app.inject({ method: 'POST', url: '/v1/p0/session/guest', payload: guest({ name: undefined, skip: true }) })).json();
    expect(store.peek(r.player)!.profile).toBeUndefined();
  });
  it('refuses: no age, old versions, a bad name, a short token, a pending sign-in (PR-B), too many from one address', async () => {
    const { app } = setup({ guestsPerHour: 1 });
    const code = async (p: Record<string, unknown>) => (await app.inject({ method: 'POST', url: '/v1/p0/session/guest', payload: p })).json();
    expect((await code(guest({ age_ok: false }))).code).toBe('schema');
    expect(await code(guest({ terms: 'old' }))).toEqual({ ok: false, code: 'consent_outdated', terms_version: V.terms, privacy_version: V.privacy });
    expect(await code(guest({ name: '  ' }))).toEqual({ ok: false, code: 'name_rejected', reason: 'empty' });
    expect((await code(guest({ token: 'ab'.repeat(31) }))).code).toBe('token_too_short');
    expect((await code(guest({ pending: 'x' }))).code).toBe('pending_expired');   // unknown, spent or gone with a restart
    expect((await code(guest())).ok).toBe(true);
    expect((await code(guest({ token: T(2) }))).code).toBe('rate_limited');
  });
  it('a token player without a save is not given one by a read', async () => {
    const { app, store, accounts } = setup();
    accounts.issue('p0-ghost00001', T(5));
    const r = await app.inject({ method: 'GET', url: '/v1/p0/state', headers: { authorization: `Bearer ${T(5)}` } });
    expect([r.statusCode, r.json().code]).toEqual([401, 'unauthenticated']);
    expect(store.size()).toBe(0);
  });
});

describe('session/claim', () => {
  const claim = (app: ReturnType<typeof Fastify>, player: string, token: string) =>
    app.inject({ method: 'POST', url: '/v1/p0/session/claim', headers: { 'x-p0-player': player }, payload: { token } });
  it('gives an old player its token once, with the voice gate answer and its consent; again with the same token is ok', async () => {
    const { app, store } = setup({ ages: { 'p0-old00001': true } });
    store.get('p0-old00001', T0);
    expect((await claim(app, 'p0-old00001', T(1))).json()).toEqual({ ok: true, player: 'p0-old00001', age: true, consent: null });
    expect((await claim(app, 'p0-old00001', T(1))).json().ok).toBe(true);
    const other = await claim(app, 'p0-old00001', T(2));
    expect([other.statusCode, other.json()]).toEqual([409, { ok: false, code: 'claimed', linked: [] }]);
    // and the old build on it now updates
    const old = await app.inject({ method: 'GET', url: '/v1/p0/state', headers: { 'x-p0-player': 'p0-old00001' } });
    expect([old.statusCode, old.json().code]).toEqual([426, 'update_required']);
  });
  it('age false and never asked come through as they are', async () => {
    const { app, store } = setup({ ages: { 'p0-old00002': false } });
    store.get('p0-old00002', T0); store.get('p0-old00003', T0);
    expect((await claim(app, 'p0-old00002', T(1))).json().age).toBe(false);
    expect((await claim(app, 'p0-old00003', T(2))).json().age).toBeNull();
  });
  it('unknown_player for an id the server has not or has deleted; a token already another\'s is refused', async () => {
    const { app, store, accounts } = setup();
    expect((await claim(app, 'p0-nobody001', T(1))).json().code).toBe('unknown_player');
    store.get('p0-gone00001', T0); accounts.markDeleted('p0-gone00001', T0);
    expect((await claim(app, 'p0-gone00001', T(1))).json().code).toBe('unknown_player');
    store.get('p0-a00000001', T0); store.get('p0-b00000001', T0);
    await claim(app, 'p0-a00000001', T(3));
    expect((await claim(app, 'p0-b00000001', T(3))).json().code).toBe('schema');
  });
});

describe('account/consent', () => {
  it('records an old player\'s consent and age; 「没过」 is never taken, old versions are outdated', async () => {
    const { app, store } = setup();
    store.get('p0-old00001', T0);
    await app.inject({ method: 'POST', url: '/v1/p0/session/claim', headers: { 'x-p0-player': 'p0-old00001' }, payload: { token: T(1) } });
    const h = { authorization: `Bearer ${T(1)}` };
    expect((await app.inject({ method: 'POST', url: '/v1/p0/account/consent', headers: h, payload: { age_ok: false, ...V } })).json().code).toBe('schema');
    expect((await app.inject({ method: 'POST', url: '/v1/p0/account/consent', headers: h, payload: { age_ok: true, terms: 'x', privacy: V.privacy } })).json().code).toBe('consent_outdated');
    expect((await app.inject({ method: 'POST', url: '/v1/p0/account/consent', headers: h, payload: { age_ok: true, ...V } })).json()).toEqual({ ok: true });
    expect(store.peek('p0-old00001')).toMatchObject({ consent: { ...V, at: T0 }, age_ok: true });
  });
});

describe('view.account', () => {
  it('says the name, the links, when it may change and the terms agreed; nothing of it without accounts', async () => {
    const { app, accounts } = setup();
    const r = (await app.inject({ method: 'POST', url: '/v1/p0/session/guest', payload: guest() })).json();
    accounts.link(r.player, 'apple', { sub: 's', aud: 'app.gensen.maps' });
    const v = (await app.inject({ method: 'GET', url: '/v1/p0/state', headers: { authorization: `Bearer ${T(1)}` } })).json().state;
    expect(v.account).toEqual({ name: 'Mia', linked: ['apple'], rename_at: T0 + 7 * 86_400_000, consent: V });
    const plain = Fastify();
    registerP0Routes(plain, { content: c, store: new P0Store(c), now: () => T0, dev: false });
    expect((await plain.inject({ method: 'GET', url: '/v1/p0/state', headers: { 'x-p0-player': 'p0-plain0001' } })).json().state.account).toBeUndefined();
  });
  it('a skipped name may change now', async () => {
    const { app } = setup();
    await app.inject({ method: 'POST', url: '/v1/p0/session/guest', payload: guest({ name: undefined, skip: true }) });
    const v = (await app.inject({ method: 'GET', url: '/v1/p0/state', headers: { authorization: `Bearer ${T(1)}` } })).json().state;
    expect(v.account).toEqual({ name: null, linked: [], rename_at: 0, consent: V });
  });
});

describe('a test account (tech-plan §2.5)', () => {
  it('is made by the phone\'s main account, takes its consent, has a g3test- id and no name', async () => {
    const { app, store } = setup();
    const main = (await app.inject({ method: 'POST', url: '/v1/p0/session/guest', payload: guest() })).json().player;
    const r = await app.inject({ method: 'POST', url: '/v1/p0/session/guest', headers: { authorization: `Bearer ${T(1)}` }, payload: { test: true, token: T(2) } });
    const id = r.json().player;
    expect(id).toMatch(/^g3test-[0-9a-f]{32}$/);
    const s = store.peek(id)!;
    expect([s.test, s.age_ok, s.profile]).toEqual([true, true, undefined]);
    expect(s.consent).toEqual(store.peek(main)!.consent);
    expect((await app.inject({ method: 'GET', url: '/v1/p0/state', headers: { authorization: `Bearer ${T(2)}` } })).statusCode).toBe(200);
  });
  it('without the main account\'s token it is refused', async () => {
    const { app } = setup();
    const r = await app.inject({ method: 'POST', url: '/v1/p0/session/guest', payload: { test: true, token: T(2) } });
    expect(r.statusCode).toBe(400);   // no id at all: bad_player
    const r2 = await app.inject({ method: 'POST', url: '/v1/p0/session/guest', headers: { authorization: `Bearer ${T(9)}` }, payload: { test: true, token: T(2) } });
    expect([r2.statusCode, r2.json().code]).toEqual([401, 'unauthenticated']);
  });
});

describe('v1.4 必须注册', () => {
  it('a new farm needs a sign-in: sign_in_required without a pending one (unless P0_GUEST_OK or a test account)', async () => {
    const { app } = setup({ guestOk: false });
    const r = await app.inject({ method: 'POST', url: '/v1/p0/session/guest', payload: guest() });
    expect([r.statusCode, r.json().code]).toEqual([400, 'sign_in_required']);
  });
  it('guest with the pending sign-in makes the farm and links it; a pending one is spent once', async () => {
    const { app, accounts } = setup({ guestOk: false, pendings: { p1: { provider: 'apple', link: { sub: 'apple-sub', aud: 'app.gensen.maps' } } } });
    const r = (await app.inject({ method: 'POST', url: '/v1/p0/session/guest', payload: guest({ pending: 'p1' }) })).json();
    expect(r).toMatchObject({ ok: true, linked: 'apple' });
    expect(accounts.byIdentity('apple', 'apple-sub')).toBe(r.player);
    expect((await app.inject({ method: 'POST', url: '/v1/p0/session/guest', payload: guest({ pending: 'p1', token: T(2) }) })).json().code).toBe('pending_expired');
  });
  it('the account linked meanwhile to a farm that is there is a conflict, never taken from it; one left on a farm gone moves', async () => {
    const { app, accounts, store } = setup({ guestOk: false, pendings: { p1: { provider: 'google', link: { sub: 'g1' } }, p2: { provider: 'google', link: { sub: 'g2' } } } });
    store.get('p0-live00001', T0); accounts.link('p0-live00001', 'google', { sub: 'g1' });
    const conflict = (await app.inject({ method: 'POST', url: '/v1/p0/session/guest', payload: guest({ pending: 'p1' }) })).json();
    expect(conflict).toEqual({ ok: false, code: 'conflict', pending: 'again-g1' });   // v1.6 ②: a new pending one for 「进那个农场」
    expect(accounts.byIdentity('google', 'g1')).toBe('p0-live00001');
    accounts.link('p0-gone00001', 'google', { sub: 'g2' });   // no save
    const r = (await app.inject({ method: 'POST', url: '/v1/p0/session/guest', payload: guest({ pending: 'p2', token: T(3) }) })).json();
    expect(accounts.byIdentity('google', 'g2')).toBe(r.player);
    expect(accounts.find('p0-gone00001')?.google).toBeUndefined();
  });
  it('hello with an old id says its way before any sign-in: unclaimed its age and consent, claimed its links, else nothing', async () => {
    const { app, store, accounts } = setup({ ages: { 'p0-old00001': true } });
    store.get('p0-old00001', T0);
    const hello = async (id: string) => (await app.inject({ method: 'GET', url: '/v1/p0/hello', headers: { 'x-p0-player': id } })).json().legacy;
    expect(await hello('p0-old00001')).toEqual({ age: true, consent: null });
    accounts.markClaimed('p0-old00001'); accounts.link('p0-old00001', 'apple', { sub: 's', aud: 'a' });
    expect(await hello('p0-old00001')).toEqual({ claimed: true, linked: ['apple'] });
    expect(await hello('p0-nobody001')).toBeUndefined();
    accounts.markDeleted('p0-old00001', T0);
    expect(await hello('p0-old00001')).toBeUndefined();
  });
  it('claim takes the consent given on the pages before the sign-in', async () => {
    const { app, store } = setup();
    store.get('p0-old00001', T0);
    const r = (await app.inject({ method: 'POST', url: '/v1/p0/session/claim', headers: { 'x-p0-player': 'p0-old00001' }, payload: { token: T(1), consent: V } })).json();
    expect(r.consent).toEqual({ ...V, at: T0 });
    expect(store.peek('p0-old00001')!.age_ok).toBe(true);
  });
});

describe('v1.6 (奕星 on v3.2)', () => {
  it('a farm made by a sign-in and signed out is claimed: hello says so, its id alone is sent to update, claim refuses', async () => {
    const { app, accounts } = setup({ guestOk: false, pendings: { p1: { provider: 'google', link: { sub: 'g1' } } } });
    const r = (await app.inject({ method: 'POST', url: '/v1/p0/session/guest', payload: guest({ pending: 'p1' }) })).json();
    accounts.revokeAll(r.player);   // signed out
    expect((await app.inject({ method: 'GET', url: '/v1/p0/hello', headers: { 'x-p0-player': r.player } })).json().legacy).toEqual({ claimed: true, linked: ['google'] });
    const old = await app.inject({ method: 'GET', url: '/v1/p0/state', headers: { 'x-p0-player': r.player } });
    expect([old.statusCode, old.json().code]).toEqual([426, 'update_required']);
    expect((await app.inject({ method: 'POST', url: '/v1/p0/session/claim', headers: { 'x-p0-player': r.player }, payload: { token: T(7) } })).json().code).toBe('claimed');
  });
  it('the AGE page passed is written to the voice gate (claim\'s age_ok, consent), only for one never asked', async () => {
    const ages: Record<string, boolean> = {};
    const store = new P0Store(c), accounts = new P0Accounts();
    const ident = { accounts, legacyId: false, warn: () => {} };
    const app = Fastify();
    registerAccountRoutes(app, { store, accounts, identify: ident, now: () => T0, versions: V, guestOk: true,
      voiceAge: p => (p in ages ? ages[p] : null), voiceAgeOk: p => { ages[p] = true; } });
    store.get('p0-old00001', T0);
    await app.inject({ method: 'POST', url: '/v1/p0/session/claim', headers: { 'x-p0-player': 'p0-old00001' }, payload: { token: T(1), age_ok: true } });
    expect(ages['p0-old00001']).toBe(true);
    store.get('p0-old00002', T0); accounts.issue('p0-old00002', T(2));
    await app.inject({ method: 'POST', url: '/v1/p0/account/consent', headers: { authorization: `Bearer ${T(2)}` }, payload: { age_ok: true, ...V } });
    expect(ages['p0-old00002']).toBe(true);
  });
});
