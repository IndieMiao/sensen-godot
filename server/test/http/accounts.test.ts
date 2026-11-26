/**
 * 邮箱账户、游客只读与全球城市（SGODOT-135 / 136）。同一组场景跑内存与 PostgreSQL 两套 Store。
 */
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import pg from 'pg';
import { buildApp, plotFor } from '../../src/http/app.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { PgStore } from '../../src/db/pg_store.js';
import { migrate, truncateAll } from '../../src/db/migrate.js';
import type { Store } from '../../src/http/store.js';
import { newInstallKey } from '../../src/http/auth.js';
import { DEFAULT_CONTENT_DIR, contentVersion, loadContent } from '../../src/domain/content.js';
import { initialFarmState } from '../../src/domain/farm_factory.js';
import { tokenHash } from '../../src/http/auth.js';
import type { FarmLocation } from '../../src/http/farm_location.js';
import type { Mailer } from '../../src/accounts/mailer.js';
import { makeKeys, signToken } from '../fixtures/firebase_tokens.js';
import { sha256Hex } from '../../src/accounts/apple_token.js';

const APPLE_KEYS = makeKeys('apple-test');
const GOOGLE_KEYS = makeKeys('google-test');
const GOOGLE_AUD = 'web-client.apps.googleusercontent.com';
const APPLE_NONCE = 'raw-nonce-0123456789abcdef';

const DSN = process.env.TEST_DATABASE_URL;
const content = loadContent(DEFAULT_CONTENT_DIR);
const CV = contentVersion(DEFAULT_CONTENT_DIR);
const ROOT = path.resolve(DEFAULT_CONTENT_DIR, '..', '..', '..');
const REGIONS = path.join(DEFAULT_CONTENT_DIR, 'regions.json');
const TOKYO: FarmLocation = { lat: 35.6812, lng: 139.7671 };
const SHANGHAI: FarmLocation = { lat: 31.2304, lng: 121.4737 };

let pool: pg.Pool | undefined;
beforeAll(async () => { if (DSN) { pool = new pg.Pool({ connectionString: DSN, max: 5 }); await migrate(pool); } });
afterAll(async () => { await pool?.end(); });

const makers: [string, boolean, (now: () => number) => Store][] = [
  ['MemoryStore', true, now => new MemoryStore({ content, timezone: 'Asia/Shanghai', plot: plotFor(content), now, contentVersion: CV })],
  ['PgStore', Boolean(DSN), now => new PgStore({ pool: pool!, content, contentVersion: CV, timezone: () => 'Asia/Shanghai', plot: plotFor(content), now })],
];

