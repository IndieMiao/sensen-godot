/**
 * 动态农场地块认领与地块内存档（C-31）。同一组 HTTP 场景跑内存与 PostgreSQL 两套存储；
 * 并发抢地、跨进程抢地、重启后读回只在真库上有意义，放在 PgStore 专属的 describe 里。
 */
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import path from 'node:path';
import pg from 'pg';
import { buildApp } from '../../src/http/app.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { PgStore } from '../../src/db/pg_store.js';
import { migrate, truncateAll } from '../../src/db/migrate.js';
import type { Store } from '../../src/http/store.js';
import { newInstallKey } from '../../src/http/auth.js';
import { DEFAULT_CONTENT_DIR, contentVersion, loadContent } from '../../src/domain/content.js';
import { plotFor } from '../../src/http/app.js';
import { loadParcelRules } from '../../src/parcels/rules.js';
import { MemoryParcelStore, type ParcelStore } from '../../src/parcels/store.js';
import { PgParcelStore } from '../../src/parcels/pg_store.js';
import { parcelReselectFromEnv } from '../../src/parcels/routes.js';
import { emptyFarm } from '../../src/parcels/farm.js';

const DSN = process.env.TEST_DATABASE_URL;
if (process.env.CI === '1' && !DSN) throw new Error('CI 下必须设置 TEST_DATABASE_URL');

const content = loadContent(DEFAULT_CONTENT_DIR);
const CV = contentVersion(DEFAULT_CONTENT_DIR);
const ROOT = path.resolve(DEFAULT_CONTENT_DIR, '..', '..', '..');
const REGIONS = path.join(DEFAULT_CONTENT_DIR, 'regions.json');
const rules = loadParcelRules(DEFAULT_CONTENT_DIR);
const DATASET = 'sf-dynamic-farm-20261118-r4';
const T0 = Date.UTC(2026, 10, 23, 4);
/** 旧金山一带的两块地，坐标是 GeoJSON 顺序 [lng, lat]。 */
const A = { parcel_id: 'p-3512001', center: [-122.4194, 37.7749] };
const B = { parcel_id: 'p-3512002', center: [-122.4180, 37.7752] };
const FAR = { parcel_id: 'p-0001001', center: [-122.5100, 37.7000] };

let pool: pg.Pool | undefined;
beforeAll(async () => { if (DSN) { pool = new pg.Pool({ connectionString: DSN, max: 20 }); await migrate(pool); } });
afterAll(async () => { await pool?.end(); });

type Stores = { store: Store; parcels: ParcelStore };
const makers: [string, boolean, (now: () => number) => Stores][] = [
  ['MemoryStore', true, now => {
    const store = new MemoryStore({ content, timezone: 'America/Los_Angeles', plot: plotFor(content), now, contentVersion: CV });
    return { store, parcels: new MemoryParcelStore(id => store.displayNameOf(id)) };
  }],
  ['PgStore', Boolean(DSN), now => ({
    store: new PgStore({ pool: pool!, content, contentVersion: CV, timezone: () => 'America/Los_Angeles', plot: plotFor(content), now }),
    parcels: new PgParcelStore(pool!),
  })],
];

const bearer = (token: string) => ({ authorization: `Bearer ${token}` });
let clock = T0;
const appFor = (stores: Stores, opts: { reselect?: boolean; guestWrites?: boolean } = {}) => buildApp({
  store: stores.store, content, contentVersion: CV, blueprintDir: path.join(ROOT, 'assets', 'blueprints'),
  regionsFile: REGIONS, pepper: 'test-pepper', now: () => clock, realtimeEnabled: false, guestWrites: opts.guestWrites,
  parcels: { store: stores.parcels, rules, reselect: opts.reselect ?? false },
});

/** 带昵称的邮箱账号。 */
async function account(app: FastifyInstance, name: string): Promise<string> {
  const res = await app.inject({ method: 'POST', url: '/v1/auth/email/register',
    payload: { email: `${name.toLowerCase()}@example.com`, password: 'correct horse', display_name: name } });
  expect(res.statusCode).toBe(201);
  return res.json().token;
}
async function guest(app: FastifyInstance): Promise<string> {
  const res = await app.inject({ method: 'POST', url: '/v1/auth/anonymous', payload: { install_key: newInstallKey() } });
  return res.json().token;
}
const claim = (app: FastifyInstance, token: string, parcel: { parcel_id: string; center: number[] }, dataset = DATASET) =>
  app.inject({ method: 'POST', url: '/v1/parcels/claim', headers: bearer(token), payload: { dataset_version: dataset, ...parcel } });
