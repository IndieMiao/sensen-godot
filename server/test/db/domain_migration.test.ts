import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import pg from 'pg';
import { migrateDomain } from '../../src/db/domain_migration.js';
import { migrate, truncateAll } from '../../src/db/migrate.js';
import { PgStore } from '../../src/db/pg_store.js';
import { DEFAULT_CONTENT_DIR, contentVersion, loadContent } from '../../src/domain/content.js';
import { createInitialState } from '../../src/domain/state.js';
import { blueprintSets, loadBlueprint } from '../../src/http/app.js';
import { payloadHash } from '../../src/http/hash.js';
import type { FarmRow } from '../../src/http/dto.js';
import { SH, at } from '../domain/helpers.js';

const DSN = process.env.TEST_DATABASE_URL;
if (process.env.CI === '1' && !DSN) throw new Error('CI requires an isolated TEST_DATABASE_URL');
if (DSN && !/(?:^|_)(?:test|migration)(?:_|$)/i.test(new URL(DSN).pathname.slice(1)))
  throw new Error('Domain migration tests require a dedicated test or migration database');

const ROOT = path.resolve(DEFAULT_CONTENT_DIR, '../../..');
const CV = contentVersion(DEFAULT_CONTENT_DIR);
const content = loadContent(DEFAULT_CONTENT_DIR);
const sets = blueprintSets(loadBlueprint(path.join(ROOT, 'assets/blueprints'), 'sh_a', 2)!);
const cells = [...sets.cultivable].filter(id => !sets.reserved.has(id));
const NOW = at('2026-09-04T10:00:00+08:00');