for (const [name, enabled, makeStore] of makers) {
  describe.skipIf(!enabled)(`${name}: accounts, guests and global cities`, () => {
    let app: FastifyInstance;
    let store: Store;
    let clock = Date.UTC(2026, 8, 28, 2);
    let mail: { email: string; code: string; purpose: string }[] = [];
    let appleCalls: string[] = [];
    const mailer: Mailer = { async sendCode(email, code, purpose) { mail.push({ email, code, purpose }); } };
    const ipLocator = async (ip: string) => ip === '203.0.113.9' ? TOKYO : null;

    beforeEach(async () => {
      if (pool) await truncateAll(pool);
      mail = [];
      appleCalls = [];
      clock = Date.UTC(2026, 8, 28, 2);
      store = makeStore(() => clock);
      app = await build();
    });
    const build = (extra: Partial<Parameters<typeof buildApp>[0]> = {}) =>
      buildApp({ store, content, contentVersion: CV, blueprintDir: path.join(ROOT, 'assets', 'blueprints'),
        regionsFile: REGIONS, pepper: 'test-pepper', now: () => clock, mailer, ipLocator,
        qaEmailDomain: 'qa.sensen.test', qaEmailCode: '424242',
        apple: { audiences: ['app.gensen.maps'], keys: APPLE_KEYS.keys },
        google: { audiences: [GOOGLE_AUD], keys: GOOGLE_KEYS.keys },
        appleRevoker: { exchange: async code => { appleCalls.push('exchange:' + code); return code === 'good-code' ? 'refresh-1' : null; },
          revoke: async token => { appleCalls.push('revoke:' + token); return true; } }, ...extra });
    afterEach(async () => { await app.close(); });

    const bearer = (token: string) => ({ authorization: `Bearer ${token}` });
    const register = (email: string, password = 'correct horse') =>
      app.inject({ method: 'POST', url: '/v1/auth/email/register', payload: { email, password } });
    const login = (email: string, password: string) =>
      app.inject({ method: 'POST', url: '/v1/auth/email/login', payload: { email, password } });
    const guest = async () => (await app.inject({ method: 'POST', url: '/v1/auth/anonymous', payload: { install_key: newInstallKey() } })).json().token as string;
    // Map-generated farms are retired (SGODOT-304); farms start from a curated city's street candidate.
    const createFarm = (token: string, key = 'farm', region_id = 'shanghai', layout_patch_id = 'sh_a') => app.inject({ method: 'POST', url: '/v1/farms',
      headers: bearer(token), payload: { idempotency_key: key, region_id, layout_patch_id, blueprint_revision: 2 } });
    // A farm already saved in a non-curated city (created before the retirement).
    const seedFarmIn = async (token: string, region_id: string) => {
      const owner = (await store.playerByToken(tokenHash(token), clock))!;
      const seeded = await store.createFarm({ ownerId: owner.id, idempotencyKey: 'seed', payloadHash: 'seed', regionId: region_id,
        layoutPatchId: 'sh_a', blueprintRevision: 2, build: async () => ({ id: randomUUID(), owner_id: owner.id, region_id,
          layout_patch_id: 'sh_a', blueprint_revision: 2, version: 0, location_visible: true, visit_access: 'only_me' as const,
          state: initialFarmState(content, plotFor(content), 'Asia/Tokyo', clock) }) });
      if (seeded.kind === 'idempotency_mismatch') throw new Error('seed');
      return seeded.farm;
    };

    it('registers, logs in on a second device and reaches the same account player', async () => {
      const created = await register('  Ada@Example.com ');
      expect(created.statusCode).toBe(201);
      const body = created.json();
      expect(body.email).toBe('ada@example.com');
      expect(body.email_verified).toBe(false);
      expect(body.verification_sent).toBe(true);
      expect(mail).toEqual([expect.objectContaining({ email: 'ada@example.com', purpose: 'verify' })]);
      expect((await register('ada@example.com')).json().code).toBe('EMAIL_TAKEN');
      expect((await login('ada@example.com', 'wrong password')).json().code).toBe('INVALID_CREDENTIALS');
      expect((await login('nobody@example.com', 'whatever1')).json().code).toBe('INVALID_CREDENTIALS');
      const second = await login('ADA@example.com', 'correct horse');
      expect(second.statusCode).toBe(200);
      expect(second.json().player_id).toBe(body.player_id);
      expect(second.json().token).not.toBe(body.token);
      const me = await app.inject({ method: 'GET', url: '/v1/users/me', headers: bearer(second.json().token) });
      expect(me.json()).toMatchObject({ user_id: body.user_id, player_id: body.player_id, has_farm: false });
    });

    it('rejects bad input without creating anything', async () => {
      expect((await register('not-an-email')).json().code).toBe('INVALID_EMAIL');
      expect((await register('short@example.com', 'short')).json().code).toBe('WEAK_PASSWORD');
      expect((await login('short@example.com', 'whatever1')).statusCode).toBe(401);
    });

    it('verifies the email with the mailed code and refuses wrong or expired codes', async () => {
      const { token } = (await register('bea@example.com')).json();
      const code = mail[0].code;
      const wrong = code === '000000' ? '111111' : '000000';
      const bad = await app.inject({ method: 'POST', url: '/v1/auth/email/verify', headers: bearer(token), payload: { code: wrong } });
      expect(bad.json().code).toBe('CODE_INVALID');
      const ok = await app.inject({ method: 'POST', url: '/v1/auth/email/verify', headers: bearer(token), payload: { code } });
      expect(ok.json().email_verified).toBe(true);
      // Resend is throttled for a minute, then a fresh code expires after ten.
      await app.inject({ method: 'POST', url: '/v1/auth/email/code', payload: { email: 'cat@example.com', purpose: 'reset' } });
      expect((await app.inject({ method: 'POST', url: '/v1/auth/email/code', payload: { email: 'bea@example.com', purpose: 'reset' } })).statusCode).toBe(200);
      const again = await app.inject({ method: 'POST', url: '/v1/auth/email/code', payload: { email: 'bea@example.com', purpose: 'reset' } });
      expect(again.statusCode).toBe(429);
      expect(again.json().code).toBe('CODE_COOLDOWN');
      const resetCode = mail.at(-1)!.code;
      clock += 11 * 60_000;
      const expired = await app.inject({ method: 'POST', url: '/v1/auth/email/reset', payload: { email: 'bea@example.com', code: resetCode, password: 'new password 1' } });
      expect(expired.json().code).toBe('CODE_EXPIRED');
    });

    it('never mails or reveals unknown addresses on code requests', async () => {
      const r = await app.inject({ method: 'POST', url: '/v1/auth/email/code', payload: { email: 'ghost@example.com', purpose: 'reset' } });
      expect(r.statusCode).toBe(200);
      expect(mail).toEqual([]);
    });

    it('locks a code after five wrong attempts', async () => {
      await register('dan@example.com');
      await app.inject({ method: 'POST', url: '/v1/auth/email/code', payload: { email: 'dan@example.com', purpose: 'reset' } });
      const code = mail.at(-1)!.code;
      const wrong = code === '000000' ? '111111' : '000000';
      for (let i = 0; i < 5; i++)
        await app.inject({ method: 'POST', url: '/v1/auth/email/reset', payload: { email: 'dan@example.com', code: wrong, password: 'new password 1' } });
      const late = await app.inject({ method: 'POST', url: '/v1/auth/email/reset', payload: { email: 'dan@example.com', code, password: 'new password 1' } });
      expect(late.statusCode).toBe(422);
    });

    it('resets the password, ends every old session and verifies the mailbox', async () => {
      const first = (await register('eve@example.com')).json();
      await app.inject({ method: 'POST', url: '/v1/auth/email/code', payload: { email: 'eve@example.com', purpose: 'reset' } });
      const reset = await app.inject({ method: 'POST', url: '/v1/auth/email/reset',
        payload: { email: 'eve@example.com', code: mail.at(-1)!.code, password: 'brand new pass' } });
      expect(reset.statusCode).toBe(200);
      expect(reset.json().email_verified).toBe(true);
      expect((await app.inject({ method: 'GET', url: '/v1/users/me', headers: bearer(first.token) })).statusCode).toBe(401);
      expect((await app.inject({ method: 'GET', url: '/v1/users/me', headers: bearer(reset.json().token) })).statusCode).toBe(200);
      expect((await login('eve@example.com', 'correct horse')).statusCode).toBe(401);
      expect((await login('eve@example.com', 'brand new pass')).statusCode).toBe(200);
    });

    it('uses the fixed QA code for the QA domain and sends no mail', async () => {
      const { token } = (await register('bot1@qa.sensen.test')).json();
      expect(mail).toEqual([]);
      const ok = await app.inject({ method: 'POST', url: '/v1/auth/email/verify', headers: bearer(token), payload: { code: '424242' } });
      expect(ok.json().email_verified).toBe(true);
    });

    it('lets guests browse but not create or play', async () => {
      const token = await guest();
      expect((await app.inject({ method: 'GET', url: '/v1/farms/me', headers: bearer(token) })).json().code).toBe('NO_FARM');
      const create = await createFarm(token);
      expect(create.statusCode).toBe(401);
      expect(create.json().code).toBe('LOGIN_REQUIRED');
      const command = await app.inject({ method: 'POST', url: '/v1/farms/me/commands', headers: bearer(token),
        payload: { type: 'till_cells', idempotency_key: 'k', base_version: 0, payload: { cell_ids: ['1,1'] } } });
      expect(command.json().code).toBe('LOGIN_REQUIRED');
      expect((await app.inject({ method: 'GET', url: '/v1/users/me', headers: bearer(token) })).json().code).toBe('LOGIN_REQUIRED');
      expect((await app.inject({ method: 'GET', url: '/v1/nearby?region_id=shanghai', headers: bearer(token) })).statusCode).toBe(200);
      expect((await app.inject({ method: 'GET', url: '/v1/cities' })).statusCode).toBe(200);
    });

    it('creates a farm in a curated city and refuses map-generated farms', async () => {
      const { token } = (await register('fay@example.com')).json();
      const generated = await app.inject({ method: 'POST', url: '/v1/farms', headers: bearer(token),
        payload: { generation_version: 3, idempotency_key: 'gen', region_id: '', location: TOKYO } });
      expect(generated.statusCode).toBe(410);
      expect(generated.json().code).toBe('FARM_GENERATION_RETIRED');
      const created = await createFarm(token);
      expect(created.statusCode).toBe(201);
      expect(created.json()).toMatchObject({ region_id: 'shanghai', layout_patch_id: 'sh_a' });
      expect(created.json().farm_terrain).toBeUndefined();
      expect((await app.inject({ method: 'GET', url: '/v1/users/me', headers: bearer(token) })).json().has_farm).toBe(true);
      expect((await app.inject({ method: 'GET', url: '/v1/farms/me', headers: bearer(token) })).statusCode).toBe(200);
      const regions = (await app.inject({ method: 'GET', url: '/v1/regions' })).json();
      expect(regions.farm_generation_version).toBeUndefined();
      expect(regions.farm_generations).toBeUndefined();
      const outside = await app.inject({ method: 'POST', url: '/v1/farms', headers: bearer((await register('hal@example.com')).json().token),
        payload: { idempotency_key: 'out', region_id: 'shanghai', layout_patch_id: 'sh_a', blueprint_revision: 2, location: TOKYO } });
      expect(outside.json().code).toBe('LOCATION_OUTSIDE_REGION');
      const inside = await app.inject({ method: 'POST', url: '/v1/farms', headers: bearer((await register('gus@example.com')).json().token),
        payload: { idempotency_key: 'in', region_id: 'shanghai', layout_patch_id: 'sh_a', blueprint_revision: 2, location: SHANGHAI } });
      expect(inside.statusCode).toBe(201);
    });

    it('lists curated cities first, then cities with public farms, and suggests by IP', async () => {
      const { token } = (await register('ivy@example.com')).json();
      const tokyo = (await app.inject({ method: 'POST', url: '/v1/cities/resolve', payload: { location: TOKYO } })).json().city.id;
      const farm = await seedFarmIn(token, tokyo);
      const opening = await app.inject({ method: 'POST', url: '/v1/farms/me/commands', headers: bearer(token),
        payload: { type: 'set_visit_access', idempotency_key: 'open', base_version: farm.version, payload: { access: 'anyone' } } });
      expect(opening.statusCode).toBe(200);
      const list = (await app.inject({ method: 'GET', url: '/v1/cities' })).json().cities;
      expect(list.slice(0, 2).map((c: { id: string }) => c.id)).toEqual(['shanghai', 'los_angeles']);
      expect(list.find((c: { id: string }) => c.id === tokyo)).toMatchObject({ name: 'Tokyo', farm_count: 1 });
      const suggested = (await app.inject({ method: 'GET', url: '/v1/cities/suggest', remoteAddress: '203.0.113.9' })).json();
      expect(suggested.city.name).toBe('Tokyo');
      expect((await app.inject({ method: 'GET', url: '/v1/cities/suggest' })).json().city).toBeNull();
      const resolved = await app.inject({ method: 'POST', url: '/v1/cities/resolve', payload: { location: { lat: 51.5074, lng: -0.1278 } } });
      expect(resolved.json().city.name).toBe('London');
      expect((await app.inject({ method: 'POST', url: '/v1/cities/resolve', payload: { location: { lat: 0, lng: -140 } } })).statusCode).toBe(404);
      expect((await app.inject({ method: 'GET', url: '/v1/cities/search?q=lond' })).json().cities[0].name).toBe('London');
    });

    it('deletes the account with its farm after password confirmation, keeping only a tombstone', async () => {
      const body = (await register('jan@example.com')).json();
      expect((await createFarm(body.token)).statusCode).toBe(201);
      const refused = await app.inject({ method: 'DELETE', url: '/v1/users/me', headers: bearer(body.token), payload: { password: 'nope' } });
      expect(refused.statusCode).toBe(401);
      const gone = await app.inject({ method: 'DELETE', url: '/v1/users/me', headers: bearer(body.token), payload: { password: 'correct horse' } });
      expect(gone.json()).toMatchObject({ ok: true, deleted: true });
      expect((await app.inject({ method: 'GET', url: '/v1/farms/me', headers: bearer(body.token) })).statusCode).toBe(401);
      expect((await login('jan@example.com', 'correct horse')).statusCode).toBe(401);
      // The address is free again; a new account starts from nothing.
      const fresh = (await register('jan@example.com')).json();
      expect(fresh.user_id).not.toBe(body.user_id);
      expect((await app.inject({ method: 'GET', url: '/v1/users/me', headers: bearer(fresh.token) })).json().has_farm).toBe(false);
    });

    it('saves a profile with a nickname, optional gender and optional birthday', async () => {
      const body = (await app.inject({ method: 'POST', url: '/v1/auth/email/register',
        payload: { email: 'lea@example.com', password: 'correct horse', display_name: '  Lea  ' } })).json();
      expect(body.display_name).toBe('Lea');
      expect(body.profile_complete).toBe(true);
      const put = (payload: object) => app.inject({ method: 'PUT', url: '/v1/users/me/profile', headers: bearer(body.token), payload });
      const saved = await put({ display_name: 'Lea M', gender: 'nonbinary', birth_date: '2000-02-29' });
      expect(saved.statusCode).toBe(200);
      expect(saved.json()).toMatchObject({ display_name: 'Lea M', gender: 'nonbinary', birth_date: '2000-02-29', age: 26 });
      const custom = await put({ display_name: 'Lea M', gender: 'self_describe', gender_custom: 'Genderfluid' });
      expect(custom.json()).toMatchObject({ gender: 'self_describe', gender_custom: 'Genderfluid', birth_date: null, age: null });
      for (const [payload, code] of [
        [{ display_name: 'x' }, 'INVALID_NAME'],
        [{ display_name: 'a@b.com' }, 'INVALID_NAME'],
        [{ display_name: 'A​B' }, 'INVALID_NAME'],
        [{ display_name: 'Lea', gender: 'female' }, 'INVALID_GENDER'],
        [{ display_name: 'Lea', gender: 'self_describe' }, 'INVALID_GENDER'],
        [{ display_name: 'Lea', birth_date: '2020-13-01' }, 'INVALID_BIRTH_DATE'],
        [{ display_name: 'Lea', birth_date: '2015-01-01' }, 'UNDER_AGE'],
      ] as const) expect((await put(payload)).json().code).toBe(code);
      // A refused under-13 birthday is not stored.
      const me = (await app.inject({ method: 'GET', url: '/v1/users/me', headers: bearer(body.token) })).json();
      expect(me).toMatchObject({ display_name: 'Lea M', gender: 'self_describe', birth_date: null });
      const guestToken = await guest();
      expect((await app.inject({ method: 'PUT', url: '/v1/users/me/profile', headers: bearer(guestToken), payload: { display_name: 'Guest' } })).json().code).toBe('LOGIN_REQUIRED');
    });

    it('reports an incomplete profile until a nickname is set', async () => {
      const body = (await register('max@example.com')).json();
      expect(body.profile_complete).toBe(false);
      expect(body.display_name).toBeNull();
    });

    it('changes the password while signed in and ends other sessions', async () => {
      const first = (await register('ned@example.com')).json();
      const other = (await login('ned@example.com', 'correct horse')).json();
      const change = (payload: object) => app.inject({ method: 'POST', url: '/v1/auth/email/password', headers: bearer(first.token), payload });
      expect((await change({ current_password: 'wrong one', new_password: 'another pass' })).json().code).toBe('INVALID_CREDENTIALS');
      expect((await change({ current_password: 'correct horse', new_password: 'short' })).json().code).toBe('WEAK_PASSWORD');
      expect((await change({ current_password: 'correct horse', new_password: 'correct horse' })).json().code).toBe('SAME_PASSWORD');
      const changed = await change({ current_password: 'correct horse', new_password: 'another pass' });
      expect(changed.statusCode).toBe(200);
      expect((await app.inject({ method: 'GET', url: '/v1/users/me', headers: bearer(other.token) })).statusCode).toBe(401);
      expect((await app.inject({ method: 'GET', url: '/v1/users/me', headers: bearer(changed.json().token) })).statusCode).toBe(200);
      expect((await login('ned@example.com', 'another pass')).statusCode).toBe(200);
    });

    it('serves a self-contained deletion page', async () => {
      const page = await app.inject({ method: 'GET', url: '/v1/account/delete' });
      expect(page.statusCode).toBe(200);
      expect(page.headers['content-type']).toContain('text/html');
      expect(page.headers['content-security-policy']).toContain("connect-src 'self'");
      expect(page.body).toContain('Delete your Sensen account');
      // Only inline data: resources are allowed; nothing may be loaded from another host.
      expect(page.body).not.toMatch(/<script[^>]+src=|<link[^>]+href="(?!data:)|https?:\/\//);
    });

    it('deletes an account from the web with the password', async () => {
      const body = (await register('oli@example.com')).json();
      await createFarm(body.token);
      const del = (payload: object) => app.inject({ method: 'POST', url: '/v1/account/delete', payload });
      expect((await del({ email: 'oli@example.com', password: 'nope nope' })).json().code).toBe('INVALID_CREDENTIALS');
      expect((await del({ email: 'nobody@example.com', password: 'nope nope' })).json().code).toBe('INVALID_CREDENTIALS');
      expect((await del({ email: 'oli@example.com' })).statusCode).toBe(400);
      const gone = await del({ email: 'OLI@example.com', password: 'correct horse' });
      expect(gone.json()).toMatchObject({ ok: true, deleted: true });
      expect((await app.inject({ method: 'GET', url: '/v1/users/me', headers: bearer(body.token) })).statusCode).toBe(401);
      expect((await login('oli@example.com', 'correct horse')).statusCode).toBe(401);
    });

    it('deletes an account from the web with an emailed code when the password is forgotten', async () => {
      await register('pam@example.com');
      mail = [];
      const ghost = await app.inject({ method: 'POST', url: '/v1/account/delete/code', payload: { email: 'ghost@example.com' } });
      expect(ghost.statusCode).toBe(200);
      expect(mail).toEqual([]);
      await app.inject({ method: 'POST', url: '/v1/account/delete/code', payload: { email: 'pam@example.com' } });
      expect(mail).toEqual([expect.objectContaining({ email: 'pam@example.com', purpose: 'delete' })]);
      const code = mail[0].code;
      // A reset code cannot delete, and a delete code cannot reset.
      expect((await app.inject({ method: 'POST', url: '/v1/auth/email/reset', payload: { email: 'pam@example.com', code, password: 'new password 1' } })).statusCode).toBe(422);
      const gone = await app.inject({ method: 'POST', url: '/v1/account/delete', payload: { email: 'pam@example.com', code } });
      expect(gone.json()).toMatchObject({ ok: true, deleted: true });
      expect((await login('pam@example.com', 'correct horse')).statusCode).toBe(401);
    });

    it('exports the account and farm without secrets', async () => {
      const body = (await register('kim@example.com')).json();
      await createFarm(body.token);
      const exported = await app.inject({ method: 'GET', url: '/v1/users/me/export', headers: bearer(body.token) });
      expect(exported.statusCode).toBe(200);
      const text = exported.body;
      expect(text).not.toContain('scrypt$');
      expect(text).not.toContain(body.token);
      expect(exported.json().farm.city_id).toBe('shanghai');
    });
    const appleToken = (sub: string, over: Record<string, unknown> = {}) => {
      const s = Math.floor(clock / 1000);
      return signToken(APPLE_KEYS, { iss: 'https://appleid.apple.com', aud: 'app.gensen.maps', sub, iat: s, exp: s + 600,
        nonce: sha256Hex(APPLE_NONCE), ...over });
    };
    const apple = (token: string, extra: Record<string, unknown> = {}) =>
      app.inject({ method: 'POST', url: '/v1/auth/apple', payload: { identity_token: token, nonce: APPLE_NONCE, ...extra } });

    it('signs in with Apple, creating a password-less account once', async () => {
      const first = await apple(appleToken('apple.sub.1', { email: 'relay1@privaterelay.appleid.com', email_verified: 'true' }),
        { given_name: 'Avery', family_name: 'Lee' });
      expect(first.statusCode).toBe(201);
      expect(first.json()).toMatchObject({ created: true, has_password: false, email: 'relay1@privaterelay.appleid.com',
        email_verified: true, display_name: 'Avery', profile_complete: true });
      // Apple sends the email only on the first authorization; later tokens carry just the sub.
      const again = await apple(appleToken('apple.sub.1'));
      expect(again.statusCode).toBe(200);
      expect(again.json()).toMatchObject({ created: false, user_id: first.json().user_id, player_id: first.json().player_id });
      const me = await app.inject({ method: 'GET', url: '/v1/users/me', headers: bearer(again.json().token) });
      expect(me.json()).toMatchObject({ user_id: first.json().user_id, display_name: 'Avery' });
    });

    it('links Apple to a verified email account and refuses an unverified one', async () => {
      await register('sam@example.com');
      const blocked = await apple(appleToken('apple.sub.2', { email: 'sam@example.com', email_verified: true }));
      expect(blocked.statusCode).toBe(409);
      expect(blocked.json().code).toBe('EMAIL_IN_USE');
      await app.inject({ method: 'POST', url: '/v1/auth/email/code', payload: { email: 'sam@example.com', purpose: 'reset' } });
      const code = mail.find(m => m.purpose === 'reset')!.code;
      const reset = await app.inject({ method: 'POST', url: '/v1/auth/email/reset', payload: { email: 'sam@example.com', code, password: 'another pass 1' } });
      const linked = await apple(appleToken('apple.sub.2', { email: 'sam@example.com', email_verified: true }));
      expect(linked.statusCode).toBe(200);
      expect(linked.json()).toMatchObject({ user_id: reset.json().user_id, has_password: true, created: false });
    });

    it('rejects bad Apple tokens without creating anyone', async () => {
      const wrongNonce = await app.inject({ method: 'POST', url: '/v1/auth/apple',
        payload: { identity_token: appleToken('apple.sub.3'), nonce: 'another-nonce-0123456789' } });
      expect(wrongNonce.statusCode).toBe(401);
      expect(wrongNonce.json().code).toBe('APPLE_TOKEN_BAD_NONCE');
      expect((await apple(appleToken('apple.sub.3', { aud: 'com.evil' }))).json().code).toBe('APPLE_TOKEN_BAD_AUDIENCE');
      expect((await apple('not-a-token')).json().code).toBe('APPLE_TOKEN_MALFORMED');
      expect((await apple(appleToken('apple.sub.3'))).json().created).toBe(true);
    });

    it('deletes an Apple account without a password and queues token revocation', async () => {
      const body = (await apple(appleToken('apple.sub.4'))).json();
      const gone = await app.inject({ method: 'DELETE', url: '/v1/users/me', headers: bearer(body.token) });
      expect(gone.json()).toMatchObject({ ok: true, deleted: true });
      const tomb = await store.deletion(body.user_id);
      expect(tomb).toMatchObject({ provider_uid: 'apple:apple.sub.4', apple_revocation: 'pending', source: 'app' });
      // A fresh Apple sign-in after deletion starts a brand-new account.
      const back = (await apple(appleToken('apple.sub.4'))).json();
      expect(back.created).toBe(true);
      expect(back.user_id).not.toBe(body.user_id);
    });
    it('revokes the Apple authorization on deletion when sign-in provided a code', async () => {
      const body = (await apple(appleToken('apple.sub.5'), { authorization_code: 'good-code' })).json();
      expect(appleCalls).toEqual(['exchange:good-code']);
      await app.inject({ method: 'DELETE', url: '/v1/users/me', headers: bearer(body.token) });
      expect(appleCalls).toEqual(['exchange:good-code', 'revoke:refresh-1']);
      expect((await store.deletion(body.user_id))?.apple_revocation).toBe('revoked');
      // A code Apple rejects still signs in; deletion then stays pending.
      const other = (await apple(appleToken('apple.sub.6'), { authorization_code: 'stale-code' })).json();
      expect(other.token).toBeTruthy();
      await app.inject({ method: 'DELETE', url: '/v1/users/me', headers: bearer(other.token) });
      expect((await store.deletion(other.user_id))?.apple_revocation).toBe('pending');
    });
    // Each sign-in carries a fresh nonce, as the app does: a nonce signs in only once (C-132).
    let nonces = 0;
    const googleToken = (sub: string, over: Record<string, unknown> = {}) => {
      const s = Math.floor(clock / 1000), nonce = `${APPLE_NONCE}-${++nonces}`;
      return { id_token: signToken(GOOGLE_KEYS, { iss: 'https://accounts.google.com', aud: GOOGLE_AUD, sub, iat: s, exp: s + 3600,
        nonce: sha256Hex(nonce), email_verified: true, ...over }), nonce };
    };
    const google = (payload: { id_token: string; nonce: string }, remoteAddress?: string) =>
      app.inject({ method: 'POST', url: '/v1/auth/google', payload, ...(remoteAddress ? { remoteAddress } : {}) });

    it('signs in with Google, links to a verified email account and rejects bad tokens', async () => {
      const first = await google(googleToken('g-1', { email: 'grace@gmail.com', given_name: 'Grace' }));
      expect(first.statusCode).toBe(201);
      expect(first.json()).toMatchObject({ created: true, has_password: false, email: 'grace@gmail.com', display_name: 'Grace' });
      const again = await google(googleToken('g-1', { email: 'grace@gmail.com' }));
      expect(again.json()).toMatchObject({ created: false, user_id: first.json().user_id });
      // A verified email account gains the Google identity instead of a duplicate account.
      await register('hal@example.com');
      await app.inject({ method: 'POST', url: '/v1/auth/email/code', payload: { email: 'hal@example.com', purpose: 'reset' } });
      const code = mail.find(m => m.email === 'hal@example.com' && m.purpose === 'reset')!.code;
      const reset = await app.inject({ method: 'POST', url: '/v1/auth/email/reset', payload: { email: 'hal@example.com', code, password: 'another pass 2' } });
      const linked = await google(googleToken('g-2', { email: 'hal@example.com' }));
      expect(linked.json()).toMatchObject({ created: false, user_id: reset.json().user_id, has_password: true });
      expect((await google(googleToken('g-3', { aud: 'other' }))).json().code).toBe('GOOGLE_TOKEN_BAD_AUDIENCE');
      expect((await google({ id_token: 'x.y.z', nonce: APPLE_NONCE })).json().code).toBe('GOOGLE_TOKEN_MALFORMED');
    });

    it('invite-only (C-96): no self sign-up by email or Google, existing accounts still sign in', async () => {
      const ada = (await register('ada@example.com')).json();
      const grace = (await google(googleToken('g-1', { email: 'grace@gmail.com' }))).json();
      const closed = await buildApp({ store, content, contentVersion: CV, blueprintDir: path.join(ROOT, 'assets', 'blueprints'),
        regionsFile: REGIONS, pepper: 'test-pepper', now: () => clock, mailer, signupClosed: true,
        google: { audiences: [GOOGLE_AUD], keys: GOOGLE_KEYS.keys } });
      try {
        const signup = await closed.inject({ method: 'POST', url: '/v1/auth/email/register', payload: { email: 'eve@example.com', password: 'correct horse' } });
        expect(signup.statusCode).toBe(403);
        expect(signup.json().code).toBe('SIGNUP_CLOSED');
        expect(await store.userByEmail('eve@example.com')).toBeNull();
        expect(mail.filter(m => m.email === 'eve@example.com')).toEqual([]);
        const login = await closed.inject({ method: 'POST', url: '/v1/auth/email/login', payload: { email: 'ada@example.com', password: 'correct horse' } });
        expect(login.json()).toMatchObject({ user_id: ada.user_id, player_id: ada.player_id });
        const viaGoogle = (payload: { id_token: string; nonce: string }) => closed.inject({ method: 'POST', url: '/v1/auth/google', payload });
        expect((await viaGoogle(googleToken('g-1', { email: 'grace@gmail.com' }))).json()).toMatchObject({ created: false, user_id: grace.user_id });
        const stranger = await viaGoogle(googleToken('g-9', { email: 'mallory@gmail.com' }));
        expect(stranger.statusCode).toBe(403);
        expect(stranger.json().code).toBe('SIGNUP_CLOSED');
        expect(await store.userByIdentity('google', 'g-9')).toBeNull();
      } finally { await closed.close(); }
    });

    it('signs in once per Google nonce: a replayed id_token and nonce is refused, also when racing (C-132)', async () => {
      const t = googleToken('g-1', { email: 'grace@gmail.com' });
      const first = await google(t);
      expect(first.statusCode).toBe(201);
      const replay = await google(t, '203.0.113.50');
      expect(replay.statusCode).toBe(401);
      expect(replay.json().code).toBe('GOOGLE_TOKEN_REPLAYED');
      // Another token minted for the same nonce is refused as well.
      const sameNonce = signToken(GOOGLE_KEYS, { iss: 'https://accounts.google.com', aud: GOOGLE_AUD, sub: 'g-1', iat: Math.floor(clock / 1000),
        exp: Math.floor(clock / 1000) + 3600, nonce: sha256Hex(t.nonce), email: 'grace@gmail.com', email_verified: true });
      expect((await google({ id_token: sameNonce, nonce: t.nonce })).json().code).toBe('GOOGLE_TOKEN_REPLAYED');
      // Two sign-ins with one fresh token at the same time: exactly one session is issued.
      const fresh = googleToken('g-1', { email: 'grace@gmail.com' });
      const raced = await Promise.all([google(fresh), google(fresh), google(fresh)]);
      expect(raced.filter(r => r.statusCode === 200)).toHaveLength(1);
      expect(raced.filter(r => r.statusCode === 401).map(r => r.json().code)).toEqual(['GOOGLE_TOKEN_REPLAYED', 'GOOGLE_TOKEN_REPLAYED']);
      // A new nonce signs in as usual.
      expect((await google(googleToken('g-1', { email: 'grace@gmail.com' }))).json()).toMatchObject({ created: false, user_id: first.json().user_id });
    });

    it('lets the owner sign in from their own network while a stranger guesses passwords (C-132)', async () => {
      const OWNER = '198.51.100.7';
      const tryLogin = (password: string, remoteAddress: string) =>
        app.inject({ method: 'POST', url: '/v1/auth/email/login', remoteAddress, payload: { email: 'ada@example.com', password } });
      const owner = (await app.inject({ method: 'POST', url: '/v1/auth/email/register', remoteAddress: OWNER,
        payload: { email: 'ada@example.com', password: 'correct horse' } })).json();
      const stranger = [];
      for (let i = 0; i < 12; i++) stranger.push((await tryLogin('wrong guess', '203.0.113.50')).statusCode);
      expect(stranger).toEqual([...Array(10).fill(401), 429, 429]);
      // Moving to other networks does not reset the budget: unknown networks share one per-email budget (no looser brute force).
      expect((await tryLogin('wrong guess', '203.0.113.51')).json().code).toBe('RATE_LIMITED');
      expect((await tryLogin('wrong guess', '2001:db8:1:2::1')).json().code).toBe('RATE_LIMITED');
      // The owner's own network is unaffected.
      const back = await tryLogin('correct horse', OWNER);
      expect(back.statusCode).toBe(200);
      expect(back.json().user_id).toBe(owner.user_id);
      // A known network still has its own per-network cap: guessing from it is no easier than before.
      const fromOwnerNetwork = [];
      for (let i = 0; i < 10; i++) fromOwnerNetwork.push((await tryLogin('wrong guess', OWNER)).statusCode);
      expect(fromOwnerNetwork).toEqual([...Array(9).fill(401), 429]);
      // Same for an address that never had an account: unknown networks are limited the same way.
      const ghost = [];
      for (let i = 0; i < 11; i++) ghost.push((await app.inject({ method: 'POST', url: '/v1/auth/email/login', remoteAddress: `192.0.2.${i + 1}`,
        payload: { email: 'ghost@example.com', password: 'wrong guess' } })).statusCode);
      expect(ghost).toEqual([...Array(10).fill(401), 429]);
    });

    it('caps verification mail per recipient without revealing which addresses have accounts (C-132)', async () => {
      await app.close();
      app = await build({ accountLimits: { mailPerRecipientHour: 2 } });
      const code = (email: string, purpose = 'reset') => app.inject({ method: 'POST', url: '/v1/auth/email/code', payload: { email, purpose } });
      expect((await register('ada@example.com')).json().verification_sent).toBe(true);
      expect((await code('ada@example.com')).statusCode).toBe(200);
      clock += 61_000;
      const over = await code('ada@example.com', 'verify');
      expect(over.statusCode).toBe(429);
      expect(over.json()).toMatchObject({ code: 'RATE_LIMITED', reason: 'MAIL_LIMIT' });
      expect(Number(over.headers['retry-after'])).toBeGreaterThan(0);
      expect((await app.inject({ method: 'POST', url: '/v1/account/delete/code', payload: { email: 'ada@example.com' } })).json())
        .toMatchObject({ code: 'RATE_LIMITED', reason: 'MAIL_LIMIT' });
      expect(mail.map(m => m.email)).toEqual(['ada@example.com', 'ada@example.com']);
      // An address without an account gets the same answers after the same number of requests.
      expect((await code('ghost@example.com')).statusCode).toBe(200);
      clock += 61_000;
      expect((await code('ghost@example.com')).statusCode).toBe(200);
      const ghost = await code('ghost@example.com');
      expect(ghost.statusCode).toBe(429);
      expect(Object.keys(ghost.json()).sort()).toEqual(Object.keys(over.json()).sort());
      expect(ghost.json()).toMatchObject({ code: 'RATE_LIMITED', reason: 'MAIL_LIMIT' });
      // Signing up with an address already at its limit creates the account but sends nothing, and says so.
      const signup = await register('ghost@example.com');
      expect(signup.statusCode).toBe(201);
      expect(signup.json()).toMatchObject({ verification_sent: false, verification_error: 'MAIL_LIMIT' });
      expect(mail.filter(m => m.email === 'ghost@example.com')).toEqual([]);
      // QA addresses are never mailed and so never limited.
      for (let i = 0; i < 4; i++) { clock += 61_000; expect((await code('bot@qa.sensen.test')).statusCode).toBe(200); }
    });

    it('caps verification mail for the whole server (C-132)', async () => {
      await app.close();
      app = await build({ accountLimits: { mailPerHour: 3 } });
      for (const name of ['a1', 'a2', 'a3']) expect((await register(`${name}@example.com`)).json().verification_sent).toBe(true);
      const fourth = await register('a4@example.com');
      expect(fourth.statusCode).toBe(201);
      expect(fourth.json()).toMatchObject({ verification_sent: false, verification_error: 'MAIL_LIMIT' });
      const resend = await app.inject({ method: 'POST', url: '/v1/auth/email/code', payload: { email: 'a1@example.com', purpose: 'reset' } });
      expect(resend.statusCode).toBe(429);
      expect(resend.json()).toMatchObject({ code: 'RATE_LIMITED', reason: 'MAIL_LIMIT' });
      expect(mail.map(m => m.email)).toEqual(['a1@example.com', 'a2@example.com', 'a3@example.com']);
    });
  });
}