const mine = async (app: FastifyInstance, token: string) =>
  (await app.inject({ method: 'GET', url: '/v1/parcels/mine', headers: bearer(token) })).json().parcel;
const enter = (app: FastifyInstance, token: string) =>
  app.inject({ method: 'POST', url: '/v1/parcels/mine/enter', headers: bearer(token) });
const GIFT = { hoe_starter: 1, seed_carrot: 3, blueprint_cottage: 1 };
const command = (app: FastifyInstance, token: string, base_version: number, commands: object[]) =>
  app.inject({ method: 'POST', url: '/v1/parcels/mine/commands', headers: bearer(token), payload: { base_version, commands } });
const owners = (app: FastifyInstance, token: string, query: string) =>
  app.inject({ method: 'GET', url: `/v1/parcels?dataset_version=${DATASET}&${query}`, headers: bearer(token) });

for (const [name, enabled, makeStores] of makers) {
  describe.skipIf(!enabled)(`${name}: dynamic farm parcels`, () => {
    let stores: Stores;
    let app: FastifyInstance;
    beforeEach(async () => {
      if (pool) await truncateAll(pool);
      clock = T0;
      stores = makeStores(() => clock);
      app = await appFor(stores);
    });
    afterEach(async () => { await app.close(); });

    it('claims one free parcel with an empty farm; a retry of the same claim answers the same parcel', async () => {
      const ada = await account(app, 'Ada');
      expect(await mine(app, ada)).toBeNull();
      const res = await claim(app, ada, A);
      expect(res.statusCode).toBe(201);
      expect(res.json().parcel).toEqual({ community_id: 'sf', layer: 0, parcel_id: A.parcel_id, dataset_version: DATASET,
        center: A.center, claimed_at: T0, farm_version: 0, farm: emptyFarm() });
      const again = await claim(app, ada, A);
      expect(again.statusCode).toBe(200);
      expect(again.json().parcel).toEqual(res.json().parcel);
      expect(await mine(app, ada)).toEqual(res.json().parcel);
    });

    it('one player can claim only one parcel', async () => {
      const ada = await account(app, 'Ada');
      expect((await claim(app, ada, A)).statusCode).toBe(201);
      const second = await claim(app, ada, B);
      expect(second.statusCode).toBe(409);
      expect(second.json()).toMatchObject({ code: 'ALREADY_CLAIMED', parcel: { parcel_id: A.parcel_id } });
      expect((await mine(app, ada)).parcel_id).toBe(A.parcel_id);
      const bob = await account(app, 'Bob');
      expect((await claim(app, bob, B)).statusCode).toBe(201);
    });

    it('a claimed parcel cannot be claimed by anyone else', async () => {
      const ada = await account(app, 'Ada'), bob = await account(app, 'Bob');
      expect((await claim(app, ada, A)).statusCode).toBe(201);
      const res = await claim(app, bob, A);
      expect(res.statusCode).toBe(409);
      expect(res.json().code).toBe('PARCEL_TAKEN');
      expect(await mine(app, bob)).toBeNull();
      expect((await mine(app, ada)).parcel_id).toBe(A.parcel_id);
    });

    it('two simultaneous claims of the same parcel: exactly one wins', async () => {
      const tokens = await Promise.all(['Ada', 'Bob', 'Cy', 'Dee', 'Eve', 'Fay'].map(n => account(app, n)));
      const results = await Promise.all(tokens.map(t => claim(app, t, A)));
      expect(results.filter(r => r.statusCode === 201)).toHaveLength(1);
      expect(results.filter(r => r.statusCode === 409).map(r => r.json().code)).toEqual(Array(5).fill('PARCEL_TAKEN'));
      const owned = await Promise.all(tokens.map(t => mine(app, t)));
      expect(owned.filter(Boolean)).toHaveLength(1);
    });

    it('guests read but cannot claim unless the server allows guest writes', async () => {
      const g = await guest(app);
      expect(await mine(app, g)).toBeNull();
      expect((await claim(app, g, A)).json().code).toBe('LOGIN_REQUIRED');
      const open = await appFor(stores, { guestWrites: true });
      try {
        expect((await claim(open, await guest(open), A)).statusCode).toBe(201);
      } finally { await open.close(); }
    });

    it('validates the claim body and the dataset', async () => {
      const ada = await account(app, 'Ada');
      expect((await claim(app, ada, { parcel_id: '3512001', center: A.center })).statusCode).toBe(400);
      expect((await claim(app, ada, { parcel_id: 'p-1;drop', center: A.center })).statusCode).toBe(400);
      expect((await claim(app, ada, { parcel_id: A.parcel_id, center: [37.7, -122.4, 1] })).statusCode).toBe(400);
      expect((await claim(app, ada, { parcel_id: A.parcel_id, center: [-122.4, 91] })).statusCode).toBe(400);
      const unknown = await claim(app, ada, A, 'other-dataset');
      expect(unknown.statusCode).toBe(422);
      expect(unknown.json().code).toBe('UNKNOWN_DATASET');
      expect((await app.inject({ method: 'POST', url: '/v1/parcels/claim', payload: { dataset_version: DATASET, ...A } })).statusCode).toBe(401);
      expect(await mine(app, ada)).toBeNull();
    });

    it('answers who owns parcels by id list and by map area, with the other owner’s nickname', async () => {
      const ada = await account(app, 'Ada'), bob = await account(app, 'Bob');
      await claim(app, ada, A);
      await claim(app, bob, FAR);
      const byIds = await owners(app, bob, `ids=${A.parcel_id},${B.parcel_id},${FAR.parcel_id}`);
      expect(byIds.statusCode).toBe(200);
      expect(byIds.json()).toMatchObject({ dataset_version: DATASET, community_id: 'sf', layer: 0, parcels: [
        { parcel_id: A.parcel_id, owner: 'other', nickname: 'Ada' },
        { parcel_id: B.parcel_id, owner: 'none', nickname: null },
        { parcel_id: FAR.parcel_id, owner: 'mine', nickname: 'Bob' },
      ] });
      // Around A and B only: FAR is outside the box.
      const area = await owners(app, bob, 'bbox=-122.43,37.77,-122.41,37.78');
      expect(area.json()).toMatchObject({ parcels: [{ parcel_id: A.parcel_id, owner: 'other', nickname: 'Ada' }], truncated: false });
      expect((await owners(app, ada, 'bbox=-122.6,37.6,-122.3,37.9')).statusCode).toBe(400);   // wider than the cap
      expect((await owners(app, ada, 'bbox=-122.41,37.77,-122.43,37.78')).statusCode).toBe(400);  // west > east
      expect((await owners(app, ada, `ids=${A.parcel_id}&bbox=-122.43,37.77,-122.41,37.78`)).statusCode).toBe(400);
      expect((await owners(app, ada, 'ids=bad')).statusCode).toBe(400);
      expect((await app.inject({ method: 'GET', url: `/v1/parcels?dataset_version=x&ids=${A.parcel_id}`, headers: bearer(ada) })).statusCode).toBe(422);
      expect((await app.inject({ method: 'GET', url: `/v1/parcels?dataset_version=${DATASET}&ids=${A.parcel_id}` })).statusCode).toBe(401);
    });

    it('first entry gives 1 hoe, 3 carrot seeds and 1 house blueprint once; re-entry and retries give nothing', async () => {
      const ada = await account(app, 'Ada');
      expect((await enter(app, ada)).json().code).toBe('NO_PARCEL');
      await claim(app, ada, A);
      expect((await mine(app, ada)).farm.bag).toEqual({});
      const first = await enter(app, ada);
      expect(first.statusCode).toBe(200);
      expect(first.json()).toMatchObject({ granted: true, parcel: { farm_version: 1, farm: { bag: GIFT, welcomed_at: T0 } } });
      clock = T0 + 1000;
      const again = await enter(app, ada);
      expect(again.json()).toMatchObject({ granted: false, parcel: { farm_version: 1, farm: { bag: GIFT, welcomed_at: T0 } } });
      // A lost response retried many times at once still grants nothing more.
      const retries = await Promise.all(Array.from({ length: 5 }, () => enter(app, ada)));
      expect(retries.map(r => r.json().granted)).toEqual(Array(5).fill(false));
      // Spending the gift and entering again does not refill it.
      await command(app, ada, 1, [{ type: 'place_house', x: 9, y: 9 }, { type: 'till', cell: '1,1' }, { type: 'sow', cell: '1,1', crop: 'crop_carrot' }]);
      expect((await enter(app, ada)).json()).toMatchObject({ granted: false, parcel: { farm_version: 2, farm: { bag: { hoe_starter: 1, seed_carrot: 2 } } } });
      // Re-claiming the same parcel (a retry) does not reset the farm either.
      expect((await claim(app, ada, A)).json().parcel.farm.bag).toEqual({ hoe_starter: 1, seed_carrot: 2 });
    });

    it('simultaneous first entries grant the gift exactly once', async () => {
      const ada = await account(app, 'Ada');
      await claim(app, ada, A);
      const results = await Promise.all(Array.from({ length: 6 }, () => enter(app, ada)));
      expect(results.filter(r => r.json().granted)).toHaveLength(1);
      expect(await mine(app, ada)).toMatchObject({ farm_version: 1, farm: { bag: GIFT } });
    });

    it('a player only reads and writes their own parcel farm', async () => {
      const ada = await account(app, 'Ada'), bob = await account(app, 'Bob');
      await claim(app, ada, A);
      await enter(app, ada);
      await command(app, ada, 1, [{ type: 'till', cell: '1,1' }]);
      const before = await mine(app, ada);
      // Bob has no parcel: his reads show nothing of Ada's farm, his writes reach nothing.
      expect(await mine(app, bob)).toBeNull();
      expect((await enter(app, bob)).json().code).toBe('NO_PARCEL');
      expect((await command(app, bob, before.farm_version, [{ type: 'till', cell: '2,2' }])).json().code).toBe('NO_PARCEL');
      const seen = (await owners(app, bob, `ids=${A.parcel_id}`)).json().parcels[0];
      expect(Object.keys(seen).sort()).toEqual(['nickname', 'owner', 'parcel_id']);
      // With his own parcel, Bob's commands change only his.
      await claim(app, bob, B);
      await enter(app, bob);
      expect((await command(app, bob, 1, [{ type: 'till', cell: '2,2' }])).statusCode).toBe(200);
      expect(await mine(app, ada)).toEqual(before);
      expect((await mine(app, bob)).farm.tilled).toEqual(['2,2']);
      expect((await command(app, 'not-a-token', 0, [{ type: 'till', cell: '3,3' }])).statusCode).toBe(401);
      expect((await app.inject({ method: 'GET', url: '/v1/parcels/mine' })).statusCode).toBe(401);
    });

    it('saves house, cleared obstacles, tilled cells, crops with server ripening and the bag', async () => {
      const ada = await account(app, 'Ada');
      await claim(app, ada, A);
      expect((await command(app, ada, 0, [{ type: 'till', cell: '1,1' }])).json()).toMatchObject({ code: 'NO_TOOL' });
      await enter(app, ada);
      expect((await command(app, ada, 1, [{ type: 'till', cell: '1,1' }])).statusCode).toBe(200);
      const stale = await command(app, ada, 1, [{ type: 'till', cell: '2,1' }]);
      expect(stale.statusCode).toBe(409);
      expect(stale.json()).toMatchObject({ code: 'VERSION_CONFLICT', parcel: { farm_version: 2, farm: { tilled: ['1,1'] } } });
      const res = await command(app, ada, 2, [{ type: 'place_house', x: 10, y: 4, rotation: 1 }, { type: 'clear_obstacle', cell: '2,2' },
        { type: 'till', cell: '2,2' }, { type: 'sow', cell: '2,2', crop: 'crop_carrot' }]);
      expect(res.statusCode).toBe(200);
      expect(res.json().parcel.farm_version).toBe(3);
      const refused = await command(app, ada, 3, [{ type: 'harvest', cell: '2,2' }]);
      expect(refused.statusCode).toBe(422);
      expect(refused.json()).toMatchObject({ code: 'NOT_RIPE', index: 0, detail: { ripe_at: T0 + 60_000 }, parcel: { farm_version: 3 } });
      clock = T0 + 59_999;
      expect((await command(app, ada, 3, [{ type: 'harvest', cell: '2,2' }])).json().code).toBe('NOT_RIPE');
      clock = T0 + 60_000;
      const harvested = await command(app, ada, 3, [{ type: 'harvest', cell: '2,2' }]);
      expect(harvested.statusCode).toBe(200);
      expect(await mine(app, ada)).toMatchObject({ farm_version: 4, farm: {
        house: { model: 'cottage', x: 10, y: 4, width: 3, depth: 3, rotation: 1, built_at: T0 },
        cleared: ['2,2'], tilled: ['1,1', '2,2'], crops: {}, bag: { hoe_starter: 1, seed_carrot: 2, crop_carrot: 1 },
      } });
      expect((await command(app, ada, 4, [{ type: 'teleport' }])).statusCode).toBe(400);
      expect((await command(app, await account(app, 'Bob'), 0, [{ type: 'till', cell: '1,1' }])).json().code).toBe('NO_PARCEL');
    });

    it('“abandon and pick again” is refused under the production configuration and leaves the parcel', async () => {
      expect(parcelReselectFromEnv({})).toBe(false);
      expect(parcelReselectFromEnv({ DYNAMIC_FARM_RESELECT: '0' })).toBe(false);
      expect(parcelReselectFromEnv({ DYNAMIC_FARM_RESELECT: 'true' })).toBe(false);
      expect(parcelReselectFromEnv({ DYNAMIC_FARM_RESELECT: '1' })).toBe(true);
      const ada = await account(app, 'Ada');
      await claim(app, ada, A);
      const res = await app.inject({ method: 'POST', url: '/v1/parcels/mine/abandon', headers: bearer(ada) });
      expect(res.statusCode).toBe(403);
      expect(res.json().code).toBe('RESELECT_DISABLED');
      expect((await mine(app, ada)).parcel_id).toBe(A.parcel_id);
      expect((await claim(app, await account(app, 'Bob'), A)).json().code).toBe('PARCEL_TAKEN');
    });

    it('“abandon and pick again” works under the test configuration: the parcel is free and a new claim starts fresh', async () => {
      const test = await appFor(stores, { reselect: true });
      try {
        const ada = await account(test, 'Ada');
        await claim(test, ada, A);
        await enter(test, ada);
        await command(test, ada, 1, [{ type: 'till', cell: '1,1' }]);
        const res = await test.inject({ method: 'POST', url: '/v1/parcels/mine/abandon', headers: bearer(ada) });
        expect(res.statusCode).toBe(200);
        expect(res.json().abandoned).toEqual({ community_id: 'sf', layer: 0, parcel_id: A.parcel_id });
        expect(await mine(test, ada)).toBeNull();
        expect((await test.inject({ method: 'POST', url: '/v1/parcels/mine/abandon', headers: bearer(ada) })).json().code).toBe('NO_PARCEL');
        expect((await claim(test, await account(test, 'Bob'), A)).statusCode).toBe(201);
        const again = await claim(test, ada, B);
        expect(again.statusCode).toBe(201);
        expect(again.json().parcel.farm).toEqual(emptyFarm());
      } finally { await test.close(); }
    });
  });
}