describe.skipIf(!DSN)('Explicit domain 1 -> 2 migration', () => {
  let pool: pg.Pool;
  let store: PgStore;
  beforeAll(async () => {
    pool = new pg.Pool({ connectionString: DSN, max: 8, application_name: 'domain-migration-test' });
    await migrate(pool);
    store = new PgStore({ pool, content, contentVersion: CV, timezone: () => SH,
      blueprint: () => sets, now: () => NOW });
  });
  afterAll(async () => { await pool?.end(); });
  beforeEach(async () => { await truncateAll(pool); });

  async function seed(domainVersion = '1'): Promise<FarmRow> {
    const { player } = await store.authAnonymous(`migration-${randomUUID()}`);
    const state = createInitialState({ player_day_id: '2026-09-04', field_condition: 'sunny',
      now: NOW, wallet: 321, bed_cells: cells, reserved_cells: [...sets.reserved] });
    state.inventory.seeds.R = { bought: 4, bound: 5 };
    state.inventory.produce.R = 9;
    state.xp.first_harvest_crops = ['R'];
    // Historical harvest and seed ownership are not evidence of a second sowing.
    state.chapters[0].step_flags = { farm_created: true };
    for (const resident of Object.values(state.residents)) delete resident.choice_memories;
    const farm: FarmRow = { id: randomUUID(), owner_id: player.id, region_id: 'shanghai',
      layout_patch_id: 'sh_a', blueprint_revision: 2, version: 0,
      location: { lat: 31.22, lng: 121.45 }, location_visible: false, visit_access: 'anyone', state };
    await store.createFarm({ ownerId: player.id, idempotencyKey: 'created', payloadHash: 'original-create',
      regionId: farm.region_id, layoutPatchId: farm.layout_patch_id, blueprintRevision: 2, build: () => farm });
    await pool.query('UPDATE farms SET domain_version = $1 WHERE id = $2', [domainVersion, farm.id]);
    return farm;
  }

  async function snapshot() {
    const result: Record<string, unknown[]> = {};
    for (const table of ['players', 'tokens', 'farms', 'farm_creations', 'commands', 'farm_snapshots'])
      result[table] = (await pool.query(`SELECT to_jsonb(t) AS data FROM ${table} t ORDER BY to_jsonb(t)::text`))
        .rows.map(row => row.data);
    return result;
  }

  const envelope = (key: string, type: 'clear_cells' | 'till_cells' = 'clear_cells') => ({
    idempotency_key: key, base_version: 0, type, payload: { cell_ids: [cells[0]] },
  });

  async function addHistory(farm: FarmRow) {
    for (const outcome of ['applied', 'rejected']) {
      const env = envelope(`legacy-${outcome}`, outcome === 'applied' ? 'clear_cells' : 'till_cells');
      const result = { old_rule_result: outcome, wallet: 321, lesson: 'domain 1 result' };
      await pool.query(`INSERT INTO commands (farm_id,idempotency_key,base_version,type,payload,
        payload_hash,outcome,result,effective_now,content_version,domain_version,applied_at)
        VALUES ($1,$2,0,$3,$4,$5,$6,$7,$8,$9,'1',$8)`,
      [farm.id, env.idempotency_key, env.type, JSON.stringify(env.payload), payloadHash(env),
        outcome, JSON.stringify(result), NOW, CV]);
    }
    await pool.query(`INSERT INTO farm_snapshots (farm_id,snapshot_revision,snapshot_taken_at,body,
      blueprint_revision,content_version,domain_version) VALUES ($1,7,$2,$3,2,$4,'1')`,
    [farm.id, NOW, JSON.stringify({ original: true, wallet: 321 }), CV]);
  }

  async function waitForBlocked(blockerPid: number) {
    const deadline = Date.now() + 3000;
    while (Date.now() < deadline) {
      const blocked = await pool.query(`SELECT pid FROM pg_stat_activity
        WHERE application_name = 'domain-migration-test' AND $1 = ANY(pg_blocking_pids(pid))`, [blockerPid]);
      if (blocked.rowCount) return blocked.rows[0].pid as number;
      await new Promise(resolve => setTimeout(resolve, 10));
    }
    throw new Error('Expected a database writer to wait on the migration lock');
  }

  it('defaults to a read-only report and preserves the complete database', async () => {
    const old = await seed();
    const current = await seed('2');
    await addHistory(old);
    const before = await snapshot();
    const report = await migrateDomain(pool, { contentVersion: CV });
    expect(report).toMatchObject({ mode: 'dry-run', status: 'ready', migrated: 0,
      eligible: [old.id], already_current: [current.id], blocked: [] });
    expect(await snapshot()).toEqual(before);
  });

  it('changes only farm domain versions, preserves old results, and is idempotent', async () => {
    const farm = await seed();
    await addHistory(farm);
    const before = await snapshot();
    const first = await migrateDomain(pool, { contentVersion: CV, apply: true });
    expect(first).toMatchObject({ status: 'applied', migrated: 1, eligible: [farm.id] });
    const after = await snapshot();
    expect(after).toEqual({ ...before, farms: (before.farms as Record<string, unknown>[])
      .map(row => ({ ...row, domain_version: '2' })) });
    expect((await store.farmById(farm.id))!.state.chapters[0].step_flags).toEqual({ farm_created: true });
    for (const outcome of ['applied', 'rejected']) {
      const env = envelope(`legacy-${outcome}`, outcome === 'applied' ? 'clear_cells' : 'till_cells');
      const retry = await store.applyCommand(farm.owner_id, env, { type: env.type, cell_ids: [cells[0]] });
      expect(retry).toMatchObject({ kind: 'replayed', record: { outcome,
        result: { old_rule_result: outcome, wallet: 321, lesson: 'domain 1 result' } } });
    }
    expect(await snapshot()).toEqual(after);
    expect(await migrateDomain(pool, { contentVersion: CV, apply: true }))
      .toMatchObject({ status: 'applied', migrated: 0, eligible: [], already_current: [farm.id] });
    expect(await snapshot()).toEqual(after);
  });

  it('keeps new commands fail-closed until apply, then logs new commands under domain 2', async () => {
    const farm = await seed();
    await addHistory(farm);
    const env = envelope('new-command');
    const cmd = { type: 'clear_cells' as const, cell_ids: [cells[0]] };
    expect((await store.applyCommand(farm.owner_id, env, cmd)).kind).toBe('version_mismatch');
    expect((await store.applyCommand(farm.owner_id, envelope('legacy-applied'), cmd)).kind).toBe('replayed');
    await migrateDomain(pool, { contentVersion: CV, apply: true });
    expect((await store.applyCommand(farm.owner_id, env, cmd)).kind).toBe('applied');
    const logged = await pool.query('SELECT domain_version FROM commands WHERE idempotency_key = $1', ['new-command']);
    expect(logged.rows[0].domain_version).toBe('2');
  });

  it.each([
    ['domain_version', 'future', 'unknown_domain_version'],
    ['state_schema_version', 99, 'state_schema_version_mismatch'],
    ['content_version', 'different-content', 'content_version_mismatch'],
  ])('refuses the entire batch for incompatible %s', async (column, value, reason) => {
    const eligible = await seed();
    const blocked = await seed();
    await pool.query(`UPDATE farms SET ${column} = $1 WHERE id = $2`, [value, blocked.id]);
    const before = await snapshot();
    for (const apply of [false, true]) {
      const report = await migrateDomain(pool, { contentVersion: CV, apply });
      expect(report).toMatchObject({ status: 'refused', migrated: 0, eligible: [eligible.id],
        blocked: [{ farm_id: blocked.id, reasons: [reason] }] });
      expect(await snapshot()).toEqual(before);
    }
  });

  it('also refuses mismatched content on an already-domain-2 farm', async () => {
    await seed();
    const other = await seed('2');
    await pool.query('UPDATE farms SET content_version = $1 WHERE id = $2', ['old-content', other.id]);
    expect(await migrateDomain(pool, { contentVersion: CV, apply: true }))
      .toMatchObject({ status: 'refused', migrated: 0,
        blocked: [{ farm_id: other.id, reasons: ['content_version_mismatch'] }] });
  });

  it('rolls back an update failure and leaves the connection usable for a retry', async () => {
    await seed();
    await seed();
    const before = await snapshot();
    await pool.query(`CREATE FUNCTION reject_domain_test() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN RAISE EXCEPTION 'injected migration failure'; END $$`);
    await pool.query(`CREATE TRIGGER reject_domain_test BEFORE UPDATE OF domain_version ON farms
      FOR EACH ROW EXECUTE FUNCTION reject_domain_test()`);
    try {
      await expect(migrateDomain(pool, { contentVersion: CV, apply: true })).rejects.toThrow('injected migration failure');
      expect(await snapshot()).toEqual(before);
    } finally {
      await pool.query('DROP TRIGGER reject_domain_test ON farms');
      await pool.query('DROP FUNCTION reject_domain_test()');
    }
    expect(await migrateDomain(pool, { contentVersion: CV, apply: true })).toMatchObject({ migrated: 2 });
  });

  it('waits for an existing writer and preserves its committed state before migrating', async () => {
    const farm = await seed();
    const writer = await pool.connect();
    let migration: ReturnType<typeof migrateDomain> | undefined;
    try {
      await writer.query('BEGIN');
      await writer.query('SELECT id FROM farms WHERE id = $1 FOR UPDATE', [farm.id]);
      const pid = (await writer.query('SELECT pg_backend_pid() AS pid')).rows[0].pid as number;
      migration = migrateDomain(pool, { contentVersion: CV, apply: true });
      await waitForBlocked(pid);
      await writer.query(`UPDATE farms SET state = jsonb_set(state, '{wallet}', '456'::jsonb) WHERE id = $1`, [farm.id]);
      await writer.query('COMMIT');
      expect(await migration).toMatchObject({ migrated: 1 });
      expect((await store.farmById(farm.id))!.state.wallet).toBe(456);
    } finally {
      await writer.query('ROLLBACK');
      writer.release();
      if (migration) await Promise.allSettled([migration]);
    }
  });

  it('blocks a new command until migration commits, then applies it with domain 2', async () => {
    const farm = await seed();
    const blocker = await pool.connect();
    let migration: ReturnType<typeof migrateDomain> | undefined;
    let command: ReturnType<PgStore['applyCommand']> | undefined;
    await pool.query(`CREATE FUNCTION hold_domain_test() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN PERFORM pg_advisory_xact_lock(41002); RETURN NEW; END $$`);
    await pool.query(`CREATE TRIGGER hold_domain_test BEFORE UPDATE OF domain_version ON farms
      FOR EACH ROW EXECUTE FUNCTION hold_domain_test()`);
    try {
      await blocker.query('SELECT pg_advisory_lock(41002)');
      const pid = (await blocker.query('SELECT pg_backend_pid() AS pid')).rows[0].pid as number;
      migration = migrateDomain(pool, { contentVersion: CV, apply: true });
      const migratorPid = await waitForBlocked(pid);
      command = store.applyCommand(farm.owner_id, envelope('during-migration'),
        { type: 'clear_cells', cell_ids: [cells[0]] });
      await waitForBlocked(migratorPid);
      await blocker.query('SELECT pg_advisory_unlock(41002)');
      expect(await migration).toMatchObject({ migrated: 1 });
      expect((await command).kind).toBe('applied');
    } finally {
      await blocker.query('SELECT pg_advisory_unlock(41002)');
      blocker.release();
      await Promise.allSettled([migration, command].filter(Boolean));
      await pool.query('DROP TRIGGER hold_domain_test ON farms');
      await pool.query('DROP FUNCTION hold_domain_test()');
    }
  });

  it('CLI requires explicit apply; its default invocation does not mutate farms', async () => {
    const farm = await seed();
    const cli = path.join(ROOT, 'server/tools/migrate_domain.ts');
    const run = (...args: string[]) => JSON.parse(execFileSync(process.execPath,
      ['--import', 'tsx', cli, ...args], { cwd: path.join(ROOT, 'server'), encoding: 'utf8',
        env: { ...process.env, MIGRATION_DATABASE_URL: DSN!, ASSET_ROOT: ROOT } }));
    expect(run()).toMatchObject({ mode: 'dry-run', eligible: [farm.id], migrated: 0 });
    expect((await pool.query('SELECT domain_version FROM farms WHERE id = $1', [farm.id])).rows[0].domain_version).toBe('1');
    expect(run('--apply')).toMatchObject({ mode: 'apply', status: 'applied', migrated: 1 });
  });
});
