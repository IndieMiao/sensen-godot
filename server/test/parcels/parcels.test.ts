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
import type { StarterZones } from '../../src/parcels/starter_zone.js';

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
const appFor = (stores: Stores, opts: { reselect?: boolean; guestWrites?: boolean; starterZones?: StarterZones } = {}) => buildApp({
  store: stores.store, content, contentVersion: CV, blueprintDir: path.join(ROOT, 'assets', 'blueprints'),
  regionsFile: REGIONS, pepper: 'test-pepper', now: () => clock, realtimeEnabled: false, guestWrites: opts.guestWrites,
  parcels: { store: stores.parcels, rules, reselect: opts.reselect ?? false, starterZones: opts.starterZones },
});
/** C-130 起步区：A、B 在区内（清单里的中心点与客户端报的不同，认领应存清单里的），FAR 在区外。
 * C-143：SMALL 在区内但太小（too_small），不能认领。 */
const SMALL = { parcel_id: 'p-3512003', center: [-122.4170, 37.7755] };
const ZONE_CENTER_A: [number, number] = [-122.41941, 37.77491];
const zones = (enabled = true): StarterZones => ({ enabled, zones: [{
  id: 'test-zone', community_id: 'sf', name: 'Test', dataset_version: DATASET,
  boundary: [[-122.43, 37.77], [-122.41, 37.77], [-122.41, 37.78], [-122.43, 37.78], [-122.43, 37.77]],
  center: [-122.42, 37.775], zoom: 17, min_core_cells: 400,
  parcels: new Map([[A.parcel_id, ZONE_CENTER_A], [B.parcel_id, [B.center[0], B.center[1]]], [SMALL.parcel_id, [SMALL.center[0], SMALL.center[1]]]]),
  too_small: new Set([SMALL.parcel_id]),
}] });

/** 带昵称的邮箱账号。 */
async function account(app: FastifyInstance, name: string): Promise<string> {
  const res = await app.inject({ method: 'POST', url: '/v1/auth/email/register',
    payload: { email: `${name.toLowerCase()}@example.com`, password: 'correct horse', display_name: name } });
  expect(res.statusCode).toBe(201);
  return res.json().token;
}
/** 每个游客来自不同的网络：同一网络每小时只能新建 10 个匿名玩家（C-100），这里的并发场景要更多。 */
let guestNetwork = 0;
async function guest(app: FastifyInstance): Promise<string> {
  const res = await app.inject({ method: 'POST', url: '/v1/auth/anonymous', remoteAddress: `198.51.${(++guestNetwork >> 8) & 255}.${guestNetwork & 255}`,
    payload: { install_key: newInstallKey() } });
  return res.json().token;
}
const claim = (app: FastifyInstance, token: string, parcel: { parcel_id: string; center: number[] }, dataset = DATASET) =>
  app.inject({ method: 'POST', url: '/v1/parcels/claim', headers: bearer(token), payload: { dataset_version: dataset, ...parcel } });
const mine = async (app: FastifyInstance, token: string) =>
  (await app.inject({ method: 'GET', url: '/v1/parcels/mine', headers: bearer(token) })).json().parcel;
const enter = (app: FastifyInstance, token: string) =>
  app.inject({ method: 'POST', url: '/v1/parcels/mine/enter', headers: bearer(token) });
const R6 = 'sf-dynamic-farm-20261124-r6';
/** C-136：带上这次打开农场用的数据集进入（新客户端）。 */
const enterAs = (app: FastifyInstance, token: string, dataset_version: unknown) =>
  app.inject({ method: 'POST', url: '/v1/parcels/mine/enter', headers: bearer(token), payload: { dataset_version } });
