/**
 * 邮箱账户、游客只读与全球城市（SGODOT-135 / 136）。同一组场景跑内存与 PostgreSQL 两套 Store。
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
import { CENTER, fixtureGeography, geographicPoint } from '../geography/fixtures.js';
import type { FarmLocation } from '../../src/http/farm_location.js';
import type { Mailer } from '../../src/accounts/mailer.js';

const DSN = process.env.TEST_DATABASE_URL;
const content = loadContent(DEFAULT_CONTENT_DIR);
const CV = contentVersion(DEFAULT_CONTENT_DIR);
const ROOT = path.resolve(DEFAULT_CONTENT_DIR, '..', '..', '..');
const REGIONS = path.join(DEFAULT_CONTENT_DIR, 'regions.json');
const TOKYO: FarmLocation = { lat: 35.6812, lng: 139.7671 };
const landAt = (c: FarmLocation) => fixtureGeography([{ id: 'land', kind: 'land', surface: 'soil',
  polygon: [[-1, -1], [65, -1], [65, 65], [-1, 65], [-1, -1]].map(([x, y]) => geographicPoint(x, y, c)) }]);

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
    let clock = Date.UTC(2026, 8, 28, 2);
    let mail: { email: string; code: string; purpose: string }[] = [];
    const mailer: Mailer = { async sendCode(email, code, purpose) { mail.push({ email, code, purpose }); } };
    const ipLocator = async (ip: string) => ip === '203.0.113.9' ? TOKYO : null;

    beforeEach(async () => {
      if (pool) await truncateAll(pool);
      mail = [];
      clock = Date.UTC(2026, 8, 28, 2);
      app = await buildApp({ store: makeStore(() => clock), content, contentVersion: CV, blueprintDir: path.join(ROOT, 'assets', 'blueprints'),
        regionsFile: REGIONS, pepper: 'test-pepper', now: () => clock, mailer, ipLocator,
        qaEmailDomain: 'qa.sensen.test', qaEmailCode: '424242',
        geographyProvider: async location => landAt(location) });
    });
    afterEach(async () => { await app.close(); });

    const bearer = (token: string) => ({ authorization: `Bearer ${token}` });
    const register = (email: string, password = 'correct horse') =>
      app.inject({ method: 'POST', url: '/v1/auth/email/register', payload: { email, password } });
    const login = (email: string, password: string) =>
      app.inject({ method: 'POST', url: '/v1/auth/email/login', payload: { email, password } });
    const guest = async () => (await app.inject({ method: 'POST', url: '/v1/auth/anonymous', payload: { install_key: newInstallKey() } })).json().token as string;
    const createFarm = (token: string, location: FarmLocation, region_id = '', key = 'farm') => app.inject({ method: 'POST', url: '/v1/farms',
      headers: bearer(token), payload: { generation_version: 3, idempotency_key: key, region_id, location } });

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
      const create = await createFarm(token, TOKYO);
      expect(create.statusCode).toBe(401);
      expect(create.json().code).toBe('LOGIN_REQUIRED');
      const command = await app.inject({ method: 'POST', url: '/v1/farms/me/commands', headers: bearer(token),
        payload: { type: 'till_cells', idempotency_key: 'k', base_version: 0, payload: { cell_ids: ['1,1'] } } });
      expect(command.json().code).toBe('LOGIN_REQUIRED');
      expect((await app.inject({ method: 'GET', url: '/v1/users/me', headers: bearer(token) })).json().code).toBe('LOGIN_REQUIRED');
      expect((await app.inject({ method: 'GET', url: '/v1/nearby?region_id=shanghai', headers: bearer(token) })).statusCode).toBe(200);
      expect((await app.inject({ method: 'GET', url: '/v1/cities' })).statusCode).toBe(200);
    });

    it('creates a farm in any city, resolved and timed by the server', async () => {
      const { token } = (await register('fay@example.com')).json();
      const created = await createFarm(token, TOKYO, 'shanghai');
      expect(created.statusCode).toBe(201);
      const farm = created.json();
      expect(farm.region_id).toMatch(/^gn-\d+$/);
      expect(farm.farm_terrain.farm_style).toBe('east_asian');
      const city = (await app.inject({ method: 'GET', url: `/v1/cities/${farm.region_id}` })).json().city;
      expect(city).toMatchObject({ name: 'Tokyo', timezone: 'Asia/Tokyo', country_code: 'JP', curated: false });
      expect((await app.inject({ method: 'GET', url: '/v1/users/me', headers: bearer(token) })).json().has_farm).toBe(true);
      // Farm clocks follow the city: Tokyo's day id differs from UTC's at 02:00 UTC only by date math, not by region lookup.
      expect((await app.inject({ method: 'GET', url: '/v1/farms/me', headers: bearer(token) })).statusCode).toBe(200);
      const curated = await createFarm((await register('gus@example.com')).json().token, CENTER, 'shanghai', 'sh');
      expect(curated.json().region_id).toBe('shanghai');
      const sea = await createFarm((await register('hal@example.com')).json().token, { lat: 0, lng: -140 }, '', 'sea');
      expect(sea.json().code).toBe('LOCATION_OUTSIDE_REGION');
    });

    it('lists curated cities first, then cities with public farms, and suggests by IP', async () => {
      const { token } = (await register('ivy@example.com')).json();
      const farm = (await createFarm(token, TOKYO)).json();
      const opening = await app.inject({ method: 'POST', url: '/v1/farms/me/commands', headers: bearer(token),
        payload: { type: 'set_visit_access', idempotency_key: 'open', base_version: farm.version, payload: { access: 'anyone' } } });
      expect(opening.statusCode).toBe(200);
      const list = (await app.inject({ method: 'GET', url: '/v1/cities' })).json().cities;
      expect(list.slice(0, 2).map((c: { id: string }) => c.id)).toEqual(['shanghai', 'los_angeles']);
      expect(list.find((c: { id: string }) => c.id === farm.region_id)).toMatchObject({ name: 'Tokyo', farm_count: 1 });
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
      expect((await createFarm(body.token, TOKYO)).statusCode).toBe(201);
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

    it('exports the account and farm without secrets', async () => {
      const body = (await register('kim@example.com')).json();
      await createFarm(body.token, TOKYO);
      const exported = await app.inject({ method: 'GET', url: '/v1/users/me/export', headers: bearer(body.token) });
      expect(exported.statusCode).toBe(200);
      const text = exported.body;
      expect(text).not.toContain('scrypt$');
      expect(text).not.toContain(body.token);
      expect(exported.json().farm.city_id).toMatch(/^gn-/);
    });
  });
}
