/**
 * C-101 动态农场的邮箱注册和 Google 登录：同一组 HTTP 场景跑内存与 PostgreSQL 两套存储。
 * - 同一个账号（邮箱或 Google）换一台设备登录，读到的是同一块地和同一份进度，两边写的都互相看得到。
 * - 登出只撤销这台设备的会话，另一台设备照常用。
 * - 游客（装上即建号）和账号是两个玩家：在同一台手机上登录账号，不会把游客的地块挪给账号，也不会挪给别人。
 * - Google 邮箱被一个未验证的邮箱账号占着时拒绝登录，抢注者的地块不会落到 Google 账号名下，反之亦然。
 * - 开放注册后，邀请账号（服务端直接写入、邮箱已验证）照常登录，地块不受影响。
 */
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import path from 'node:path';
import pg from 'pg';
import { buildApp, plotFor } from '../../src/http/app.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { PgStore } from '../../src/db/pg_store.js';
import { migrate, truncateAll } from '../../src/db/migrate.js';
import type { Store } from '../../src/http/store.js';
import { newInstallKey } from '../../src/http/auth.js';
import { DEFAULT_CONTENT_DIR, contentVersion, loadContent } from '../../src/domain/content.js';
import { loadParcelRules } from '../../src/parcels/rules.js';
import { MemoryParcelStore, type ParcelStore } from '../../src/parcels/store.js';
import { PgParcelStore } from '../../src/parcels/pg_store.js';
import { hashPassword } from '../../src/accounts/password.js';
import { sha256Hex } from '../../src/accounts/apple_token.js';
import type { Mailer } from '../../src/accounts/mailer.js';
import { makeKeys, signToken } from '../fixtures/firebase_tokens.js';

const DSN = process.env.TEST_DATABASE_URL;
if (process.env.CI === '1' && !DSN) throw new Error('CI 下必须设置 TEST_DATABASE_URL');

const content = loadContent(DEFAULT_CONTENT_DIR);
const CV = contentVersion(DEFAULT_CONTENT_DIR);
const ROOT = path.resolve(DEFAULT_CONTENT_DIR, '..', '..', '..');
const rules = loadParcelRules(DEFAULT_CONTENT_DIR);
const DATASET = 'sf-dynamic-farm-20261118-r4';
const T0 = Date.UTC(2026, 10, 25, 4);
const A = { parcel_id: 'p-3512001', center: [-122.4194, 37.7749] };
const B = { parcel_id: 'p-3512002', center: [-122.4180, 37.7752] };
const GOOGLE_KEYS = makeKeys('google-c101');
const GOOGLE_AUD = 'web-client.apps.googleusercontent.com';
const NONCE = 'raw-nonce-0123456789abcdef';

let pool: pg.Pool | undefined;
beforeAll(async () => { if (DSN) { pool = new pg.Pool({ connectionString: DSN, max: 10 }); await migrate(pool); } });
afterAll(async () => { await pool?.end(); });

type Stores = { store: Store; parcels: ParcelStore };
const makers: [string, boolean, (now: () => number) => Stores][] = [
  ['MemoryStore', true, now => {
    const store = new MemoryStore({ content, timezone: 'America/Los_Angeles', plot: plotFor(content), now, contentVersion: CV });
    return { store, parcels: new MemoryParcelStore(id => store.displayNameOf(id), id => store.playerActivity(id)) };
  }],
  ['PgStore', Boolean(DSN), now => ({
    store: new PgStore({ pool: pool!, content, contentVersion: CV, timezone: () => 'America/Los_Angeles', plot: plotFor(content), now }),
    parcels: new PgParcelStore(pool!),
  })],
];

const bearer = (token: string) => ({ authorization: `Bearer ${token}` });