/** r4 上认领、进入，盖房、清障碍、开垦三格、种两颗（一颗熟一颗没熟）、卖一次、领鸡舍蓝图、采一棵树；返回此时的地块。 */
async function r4Farm(app: FastifyInstance, token: string, parcel = A) {
  await claim(app, token, parcel);
  await enter(app, token);
  await command(app, token, 1, [{ type: 'place_house', x: 9, y: 9 }, { type: 'clear_obstacle', cell: '3,3' }, { type: 'till', cell: '1,1' },
    { type: 'till', cell: '2,1' }, { type: 'till', cell: '3,1' }, { type: 'sow', cell: '1,1', crop: 'crop_carrot' }]);
  clock = T0 + 60_000;
  await command(app, token, 2, [{ type: 'harvest', cell: '1,1' }, { type: 'sell', item: 'crop_carrot', count: 1 }, { type: 'claim_blueprint', blueprint: 'coop' },
    { type: 'sow', cell: '1,1', crop: 'crop_carrot' }, { type: 'gather', object: `${parcel.parcel_id}:outer-groves-v2:wild_pz_tree_20:41,7:0` }]);
  clock = T0 + 90_000;
  const res = await command(app, token, 3, [{ type: 'sow', cell: '2,1', crop: 'crop_carrot' }]);
  expect(res.statusCode).toBe(200);
  const farm = res.json().parcel;
  expect(farm).toMatchObject({ dataset_version: DATASET, farm_version: 4, farm: { coins: 12, sales: 1, bag: { hoe_starter: 1, blueprint_coop: 1, wood: 1 } } });
  expect(Object.keys(farm.farm.crops)).toEqual(['1,1', '2,1']);
  return farm;
}
/** 换到 r6 之后应有的样子：格子上的清空，每棵作物退一颗种子、房子退住宅蓝图，其余不动。 */
const rebased = (before: { farm: Record<string, unknown> }) => ({ ...before.farm, house: null, cleared: [], tilled: [], crops: {}, gathered: {},
  bag: { hoe_starter: 1, blueprint_coop: 1, wood: 1, seed_carrot: 2, blueprint_cottage: 1 } });
const GIFT = { hoe_starter: 1, seed_carrot: 3, blueprint_cottage: 1 };
const command = (app: FastifyInstance, token: string, base_version: number, commands: object[]) =>
  app.inject({ method: 'POST', url: '/v1/parcels/mine/commands', headers: bearer(token), payload: { base_version, commands } });
