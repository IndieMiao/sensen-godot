/** Player names on the wire (contract-accounts §1, 后裔 11-13 v1.2): name/check, account/name, session/guest's name and
 *  view.account's name fields; one bucket of 20 a minute per address for all three. */
import Fastify from 'fastify';
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { P0Store } from '../../src/p0/store.js';
import { accountNameView, NAME_PER_MINUTE, NameLimiter, nameForGuest, registerNameRoutes, RENAME_COOLDOWN_MS, setName,
  type NameList } from '../../src/p0/accounts/name.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 10, 13, 4);
const DAY = 86_400_000;
const LIST: NameList = { severe: ['fuck'], words: ['ass'], impersonation: ['admin'], impersonation_anywhere: ['gensen'], allow: [] };

/** The routes with a stand-in identify: x-p0-player, or 401 unauthenticated as 后裔's identify would send. */
function server() {
  let t = T0;
  const store = new P0Store(c);
  const limiter = new NameLimiter();
  const app = Fastify();
  registerNameRoutes(app, { store, now: () => t, limiter, list: () => LIST,
    identify: (req, reply) => {
      const p = req.headers['x-p0-player'];
      if (typeof p === 'string') return p;
      reply.code(401).send({ ok: false, code: 'unauthenticated' });
      return null;
    } });
  const post = (url: string, payload: unknown, player?: string, ip = '203.0.113.7') =>
    app.inject({ method: 'POST', url, payload: payload as object, remoteAddress: ip, headers: player ? { 'x-p0-player': player } : {} });
  return { app, store, limiter, post, tick: (ms: number) => { t += ms; } };
}

