/**
 * 邀请账号（C-96）：工具直接写库建的账号能在只用邀请账号的服务上登录、认领、存档；重置、停用；命令行不把密码打到终端或仓库里。
 * 写库的场景只在 PostgreSQL 上跑（邀请账号就是写真库）；输出位置的检查不连库。
 */
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { mkdtempSync, readFileSync, rmSync, statSync, writeFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import pg from 'pg';
import { buildApp, plotFor } from '../../src/http/app.js';
import { PgStore } from '../../src/db/pg_store.js';
import { migrate, truncateAll } from '../../src/db/migrate.js';
import { DEFAULT_CONTENT_DIR, contentVersion, loadContent } from '../../src/domain/content.js';
import { loadParcelRules } from '../../src/parcels/rules.js';
import { PgParcelStore } from '../../src/parcels/pg_store.js';
import { createInvites, disableInvite, isInviteDomain, listInvites, newInvitePassword, resetInvite } from '../../src/accounts/invites.js';
import { insideGitWorkTree, outRefusal, runInviteCli, type InviteCliIo } from '../../src/accounts/invite_cli.js';
import { signupClosedFromEnv } from '../../src/accounts/routes.js';

const DSN = process.env.TEST_DATABASE_URL;
if (process.env.CI === '1' && !DSN) throw new Error('CI 下必须设置 TEST_DATABASE_URL');

const content = loadContent(DEFAULT_CONTENT_DIR);
const CV = contentVersion(DEFAULT_CONTENT_DIR);
const ROOT = path.resolve(DEFAULT_CONTENT_DIR, '..', '..', '..');
const REGIONS = path.join(DEFAULT_CONTENT_DIR, 'regions.json');
const DOMAIN = 'invite.example.org';
const DATASET = 'sf-dynamic-farm-20261118-r4';
const T0 = Date.UTC(2026, 10, 24, 4);

describe('ACCOUNT_SIGNUP', () => {
  it('is open unless set to closed, and refuses anything else', () => {
    expect(signupClosedFromEnv({})).toBe(false);
    expect(signupClosedFromEnv({ ACCOUNT_SIGNUP: '' })).toBe(false);
    expect(signupClosedFromEnv({ ACCOUNT_SIGNUP: 'open' })).toBe(false);
    expect(signupClosedFromEnv({ ACCOUNT_SIGNUP: 'closed' })).toBe(true);
    for (const bad of ['close', 'CLOSED', '1', 'true']) expect(signupClosedFromEnv({ ACCOUNT_SIGNUP: bad })).toBeNull();
  });
});

describe('invite passwords and output locations', () => {
  let dir: string;
  beforeEach(() => { dir = mkdtempSync(path.join(tmpdir(), 'invites-')); });
  afterEach(() => { rmSync(dir, { recursive: true, force: true }); });

  it('makes long, unambiguous passwords and checks the domain', () => {
    const seen = new Set<string>();
    for (let i = 0; i < 200; i++) {
      const p = newInvitePassword();
      expect(p).toMatch(/^[a-hjkmnp-z2-9]{4}(-[a-hjkmnp-z2-9]{4}){3}$/);
      seen.add(p);
    }
    expect(seen.size).toBe(200);
    expect(isInviteDomain('invite.example.org')).toBe(true);
    for (const bad of ['', 'localhost', 'a b.org', 'x@y.org', 'Invite.Example.org']) expect(isInviteDomain(bad)).toBe(false);
  });

  it('refuses a terminal, an existing file, a missing directory and anywhere inside a Git work tree', () => {
    expect(outRefusal(undefined, dir, false)).toMatch(/--out/);
    expect(outRefusal('-', dir, true)).toMatch(/终端/);
    expect(outRefusal('-', dir, false)).toBeNull();
    writeFileSync(path.join(dir, 'taken.csv'), '');
    expect(outRefusal('taken.csv', dir, false)).toMatch(/已存在/);
    expect(outRefusal('missing/x.csv', dir, false)).toMatch(/目录不存在/);
    expect(outRefusal('new.csv', dir, false)).toBeNull();
    expect(insideGitWorkTree(ROOT)).toBe(true);
    expect(outRefusal(path.join(ROOT, 'invites.csv'), dir, false)).toMatch(/Git 工作区/);
    expect(outRefusal(path.join(ROOT, 'server', 'invites.csv'), dir, false)).toMatch(/Git 工作区/);
  });

  it('stops before touching the database when the output is refused', async () => {
    const lines: string[] = [];
    const pool = new Proxy({}, { get: () => { throw new Error('database touched'); } }) as unknown as pg.Pool;
    const io: InviteCliIo = { pool, env: { INVITE_EMAIL_DOMAIN: DOMAIN }, cwd: dir, stdoutIsTTY: true,
      stdout: t => { lines.push('out:' + t); }, stderr: t => { lines.push('err:' + t); }, now: () => T0 };
    expect(await runInviteCli(['create', '--count', '2', '--batch', 'b1', '--out', '-'], io)).toBe(2);
    expect(await runInviteCli(['create', '--count', '2', '--batch', 'b1', '--out', path.join(ROOT, 'x.csv')], io)).toBe(2);
    expect(await runInviteCli(['reset', '--email', `a@${DOMAIN}`], io)).toBe(2);
    expect(lines.every(l => l.startsWith('err:'))).toBe(true);
    expect(existsSync(path.join(ROOT, 'x.csv'))).toBe(false);
  });
});

describe.skipIf(!DSN)('PgStore: invite accounts', () => {
  let pool: pg.Pool;
  let app: FastifyInstance;
  let dir: string;
  let clock = T0;
  beforeAll(async () => { pool = new pg.Pool({ connectionString: DSN, max: 5 }); await migrate(pool); });
  afterAll(async () => { await pool.end(); });
  beforeEach(async () => {
    await truncateAll(pool);
    clock = T0;
    dir = mkdtempSync(path.join(tmpdir(), 'invites-'));
    const store = new PgStore({ pool, content, contentVersion: CV, timezone: () => 'America/Los_Angeles', plot: plotFor(content), now: () => clock });
    app = await buildApp({ store, content, contentVersion: CV, blueprintDir: path.join(ROOT, 'assets', 'blueprints'),
      regionsFile: REGIONS, pepper: 'test-pepper', now: () => clock, realtimeEnabled: false, signupClosed: true,
      parcels: { store: new PgParcelStore(pool), rules: loadParcelRules(DEFAULT_CONTENT_DIR), reselect: false } });
  });
  afterEach(async () => { await app.close(); rmSync(dir, { recursive: true, force: true }); });

  const login = (email: string, password: string) => app.inject({ method: 'POST', url: '/v1/auth/email/login', payload: { email, password } });
  const bearer = (token: string) => ({ authorization: `Bearer ${token}` });
  const io = (over: Partial<InviteCliIo> = {}): InviteCliIo & { out: string[]; err: string[] } => {
    const out: string[] = [], err: string[] = [];
    return { pool, env: { INVITE_EMAIL_DOMAIN: DOMAIN }, cwd: dir, stdoutIsTTY: false,
      stdout: t => { out.push(t); }, stderr: t => { err.push(t); }, now: () => clock, out, err, ...over };
  };

  it('signs in with a generated invite, claims a parcel and saves it; a guest still cannot claim', async () => {
    const [ada, bob] = await createInvites(pool, { count: 2, domain: DOMAIN, batch: 'wave-1' }, clock);
    expect(ada.email).toMatch(new RegExp(`^df-[a-hjkmnp-z2-9]{8}@${DOMAIN.replace(/\./g, '\\.')}$`));
    expect(ada.email).not.toBe(bob.email);
    const stored = await pool.query('SELECT password_hash, email_verified FROM users WHERE email = $1', [ada.email]);
    expect(stored.rows[0].email_verified).toBe(true);
    expect(stored.rows[0].password_hash).toMatch(/^scrypt\$/);
    expect(stored.rows[0].password_hash).not.toContain(ada.password);

    const session = await login(ada.email, ada.password);
    expect(session.statusCode).toBe(200);
    const token = session.json().token as string;
    const claim = await app.inject({ method: 'POST', url: '/v1/parcels/claim', headers: bearer(token),
      payload: { dataset_version: DATASET, parcel_id: 'p-3512001', center: [-122.4194, 37.7749] } });
    expect(claim.statusCode).toBe(201);
    const enter = await app.inject({ method: 'POST', url: '/v1/parcels/mine/enter', headers: bearer(token) });
    expect(enter.json().granted).toBe(true);
    const saved = await app.inject({ method: 'POST', url: '/v1/parcels/mine/commands', headers: bearer(token),
      payload: { base_version: enter.json().parcel.farm_version, commands: [{ type: 'place_house', x: 9, y: 9 }, { type: 'till', cell: '1,1' }] } });
    expect(saved.statusCode).toBe(200);
    const mine = await app.inject({ method: 'GET', url: '/v1/parcels/mine', headers: bearer((await login(ada.email, ada.password)).json().token) });
    expect(mine.json().parcel.farm.tilled).toEqual(['1,1']);

    const guest = (await app.inject({ method: 'POST', url: '/v1/auth/anonymous', payload: { install_key: 'a'.repeat(32) } })).json().token;
    const refused = await app.inject({ method: 'POST', url: '/v1/parcels/claim', headers: bearer(guest),
      payload: { dataset_version: DATASET, parcel_id: 'p-3512002', center: [-122.418, 37.7752] } });
    expect(refused.statusCode).toBe(401);
    expect(refused.json().code).toBe('LOGIN_REQUIRED');

    const listed = await listInvites(pool);
    expect(listed.map(r => [r.email, r.batch, r.has_parcel, r.disabled])).toEqual(
      [[ada.email, 'wave-1', true, false], [bob.email, 'wave-1', false, false]].sort((a, b) => String(a[0]).localeCompare(String(b[0]))));
    expect(await listInvites(pool, 'wave-2')).toEqual([]);
  });

  it('resets and disables only invite accounts, revoking their sessions and keeping the parcel', async () => {
    const [ada] = await createInvites(pool, { count: 1, domain: DOMAIN, batch: 'wave-1' }, clock);
    const old = (await login(ada.email, ada.password)).json().token as string;
    const reset = await resetInvite(pool, ada.email.toUpperCase());
    expect(reset).toMatchObject({ email: ada.email, batch: 'wave-1' });
    expect((await app.inject({ method: 'GET', url: '/v1/users/me', headers: bearer(old) })).statusCode).toBe(401);
    expect((await login(ada.email, ada.password)).statusCode).toBe(401);
    expect((await login(ada.email, reset!.password)).statusCode).toBe(200);

    expect(await disableInvite(pool, ada.email)).toBe(true);
    expect((await login(ada.email, reset!.password)).json().code).toBe('INVALID_CREDENTIALS');
    expect((await listInvites(pool))[0].disabled).toBe(true);

    // An ordinary account (not made by the tool) is never touched.
    await pool.query(`INSERT INTO users (id, email, email_verified, password_hash, created_at, last_seen_at)
      VALUES ('00000000-0000-4000-8000-000000000001', 'plain@example.org', true, 'scrypt$x', 0, 0)`);
    await pool.query(`INSERT INTO user_identities (provider, provider_uid, user_id, sign_in_provider, created_at)
      VALUES ('email', 'plain@example.org', '00000000-0000-4000-8000-000000000001', 'password', 0)`);
    expect(await resetInvite(pool, 'plain@example.org')).toBeNull();
    expect(await disableInvite(pool, 'plain@example.org')).toBe(false);
    expect((await pool.query("SELECT password_hash FROM users WHERE email = 'plain@example.org'")).rows[0].password_hash).toBe('scrypt$x');
    await expect(createInvites(pool, { count: 0, domain: DOMAIN, batch: 'b' }, clock)).rejects.toThrow(/count/);
    await expect(createInvites(pool, { count: 1, domain: DOMAIN, batch: 'Bad Batch' }, clock)).rejects.toThrow(/batch/);
  });

  it('command line: writes passwords only to a new 0600 file or redirected stdout, never to stderr', async () => {
    const file = path.join(dir, 'wave-1.csv');
    const run = io();
    expect(await runInviteCli(['create', '--count', '3', '--batch', 'wave-1', '--out', file], run)).toBe(0);
    expect(statSync(file).mode & 0o777).toBe(0o600);
    const rows = readFileSync(file, 'utf8').trim().split('\n');
    expect(rows[0]).toBe('email,password,batch');
    expect(rows).toHaveLength(4);
    const [email, password] = rows[1].split(',');
    expect((await login(email, password)).statusCode).toBe(200);
    expect(run.out).toEqual([]);
    expect(run.err.join('')).not.toContain(password);
    // The same file again is refused before anything is created.
    expect(await runInviteCli(['create', '--count', '3', '--batch', 'wave-1', '--out', file], io())).toBe(2);
    expect(await listInvites(pool)).toHaveLength(3);

    const piped = io();
    expect(await runInviteCli(['reset', '--email', email, '--out', '-'], piped)).toBe(0);
    const fresh = piped.out.join('').trim().split('\n')[1].split(',')[1];
    expect((await login(email, fresh)).statusCode).toBe(200);
    expect(piped.err.join('')).not.toContain(fresh);

    const missing = io();
    expect(await runInviteCli(['reset', '--email', `nobody@${DOMAIN}`, '--out', path.join(dir, 'none.csv')], missing)).toBe(1);
    expect(existsSync(path.join(dir, 'none.csv'))).toBe(false);

    const listed = io();
    expect(await runInviteCli(['list', '--batch', 'wave-1'], listed)).toBe(0);
    expect(listed.out.join('')).toContain(email);
    expect(listed.out.join('')).not.toContain(fresh);
    expect(await runInviteCli(['disable', '--email', email], io())).toBe(0);
    expect((await login(email, fresh)).statusCode).toBe(401);
  });
});