/** 认领、进入、种两颗萝卜并在 60 秒后收获；返回此时的 farm_version，时钟停在 T0 + 60 s。 */
async function withCarrots(app: FastifyInstance, token: string, parcel: { parcel_id: string; center: number[] }): Promise<number> {
  await claim(app, token, parcel);
  await enter(app, token);
  expect((await command(app, token, 1, [{ type: 'till', cell: '1,1' }, { type: 'till', cell: '2,1' },
    { type: 'sow', cell: '1,1', crop: 'crop_carrot' }, { type: 'sow', cell: '2,1', crop: 'crop_carrot' }])).statusCode).toBe(200);
  clock = T0 + 60_000;
  const res = await command(app, token, 2, [{ type: 'harvest', cell: '1,1' }, { type: 'harvest', cell: '2,1' }]);
  expect(res.json().parcel.farm.bag.crop_carrot).toBe(2);
  return 3;
}
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

    it('C-136 an r4 claim entered by an r6 client moves to r6 once: cells cleared, crops back as seeds, house back as its blueprint', async () => {
      const ada = await account(app, 'Ada');
      const before = await r4Farm(app, ada);
      clock = T0 + 100_000;
      const res = await enterAs(app, ada, R6);
      expect(res.statusCode).toBe(200);
      expect(res.json()).toMatchObject({ granted: false, parcel: { parcel_id: A.parcel_id, community_id: 'sf', dataset_version: R6, farm_version: 5,
        center: A.center, claimed_at: T0 } });
      expect(res.json().parcel.farm).toEqual(rebased(before));
      expect(await mine(app, ada)).toEqual(res.json().parcel);
      // Retries, many at once, and the old client: nothing moves again and nothing more is given back.
      const again = await Promise.all([...Array.from({ length: 5 }, () => enterAs(app, ada, R6)), enter(app, ada)]);
      expect(again.map(r => [r.statusCode, r.json().parcel.farm_version, r.json().parcel.dataset_version])).toEqual(Array(6).fill([200, 5, R6]));
      expect((await mine(app, ada)).farm).toEqual(rebased(before));
      // Never back to r4: the claim stays on r6.
      expect((await enterAs(app, ada, DATASET)).json().parcel).toMatchObject({ dataset_version: R6, farm_version: 5 });
      // The owner and the map still see the same parcel; play goes on on the new cells.
      expect((await owners(app, ada, `ids=${A.parcel_id}`)).json().parcels[0].owner).toBe('mine');
      expect((await command(app, ada, 5, [{ type: 'place_house', x: 2, y: 2 }, { type: 'till', cell: '9,9' }, { type: 'sow', cell: '9,9', crop: 'crop_carrot' }])).statusCode).toBe(200);
      // A command based on the version before the move is refused, not applied to the new cells.
      expect((await command(app, ada, 4, [{ type: 'till', cell: '4,4' }])).statusCode).toBe(409);
    });

    it('C-136 without the field, with an unknown, older or same dataset the claim and its farm stay as they are', async () => {
      const ada = await account(app, 'Ada');
      const before = await r4Farm(app, ada);
      for (const res of [await enter(app, ada), await enterAs(app, ada, undefined), await enterAs(app, ada, 'sf-dynamic-farm-20261124-r5'),
        await enterAs(app, ada, 'ny-dynamic-farm-1'), await enterAs(app, ada, DATASET)]) {
        expect(res.statusCode).toBe(200);
        expect(res.json()).toMatchObject({ granted: false, parcel: { dataset_version: DATASET, farm_version: 4 } });
      }
      expect(await mine(app, ada)).toEqual(before);
      for (const bad of [6, null, ['x'], 'x'.repeat(129)]) expect((await enterAs(app, ada, bad)).json().code).toBe('SCHEMA');
      expect(await mine(app, ada)).toEqual(before);
      // An r6 claim entered by the r6 client is an ordinary entry; an r6 claim is not moved back by an r4 client.
      const bob = await account(app, 'Bob');
      await claim(app, bob, B, R6);
      expect((await enterAs(app, bob, R6)).json()).toMatchObject({ granted: true, parcel: { dataset_version: R6, farm_version: 1, farm: { bag: GIFT } } });
      expect((await enterAs(app, bob, DATASET)).json()).toMatchObject({ granted: false, parcel: { dataset_version: R6, farm_version: 1 } });
    });

    it('C-136 a never-entered r4 claim moves to r6 and gets the first-entry gift in the same write', async () => {
      const ada = await account(app, 'Ada');
      await claim(app, ada, A);
      const results = await Promise.all(Array.from({ length: 4 }, () => enterAs(app, ada, R6)));
      expect(results.filter(r => r.json().granted)).toHaveLength(1);
      expect(await mine(app, ada)).toMatchObject({ dataset_version: R6, farm_version: 1, farm: { bag: GIFT, welcomed_at: T0, house: null, tilled: [] } });
    });

    it('C-136 only one\'s own claim moves; another player\'s parcel and farm are untouched', async () => {
      const ada = await account(app, 'Ada'), bob = await account(app, 'Bob');
      const bobs = await r4Farm(app, bob, B);
      await claim(app, ada, A);
      await enterAs(app, ada, R6);
      expect(await mine(app, bob)).toEqual(bobs);
      expect((await enterAs(app, await account(app, 'Cy'), R6)).json().code).toBe('NO_PARCEL');
    });

    it('C-113 with r8 registered: an r6 home entered naming r6 (its r6 farm, Q-172) keeps its cells; an r4 home entered naming r8 moves to r8', async () => {
      const R8 = 'sf-dynamic-farm-20261125-r8';
      const bob = await account(app, 'Bob');
      await claim(app, bob, B, R6);
      await enterAs(app, bob, R6);
      expect((await command(app, bob, 1, [{ type: 'place_house', x: 9, y: 9 }, { type: 'till', cell: '1,1' }, { type: 'sow', cell: '1,1', crop: 'crop_carrot' }])).statusCode).toBe(200);
      const r6 = await mine(app, bob);
      expect(r6).toMatchObject({ dataset_version: R6, farm_version: 2 });
      const again = await enterAs(app, bob, R6);
      expect(again.json()).toMatchObject({ granted: false, parcel: { dataset_version: R6, farm_version: 2 } });
      expect(await mine(app, bob)).toEqual(r6);
      const ada = await account(app, 'Ada');
      const before = await r4Farm(app, ada);
      const moved = await enterAs(app, ada, R8);
      expect(moved.json()).toMatchObject({ granted: false, parcel: { dataset_version: R8, farm_version: 5 } });
      expect(moved.json().parcel.farm).toEqual(rebased(before));
      expect(await mine(app, bob)).toEqual(r6);
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

    it('C-58 sell: too few is refused; a sale takes from the bag and pays the configured price, server-side only', async () => {
      const ada = await account(app, 'Ada');
      const v = await withCarrots(app, ada, A);
      const short = await command(app, ada, v, [{ type: 'sell', item: 'crop_carrot', count: 3 }]);
      expect(short.statusCode).toBe(422);
      expect(short.json()).toMatchObject({ code: 'NOT_ENOUGH', detail: { item: 'crop_carrot', have: 2, need: 3 }, parcel: { farm_version: v, farm: { coins: 0 } } });
      // A price in the request is ignored; the configured 12 applies.
      const sold = await command(app, ada, v, [{ type: 'sell', item: 'crop_carrot', count: 2, price: 5000 }]);
      expect(sold.statusCode).toBe(200);
      expect(sold.json().parcel).toMatchObject({ farm_version: v + 1, farm: { coins: 24, sales: 1 } });
      expect(sold.json().parcel.farm.bag.crop_carrot).toBeUndefined();
      expect((await mine(app, ada)).farm).toMatchObject({ coins: 24, sales: 1 });
      expect((await command(app, ada, v + 1, [{ type: 'sell', item: 'hoe_starter', count: 1 }])).json().code).toBe('NOT_SELLABLE');
    });

    it('C-58 the same request resent or sent many times at once pays, gathers and grants only once', async () => {
      const ada = await account(app, 'Ada');
      const v = await withCarrots(app, ada, A);
      const sale = [{ type: 'sell', item: 'crop_carrot', count: 1 }];
      // A lost response retried: the second copy carries the old base version and is refused.
      expect((await command(app, ada, v, sale)).statusCode).toBe(200);
      const retry = await command(app, ada, v, sale);
      expect(retry.statusCode).toBe(409);
      expect(retry.json()).toMatchObject({ code: 'VERSION_CONFLICT', parcel: { farm_version: v + 1, farm: { coins: 12, sales: 1 } } });
      // Six identical copies at once: one lands.
      const sales = await Promise.all(Array.from({ length: 6 }, () => command(app, ada, v + 1, sale)));
      expect(sales.filter(r => r.statusCode === 200)).toHaveLength(1);
      expect(sales.filter(r => r.statusCode === 409)).toHaveLength(5);
      expect((await mine(app, ada)).farm).toMatchObject({ coins: 24, sales: 2 });
      const tree = `${A.parcel_id}:outer-groves-v2:wild_pz_tree_20:41,7:0`;
      const gathers = await Promise.all(Array.from({ length: 6 }, () => command(app, ada, v + 2, [{ type: 'gather', object: tree }])));
      expect(gathers.filter(r => r.statusCode === 200)).toHaveLength(1);
      const blueprints = await Promise.all(Array.from({ length: 6 }, () => command(app, ada, v + 3, [{ type: 'claim_blueprint', blueprint: 'coop' }])));
      expect(blueprints.filter(r => r.statusCode === 200)).toHaveLength(1);
      const after = await mine(app, ada);
      expect(after).toMatchObject({ farm_version: v + 4, farm: { coins: 24, sales: 2, blueprints_claimed: { coop: T0 + 60_000 } } });
      expect(after.farm.bag).toMatchObject({ wood: 1, blueprint_coop: 1 });
      // Even with a fresh base version, a second gather or claim is refused.
      expect((await command(app, ada, v + 4, [{ type: 'gather', object: tree }])).json().code).toBe('NOT_RESPAWNED');
      expect((await command(app, ada, v + 4, [{ type: 'claim_blueprint', blueprint: 'coop' }])).json().code).toBe('BLUEPRINT_CLAIMED');
    });

    it('C-58 gather: only one\'s own parcel; respawn follows server time; the coop blueprint needs a sale first', async () => {
      const ada = await account(app, 'Ada'), bob = await account(app, 'Bob');
      await claim(app, ada, A);
      await enter(app, ada);
      await claim(app, bob, B);
      await enter(app, bob);
      const adaTree = `${A.parcel_id}:outer-groves-v2:wild_pz_pine_01:30,2:0`;
      // Bob names Ada's tree: refused; Ada's farm is untouched.
      const before = await mine(app, ada);
      const theft = await command(app, bob, 1, [{ type: 'gather', object: adaTree }]);
      expect(theft.statusCode).toBe(422);
      expect(theft.json()).toMatchObject({ code: 'NOT_YOUR_PARCEL', parcel: { parcel_id: B.parcel_id } });
      expect(await mine(app, ada)).toEqual(before);
      expect((await command(app, ada, 1, [{ type: 'gather', object: 'p-3512001:outer-groves-v2:wild_pz_pine_01' }])).json().code).toBe('UNKNOWN_OBJECT');
      expect((await command(app, ada, 1, [{ type: 'gather', object: `${A.parcel_id}:outer-groves-v2:wild_pz_bush_05:30,2:0` }])).json().code).toBe('UNKNOWN_OBJECT');
      expect((await command(app, ada, 1, [{ type: 'claim_blueprint', blueprint: 'coop' }])).json()).toMatchObject({ code: 'CONDITION_NOT_MET' });
      expect((await command(app, ada, 1, [{ type: 'gather', object: adaTree }])).statusCode).toBe(200);
      clock = T0 + 24 * 3600_000 - 1;
      expect((await command(app, ada, 2, [{ type: 'gather', object: adaTree }])).json()).toMatchObject({ code: 'NOT_RESPAWNED', detail: { ready_at: T0 + 24 * 3600_000 } });
      clock = T0 + 24 * 3600_000;
      const again = await command(app, ada, 2, [{ type: 'gather', object: adaTree }, { type: 'sell', item: 'wood', count: 2 }, { type: 'claim_blueprint', blueprint: 'coop' }]);
      expect(again.statusCode).toBe(200);
      expect(again.json().parcel.farm).toMatchObject({ coins: 4, sales: 1, bag: { blueprint_coop: 1 } });
      expect(again.json().parcel.farm.bag.wood).toBeUndefined();
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

    it('C-130 starter zone: a player without a parcel may only claim inside it; outside is refused and nothing is stored', async () => {
      const zoned = await appFor(stores, { starterZones: zones() });
      try {
        const ada = await account(zoned, 'Ada');
        const outside = await claim(zoned, ada, FAR);
        expect(outside.statusCode).toBe(403);
        expect(outside.json()).toMatchObject({ code: 'OUTSIDE_STARTER_ZONE', starter_zone: 'test-zone' });
        expect(await mine(zoned, ada)).toBeNull();
        expect((await owners(zoned, ada, `ids=${FAR.parcel_id}`)).json().parcels[0].owner).toBe('none');
        // A fake centre inside the zone does not help an outside parcel: the zone is judged by parcel id only.
        expect((await claim(zoned, ada, { parcel_id: FAR.parcel_id, center: A.center })).json().code).toBe('OUTSIDE_STARTER_ZONE');
        // The older dataset of the same community is held to the same zone.
        expect((await claim(zoned, ada, FAR, 'sf-dynamic-farm-20261124-r6')).json().code).toBe('OUTSIDE_STARTER_ZONE');
        // Inside: claimed, with the zone's centre for the parcel rather than the one the client sent.
        const inside = await claim(zoned, ada, { parcel_id: A.parcel_id, center: [-122.5, 37.7] });
        expect(inside.statusCode).toBe(201);
        expect(inside.json().parcel).toMatchObject({ parcel_id: A.parcel_id, center: ZONE_CENTER_A });
        expect((await claim(zoned, ada, A)).statusCode).toBe(200);
        // The other rules are unchanged: one parcel per player, first come first served.
        expect((await claim(zoned, ada, B)).json().code).toBe('ALREADY_CLAIMED');
        expect((await claim(zoned, await account(zoned, 'Bob'), A)).json().code).toBe('PARCEL_TAKEN');
        // Guests are still refused before the zone when the server does not allow guest writes.
        expect((await claim(zoned, await guest(zoned), FAR)).json().code).toBe('LOGIN_REQUIRED');
      } finally { await zoned.close(); }
    });

    it('C-130 starter zone: a parcel claimed outside before the zone keeps working and is never taken back', async () => {
      const ada = await account(app, 'Ada');
      expect((await claim(app, ada, FAR)).statusCode).toBe(201);
      const before = await mine(app, ada);
      await enter(app, ada);
      const zoned = await appFor(stores, { starterZones: zones() });
      try {
        expect(await mine(zoned, ada)).toMatchObject({ parcel_id: FAR.parcel_id, center: before.center });
        // A retry of the old claim is not refused by the zone; another parcel answers the existing home as before.
        const retry = await claim(zoned, ada, FAR);
        expect(retry.statusCode).toBe(200);
        expect(retry.json().parcel.parcel_id).toBe(FAR.parcel_id);
        for (const other of [B, { parcel_id: 'p-0001002', center: FAR.center }]) {
          const res = await claim(zoned, ada, other);
          expect(res.statusCode).toBe(409);
          expect(res.json()).toMatchObject({ code: 'ALREADY_CLAIMED', parcel: { parcel_id: FAR.parcel_id } });
        }
        expect((await enter(zoned, ada)).json()).toMatchObject({ granted: false, parcel: { parcel_id: FAR.parcel_id } });
        expect((await command(zoned, ada, 1, [{ type: 'till', cell: '1,1' }])).statusCode).toBe(200);
        const bob = await account(zoned, 'Bob');
        expect((await owners(zoned, bob, `ids=${FAR.parcel_id}`)).json().parcels[0]).toMatchObject({ owner: 'other', nickname: 'Ada' });
        expect((await claim(zoned, bob, FAR)).json().code).toBe('OUTSIDE_STARTER_ZONE');
      } finally { await zoned.close(); }
    });

    it('C-143 starter zone: a parcel too small to claim is refused by the server too, and nothing is stored', async () => {
      const zoned = await appFor(stores, { starterZones: zones() });
      try {
        const ada = await account(zoned, 'Ada');
        const small = await claim(zoned, ada, SMALL);
        expect(small.statusCode).toBe(403);
        expect(small.json()).toMatchObject({ code: 'PARCEL_TOO_SMALL', starter_zone: 'test-zone' });
        expect(await mine(zoned, ada)).toBeNull();
        expect((await owners(zoned, ada, `ids=${SMALL.parcel_id}`)).json().parcels[0].owner).toBe('none');
        // The older dataset of the same community is held to the same list.
        expect((await claim(zoned, ada, SMALL, 'sf-dynamic-farm-20261124-r6')).json().code).toBe('PARCEL_TOO_SMALL');
        // Claimable parcels are claimed as before; afterwards a too-small one answers the home like any other parcel.
        expect((await claim(zoned, ada, A)).statusCode).toBe(201);
        expect((await claim(zoned, ada, SMALL)).json()).toMatchObject({ code: 'ALREADY_CLAIMED', parcel: { parcel_id: A.parcel_id } });
        // The map still sees it as a parcel inside the zone (the client judges the size itself).
        const view = await zoned.inject({ method: 'GET', url: `/v1/parcels/starter-zone?dataset_version=${DATASET}` });
        expect(view.json().zone.parcel_ids).toContain(SMALL.parcel_id);
      } finally { await zoned.close(); }
    });

    it('C-143 starter zone: a too-small parcel claimed before keeps working and is never taken back', async () => {
      const ada = await account(app, 'Ada');
      expect((await claim(app, ada, SMALL)).statusCode).toBe(201);
      await enter(app, ada);
      const zoned = await appFor(stores, { starterZones: zones() });
      try {
        expect(await mine(zoned, ada)).toMatchObject({ parcel_id: SMALL.parcel_id });
        const retry = await claim(zoned, ada, SMALL);
        expect(retry.statusCode).toBe(200);
        expect(retry.json().parcel.parcel_id).toBe(SMALL.parcel_id);
        expect((await claim(zoned, ada, A)).json()).toMatchObject({ code: 'ALREADY_CLAIMED', parcel: { parcel_id: SMALL.parcel_id } });
        expect((await enter(zoned, ada)).json()).toMatchObject({ granted: false, parcel: { parcel_id: SMALL.parcel_id } });
        expect((await command(zoned, ada, 1, [{ type: 'till', cell: '1,1' }])).statusCode).toBe(200);
        const bob = await account(zoned, 'Bob');
        expect((await owners(zoned, bob, `ids=${SMALL.parcel_id}`)).json().parcels[0]).toMatchObject({ owner: 'other', nickname: 'Ada' });
        expect((await claim(zoned, bob, SMALL)).json().code).toBe('PARCEL_TOO_SMALL');
      } finally { await zoned.close(); }
    });

    it('C-130 starter zone switched off: claims anywhere, as before', async () => {
      const off = await appFor(stores, { starterZones: zones(false) });
      try {
        expect((await claim(off, await account(off, 'Ada'), FAR)).statusCode).toBe(201);
        const zone = await off.inject({ method: 'GET', url: `/v1/parcels/starter-zone?dataset_version=${DATASET}` });
        expect(zone.json()).toMatchObject({ enabled: false, zone: null });
      } finally { await off.close(); }
    });

    it('C-130 one player racing an outside and an inside claim at once gets only the inside one', async () => {
      const zoned = await appFor(stores, { starterZones: zones() });
      try {
        const ada = await account(zoned, 'Ada');
        const results = await Promise.all([claim(zoned, ada, FAR), claim(zoned, ada, A), claim(zoned, ada, FAR)]);
        // The outside claims are refused, or answer the inside home if it landed first; none is stored.
        expect(results[1].statusCode).toBe(201);
        for (const r of [results[0], results[2]]) expect(['OUTSIDE_STARTER_ZONE', 'ALREADY_CLAIMED']).toContain(r.json().code);
        expect((await mine(zoned, ada)).parcel_id).toBe(A.parcel_id);
        expect((await owners(zoned, ada, `ids=${FAR.parcel_id}`)).json().parcels[0].owner).toBe('none');
      } finally { await zoned.close(); }
    });

    it('C-130 the starter zone is public: boundary, landing point and parcel ids; unknown datasets are refused', async () => {
      const zoned = await appFor(stores, { starterZones: zones() });
      try {
        const res = await zoned.inject({ method: 'GET', url: `/v1/parcels/starter-zone?dataset_version=${DATASET}` });
        expect(res.statusCode).toBe(200);
        expect(res.json()).toEqual({ enabled: true, server_time: T0, zone: { id: 'test-zone', community_id: 'sf', name: 'Test',
          dataset_version: DATASET, boundary: zones().zones[0].boundary, center: [-122.42, 37.775], zoom: 17,
          parcel_ids: [A.parcel_id, B.parcel_id, SMALL.parcel_id] } });
        expect((await zoned.inject({ method: 'GET', url: '/v1/parcels/starter-zone?dataset_version=other' })).statusCode).toBe(422);
        expect((await zoned.inject({ method: 'GET', url: '/v1/parcels/starter-zone' })).statusCode).toBe(400);
        const none = await app.inject({ method: 'GET', url: `/v1/parcels/starter-zone?dataset_version=${DATASET}` });
        expect(none.json()).toMatchObject({ enabled: false, zone: null });
      } finally { await zoned.close(); }
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

  it('C-58 coins and gather records written before a restart read back after it', async () => {
    const before = new pg.Pool({ connectionString: DSN, max: 5 });
    const app = await appFor(pgStores(before));
    const ada = await account(app, 'Ada');
    const v = await withCarrots(app, ada, A);
    const tree = `${A.parcel_id}:outer-groves-v2:wild_pz_tree_20:41,7:0`;
    expect((await command(app, ada, v, [{ type: 'sell', item: 'crop_carrot', count: 2 }, { type: 'gather', object: tree },
      { type: 'claim_blueprint', blueprint: 'coop' }])).statusCode).toBe(200);
    const saved = await mine(app, ada);
    await app.close();
    await before.end();

    const after = new pg.Pool({ connectionString: DSN, max: 5 });
    await migrate(after);
    const restarted = await appFor(pgStores(after));
    try {
      const read = await mine(restarted, ada);
      expect(read).toEqual(saved);
      expect(read.farm).toMatchObject({ coins: 24, sales: 1, gathered: { [tree]: T0 + 60_000 }, blueprints_claimed: { coop: T0 + 60_000 },
        bag: { wood: 1, blueprint_coop: 1 } });
      expect((await command(restarted, ada, read.farm_version, [{ type: 'gather', object: tree }])).json().code).toBe('NOT_RESPAWNED');
      expect((await command(restarted, ada, read.farm_version, [{ type: 'claim_blueprint', blueprint: 'coop' }])).json().code).toBe('BLUEPRINT_CLAIMED');
    } finally { await restarted.close(); await after.end(); }
  });

  it('C-58 two server processes selling the same request at once: coins are paid once', async () => {
    const other = new pg.Pool({ connectionString: DSN, max: 20 });
    const one = await appFor(pgStores(pool!)), two = await appFor(pgStores(other));
    try {
      const ada = await account(one, 'Ada');
      const v = await withCarrots(one, ada, A);
      const results = await Promise.all(Array.from({ length: 10 }, (_, i) => command(i % 2 ? two : one, ada, v, [{ type: 'sell', item: 'crop_carrot', count: 1 }])));
      expect(results.filter(r => r.statusCode === 200)).toHaveLength(1);
      expect(results.filter(r => r.statusCode === 409)).toHaveLength(9);
      const row = await pool!.query('SELECT farm_state, farm_version FROM parcel_claims WHERE parcel_id = $1', [A.parcel_id]);
      expect(row.rows[0]).toMatchObject({ farm_version: v + 1, farm_state: { coins: 12, sales: 1, bag: { crop_carrot: 1 } } });
    } finally { await one.close(); await two.close(); await other.end(); }
  });

  it('C-58 a C-31 era save without coins reads as 0 coins and keeps everything else; the first sale writes the new fields', async () => {
    const app = await appFor(pgStores(pool!));
    try {
      const ada = await account(app, 'Ada');
      await claim(app, ada, A);
      const legacy = { v: 1, house: { model: 'cottage', x: 6, y: 6, width: 3, depth: 3, rotation: 0, built_at: T0 }, cleared: ['1,2'], tilled: ['1,2'],
        crops: {}, bag: { hoe_starter: 1, seed_carrot: 2, crop_carrot: 1 }, welcomed_at: T0 };
      await pool!.query('UPDATE parcel_claims SET farm_state = $1, farm_version = 4 WHERE parcel_id = $2', [JSON.stringify(legacy), A.parcel_id]);
      expect((await mine(app, ada)).farm).toEqual({ ...legacy, coins: 0, sales: 0, gathered: {}, blueprints_claimed: {} });
      // Re-entering an old save still gives no gift and does not rewrite it.
      expect((await enter(app, ada)).json()).toMatchObject({ granted: false, parcel: { farm_version: 4 } });
      expect((await pool!.query('SELECT farm_state FROM parcel_claims WHERE parcel_id = $1', [A.parcel_id])).rows[0].farm_state).toEqual(legacy);
      const sold = await command(app, ada, 4, [{ type: 'sell', item: 'crop_carrot', count: 1 }]);
      expect(sold.statusCode).toBe(200);
      const stored = (await pool!.query('SELECT farm_state FROM parcel_claims WHERE parcel_id = $1', [A.parcel_id])).rows[0].farm_state;
      expect(stored).toEqual({ ...legacy, bag: { hoe_starter: 1, seed_carrot: 2 }, coins: 12, sales: 1, gathered: {}, blueprints_claimed: {} });
    } finally { await app.close(); }
  });

  it('C-136 two server processes entering one r4 claim with r6 at once: it moves once and gives back once', async () => {
    const other = new pg.Pool({ connectionString: DSN, max: 20 });
    const one = await appFor(pgStores(pool!)), two = await appFor(pgStores(other));
    try {
      const ada = await account(one, 'Ada');
      const before = await r4Farm(one, ada);
      const results = await Promise.all(Array.from({ length: 10 }, (_, i) => enterAs(i % 2 ? two : one, ada, R6)));
      expect(results.map(r => r.statusCode)).toEqual(Array(10).fill(200));
      const row = await pool!.query('SELECT dataset_version, farm_version, farm_state FROM parcel_claims WHERE parcel_id = $1', [A.parcel_id]);
      expect(row.rows[0]).toEqual({ dataset_version: R6, farm_version: 5, farm_state: rebased(before) });
    } finally { await one.close(); await two.close(); await other.end(); }
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