for (const [name, enabled, makeStores] of makers) {
  describe.skipIf(!enabled)(`${name}: email sign-up and Google sign-in across devices (C-101)`, () => {
    let clock = T0;
    let stores: Stores;
    let app: FastifyInstance;
    let mail: { email: string; code: string; purpose: string }[] = [];
    const mailer: Mailer = { async sendCode(email, code, purpose) { mail.push({ email, code, purpose }); } };

    beforeEach(async () => {
      if (pool) await truncateAll(pool);
      clock = T0;
      mail = [];
      stores = makeStores(() => clock);
      // The production switches this card opens: sign-up open, Google on; guests may play (C-100) to cover both.
      app = await buildApp({ store: stores.store, content, contentVersion: CV, blueprintDir: path.join(ROOT, 'assets', 'blueprints'),
        regionsFile: path.join(DEFAULT_CONTENT_DIR, 'regions.json'), pepper: 'test-pepper', now: () => clock, realtimeEnabled: false,
        mailer, signupClosed: false, google: { audiences: [GOOGLE_AUD], keys: GOOGLE_KEYS.keys },
        parcels: { store: stores.parcels, rules, reselect: false, guestWrites: true } });
    });
    afterEach(async () => { await app.close(); });

    const post = (url: string, payload: object, token?: string) =>
      app.inject({ method: 'POST', url, payload, headers: token ? bearer(token) : {} });
    const googleToken = (sub: string, over: Record<string, unknown> = {}) => {
      const s = Math.floor(clock / 1000);
      return signToken(GOOGLE_KEYS, { iss: 'https://accounts.google.com', aud: GOOGLE_AUD, sub, iat: s, exp: s + 3600,
        nonce: sha256Hex(NONCE), email_verified: true, ...over });
    };
    const google = (sub: string, over: Record<string, unknown> = {}) => post('/v1/auth/google', { id_token: googleToken(sub, over), nonce: NONCE });
    const register = (email: string) => post('/v1/auth/email/register', { email, password: 'correct horse', display_name: 'Ada' });
    const login = (email: string, password = 'correct horse') => post('/v1/auth/email/login', { email, password });
    const mine = async (token: string) => (await app.inject({ method: 'GET', url: '/v1/parcels/mine', headers: bearer(token) })).json().parcel;
    const ownerOf = async (token: string, id: string) =>
      (await app.inject({ method: 'GET', url: `/v1/parcels?dataset_version=${DATASET}&ids=${id}`, headers: bearer(token) })).json().parcels[0].owner;
    const claim = (token: string, parcel: typeof A) => post('/v1/parcels/claim', { dataset_version: DATASET, ...parcel }, token);
    const command = (token: string, base_version: number, commands: object[]) => post('/v1/parcels/mine/commands', { base_version, commands }, token);

    /** Device one: claim, take the welcome gift, build, clear, till and sow. Returns the saved version. */
    async function playOn(token: string, parcel = A): Promise<number> {
      expect((await claim(token, parcel)).statusCode).toBe(201);
      expect((await post('/v1/parcels/mine/enter', {}, token)).json()).toMatchObject({ granted: true, parcel: { farm_version: 1 } });
      const saved = await command(token, 1, [{ type: 'place_house', x: 9, y: 9 }, { type: 'clear_obstacle', cell: '2,2' },
        { type: 'till', cell: '1,1' }, { type: 'sow', cell: '1,1', crop: 'crop_carrot' }]);
      expect(saved.statusCode).toBe(200);
      return 2;
    }

    /** Device two reads the same home and progress, writes, and device one sees that write. */
    async function sameHomeOnBothDevices(first: string, second: string) {
      const there = await mine(first);
      const here = await mine(second);
      expect(here).toEqual(there);
      expect(here).toMatchObject({ parcel_id: A.parcel_id, farm_version: 2, farm: { house: { model: 'cottage' }, cleared: ['2,2'],
        tilled: ['1,1'], bag: { hoe_starter: 1, seed_carrot: 2 } } });
      // Entering again on the new device never grants the gift a second time.
      expect((await post('/v1/parcels/mine/enter', {}, second)).json()).toMatchObject({ granted: false });
      expect(await ownerOf(second, A.parcel_id)).toBe('mine');
      clock = T0 + 60_000;
      expect((await command(second, 2, [{ type: 'harvest', cell: '1,1' }])).statusCode).toBe(200);
      expect(await mine(first)).toMatchObject({ farm_version: 3, farm: { bag: { crop_carrot: 1 } } });
      // A second claim from either device keeps the one home.
      expect((await claim(second, B)).json()).toMatchObject({ code: 'ALREADY_CLAIMED', parcel: { parcel_id: A.parcel_id } });
      expect(await mine(second)).toMatchObject({ parcel_id: A.parcel_id });
    }

    it('an email account made on one phone signs in on another and finds the same home and progress', async () => {
      const made = await register('ada@example.com');
      expect(made.statusCode).toBe(201);
      expect(mail).toEqual([expect.objectContaining({ email: 'ada@example.com', purpose: 'verify' })]);
      await playOn(made.json().token);
      const other = await login('ada@example.com');
      expect(other.json()).toMatchObject({ user_id: made.json().user_id, player_id: made.json().player_id });
      expect(other.json().token).not.toBe(made.json().token);
      await sameHomeOnBothDevices(made.json().token, other.json().token);
    });

    it('a Google account signs in on another phone and finds the same home and progress', async () => {
      const first = await google('g-ada', { email: 'ada@gmail.com', given_name: 'Ada' });
      expect(first.statusCode).toBe(201);
      await playOn(first.json().token);
      const second = await google('g-ada', { email: 'ada@gmail.com' });
      expect(second.json()).toMatchObject({ created: false, user_id: first.json().user_id, player_id: first.json().player_id });
      await sameHomeOnBothDevices(first.json().token, second.json().token);
      // A different Google account is someone else: no home, and this one shows as taken.
      const stranger = await google('g-eve', { email: 'eve@gmail.com' });
      expect(await mine(stranger.json().token)).toBeNull();
      expect(await ownerOf(stranger.json().token, A.parcel_id)).toBe('other');
      expect((await claim(stranger.json().token, A)).json().code).toBe('PARCEL_TAKEN');
    });

    it('signing out on one phone leaves the other signed in', async () => {
      const made = await register('ada@example.com');
      await playOn(made.json().token);
      const other = (await login('ada@example.com')).json().token as string;
      expect((await app.inject({ method: 'DELETE', url: '/v1/auth/token', headers: bearer(made.json().token) })).statusCode).toBe(200);
      expect((await app.inject({ method: 'GET', url: '/v1/parcels/mine', headers: bearer(made.json().token) })).statusCode).toBe(401);
      expect(await mine(other)).toMatchObject({ parcel_id: A.parcel_id, farm_version: 2 });
    });

    it('a guest who signs in on the same phone keeps the guest home apart; the account starts its own', async () => {
      const key = newInstallKey();
      const guest = (await post('/v1/auth/anonymous', { install_key: key })).json();
      await playOn(guest.token);
      const account = (await register('ada@example.com')).json();
      expect(account.player_id).not.toBe(guest.player_id);
      expect(await mine(account.token)).toBeNull();
      expect(await ownerOf(account.token, A.parcel_id)).toBe('other');
      expect((await claim(account.token, B)).statusCode).toBe(201);
      // Signing out again on that phone is the same guest with the same home, untouched.
      const back = (await post('/v1/auth/anonymous', { install_key: key })).json();
      expect(back.player_id).toBe(guest.player_id);
      expect(await mine(back.token)).toMatchObject({ parcel_id: A.parcel_id, farm_version: 2 });
      // Another phone signing in to the account sees only the account's home.
      const elsewhere = (await login('ada@example.com')).json().token as string;
      expect(await mine(elsewhere)).toMatchObject({ parcel_id: B.parcel_id, farm_version: 0 });
    });

    it('Google cannot take over a home behind an unverified email account, and the other way round', async () => {
      const squatter = (await register('grace@gmail.com')).json();
      await playOn(squatter.token);
      const viaGoogle = await google('g-grace', { email: 'grace@gmail.com' });
      expect(viaGoogle.statusCode).toBe(409);
      expect(viaGoogle.json().code).toBe('EMAIL_IN_USE');
      expect(await stores.store.userByIdentity('google', 'g-grace')).toBeNull();
      // The mailbox owner proves it with a reset code: the squatter's sessions end and the account is verified.
      await post('/v1/auth/email/code', { email: 'grace@gmail.com', purpose: 'reset' });
      const code = mail.find(m => m.email === 'grace@gmail.com' && m.purpose === 'reset')!.code;
      const reset = (await post('/v1/auth/email/reset', { email: 'grace@gmail.com', code, password: 'owner pass 22' })).json();
      expect((await app.inject({ method: 'GET', url: '/v1/parcels/mine', headers: bearer(squatter.token) })).statusCode).toBe(401);
      const linked = await google('g-grace', { email: 'grace@gmail.com' });
      expect(linked.json()).toMatchObject({ created: false, user_id: reset.user_id });
      expect(await mine(linked.json().token)).toMatchObject({ parcel_id: A.parcel_id, farm_version: 2 });
      // A Google account whose email Google has not verified never links to the verified account or its home.
      const unverified = await google('g-mallory', { email: 'grace@gmail.com', email_verified: false });
      expect(unverified.json().user_id).not.toBe(reset.user_id);
      expect(await mine(unverified.json().token)).toBeNull();
    });

    it('with sign-up open, an invite account still signs in to its own home', async () => {
      // Invite accounts are written by the operator (C-96): email + password, already verified.
      const made = await stores.store.createEmailUser('qa-abcdefgh@invite.example', await hashPassword('k3mq-7hxa-pt2d-wz9e'), clock);
      if (made.kind !== 'created') throw new Error('invite account not created');
      await stores.store.markEmailVerified(made.user.id);
      const first = (await login('qa-abcdefgh@invite.example', 'k3mq-7hxa-pt2d-wz9e')).json();
      expect(first).toMatchObject({ user_id: made.user.id, email_verified: true });
      await playOn(first.token);
      const second = (await login('qa-abcdefgh@invite.example', 'k3mq-7hxa-pt2d-wz9e')).json();
      await sameHomeOnBothDevices(first.token, second.token);
      expect((await register('qa-abcdefgh@invite.example')).json().code).toBe('EMAIL_TAKEN');
    });
  });
}