describe.skipIf(!DSN)('PgStore: dynamic farm parcels across processes and restarts', () => {
  beforeEach(async () => { await truncateAll(pool!); clock = T0; });

  const pgStores = (p: pg.Pool): Stores => ({
    store: new PgStore({ pool: p, content, contentVersion: CV, timezone: () => 'America/Los_Angeles', plot: plotFor(content), now: () => clock }),
    parcels: new PgParcelStore(p),
  });

  it('two server processes racing for one parcel: exactly one claim lands', async () => {
    const other = new pg.Pool({ connectionString: DSN, max: 20 });
    const one = await appFor(pgStores(pool!), { guestWrites: true }), two = await appFor(pgStores(other), { guestWrites: true });
    try {
      for (let round = 0; round < 5; round++) {
        const parcel = { parcel_id: `p-race${round}`, center: A.center };
        const tokens = await Promise.all(Array.from({ length: 10 }, (_, i) => guest(i % 2 ? two : one)));
        const results = await Promise.all(tokens.map((t, i) => claim(i % 2 ? two : one, t, parcel)));
        expect(results.filter(r => r.statusCode === 201)).toHaveLength(1);
        expect(results.filter(r => r.statusCode === 409 && r.json().code === 'PARCEL_TAKEN')).toHaveLength(9);
        const rows = await pool!.query('SELECT count(*)::int AS n FROM parcel_claims WHERE parcel_id = $1', [parcel.parcel_id]);
        expect(rows.rows[0].n).toBe(1);
      }
    } finally { await one.close(); await two.close(); await other.end(); }
  });

  it('one player racing for several parcels at once still gets only one', async () => {
    const app = await appFor(pgStores(pool!), { guestWrites: true });
    try {
      const token = await guest(app);
      const results = await Promise.all(Array.from({ length: 8 }, (_, i) => claim(app, token, { parcel_id: `p-many${i}`, center: A.center })));
      expect(results.filter(r => r.statusCode === 201)).toHaveLength(1);
      expect(results.filter(r => r.statusCode === 409).map(r => r.json().code)).toEqual(Array(7).fill('ALREADY_CLAIMED'));
      expect((await pool!.query('SELECT count(*)::int AS n FROM parcel_claims')).rows[0].n).toBe(1);
    } finally { await app.close(); }
  });

  it('the parcel farm written before a restart reads back after it', async () => {
    const before = new pg.Pool({ connectionString: DSN, max: 5 });
    const app = await appFor(pgStores(before));
    const ada = await account(app, 'Ada');
    await claim(app, ada, A);
    await enter(app, ada);
    await command(app, ada, 1, [{ type: 'place_house', x: 6, y: 6 }, { type: 'clear_obstacle', cell: '1,2' }, { type: 'till', cell: '1,2' },
      { type: 'sow', cell: '1,2', crop: 'crop_carrot' }]);
    const saved = await mine(app, ada);
    await app.close();
    await before.end();

    // A new process: new pool, new stores, migrations run again on start.
    clock = T0 + 5 * 60_000;
    const after = new pg.Pool({ connectionString: DSN, max: 5 });
    await migrate(after);
    const restarted = await appFor(pgStores(after));
    try {
      const read = await mine(restarted, ada);
      expect(read).toEqual(saved);
      expect(read.farm).toMatchObject({ house: { x: 6, y: 6 }, cleared: ['1,2'], tilled: ['1,2'],
        crops: { '1,2': { crop: 'crop_carrot', planted_at: T0, ripe_at: T0 + 60_000 } }, bag: { hoe_starter: 1, seed_carrot: 2 }, welcomed_at: T0 });
      // Reopening after the restart does not give the first-entry gift again.
      expect((await enter(restarted, ada)).json()).toMatchObject({ granted: false, parcel: { farm_version: read.farm_version, farm: { bag: { hoe_starter: 1, seed_carrot: 2 } } } });
      const harvested = await command(restarted, ada, read.farm_version, [{ type: 'harvest', cell: '1,2' }]);
      expect(harvested.json().parcel.farm.bag.crop_carrot).toBe(1);
    } finally { await restarted.close(); await after.end(); }
  });

  it('deleting the account frees the parcel', async () => {
    const stores = pgStores(pool!);
    const app = await appFor(stores);
    try {
      const ada = await account(app, 'Ada');
      await claim(app, ada, A);
      const res = await app.inject({ method: 'DELETE', url: '/v1/users/me', headers: bearer(ada), payload: { password: 'correct horse' } });
      expect(res.statusCode).toBe(200);
      expect((await pool!.query('SELECT count(*)::int AS n FROM parcel_claims')).rows[0].n).toBe(0);
      expect((await claim(app, await account(app, 'Bob'), A)).statusCode).toBe(201);
    } finally { await app.close(); }
  });
});