describe('name routes (contract §1)', () => {
  it('name/check answers ok or name_rejected with one of the four reasons, never the word', async () => {
    const { post } = server();
    expect((await post('/v1/p0/name/check', { name: '  Mia   Rose ' })).json()).toEqual({ ok: true });
    for (const [name, reason] of [['', 'empty'], ['M', 'length'], ['Mia😀', 'chars'], ['Big Ass', 'blocked'], ['Pаul', 'blocked']]) {
      const r = await post('/v1/p0/name/check', { name });
      expect(r.statusCode).toBe(400);
      expect(r.json()).toEqual({ ok: false, code: 'name_rejected', reason });
    }
    expect((await post('/v1/p0/name/check', {})).json()).toEqual({ ok: false, code: 'name_rejected', reason: 'empty' });
  });

  it('name/check, account/name and a guest with a name share 20 a minute per address; a new minute starts over', async () => {
    const { store, limiter, post, tick } = server();
    store.get('p-namer-0001', T0);
    for (let i = 0; i < NAME_PER_MINUTE - 2; i++) expect((await post('/v1/p0/name/check', { name: 'Mia' })).statusCode).toBe(200);
    expect((await post('/v1/p0/account/name', { name: 'Mia' }, 'p-namer-0001')).statusCode).toBe(200);
    expect(nameForGuest({ name: 'Mia' }, { limiter, ip: '203.0.113.7', now: T0, list: LIST })).toMatchObject({ ok: true });
    const over = await post('/v1/p0/name/check', { name: 'Mia' });
    expect([over.statusCode, over.json()]).toEqual([429, { ok: false, code: 'rate_limited' }]);
    expect(nameForGuest({ name: 'Mia' }, { limiter, ip: '203.0.113.7', now: T0, list: LIST })).toMatchObject({ status: 429 });
    expect((await post('/v1/p0/name/check', { name: 'Mia' }, undefined, '198.51.100.2')).statusCode).toBe(200);   // another address
    expect(nameForGuest({ skip: true }, { limiter, ip: '203.0.113.7', now: T0, list: LIST })).toEqual({ ok: true });   // Skip takes none
    tick(60_000);
    expect((await post('/v1/p0/name/check', { name: 'Mia' })).statusCode).toBe(200);
  });

  it('account/name keeps the name normalized and answers when it can change next', async () => {
    const { store, post } = server();
    store.get('p-namer-0002', T0);
    const r = await post('/v1/p0/account/name', { name: ' Mia  Rose ' }, 'p-namer-0002');
    expect(r.json()).toEqual({ ok: true, name: 'Mia Rose', rename_at: T0 + RENAME_COOLDOWN_MS });
    expect(store.find('p-namer-0002', T0)!.profile).toEqual({ name: 'Mia Rose', name_set_at: T0 });
  });

  it('a Skip (no name_set_at) renames at once; then 7 days, rename_too_soon with when; after them, again', async () => {
    const { store, post, tick } = server();
    store.get('p-namer-0003', T0);
    expect((await post('/v1/p0/account/name', { name: 'Mia' }, 'p-namer-0003')).statusCode).toBe(200);
    tick(6 * DAY);
    const soon = await post('/v1/p0/account/name', { name: 'Ana' }, 'p-namer-0003');
    expect([soon.statusCode, soon.json()]).toEqual([409, { ok: false, code: 'rename_too_soon', rename_at: T0 + RENAME_COOLDOWN_MS }]);
    tick(DAY);
    expect((await post('/v1/p0/account/name', { name: 'Ana' }, 'p-namer-0003')).json()).toMatchObject({ ok: true, name: 'Ana' });
  });

  it("the save's clock: the dev time skip moves the wait as it moves the game", async () => {
    const { store, post } = server();
    const s = store.get('p-namer-0004', T0);
    setName(s, 'Mia', T0);
    s.clock_ms = 7 * DAY;
    expect((await post('/v1/p0/account/name', { name: 'Ana' }, 'p-namer-0004')).json()).toMatchObject({ ok: true, name: 'Ana' });
  });

  it("a moderator's lock holds past the 7 days", async () => {
    const { store, post } = server();
    const s = store.get('p-namer-0005', T0);
    s.profile = { name_locked_until: T0 + 3 * DAY };
    const r = await post('/v1/p0/account/name', { name: 'Ana' }, 'p-namer-0005');
    expect([r.statusCode, r.json().rename_at]).toEqual([409, T0 + 3 * DAY]);
  });

  it('the same name again changes nothing and starts no new wait', async () => {
    const { store, post, tick } = server();
    const s = store.get('p-namer-0006', T0);
    setName(s, 'Mia', T0 - 8 * DAY);
    tick(1);
    expect((await post('/v1/p0/account/name', { name: ' Mia ' }, 'p-namer-0006')).json()).toEqual({ ok: true, name: 'Mia', rename_at: 0 });
    expect(store.find('p-namer-0006', T0)!.profile!.name_set_at).toBe(T0 - 8 * DAY);
  });

  it('account/name refuses: no identity (identify answers), no save, no name, a rejected name', async () => {
    const { store, post } = server();
    expect((await post('/v1/p0/account/name', { name: 'Mia' })).json()).toEqual({ ok: false, code: 'unauthenticated' });
    const gone = await post('/v1/p0/account/name', { name: 'Mia' }, 'p-namer-none');
    expect([gone.statusCode, gone.json()]).toEqual([401, { ok: false, code: 'unauthenticated' }]);
    expect(store.peek('p-namer-none')).toBeUndefined();   // find, never get: no save is made
    store.get('p-namer-0007', T0);
    expect((await post('/v1/p0/account/name', { name: 7 }, 'p-namer-0007')).json()).toEqual({ ok: false, code: 'schema' });
    expect((await post('/v1/p0/account/name', { name: 'GensenTeam' }, 'p-namer-0007')).json())
      .toEqual({ ok: false, code: 'name_rejected', reason: 'blocked' });
    expect(store.find('p-namer-0007', T0)!.profile).toBeUndefined();
  });
});

describe("session/guest's name and view.account (contract §1)", () => {
  const ctx = () => ({ limiter: new NameLimiter(), ip: '203.0.113.9', now: T0, list: LIST });
  it('a name: kept normalized, its 7 days from the creation; Skip: no name, no wait; both or neither: schema', () => {
    expect(nameForGuest({ name: ' Mia ', age_ok: true }, ctx())).toEqual({ ok: true, name: 'Mia', name_set_at: T0 });
    expect(nameForGuest({ skip: true }, ctx())).toEqual({ ok: true });
    for (const body of [{}, { name: 'Mia', skip: true }, { skip: false }, { name: 3 }, null])
      expect(nameForGuest(body, ctx())).toEqual({ ok: false, status: 400, body: { ok: false, code: 'schema' } });
    expect(nameForGuest({ name: 'admin' }, ctx())).toEqual({ ok: false, status: 400, body: { ok: false, code: 'name_rejected', reason: 'blocked' } });
  });

  it('view.account: the name or null (the client writes the default), rename_at 0 once passed', () => {
    const s = new P0Store(c).get('p-namer-0008', T0);
    expect(accountNameView(s, T0)).toEqual({ name: null, rename_at: 0 });
    setName(s, 'Mia', T0);
    expect(accountNameView(s, T0 + DAY)).toEqual({ name: 'Mia', rename_at: T0 + RENAME_COOLDOWN_MS });
    expect(accountNameView(s, T0 + RENAME_COOLDOWN_MS)).toEqual({ name: 'Mia', rename_at: 0 });
  });
});
