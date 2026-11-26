/**
 * C-146：去掉游客入口（GUEST_ACCOUNTS=closed）和删除游客号的工具（所有者在 Q-265 选了 delete）。
 * - 关掉后 /v1/auth/anonymous 对新安装和已有游客一律 403 GUEST_CLOSED，不建号；之前发出的游客 token 不再算登录。
 * - 删除工具只删游客号和它们的地块、进度：先备份并核对条数；预演不改数据；备份之后有变化、备份被改过、库名不对都不删；
 *   邮箱账号、邀请账号和系统玩家的数据逐字节不变；备份能原样恢复。工具只在 PostgreSQL 上跑。
 */
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { mkdtempSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import pg from 'pg';
import { buildApp, plotFor } from '../../src/http/app.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { PgStore } from '../../src/db/pg_store.js';
import { migrate, truncateAll } from '../../src/db/migrate.js';
import type { Store } from '../../src/http/store.js';
import { newInstallKey } from '../../src/http/auth.js';
import { guestAccountsClosedFromEnv } from '../../src/http/signup_limits.js';
import { DEFAULT_CONTENT_DIR, contentVersion, loadContent } from '../../src/domain/content.js';
import { loadParcelRules } from '../../src/parcels/rules.js';
import { MemoryParcelStore, type ParcelStore } from '../../src/parcels/store.js';
import { PgParcelStore } from '../../src/parcels/pg_store.js';
import { DAY_MS, reclaimIdleParcels } from '../../src/parcels/reclaim.js';
import { createInvites } from '../../src/accounts/invites.js';
import {
  BACKUP_FORMAT, GUEST_TABLES, GuestPurgeError, guestWhere, backupGuests, parseGuestBackup, planGuestPurge, purgeGuests, restoreGuests,
  runGuestPurgeCli, type GuestPurgeIo,
} from '../../src/ops/guest_purge.js';

const DSN = process.env.TEST_DATABASE_URL;
if (process.env.CI === '1' && !DSN) throw new Error('CI 下必须设置 TEST_DATABASE_URL');

const content = loadContent(DEFAULT_CONTENT_DIR);
const CV = contentVersion(DEFAULT_CONTENT_DIR);
const ROOT = path.resolve(DEFAULT_CONTENT_DIR, '..', '..', '..');
const rules = loadParcelRules(DEFAULT_CONTENT_DIR);
const DATASET = 'sf-dynamic-farm-20261118-r4';
const T0 = Date.UTC(2026, 10, 26, 4);
const A = { parcel_id: 'p-3512001', center: [-122.4194, 37.7749] };
const B = { parcel_id: 'p-3512002', center: [-122.4180, 37.7752] };
const C = { parcel_id: 'p-3512003', center: [-122.4170, 37.7755] };
const D = { parcel_id: 'p-3512004', center: [-122.4160, 37.7758] };

let pool: pg.Pool | undefined;
beforeAll(async () => { if (DSN) { pool = new pg.Pool({ connectionString: DSN, max: 10 }); await migrate(pool); } });
afterAll(async () => { await pool?.end(); });

let clock = T0;
const bearer = (token: string) => ({ authorization: `Bearer ${token}` });
type Stores = { store: Store; parcels: ParcelStore };
const memoryStores = (): Stores => {
  const store = new MemoryStore({ content, timezone: 'America/Los_Angeles', plot: plotFor(content), now: () => clock, contentVersion: CV });
  return { store, parcels: new MemoryParcelStore(id => store.displayNameOf(id), id => store.playerActivity(id)) };
};
const pgStores = (): Stores => ({
  store: new PgStore({ pool: pool!, content, contentVersion: CV, timezone: () => 'America/Los_Angeles', plot: plotFor(content), now: () => clock }),
  parcels: new PgParcelStore(pool!),
});
const appFor = (stores: Stores, o: { closed?: boolean; guestWrites?: boolean } = {}) => buildApp({
  store: stores.store, content, contentVersion: CV, blueprintDir: path.join(ROOT, 'assets', 'blueprints'),
  regionsFile: path.join(DEFAULT_CONTENT_DIR, 'regions.json'), pepper: 'test-pepper', now: () => clock, realtimeEnabled: false,
  guestWrites: o.guestWrites, guestAccountsClosed: o.closed,
  parcels: { store: stores.parcels, rules, reselect: false, guestWrites: o.guestWrites },
});

const install = async (app: FastifyInstance, key = newInstallKey()) => {
  const res = await app.inject({ method: 'POST', url: '/v1/auth/anonymous', payload: { install_key: key } });
  return { res, key, token: res.json().token as string, player: res.json().player_id as string };
};
const register = async (app: FastifyInstance, name: string) => {
  const res = await app.inject({ method: 'POST', url: '/v1/auth/email/register',
    payload: { email: `${name.toLowerCase()}@example.com`, password: 'correct horse', display_name: name } });
  expect(res.statusCode).toBe(201);
  return { token: res.json().token as string, player: res.json().player_id as string };
};
const claim = (app: FastifyInstance, token: string, parcel: { parcel_id: string; center: number[] }) =>
  app.inject({ method: 'POST', url: '/v1/parcels/claim', headers: bearer(token), payload: { dataset_version: DATASET, ...parcel } });
const enterAndTill = async (app: FastifyInstance, token: string) => {
  expect((await app.inject({ method: 'POST', url: '/v1/parcels/mine/enter', headers: bearer(token) })).statusCode).toBe(200);
  expect((await app.inject({ method: 'POST', url: '/v1/parcels/mine/commands', headers: bearer(token),
    payload: { base_version: 1, commands: [{ type: 'till', cell: '1,1' }] } })).statusCode).toBe(200);
};
const journeyFarm = async (app: FastifyInstance, token: string) => {
  const farm = await app.inject({ method: 'POST', url: '/v1/farms', headers: bearer(token),
    payload: { idempotency_key: 'k1', region_id: 'shanghai', layout_patch_id: 'sh_a', blueprint_revision: 2 } });
  expect(farm.statusCode).toBe(201);
  const tilled = await app.inject({ method: 'POST', url: '/v1/farms/me/commands', headers: bearer(token),
    payload: { type: 'till_cells', idempotency_key: 'till', base_version: farm.json().version, payload: { cell_ids: ['0,0'] } } });
  expect(tilled.statusCode).toBe(200);
  return farm.json().farm_id as string;
};

describe('GUEST_ACCOUNTS switch', () => {
  it('parses open / closed and refuses anything else', () => {
    expect(guestAccountsClosedFromEnv({})).toBe(false);
    expect(guestAccountsClosedFromEnv({ GUEST_ACCOUNTS: '' })).toBe(false);
    expect(guestAccountsClosedFromEnv({ GUEST_ACCOUNTS: 'open' })).toBe(false);
    expect(guestAccountsClosedFromEnv({ GUEST_ACCOUNTS: 'closed' })).toBe(true);
    for (const v of ['Closed', '0', '1', 'off', 'close']) expect(guestAccountsClosedFromEnv({ GUEST_ACCOUNTS: v })).toBeNull();
  });
});

const makers: [string, boolean, () => Stores][] = [['MemoryStore', true, memoryStores], ['PgStore', Boolean(DSN), pgStores]];
for (const [name, enabled, makeStores] of makers) {
  describe.skipIf(!enabled)(`${name}: no guest entry (C-146)`, () => {
    let stores: Stores;
    beforeEach(async () => { if (pool) await truncateAll(pool); clock = T0; stores = makeStores(); });

    it('a direct call to the guest sign-in creates no player: new installations and existing guests get 403 GUEST_CLOSED', async () => {
      const open = await appFor(stores, { guestWrites: true });
      const closed = await appFor(stores, { closed: true, guestWrites: true });
      try {
        const old = await install(open);
        expect(old.res.statusCode).toBe(200);
        await claim(open, old.token, A);
        const players = pool ? (await pool.query('SELECT count(*)::int AS n FROM players')).rows[0].n : 0;
        for (const key of [newInstallKey(), newInstallKey(), old.key]) {
          const refused = await install(closed, key);
          expect(refused.res.statusCode).toBe(403);
          expect(refused.res.json().code).toBe('GUEST_CLOSED');
          expect(refused.token).toBeUndefined();
        }
        // Not a rate limit: the refusal is the same however often it is asked, and nothing is created.
        for (let i = 0; i < 15; i++) expect((await install(closed)).res.json().code).toBe('GUEST_CLOSED');
        if (pool) expect((await pool.query('SELECT count(*)::int AS n FROM players')).rows[0].n).toBe(players);
        expect(await stores.store.installationKnown('0'.repeat(64))).toBe(false);
      } finally { await open.close(); await closed.close(); }
    });

    it('a guest token issued before is no longer a sign-in anywhere; accounts are unaffected', async () => {
      const open = await appFor(stores, { guestWrites: true });
      const closed = await appFor(stores, { closed: true, guestWrites: true });
      try {
        const guest = await install(open);
        await claim(open, guest.token, A);
        const ada = await register(open, 'Ada');
        await claim(open, ada.token, B);
        const asGuest: [string, string, object?][] = [
          ['GET', '/v1/parcels/mine'], ['GET', '/v1/farms/me'], ['GET', '/v1/users/me'],
          ['POST', '/v1/parcels/claim', { dataset_version: DATASET, ...C }],
          ['POST', '/v1/parcels/mine/commands', { base_version: 0, commands: [{ type: 'till', cell: '1,1' }] }],
          ['POST', '/v1/farms', { idempotency_key: 'k', region_id: 'shanghai', layout_patch_id: 'sh_a', blueprint_revision: 2 }],
        ];
        for (const [method, url, payload] of asGuest) {
          const res = await closed.inject({ method: method as 'GET' | 'POST', url, headers: bearer(guest.token), payload });
          expect.soft(res.statusCode, `${method} ${url}`).toBe(401);
          expect.soft(res.json().code, `${method} ${url}`).toBe('UNAUTHENTICATED');
        }
        // The same server: email sign-up, sign-in and the account's own parcel work as before.
        expect((await closed.inject({ method: 'GET', url: '/v1/parcels/mine', headers: bearer(ada.token) })).json().parcel.parcel_id).toBe(B.parcel_id);
        const bob = await register(closed, 'Bob');
        expect((await claim(closed, bob.token, C)).statusCode).toBe(201);
        const login = await closed.inject({ method: 'POST', url: '/v1/auth/email/login', payload: { email: 'ada@example.com', password: 'correct horse' } });
        expect(login.statusCode).toBe(200);
        expect(login.json().player_id).toBe(ada.player);
      } finally { await open.close(); await closed.close(); }
    });

    it('without the switch (Journey, development) guests sign in as before', async () => {
      const app = await appFor(stores);
      try { expect((await install(app)).res.statusCode).toBe(200); } finally { await app.close(); }
    });
  });
}

/** Every row of every table, for "nothing else changed". */
const ALL_TABLES = ['players', 'tokens', 'farms', 'farm_creations', 'commands', 'farm_snapshots', 'online_rooms', 'online_parties',
  'online_players', 'users', 'user_identities', 'email_codes', 'account_deletions', 'parcel_claims', 'parcel_reclaims'];
async function dump(db: pg.Pool, except?: { players: string[]; farms: string[] }): Promise<Record<string, string[]>> {
  const out: Record<string, string[]> = {};
  for (const table of ALL_TABLES) {
    const guest = except && GUEST_TABLES.find(t => t.name === table);
    const w = guest ? guestWhere(guest.where, except.players, except.farms) : { sql: '', params: [] };
    const r = await db.query(`SELECT to_jsonb(t)::text AS row FROM ${table} t ${guest ? `WHERE NOT (${w.sql})` : ''} ORDER BY 1`, w.params);
    out[table] = r.rows.map(row => row.row as string);
  }
  return out;
}

describe.skipIf(!DSN)('guest purge tool (PostgreSQL)', () => {
  let app: FastifyInstance;
  let guests: { players: string[]; farms: string[] };
  let accounts: { ada: string; invite: string };

  /** Three guests (a parcel with a save, a Journey farm with commands and a snapshot, an archived reclaimed parcel and an
   * online seat), an email account with a parcel and a Journey farm, an invite account with a parcel, and a system player. */
  beforeEach(async () => {
    await truncateAll(pool!);
    clock = T0;
    const stores = pgStores();
    app = await appFor(stores, { guestWrites: true });
    const g1 = await install(app); await claim(app, g1.token, A); await enterAndTill(app, g1.token);
    const g2 = await install(app); const g2farm = await journeyFarm(app, g2.token);
    await pool!.query(`INSERT INTO farm_snapshots (farm_id, snapshot_revision, snapshot_taken_at, body, blueprint_revision, content_version, domain_version)
      VALUES ($1, 1, $2, '{"cells":{}}', 2, 'cv', 'dv')`, [g2farm, T0]);
    await pool!.query(`INSERT INTO online_players (player_id, instance_id, party_id) VALUES ($1, 'street:1', '')`, [g2.player]);
    const g3 = await install(app); await claim(app, g3.token, C);
    expect(await reclaimIdleParcels(stores.parcels, 30, T0 + 31 * DAY_MS)).toBeGreaterThanOrEqual(1);
    // Accounts act after the reclaim, so their parcels stay.
    clock = T0 + 31 * DAY_MS + 1000;
    const g1again = await install(app, g1.key); await claim(app, g1again.token, A); // g1 claims again after losing it
    const ada = await register(app, 'Ada'); await claim(app, ada.token, B); await enterAndTill(app, ada.token);
    const adaFarm = await journeyFarm(app, ada.token);
    await pool!.query(`INSERT INTO farm_snapshots (farm_id, snapshot_revision, snapshot_taken_at, body, blueprint_revision, content_version, domain_version)
      VALUES ($1, 1, $2, '{"cells":{}}', 2, 'cv', 'dv')`, [adaFarm, T0]);
    const [invite] = await createInvites(pool!, { count: 1, domain: 'invite.example', batch: 'wave-1' }, clock);
    const login = await app.inject({ method: 'POST', url: '/v1/auth/email/login', payload: { email: invite!.email, password: invite!.password } });
    expect(login.statusCode).toBe(200);
    await claim(app, login.json().token, D);
    await pool!.query(`INSERT INTO players (id, install_key_hmac, created_at, last_seen_at) VALUES ('00000000-0000-5000-8000-000000000001', 'preset:demo', 0, 0)`);
    guests = { players: [g1.player, g2.player, g3.player].sort(), farms: [g2farm] };
    accounts = { ada: ada.player, invite: login.json().player_id };
  });
  afterEach(async () => { await app.close(); });

  it('plan lists what would be deleted and changes nothing', async () => {
    const before = await dump(pool!);
    const plan = await planGuestPurge(pool!);
    expect(plan.counts).toEqual({ players: 3, farms: 1, farm_creations: 1, commands: 1, farm_snapshots: 1, tokens: 4,
      online_players: 1, parcel_claims: 1, parcel_reclaims: 2 });
    expect(plan.totals.players).toBe(6);
    expect(plan.kept).toEqual({ account_players: 2, other_players: 1 });
    expect(await dump(pool!)).toEqual(before);
  });

  it('backs up, deletes only the guests and their data, and restores them exactly', async () => {
    const before = await dump(pool!);
    const others = await dump(pool!, guests);
    const text = await backupGuests(pool!, clock);
    const backup = parseGuestBackup(text);
    expect(backup.header).toMatchObject({ format: BACKUP_FORMAT, counts: { players: 3, tokens: 4, parcel_claims: 1, parcel_reclaims: 2 } });
    expect(JSON.parse(backup.rows.get('players')!).map((p: { id: string }) => p.id)).toEqual(guests.players);
    const database = (await pool!.query('SELECT current_database() AS db')).rows[0].db as string;

    expect(await purgeGuests(pool!, text, database)).toEqual(backup.header.counts);
    const after = await dump(pool!);
    expect(after).toEqual(others); // email, invite and system players and all their data: byte for byte as before
    expect(after.players.map(p => JSON.parse(p).id)).toEqual(expect.arrayContaining([accounts.ada, accounts.invite]));
    expect((await planGuestPurge(pool!)).counts.players).toBe(0);
    // The account still signs in and finds its parcel and farm.
    const login = await app.inject({ method: 'POST', url: '/v1/auth/email/login', payload: { email: 'ada@example.com', password: 'correct horse' } });
    const token = login.json().token as string;
    expect((await app.inject({ method: 'GET', url: '/v1/parcels/mine', headers: bearer(token) })).json().parcel.parcel_id).toBe(B.parcel_id);
    expect((await app.inject({ method: 'GET', url: '/v1/farms/me', headers: bearer(token) })).statusCode).toBe(200);

  });

  it('a restored database is the original one again', async () => {
    const before = await dump(pool!);
    const text = await backupGuests(pool!, clock);
    const database = (await pool!.query('SELECT current_database() AS db')).rows[0].db as string;
    await purgeGuests(pool!, text, database);
    await restoreGuests(pool!, text, database);
    expect(await dump(pool!)).toEqual(before);
  });

  it('deletes nothing when the guests changed after the backup, the backup was altered or the database is another one', async () => {
    const text = await backupGuests(pool!, clock);
    const database = (await pool!.query('SELECT current_database() AS db')).rows[0].db as string;
    const before = await dump(pool!);
    const refusals: [string, () => Promise<unknown>][] = [
      ['wrong confirmation', () => purgeGuests(pool!, text, 'sensen_journey')],
      ['empty confirmation', () => purgeGuests(pool!, text, '')],
      ['truncated', () => purgeGuests(pool!, text.slice(0, -40), database)],
      ['edited row', () => purgeGuests(pool!, text.replace('"install_key_hmac": "', '"install_key_hmac": "0'), database)],
      ['edited count', () => purgeGuests(pool!, text.replace('"players":3', '"players":2'), database)],
      ['other database', () => purgeGuests(pool!, text.replace(`"database":"${database}"`, '"database":"elsewhere"'), 'elsewhere')],
      ['not a backup', () => purgeGuests(pool!, 'hello\n', database)],
    ];
    for (const [what, run] of refusals) {
      await expect(run(), what).rejects.toBeInstanceOf(GuestPurgeError);
      expect(await dump(pool!), what).toEqual(before);
    }
    // A guest signs in once more after the backup: a new token, so the data no longer matches.
    const open = await appFor(pgStores(), { guestWrites: true });
    try {
      const another = await install(open); // a new guest after the backup
      expect(another.res.statusCode).toBe(200);
    } finally { await open.close(); }
    const changed = await dump(pool!);
    await expect(purgeGuests(pool!, text, database)).rejects.toThrow(/有变化/);
    expect(await dump(pool!)).toEqual(changed);
    // A fresh backup then goes through and takes the new guest too.
    const fresh = await backupGuests(pool!, clock);
    expect((await purgeGuests(pool!, fresh, database)).players).toBe(4);
  });

  it('refuses to run when another table references players or farms (it would be deleted without a backup)', async () => {
    await pool!.query('CREATE TABLE guest_purge_probe (player_id uuid REFERENCES players(id) ON DELETE CASCADE)');
    try {
      const before = await dump(pool!);
      await expect(planGuestPurge(pool!)).rejects.toThrow(/guest_purge_probe\.player_id>players/);
      await expect(backupGuests(pool!, clock)).rejects.toThrow(/guest_purge_probe/);
      expect(await dump(pool!)).toEqual(before);
    } finally { await pool!.query('DROP TABLE guest_purge_probe'); }
    const text = await backupGuests(pool!, clock);
    await pool!.query('CREATE TABLE guest_purge_probe (farm_id uuid REFERENCES farms(id))');
    try {
      const database = (await pool!.query('SELECT current_database() AS db')).rows[0].db as string;
      await expect(purgeGuests(pool!, text, database)).rejects.toThrow(/guest_purge_probe\.farm_id>farms/);
    } finally { await pool!.query('DROP TABLE guest_purge_probe'); }
    expect((await planGuestPurge(pool!)).counts.players).toBe(3);
  });

  it('restore refuses and keeps the database as it is when a restored row would collide', async () => {
    const text = await backupGuests(pool!, clock);
    const database = (await pool!.query('SELECT current_database() AS db')).rows[0].db as string;
    await purgeGuests(pool!, text, database);
    // Someone claimed the guest's parcel A in the meantime.
    const bob = await register(app, 'Bob');
    expect((await claim(app, bob.token, A)).statusCode).toBe(201);
    const before = await dump(pool!);
    await expect(restoreGuests(pool!, text, database)).rejects.toThrow();
    expect(await dump(pool!)).toEqual(before);
  });

  describe('command line', () => {
    const run = async (argv: string[], o: { stdin?: string; tty?: boolean; cwd?: string } = {}) => {
      let out = '', err = '';
      const io: GuestPurgeIo = { pool: pool!, cwd: o.cwd ?? dir, stdoutIsTTY: o.tty ?? false, now: () => clock,
        stdout: t => { out += t; }, stderr: t => { err += t; }, readStdin: () => o.stdin ?? '' };
      return { code: await runGuestPurgeCli(argv, io), out, err };
    };
    let dir: string;
    beforeEach(() => { dir = mkdtempSync(path.join(tmpdir(), 'guest-purge-')); });

    it('plan, backup to a new 0600 file, verify, purge and restore', async () => {
      const before = await dump(pool!);
      const plan = await run(['plan']);
      expect(plan.code).toBe(0);
      expect(plan.out).toContain('会删 players=3 farms=1');
      expect(await dump(pool!)).toEqual(before);
      const file = path.join(dir, 'guests.txt');
      expect((await run(['backup', '--out', file])).code).toBe(0);
      expect(statSync(file).mode & 0o777).toBe(0o600);
      expect((await run(['backup', '--out', file])).code).toBe(2); // never overwritten
      expect((await run(['backup', '--out', '-'], { tty: true })).code).toBe(2); // not onto a terminal
      const piped = await run(['backup', '--out', '-']);
      expect(piped.out).toBe(readFileSync(file, 'utf8')); // the same snapshot either way
      const verify = await run(['verify', '--backup', file]);
      expect(verify.code).toBe(0);
      expect(verify.out).toContain('players=3');
      const database = (await pool!.query('SELECT current_database() AS db')).rows[0].db as string;
      expect((await run(['purge', '--backup', file])).code).toBe(2); // needs --confirm-database
      expect(await dump(pool!)).toEqual(before);
      const purge = await run(['purge', '--backup', '-', '--confirm-database', database], { stdin: readFileSync(file, 'utf8') });
      expect(purge.code, purge.err).toBe(0);
      expect(purge.out).toContain('已删除并核对：players=3');
      expect((await planGuestPurge(pool!)).counts.players).toBe(0);
      const restore = await run(['restore', '--backup', file, '--confirm-database', database]);
      expect(restore.code, restore.err).toBe(0);
      expect(await dump(pool!)).toEqual(before);
    });

    it('a damaged backup file is reported and nothing is deleted', async () => {
      const file = path.join(dir, 'guests.txt');
      await run(['backup', '--out', file]);
      writeFileSync(path.join(dir, 'cut.txt'), readFileSync(file, 'utf8').slice(0, -10));
      const before = await dump(pool!);
      const database = (await pool!.query('SELECT current_database() AS db')).rows[0].db as string;
      expect((await run(['verify', '--backup', path.join(dir, 'cut.txt')])).code).toBe(1);
      const purge = await run(['purge', '--backup', path.join(dir, 'cut.txt'), '--confirm-database', database]);
      expect(purge.code).toBe(1);
      expect(purge.err).toContain('SHA-256');
      expect(await dump(pool!)).toEqual(before);
      expect((await run(['bogus'])).code).toBe(2);
    });
  });
});
