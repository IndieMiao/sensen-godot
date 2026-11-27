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
import { emptyFarm, NEVER, withEconomy, type ParcelFarmState } from '../../src/parcels/farm.js';
import { emptyBoard, settleBoard } from '../../src/parcels/requests.js';
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
const appFor = (stores: Stores, opts: { reselect?: boolean; guestWrites?: boolean; starterZones?: StarterZones; rules?: typeof rules } = {}) => buildApp({
  store: stores.store, content, contentVersion: CV, blueprintDir: path.join(ROOT, 'assets', 'blueprints'),
  regionsFile: REGIONS, pepper: 'test-pepper', now: () => clock, realtimeEnabled: false, guestWrites: opts.guestWrites,
  parcels: { store: stores.parcels, rules: opts.rules ?? rules, reselect: opts.reselect ?? false, starterZones: opts.starterZones },
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
/** C-151：井放在这里（建筑 2，小屋之后），打水并浇 cells。 */
const WELL = { type: 'place_building', building: 'well', x: 20, y: 20, rotation: 0 };
const wet = (well: number, ...cells: string[]) => [{ type: 'draw_water', building: well }, ...cells.map(cell => ({ type: 'water', cell }))];
/** r4 上认领、进入，盖房和井、清障碍、开垦三格、种两颗（一颗熟一颗没熟）、卖一次、领鸡舍蓝图、采一棵树；返回此时的地块。 */
async function r4Farm(app: FastifyInstance, token: string, parcel = A) {
  await claim(app, token, parcel);
  await enter(app, token);
  await command(app, token, 1, [{ type: 'place_house', x: 9, y: 9 }, WELL, { type: 'clear_obstacle', cell: '3,3' }, { type: 'till', cell: '1,1' },
    { type: 'till', cell: '2,1' }, { type: 'till', cell: '3,1' }, { type: 'sow', cell: '1,1', crop: 'crop_carrot' }, ...wet(2, '1,1')]);
  clock = T0 + 60_000;
  await command(app, token, 2, [{ type: 'harvest', cell: '1,1' }, { type: 'sell', item: 'crop_carrot', count: 1 }, { type: 'claim_blueprint', blueprint: 'coop' },
    { type: 'sow', cell: '1,1', crop: 'crop_carrot' }, { type: 'gather', object: `${parcel.parcel_id}:outer-groves-v2:wild_pz_tree_20:41,7:0` }]);
  clock = T0 + 90_000;
  const res = await command(app, token, 3, [{ type: 'sow', cell: '2,1', crop: 'crop_carrot' }]);
  expect(res.statusCode).toBe(200);
  const farm = res.json().parcel;
  expect(farm).toMatchObject({ dataset_version: DATASET, farm_version: 4, farm: { coins: 12, sales: 1, bag: { hoe_starter: 1, blueprint_coop: 1, wood: 1, pail: 1 } } });
  expect(Object.keys(farm.farm.crops)).toEqual(['1,1', '2,1']);
  return farm;
}
/** 换到 r6 之后应有的样子：格子上的清空，每棵作物退一颗种子、每栋建筑退它的蓝图（小屋、井），其余（水桶和桶里的水）不动。 */
const rebased = (before: { farm: Record<string, unknown> }) => ({ ...before.farm, buildings: [], house: null, cleared: [], tilled: [], crops: {}, gathered: {},
  bag: { hoe_starter: 1, blueprint_coop: 1, wood: 1, pail: 1, seed_carrot: 2, blueprint_cottage: 1, blueprint_well: 1 } });
const GIFT = { hoe_starter: 1, seed_carrot: 3, blueprint_cottage: 1 };
/** C-151 的一次性补发：井的蓝图和水桶。 */
const WATERING = { blueprint_well: 1, pail: 1 };
/** 首次进入后的背包：赠品加补发。 */
const FIRST_BAG = { ...GIFT, ...WATERING };
const command = (app: FastifyInstance, token: string, base_version: number, commands: object[]) =>
  app.inject({ method: 'POST', url: '/v1/parcels/mine/commands', headers: bearer(token), payload: { base_version, commands } });
/** 认领、进入、种两颗萝卜、盖井浇水并在 60 秒后收获；返回此时的 farm_version，时钟停在 T0 + 60 s。 */
async function withCarrots(app: FastifyInstance, token: string, parcel: { parcel_id: string; center: number[] }): Promise<number> {
  await claim(app, token, parcel);
  await enter(app, token);
  expect((await command(app, token, 1, [{ type: 'till', cell: '1,1' }, { type: 'till', cell: '2,1' },
    { type: 'sow', cell: '1,1', crop: 'crop_carrot' }, { type: 'sow', cell: '2,1', crop: 'crop_carrot' }, WELL, ...wet(1, '1,1', '2,1')])).statusCode).toBe(200);
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
        center: A.center, claimed_at: T0, farm_version: 0, farm: { ...emptyFarm(), energy: { value: 200, at: T0, rested_on: null } } });
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
      // C-151: the well blueprint and the pail come with it, in the same write, and gift names all of it.
      expect(first.json()).toMatchObject({ granted: true, gift: FIRST_BAG, parcel: { farm_version: 1, farm: { bag: FIRST_BAG, welcomed_at: T0, grants: { watering: T0 } } } });
      clock = T0 + 1000;
      const again = await enter(app, ada);
      expect(again.json()).toMatchObject({ granted: false, gift: {}, parcel: { farm_version: 1, farm: { bag: FIRST_BAG, welcomed_at: T0 } } });
      // A lost response retried many times at once still grants nothing more.
      const retries = await Promise.all(Array.from({ length: 5 }, () => enter(app, ada)));
      expect(retries.map(r => r.json().granted)).toEqual(Array(5).fill(false));
      // Spending the gift and entering again does not refill it.
      await command(app, ada, 1, [{ type: 'place_house', x: 9, y: 9 }, WELL, { type: 'till', cell: '1,1' }, { type: 'sow', cell: '1,1', crop: 'crop_carrot' }]);
      expect((await enter(app, ada)).json()).toMatchObject({ granted: false, gift: {}, parcel: { farm_version: 2, farm: { bag: { hoe_starter: 1, seed_carrot: 2, pail: 1 } } } });
      // Re-claiming the same parcel (a retry) does not reset the farm either.
      expect((await claim(app, ada, A)).json().parcel.farm.bag).toEqual({ hoe_starter: 1, seed_carrot: 2, pail: 1 });
    });

    it('simultaneous first entries grant the gift exactly once', async () => {
      const ada = await account(app, 'Ada');
      await claim(app, ada, A);
      const results = await Promise.all(Array.from({ length: 6 }, () => enter(app, ada)));
      expect(results.filter(r => r.json().granted)).toHaveLength(1);
      expect(results.filter(r => Object.keys(r.json().gift).length)).toHaveLength(1);
      expect(await mine(app, ada)).toMatchObject({ farm_version: 1, farm: { bag: FIRST_BAG } });
    });

    it('C-151 a farm from before watering gets the well blueprint and the pail on its next entry, once, even entered many times at once', async () => {
      // The same stores served first by a server whose rules have no grants yet (0.4.4), then by the 0.4.5 one.
      const old = await appFor(stores, { rules: { ...rules, grants: {} } });
      const ada = await account(old, 'Ada');
      await claim(old, ada, A);
      expect((await enter(old, ada)).json()).toMatchObject({ granted: true, gift: GIFT, parcel: { farm_version: 1, farm: { bag: GIFT, grants: {} } } });
      await command(old, ada, 1, [{ type: 'place_house', x: 9, y: 9 }, { type: 'till', cell: '1,1' }, { type: 'sow', cell: '1,1', crop: 'crop_carrot' }]);
      await old.close();
      clock = T0 + 86_400_000;
      const results = await Promise.all(Array.from({ length: 5 }, () => enter(app, ada)));
      expect(results.map(r => r.json().granted)).toEqual(Array(5).fill(false));
      expect(results.filter(r => Object.keys(r.json().gift).length).map(r => r.json().gift)).toEqual([WATERING]);
      expect(await mine(app, ada)).toMatchObject({ farm_version: 3, farm: { bag: { hoe_starter: 1, seed_carrot: 2, ...WATERING }, grants: { watering: clock } } });
      // Spent (the well built) and entered again: nothing more.
      await command(app, ada, 3, [WELL]);
      expect((await enter(app, ada)).json()).toMatchObject({ gift: {}, parcel: { farm_version: 4, farm: { bag: { hoe_starter: 1, seed_carrot: 2, pail: 1 } } } });
    });

    it('C-209 an 8×6 barn built before its cutout reads as taken down and given back; the next entry writes that once; the 11×6 goes down where it stood', async () => {
      // Built and fed under C-192's rules (8×6, no cutout); the materials and carrots come as a one-off grant there.
      const { cutouts: _cutouts, ...barn } = rules.buildings.barn;
      const old = await appFor(stores, { rules: { ...rules, buildings: { ...rules.buildings, barn: { ...barn, width: 8 } },
        grants: { ...rules.grants, c192: { blueprint_barn: 1, wood: 20, stone: 10, crop_carrot: 2 } } } });
      const ada = await account(old, 'Ada');
      await claim(old, ada, A);
      await enter(old, ada);
      expect((await command(old, ada, 1, [{ type: 'place_building', building: 'barn', x: 20, y: 20, rotation: 0 }, { type: 'feed', building: 1 }])).statusCode).toBe(200);
      expect((await mine(old, ada)).farm).toMatchObject({ buildings: [{ type: 'barn', width: 8 }], drops: [{ id: 1, item: 'milk' }] });
      await old.close();
      const read = await mine(app, ada);
      expect(read).toMatchObject({ farm_version: 2, farm: { buildings: [], drops: [], drop_seq: 1, bag: { ...FIRST_BAG, blueprint_barn: 1, wood: 20, stone: 10, milk: 1 } } });
      const results = await Promise.all(Array.from({ length: 4 }, () => enter(app, ada)));
      expect(results.map(r => [r.json().gift, r.json().parcel.farm.bag])).toEqual(Array(4).fill([{}, read.farm.bag]));
      expect(await mine(app, ada)).toEqual({ ...read, farm_version: 3 });
      const placed = await command(app, ada, 3, [{ type: 'place_building', building: 'barn', x: 20, y: 20, rotation: 0 }]);
      expect(placed.json().parcel).toMatchObject({ farm_version: 4, farm: { buildings: [{ id: 1, type: 'barn', width: 11, cutouts: [[0, 0, 2, 2]] }],
        bag: { ...FIRST_BAG, milk: 1 } } });
      expect((await enter(app, ada)).json().parcel.farm_version).toBe(4);
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
      expect((await command(app, ada, 5, [{ type: 'place_house', x: 2, y: 2 }, { ...WELL, x: 6, y: 2 }, { type: 'till', cell: '9,9' }, { type: 'sow', cell: '9,9', crop: 'crop_carrot' }])).statusCode).toBe(200);
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
      expect((await enterAs(app, bob, R6)).json()).toMatchObject({ granted: true, parcel: { dataset_version: R6, farm_version: 1, farm: { bag: FIRST_BAG } } });
      expect((await enterAs(app, bob, DATASET)).json()).toMatchObject({ granted: false, parcel: { dataset_version: R6, farm_version: 1 } });
    });

    it('C-136 a never-entered r4 claim moves to r6 and gets the first-entry gift in the same write', async () => {
      const ada = await account(app, 'Ada');
      await claim(app, ada, A);
      const results = await Promise.all(Array.from({ length: 4 }, () => enterAs(app, ada, R6)));
      expect(results.filter(r => r.json().granted)).toHaveLength(1);
      expect(await mine(app, ada)).toMatchObject({ dataset_version: R6, farm_version: 1, farm: { bag: FIRST_BAG, welcomed_at: T0, house: null, tilled: [] } });
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
      // C-151: sown dry, it does not grow until watered.
      expect(res.json().parcel.farm.crops['2,2']).toEqual({ crop: 'crop_carrot', planted_at: T0, ripe_at: NEVER, watered_at: null });
      clock = T0 + 3600_000;
      const dry = await command(app, ada, 3, [{ type: 'harvest', cell: '2,2' }]);
      expect(dry.statusCode).toBe(422);
      expect(dry.json()).toMatchObject({ code: 'NOT_WATERED', index: 0, parcel: { farm_version: 3 } });
      const W = clock;
      expect((await command(app, ada, 3, [WELL, ...wet(2, '2,2')])).statusCode).toBe(200);
      const refused = await command(app, ada, 4, [{ type: 'harvest', cell: '2,2' }]);
      expect(refused.statusCode).toBe(422);
      expect(refused.json()).toMatchObject({ code: 'NOT_RIPE', index: 0, detail: { ripe_at: W + 60_000 }, parcel: { farm_version: 4 } });
      clock = W + 59_999;
      expect((await command(app, ada, 4, [{ type: 'harvest', cell: '2,2' }])).json().code).toBe('NOT_RIPE');
      clock = W + 60_000;
      const harvested = await command(app, ada, 4, [{ type: 'harvest', cell: '2,2' }]);
      expect(harvested.statusCode).toBe(200);
      expect(await mine(app, ada)).toMatchObject({ farm_version: 5, farm: {
        buildings: [{ id: 1, type: 'cottage', model: 'cottage', x: 10, y: 4, width: 3, depth: 3, rotation: 1, built_at: T0 },
          { id: 2, type: 'well', model: 'well', x: 20, y: 20, width: 1, depth: 1, rotation: 0, built_at: W }],
        house: { model: 'cottage', x: 10, y: 4, width: 3, depth: 3, rotation: 1, built_at: T0 },
        cleared: ['2,2'], tilled: ['1,1', '2,2'], crops: {}, bag: { hoe_starter: 1, seed_carrot: 2, crop_carrot: 1, pail: 1 }, pail_water: 2,
      } });
      expect((await command(app, ada, 5, [{ type: 'teleport' }])).statusCode).toBe(400);
      // C-150 place_building: the shape is checked (400), an unknown type or a second cottage is refused (422) and changes nothing.
      expect((await command(app, ada, 5, [{ type: 'place_building', building: 'cottage', x: 1, y: 1, rotation: 4 }])).statusCode).toBe(400);
      expect((await command(app, ada, 5, [{ type: 'place_building', x: 1, y: 1 }])).statusCode).toBe(400);
      expect((await command(app, ada, 5, [{ type: 'place_building', building: 'silo', x: 30, y: 30 }])).json())
        .toMatchObject({ code: 'UNKNOWN_BUILDING', index: 0, detail: { building: 'silo' }, parcel: { farm_version: 5 } });
      expect((await command(app, ada, 5, [{ type: 'place_building', building: 'cottage', x: 30, y: 30 }])).json())
        .toMatchObject({ code: 'BUILDING_LIMIT', detail: { building: 'cottage', max: 1 }, parcel: { farm_version: 5 } });
      // C-151 draw_water and water: the shape is checked (400); the server's own refusals keep the save.
      expect((await command(app, ada, 5, [{ type: 'draw_water', building: 'well' }])).statusCode).toBe(400);
      expect((await command(app, ada, 5, [{ type: 'water', cell: 'x' }])).statusCode).toBe(400);
      expect((await command(app, ada, 5, [{ type: 'water', cell: '1,1' }])).json()).toMatchObject({ code: 'NO_CROP', parcel: { farm_version: 5 } });
      expect((await command(app, ada, 5, [{ type: 'draw_water', building: 1 }])).json()).toMatchObject({ code: 'NO_WELL', detail: { building: 1 }, parcel: { farm_version: 5 } });
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

    it('C-149 buy: carrot seeds at the configured 9 coins whatever the request says; too few coins changes nothing', async () => {
      const ada = await account(app, 'Ada');
      const v = await withCarrots(app, ada, A);
      const broke = await command(app, ada, v, [{ type: 'buy', item: 'seed_carrot', count: 1 }]);
      expect(broke.statusCode).toBe(422);
      expect(broke.json()).toMatchObject({ code: 'NOT_ENOUGH_COINS', detail: { coins: 0, need: 9 }, parcel: { farm_version: v } });
      const before = await mine(app, ada);
      expect(before.farm_version).toBe(v);
      expect((await command(app, ada, v, [{ type: 'sell', item: 'crop_carrot', count: 2 }])).statusCode).toBe(200);
      // A price in the request is ignored; the configured 9 applies.
      const bought = await command(app, ada, v + 1, [{ type: 'buy', item: 'seed_carrot', count: 2, price: 0 }]);
      expect(bought.statusCode).toBe(200);
      expect(bought.json().parcel).toMatchObject({ farm_version: v + 2, farm: { coins: 6, sales: 1 } });
      const seeds = before.farm.bag.seed_carrot ?? 0;
      expect((await mine(app, ada)).farm).toMatchObject({ coins: 6, bag: { seed_carrot: seeds + 2 } });
      // 6 coins cannot pay for a 9-coin seed: refused and the save is the same.
      const short = await command(app, ada, v + 2, [{ type: 'buy', item: 'seed_carrot', count: 1, price: 1 }]);
      expect(short.statusCode).toBe(422);
      expect(short.json()).toMatchObject({ code: 'NOT_ENOUGH_COINS', detail: { coins: 6, need: 9 } });
      expect(await mine(app, ada)).toMatchObject({ farm_version: v + 2, farm: { coins: 6, bag: { seed_carrot: seeds + 2 } } });
      expect((await command(app, ada, v + 2, [{ type: 'buy', item: 'crop_carrot', count: 1 }])).json().code).toBe('NOT_FOR_SALE');
    });

    it('C-152 upgrade_farm: short of wood, stone or coins is refused and the save stays; paid, the farm is Lv2 with 10 more max Energy', async () => {
      const ada = await account(app, 'Ada');
      await claim(app, ada, A);
      await enter(app, ada);
      const short = await command(app, ada, 1, [{ type: 'upgrade_farm' }]);
      expect(short.statusCode).toBe(422);
      expect(short.json()).toMatchObject({ code: 'NOT_ENOUGH', detail: { item: 'wood', have: 0, need: 6 }, parcel: { farm_version: 1, farm: { level: 1 } } });
      // 40 trees and 20 rocks of one's own outer ring (2 Energy each), 34 Timber and 16 Stone sold for 100 coins: Lv2's 100 coins (Q-282), 6 Timber and 4 Stone.
      const tree = (x: number) => ({ type: 'gather', object: `${A.parcel_id}:outer-groves-v2:wild_pz_tree_20:${x},7:0` });
      const rock = (x: number) => ({ type: 'gather', object: `${A.parcel_id}:outer-groves-v2:wild_pz_rock_08:${x},9:0` });
      expect((await command(app, ada, 1, Array.from({ length: 40 }, (_, i) => tree(40 + i)))).statusCode).toBe(200);
      const stocked = await command(app, ada, 2, [...Array.from({ length: 20 }, (_, i) => rock(40 + i)),
        { type: 'sell', item: 'wood', count: 34 }, { type: 'sell', item: 'stone', count: 16 }]);
      expect(stocked.json().parcel.farm).toMatchObject({ coins: 100, bag: { wood: 6, stone: 4 }, energy: { value: 80 } });
      // 9 coins short after a seed: refused whole, nothing taken.
      expect((await command(app, ada, 3, [{ type: 'buy', item: 'seed_carrot', count: 1 }, { type: 'upgrade_farm' }])).json())
        .toMatchObject({ code: 'NOT_ENOUGH_COINS', index: 1, detail: { coins: 91, need: 100 }, parcel: { farm_version: 3, farm: { coins: 100, level: 1 } } });
      expect(await mine(app, ada)).toMatchObject({ farm_version: 3, farm: { level: 1, coins: 100, bag: { wood: 6, stone: 4 } } });
      const up = await command(app, ada, 3, [{ type: 'upgrade_farm' }]);
      expect(up.statusCode).toBe(200);
      const farm = up.json().parcel.farm;
      expect(farm).toMatchObject({ level: 2, coins: 0, energy: { value: 80 } });
      expect(farm.bag.wood).toBeUndefined();
      expect(farm.bag.stone).toBeUndefined();
      expect((await mine(app, ada)).farm).toMatchObject({ level: 2, coins: 0 });
      // Lv3 asks for 10 Timber: refused, still Lv2.
      expect((await command(app, ada, 4, [{ type: 'upgrade_farm' }])).json()).toMatchObject({ code: 'NOT_ENOUGH', detail: { item: 'wood', have: 0, need: 10 } });
      expect(await mine(app, ada)).toMatchObject({ farm_version: 4, farm: { level: 2 } });
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

    it('C-148 Energy over HTTP: the price comes off, 422 NO_ENERGY keeps the save and its version, time brings it back', async () => {
      const ada = await account(app, 'Ada');
      await claim(app, ada, A);
      expect((await enter(app, ada)).json().parcel.farm.energy).toEqual({ value: 200, at: T0, rested_on: null });
      // 100 tills at 2 Energy spend the whole pool of 200.
      const row = (y: number) => Array.from({ length: 50 }, (_, x) => ({ type: 'till', cell: `${x},${y}` }));
      expect((await command(app, ada, 1, row(0))).json().parcel.farm.energy).toEqual({ value: 100, at: T0, rested_on: null });
      expect((await command(app, ada, 2, row(1))).json().parcel.farm.energy.value).toBe(0);
      const refused = await command(app, ada, 3, [{ type: 'till', cell: '0,2' }]);
      expect(refused.statusCode).toBe(422);
      // Newcomer (entered at T0): the next point in 2:40.
      expect(refused.json()).toMatchObject({ code: 'NO_ENERGY', index: 0, detail: { need: 2, have: 0, next_in: 160_000 },
        parcel: { farm_version: 3, farm: { energy: { value: 0, at: T0 } } } });
      expect((await mine(app, ada)).farm.tilled).toHaveLength(100);
      clock = T0 + 2 * 160_000;
      const later = await command(app, ada, 3, [{ type: 'till', cell: '0,2' }]);
      expect(later.statusCode).toBe(200);
      expect(later.json().parcel).toMatchObject({ farm_version: 4, farm: { energy: { value: 0, at: T0 + 2 * 160_000 } } });
    });

    it('C-154 coop over HTTP: an egg laid on the ground stays through re-reads and re-entry; picked once, even sent many times at once', async () => {
      const ada = await account(app, 'Ada');
      let v = await withCarrots(app, ada, A);
      // Sell one carrot, take Scott's coop blueprint, build the coop turned a quarter (building 2, after C-151's well), feed the other carrot.
      const built = await command(app, ada, v, [{ type: 'sell', item: 'crop_carrot', count: 1 }, { type: 'claim_blueprint', blueprint: 'coop' },
        { type: 'place_building', building: 'coop', x: 22, y: 22, rotation: 1 }, { type: 'feed', building: 2 }]);
      expect(built.statusCode).toBe(200);
      const laidAt = T0 + 60_000 + 120_000;
      expect(built.json().parcel.farm).toMatchObject({ bag: { hoe_starter: 1, pail: 1 }, drop_seq: 1,
        buildings: [{ type: 'well' }, { id: 2, type: 'coop', width: 7, depth: 5, rotation: 1, animals: ['hen_white', 'hen_brown', 'hen_white'] }],
        drops: [{ id: 1, item: 'egg', amount: 1, building: 2, animal: 0, ready_at: laidAt }] });
      v += 1;
      // No carrot left: refused, save and version unchanged.
      const hungry = await command(app, ada, v, [{ type: 'feed', building: 2 }]);
      expect(hungry.json()).toMatchObject({ code: 'NO_FEED', parcel: { farm_version: v } });
      // Logged off and back later: the egg lies there.
      clock = laidAt + 3_600_000;
      expect((await mine(app, ada)).farm.drops).toEqual(built.json().parcel.farm.drops);
      expect((await enter(app, ada)).json().parcel.farm.drops).toHaveLength(1);
      // The same pickup sent eight times at once: one egg.
      const results = await Promise.all(Array.from({ length: 8 }, () => command(app, ada, v, [{ type: 'pick_up', drop: 1 }])));
      expect(results.filter(r => r.statusCode === 200)).toHaveLength(1);
      const after = await mine(app, ada);
      expect(after.farm).toMatchObject({ bag: { egg: 1 }, drops: [] });
      expect((await command(app, ada, after.farm_version, [{ type: 'pick_up', drop: 1 }])).json()).toMatchObject({ code: 'NO_DROP' });
      const sold = await command(app, ada, after.farm_version, [{ type: 'sell', item: 'egg', count: 1 }]);
      expect(sold.json().parcel.farm).toMatchObject({ coins: 32, sales: 2 });
    });

    it('C-181 barn over HTTP: the blueprint bought with coins, built with materials, two carrots give one milk that stays through re-entry and is picked once', async () => {
      // The shipped numbers (600 coins from farm level 2, 20 Timber + 10 Stone; SEN-Q-282) are farm.test.ts's; here only the price, level
      // and materials are scaled down to what a fresh farm reaches over HTTP: the blueprint 2 coins (one Timber sold) at level 1, 1 Timber
      // to build. Feed (2 carrots) and timing are the shipped ones.
      const cheap = structuredClone(rules);
      cheap.economy.blueprints.barn.coins = 2;
      cheap.economy.blueprints.barn.min_level = 1;
      cheap.buildings.barn.materials = { wood: 1 };
      const barnApp = await appFor(stores, { rules: cheap });
      try {
        const ada = await account(barnApp, 'Ada');
        let v = await withCarrots(barnApp, ada, A);
        const tree = (y: number) => `${A.parcel_id}:outer-groves-v2:wild_pz_tree_20:41,${y}:0`;
        const poor = await command(barnApp, ada, v, [{ type: 'claim_blueprint', blueprint: 'barn' }]);
        expect(poor.statusCode).toBe(422);
        expect(poor.json()).toMatchObject({ code: 'NOT_ENOUGH_COINS', detail: { coins: 0, need: 2 }, parcel: { farm_version: v } });
        const built = await command(barnApp, ada, v, [{ type: 'gather', object: tree(7) }, { type: 'gather', object: tree(8) },
          { type: 'sell', item: 'wood', count: 1 }, { type: 'claim_blueprint', blueprint: 'barn' },
          { type: 'place_building', building: 'barn', x: 22, y: 22, rotation: 1 }, { type: 'feed', building: 2 }]);
        expect(built.statusCode).toBe(200);
        const givenAt = T0 + 60_000 + 900_000;
        expect(built.json().parcel.farm).toMatchObject({ coins: 0, blueprints_claimed: { barn: T0 + 60_000 }, drop_seq: 1,
          buildings: [{ type: 'well' }, { id: 2, type: 'barn', width: 11, depth: 6, rotation: 1, animals: ['cow', 'cow'], cutouts: [[0, 0, 2, 2]] }],
          drops: [{ id: 1, item: 'milk', amount: 1, building: 2, animal: 0, ready_at: givenAt }] });
        expect(built.json().parcel.farm.bag).toEqual({ hoe_starter: 1, seed_carrot: 1, blueprint_cottage: 1, pail: 1 });
        v += 1;
        expect((await command(barnApp, ada, v, [{ type: 'feed', building: 2 }])).json()).toMatchObject({ code: 'NO_FEED', parcel: { farm_version: v } });
        expect((await command(barnApp, ada, v, [{ type: 'claim_blueprint', blueprint: 'barn' }])).json()).toMatchObject({ code: 'BLUEPRINT_CLAIMED' });
        clock = givenAt + 3_600_000;
        expect((await mine(barnApp, ada)).farm.drops).toEqual(built.json().parcel.farm.drops);
        expect((await enter(barnApp, ada)).json().parcel.farm.drops).toHaveLength(1);
        const results = await Promise.all(Array.from({ length: 8 }, () => command(barnApp, ada, v, [{ type: 'pick_up', drop: 1 }])));
        expect(results.filter(r => r.statusCode === 200)).toHaveLength(1);
        const after = await mine(barnApp, ada);
        expect(after.farm).toMatchObject({ bag: { milk: 1 }, drops: [] });
        expect((await command(barnApp, ada, after.farm_version, [{ type: 'pick_up', drop: 1 }])).json()).toMatchObject({ code: 'NO_DROP' });
        expect((await command(barnApp, ada, after.farm_version, [{ type: 'sell', item: 'milk', count: 1 }])).json().parcel.farm).toMatchObject({ coins: 45 });
      } finally { await barnApp.close(); }
    });

    it('C-182 sheep pen over HTTP: locked until 15 requests and level 3; bought, built, three Wild Herbs give one wool that stays through re-entry and is picked once', async () => {
      // The shipped rules: a fresh farm (no request delivered, level 1) cannot buy it; the save and its version stay.
      const bob = await account(app, 'Bob');
      await claim(app, bob, B);
      await enter(app, bob);
      const locked = await command(app, bob, 1, [{ type: 'claim_blueprint', blueprint: 'sheep_pen' }]);
      expect(locked.statusCode).toBe(422);
      expect(locked.json()).toMatchObject({ code: 'CONDITION_NOT_MET', detail: { requests_done: 0, min_requests: 15 }, parcel: { farm_version: 1 } });
      expect((await mine(app, bob)).farm.blueprints_claimed).toEqual({});
      // The shipped numbers (15 requests, farm level 3, 1,200 coins, 15 Timber + 15 Stone; SEN-Q-282) are farm.test.ts's; here the unlock,
      // price and materials are scaled down to what a fresh farm reaches over HTTP: no request, level 1, 2 coins (one Timber sold), 1 Timber
      // to build. Feed (3 Wild Herbs) and timing are the shipped ones.
      const cheap = structuredClone(rules);
      Object.assign(cheap.economy.blueprints.sheep_pen, { coins: 2, min_level: 1, min_requests: 0 });
      cheap.buildings.sheep_pen.materials = { wood: 1 };
      const penApp = await appFor(stores, { rules: cheap });
      try {
        const ada = await account(penApp, 'Ada');
        let v = await withCarrots(penApp, ada, A);
        const outer = (model: string, y: number) => `${A.parcel_id}:outer-groves-v2:${model}:41,${y}:0`;
        const built = await command(penApp, ada, v, [{ type: 'gather', object: outer('wild_pz_tree_20', 7) }, { type: 'gather', object: outer('wild_pz_tree_20', 8) },
          ...[11, 12, 13].map(y => ({ type: 'gather', object: outer('wild_pz_flower_20', y) })),
          { type: 'sell', item: 'wood', count: 1 }, { type: 'claim_blueprint', blueprint: 'sheep_pen' },
          { type: 'place_building', building: 'sheep_pen', x: 22, y: 22, rotation: 1 }, { type: 'feed', building: 2 }]);
        expect(built.statusCode).toBe(200);
        const givenAt = T0 + 60_000 + 1_800_000;
        expect(built.json().parcel.farm).toMatchObject({ coins: 0, blueprints_claimed: { sheep_pen: T0 + 60_000 }, drop_seq: 1,
          buildings: [{ type: 'well' }, { id: 2, type: 'sheep_pen', width: 6, depth: 6, rotation: 1, animals: ['sheep', 'sheep', 'sheep', 'sheep'] }],
          drops: [{ id: 1, item: 'wool', amount: 1, building: 2, animal: 0, ready_at: givenAt }] });
        expect(built.json().parcel.farm.bag.wild_herb).toBeUndefined();
        v += 1;
        expect((await command(penApp, ada, v, [{ type: 'feed', building: 2 }])).json()).toMatchObject({ code: 'NO_FEED', detail: { item: 'wild_herb' }, parcel: { farm_version: v } });
        expect((await command(penApp, ada, v, [{ type: 'claim_blueprint', blueprint: 'sheep_pen' }])).json()).toMatchObject({ code: 'BLUEPRINT_CLAIMED' });
        clock = givenAt + 3_600_000;
        expect((await mine(penApp, ada)).farm.drops).toEqual(built.json().parcel.farm.drops);
        expect((await enter(penApp, ada)).json().parcel.farm.drops).toHaveLength(1);
        const results = await Promise.all(Array.from({ length: 8 }, () => command(penApp, ada, v, [{ type: 'pick_up', drop: 1 }])));
        expect(results.filter(r => r.statusCode === 200)).toHaveLength(1);
        const after = await mine(penApp, ada);
        expect(after.farm).toMatchObject({ bag: { wool: 1 }, drops: [] });
        expect((await command(penApp, ada, after.farm_version, [{ type: 'pick_up', drop: 1 }])).json()).toMatchObject({ code: 'NO_DROP' });
        expect((await command(penApp, ada, after.farm_version, [{ type: 'sell', item: 'wool', count: 1 }])).json().parcel.farm).toMatchObject({ coins: 30 });
      } finally { await penApp.close(); }
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
        // A fresh farm reads at full Energy (C-148), the rest as empty.
        expect(again.json().parcel.farm).toEqual({ ...emptyFarm(), energy: { value: 200, at: clock, rested_on: null } });
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

    it('C-191 the board the read shows is the one the commands find; a delivery pays, refills the slot and is saved', async () => {
      const ada = await account(app, 'Ada');
      const version = await withCarrots(app, ada, A);
      // Read twice with no command between: the same two requests, drawn at the first entry (T0), not at the read.
      const first = (await mine(app, ada)).farm.board;
      clock = T0 + 3_600_000;
      const read = await mine(app, ada);
      expect(read.farm.board).toEqual(first);
      expect(first.slots.map((sl: { req: { id: number; drawn_at: number } }) => [sl.req.id, sl.req.drawn_at])).toEqual([[1, T0], [2, T0]]);
      // At T0 the first entry draws 5 carrots (slot 1) and 4 timber (slot 2), as request_cases.json's first case (C-197 counts).
      expect(first.slots.map((sl: { req: { item: string; qty: number } }) => [sl.req.item, sl.req.qty])).toEqual([['crop_carrot', 5], ['wood', 4]]);
      // Only 2 carrots: refused, the save and its version unchanged.
      const short = await command(app, ada, version, [{ type: 'deliver_request', request: 1 }]);
      expect(short.statusCode).toBe(422);
      expect(short.json()).toMatchObject({ code: 'NOT_ENOUGH', detail: { item: 'crop_carrot', have: 2, need: 5 }, parcel: { farm_version: version } });
      // Four trees for the timber, then deliver it: Jasmine's 2 × 4 + 10 (SEN-Q-281).
      const trees = [41, 42, 43, 44].map(x => ({ type: 'gather', object: `${A.parcel_id}:outer-groves-v2:wild_pz_tree_20:${x},7:0` }));
      const res = await command(app, ada, version, [...trees, { type: 'deliver_request', request: 2 }]);
      expect(res.statusCode).toBe(200);
      const farm = res.json().parcel.farm;
      expect(farm.coins).toBe(4 * 2 + 10);
      expect(farm.bag.wood).toBeUndefined();
      expect(farm.requests_done).toBe(1);
      expect(farm.board.slots[1].req).toMatchObject({ id: 3, drawn_at: T0 + 3_600_000, status: 'open' });
      expect(farm.board.slots[0].req).toEqual(first.slots[0].req);
      expect((await mine(app, ada)).farm).toEqual(farm);
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
      { type: 'sow', cell: '1,2', crop: 'crop_carrot' }, WELL, ...wet(2, '1,2')]);
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
      expect(read.farm).toMatchObject({ house: { x: 6, y: 6 }, cleared: ['1,2'], tilled: ['1,2'], pail_water: 2, grants: { watering: T0 },
        crops: { '1,2': { crop: 'crop_carrot', planted_at: T0, ripe_at: T0 + 60_000, watered_at: T0 } }, bag: { hoe_starter: 1, seed_carrot: 2, pail: 1 }, welcomed_at: T0 });
      // Reopening after the restart does not give the first-entry gift or the watering grant again.
      expect((await enter(restarted, ada)).json()).toMatchObject({ granted: false, gift: {}, parcel: { farm_version: read.farm_version, farm: { bag: { hoe_starter: 1, seed_carrot: 2, pail: 1 } } } });
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

  it('C-154 an egg on the ground written before a restart reads back after it and is picked once across two processes', async () => {
    const before = new pg.Pool({ connectionString: DSN, max: 5 });
    const app = await appFor(pgStores(before));
    const ada = await account(app, 'Ada');
    const v = await withCarrots(app, ada, A);
    expect((await command(app, ada, v, [{ type: 'sell', item: 'crop_carrot', count: 1 }, { type: 'claim_blueprint', blueprint: 'coop' },
      { type: 'place_building', building: 'coop', x: 22, y: 22, rotation: 1 }, { type: 'feed', building: 2 }])).statusCode).toBe(200);
    const saved = await mine(app, ada);
    await app.close();
    await before.end();

    clock = T0 + 60_000 + 120_000;
    const after = new pg.Pool({ connectionString: DSN, max: 5 });
    const other = new pg.Pool({ connectionString: DSN, max: 5 });
    await migrate(after);
    const one = await appFor(pgStores(after)), two = await appFor(pgStores(other));
    try {
      const read = await mine(one, ada);
      expect(read.farm.drops).toEqual(saved.farm.drops);
      expect(read.farm.drops).toHaveLength(1);
      const results = await Promise.all(Array.from({ length: 6 }, (_, i) => command(i % 2 ? two : one, ada, read.farm_version, [{ type: 'pick_up', drop: 1 }])));
      expect(results.filter(r => r.statusCode === 200)).toHaveLength(1);
      const row = await pool!.query('SELECT farm_state FROM parcel_claims WHERE parcel_id = $1', [A.parcel_id]);
      expect(row.rows[0].farm_state).toMatchObject({ bag: { egg: 1 }, drops: [], drop_seq: 1 });
    } finally { await one.close(); await two.close(); await after.end(); await other.end(); }
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
      // C-150: the old house reads as building 1, a cottage, where it stood and facing as it did; house stays for old clients.
      const buildings = [{ id: 1, type: 'cottage', ...legacy.house }];
      // C-148: a save from before Energy also reads at full Energy, nothing else changes.
      const full = { value: 200, at: clock, rested_on: null };
      // C-151: and as an empty pail, no one-off grant given yet. C-152: and at farm level 1.
      // C-154: and with nothing on the ground yet. C-191: and with no requests done; the read shows the board drawn now, not saved.
      const drawn = withEconomy(legacy as unknown as ParcelFarmState);
      settleBoard(rules, drawn, clock);
      expect((await mine(app, ada)).farm).toEqual({ ...legacy, buildings, coins: 0, sales: 0, gathered: {}, blueprints_claimed: {}, drops: [], drop_seq: 0,
        pail_water: 0, grants: {}, level: 1, energy: full, board: drawn.board, requests_done: 0, seed_aid_day: null });
      // Re-entering an old save gives no first-entry gift; it gets the watering grant (C-151) once, which writes the new fields.
      expect((await enter(app, ada)).json()).toMatchObject({ granted: false, gift: WATERING, parcel: { farm_version: 5 } });
      const bag = { hoe_starter: 1, seed_carrot: 2, crop_carrot: 1, ...WATERING };
      const entered = { ...legacy, buildings, bag, coins: 0, sales: 0, gathered: {}, blueprints_claimed: {}, drops: [], drop_seq: 0, pail_water: 0,
        grants: { watering: clock }, level: 1, board: emptyBoard(), requests_done: 0, seed_aid_day: null };
      expect((await pool!.query('SELECT farm_state FROM parcel_claims WHERE parcel_id = $1', [A.parcel_id])).rows[0].farm_state).toEqual(entered);
      expect((await enter(app, ada)).json()).toMatchObject({ granted: false, gift: {}, parcel: { farm_version: 5 } });
      const sold = await command(app, ada, 5, [{ type: 'sell', item: 'crop_carrot', count: 1 }]);
      expect(sold.statusCode).toBe(200);
      const stored = (await pool!.query('SELECT farm_state FROM parcel_claims WHERE parcel_id = $1', [A.parcel_id])).rows[0].farm_state;
      // The sale settles the board first, so the save now holds the board the read showed.
      expect(stored).toEqual({ ...entered, bag: { hoe_starter: 1, seed_carrot: 2, ...WATERING }, coins: 12, sales: 1, energy: full, board: drawn.board });
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
