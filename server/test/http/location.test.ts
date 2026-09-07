import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import path from 'node:path';
import { buildApp, blueprintSets, loadBlueprint } from '../../src/http/app.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { MemoryAccountStore } from '../../src/http/memory_accounts.js';
import { MemorySocialStore } from '../../src/http/memory_social.js';
import { MemoryLocationStore } from '../../src/http/memory_location.js';
import { socialAccountModule } from '../../src/http/social.js';
import { LOCATION_MAX_AGE_MS, locationAccountModule, validateLocation } from '../../src/http/location.js';
import { DEFAULT_CONTENT_DIR, contentVersion, loadContent } from '../../src/domain/content.js';
import { at, SH } from '../domain/helpers.js';
import { PROJECT, idToken, makeKeys } from '../fixtures/firebase_tokens.js';

const ROOT = path.resolve(DEFAULT_CONTENT_DIR, '..', '..', '..');
const BLUEPRINTS = path.join(ROOT, 'assets', 'blueprints');
const REGIONS = path.join(DEFAULT_CONTENT_DIR, 'regions.json');
const content = loadContent(DEFAULT_CONTENT_DIR);
const CV = contentVersion(DEFAULT_CONTENT_DIR);
const bp = loadBlueprint(BLUEPRINTS, 'sh_a', 2)!;
const k = makeKeys();

let app: FastifyInstance;
let accounts: MemoryAccountStore;
let social: MemorySocialStore;
let locations: MemoryLocationStore;
let clock = at('2026-09-08T10:00:00+08:00');

beforeEach(async () => {
  clock = at('2026-09-08T10:00:00+08:00');
  accounts = new MemoryAccountStore();
  social = new MemorySocialStore(async id => (await accounts.userById(id)) !== null);
  locations = new MemoryLocationStore();
  const store = new MemoryStore({ content, timezone: SH, blueprint: blueprintSets(bp), now: () => clock, contentVersion: CV });
  app = await buildApp({
    store, content, contentVersion: CV, blueprintDir: BLUEPRINTS, regionsFile: REGIONS, pepper: 'p', now: () => clock,
    accounts, firebase: { projectId: PROJECT, keys: k.keys }, social, locations,
    accountModules: [socialAccountModule(social), locationAccountModule(locations)],
  });
});
afterEach(async () => { await app.close(); });

const tok = (uid: string) => idToken(k, clock, {}, uid);
const authed = (uid: string) => ({ authorization: `Bearer ${tok(uid)}` });
const signIn = async (uid: string): Promise<string> =>
  (await app.inject({ method: 'POST', url: '/v1/auth/firebase', payload: { id_token: tok(uid) } })).json().user_id as string;
const get = (uid: string, url: string) => app.inject({ method: 'GET', url, headers: authed(uid) });
const put = (uid: string, url: string, payload?: object) => app.inject({ method: 'PUT', url, headers: authed(uid), payload });
const del = (uid: string, url: string) => app.inject({ method: 'DELETE', url, headers: authed(uid) });
const follow = (uid: string, other: string) => put(uid, `/v1/users/${other}/follow`);

describe('B5 好友位置', () => {
  it('校验：经纬度越界 / 非数字 400；精度可选且夹到上限', () => {
    expect(validateLocation({ lat: 31.2, lng: 121.5 })).toEqual({ ok: true, lat: 31.2, lng: 121.5, accuracy_m: null });
    expect(validateLocation({ lat: 31.2, lng: 121.5, accuracy_m: 99_999_999 })).toMatchObject({ ok: true, accuracy_m: 50_000 });
    expect(validateLocation({ lat: '31', lng: 121.5 })).toMatchObject({ ok: false, field: 'lat' });
    expect(validateLocation({ lat: 91, lng: 0 })).toMatchObject({ ok: false, field: 'lat' });
    expect(validateLocation({ lat: 0, lng: -181 })).toMatchObject({ ok: false, field: 'lng' });
    expect(validateLocation({ lat: 0, lng: 0, accuracy_m: -1 })).toMatchObject({ ok: false, field: 'accuracy_m' });
    expect(validateLocation(null)).toMatchObject({ ok: false, field: 'body' });
  });

  it('只有互相关注的人能看到彼此；单向关注看不到；陈旧位置与停止分享后不下发', async () => {
    const a = await signIn('alice'); const b = await signIn('bob'); const c = await signIn('carol');
    await follow('alice', b); await follow('bob', a);          // alice ⇄ bob 好友
    await follow('carol', a);                                  // carol → alice 单向
    expect((await put('alice', '/v1/location', { lat: 31.23, lng: 121.47, accuracy_m: 12 })).statusCode).toBe(200);
    expect((await put('bob', '/v1/location', { lat: 31.24, lng: 121.48 })).statusCode).toBe(200);
    expect((await put('carol', '/v1/location', { lat: 31.25, lng: 121.49 })).statusCode).toBe(200);
    expect((await put('alice', '/v1/location', { lat: 999, lng: 0 })).statusCode).toBe(400);

    const seenByAlice = (await get('alice', '/v1/friends/locations')).json().items;
    expect(seenByAlice).toEqual([expect.objectContaining({ user_id: b, display_name: 'bob', lat: 31.24, lng: 121.48, accuracy_m: null })]);
    const seenByBob = (await get('bob', '/v1/friends/locations')).json().items;
    expect(seenByBob).toEqual([expect.objectContaining({ user_id: a, lat: 31.23, lng: 121.47, accuracy_m: 12 })]);
    // carol 只是单向关注 alice：两边都看不到对方。
    expect((await get('carol', '/v1/friends/locations')).json().items).toEqual([]);
    expect(seenByAlice.some((x: { user_id: string }) => x.user_id === c)).toBe(false);

    // bob 的位置过了 24 小时没更新 → alice 看不到了。
    clock = clock + LOCATION_MAX_AGE_MS + 1;
    expect((await get('alice', '/v1/friends/locations')).json().items).toEqual([]);
    // alice 刷新后 bob 又能看到 alice；alice 停止分享后消失。
    await put('alice', '/v1/location', { lat: 31.3, lng: 121.5 });
    expect((await get('bob', '/v1/friends/locations')).json().items).toHaveLength(1);
    expect((await del('alice', '/v1/location')).statusCode).toBe(200);
    expect((await get('bob', '/v1/friends/locations')).json().items).toEqual([]);
  });

  it('删号级联与导出登记；未配置时 503', async () => {
    const a = await signIn('alice');
    await put('alice', '/v1/location', { lat: 1, lng: 2 });
    const mod = locationAccountModule(locations);
    expect(await mod.export!(a)).toMatchObject({ lat: 1, lng: 2 });
    await mod.del!(a);
    expect(await locations.get(a)).toBeNull();
    const bare = await buildApp({
      store: new MemoryStore({ content, timezone: SH, blueprint: blueprintSets(bp), now: () => clock, contentVersion: CV }),
      content, contentVersion: CV, blueprintDir: BLUEPRINTS, regionsFile: REGIONS, pepper: 'p', now: () => clock,
      accounts, firebase: { projectId: PROJECT, keys: k.keys }, social,
    });
    expect((await bare.inject({ method: 'PUT', url: '/v1/location', headers: authed('alice'), payload: { lat: 1, lng: 2 } })).statusCode).toBe(503);
    await bare.close();
  });
});
