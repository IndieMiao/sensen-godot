import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import pg from 'pg';
import { ensureBag } from '../../src/domain/bag.js';
import type { FarmState } from '../../src/domain/state.js';
import { migrateDomain } from '../../src/db/domain_migration.js';
import { migrate, truncateAll } from '../../src/db/migrate.js';
import { PgStore } from '../../src/db/pg_store.js';
import { DEFAULT_CONTENT_DIR, contentVersion, loadContent } from '../../src/domain/content.js';
import { createInitialState } from '../../src/domain/state.js';
import { DOMAIN_VERSION } from '../../src/domain/version.js';
import { startJourney, reconcileJourney } from '../../src/domain/journey.js';
import { loadBlueprint, plotFor } from '../../src/http/app.js';
import { payloadHash } from '../../src/http/hash.js';
import type { FarmRow } from '../../src/http/dto.js';
import { SH, at } from '../domain/helpers.js';
import { isTillable, type PlotLayout } from '../../src/domain/plot.js';

/** 一小片可开垦格，代替过去写死的固定田畦（SGODOT-128 自由格子种田）。 */
function soilCells(p: PlotLayout, count: number): string[] {
  const out: string[] = [];
  for (let j = 0; j < p.gy && out.length < count; j++)
    for (let i = 0; i < p.gx && out.length < count; i++)
      if (isTillable(p, `${i},${j}`)) out.push(`${i},${j}`);
  return out;
}


const DSN = process.env.TEST_DATABASE_URL;
if (process.env.CI === '1' && !DSN) throw new Error('CI requires an isolated TEST_DATABASE_URL');
if (DSN && !/(?:^|_)(?:test|migration)(?:_|$)/i.test(new URL(DSN).pathname.slice(1)))
  throw new Error('Domain migration tests require a dedicated test or migration database');

const ROOT = path.resolve(DEFAULT_CONTENT_DIR, '../../..');
const CV = contentVersion(DEFAULT_CONTENT_DIR);
const content = loadContent(DEFAULT_CONTENT_DIR);
const sets = plotFor(content);
const cells = soilCells(sets, 12);
function equipmentState(value: unknown): FarmState {
  const state = structuredClone(value) as FarmState;
  ensureBag(state, content);
  return state;
}
const NOW = at('2026-09-04T10:00:00+08:00');

describe.skipIf(!DSN)('Explicit saved-farm migration to the current domain', () => {
  let pool: pg.Pool;
  let store: PgStore;
  beforeAll(async () => {
    pool = new pg.Pool({ connectionString: DSN, max: 8, application_name: 'domain-migration-test' });
    await migrate(pool);
    store = new PgStore({ pool, content, contentVersion: CV, timezone: () => SH,
      plot: sets, now: () => NOW });
  });
  afterAll(async () => { await pool?.end(); });
  beforeEach(async () => { await truncateAll(pool); });

  async function seed(domainVersion = '1'): Promise<FarmRow> {
    const { player } = await store.authAnonymous(`migration-${randomUUID()}`);
    const state = createInitialState({ player_day_id: '2026-09-04', field_condition: 'sunny',
      now: NOW, wallet: 321 });
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

  const envelope = (key: string, type: 'till_cells' = 'till_cells') => ({
    idempotency_key: key, base_version: 0, type, payload: { cell_ids: [cells[0]] },
  });

  async function addHistory(farm: FarmRow) {
    for (const outcome of ['applied', 'rejected']) {
      const env = envelope(`legacy-${outcome}`, outcome === 'applied' ? 'till_cells' : 'till_cells');
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
    const current = await seed(DOMAIN_VERSION);
    await addHistory(old);
    const before = await snapshot();
    const report = await migrateDomain(pool, { plot: sets, contentVersion: CV });
    expect(report).toMatchObject({ mode: 'dry-run', status: 'ready', migrated: 0,
      eligible: [old.id], already_current: [current.id], blocked: [] });
    expect(await snapshot()).toEqual(before);
  });

  it('migrates equipment with domain versions, preserves old results, and is idempotent', async () => {
    const farm = await seed();
    await addHistory(farm);
    const before = await snapshot();
    const first = await migrateDomain(pool, { plot: sets, contentVersion: CV, apply: true });
    expect(first).toMatchObject({ status: 'applied', migrated: 1, eligible: [farm.id] });
    const after = await snapshot();
    expect(after).toEqual({ ...before, farm_snapshots: [], farms: (before.farms as Record<string, unknown>[])
      .map(row => ({ ...row, state: equipmentState(row.state), domain_version: DOMAIN_VERSION })) });
    expect((await store.farmById(farm.id))!.state.chapters[0].step_flags).toEqual({ farm_created: true });
    for (const outcome of ['applied', 'rejected']) {
      const env = envelope(`legacy-${outcome}`, outcome === 'applied' ? 'till_cells' : 'till_cells');
      const retry = await store.applyCommand(farm.owner_id, env, { type: env.type, cell_ids: [cells[0]] });
      expect(retry).toMatchObject({ kind: 'replayed', record: { outcome,
        result: { old_rule_result: outcome, wallet: 321, lesson: 'domain 1 result' } } });
    }
    expect(await snapshot()).toEqual(after);
    expect(await migrateDomain(pool, { plot: sets, contentVersion: CV, apply: true }))
      .toMatchObject({ status: 'applied', migrated: 0, eligible: [], already_current: [farm.id] });
    expect(await snapshot()).toEqual(after);
  });

  it('keeps new commands fail-closed until apply, then logs the current domain', async () => {
    const farm = await seed();
    await addHistory(farm);
    const env = envelope('new-command');
    const cmd = { type: 'till_cells' as const, cell_ids: [cells[0]] };
    expect((await store.applyCommand(farm.owner_id, env, cmd)).kind).toBe('version_mismatch');
    expect((await store.applyCommand(farm.owner_id, envelope('legacy-applied'), cmd)).kind).toBe('replayed');
    await migrateDomain(pool, { plot: sets, contentVersion: CV, apply: true });
    expect((await store.applyCommand(farm.owner_id, env, cmd)).kind).toBe('applied');
    const logged = await pool.query('SELECT domain_version FROM commands WHERE idempotency_key = $1', ['new-command']);
    expect(logged.rows[0].domain_version).toBe(DOMAIN_VERSION);
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
      const report = await migrateDomain(pool, { plot: sets, contentVersion: CV, apply });
      expect(report).toMatchObject({ status: 'refused', migrated: 0, eligible: [eligible.id],
        blocked: [{ farm_id: blocked.id, reasons: [reason] }] });
      expect(await snapshot()).toEqual(before);
    }
  });

  it('refuses to upgrade a map-generated farm because its generator is retired (SGODOT-304)', async () => {
    const eligible = await seed();
    const geographic = await seed('27');
    const current = await seed(DOMAIN_VERSION);
    const terrain = JSON.stringify({ format: 1, layout_id: 'geo', plot: {}, source: {} });
    await pool.query('UPDATE farms SET farm_terrain = $1 WHERE id = ANY($2::uuid[])', [terrain, [geographic.id, current.id]]);
    const before = await snapshot();
    for (const apply of [false, true]) {
      const report = await migrateDomain(pool, { plot: sets, contentVersion: CV, apply });
      expect(report).toMatchObject({ status: 'refused', migrated: 0, eligible: [eligible.id], already_current: [current.id],
        blocked: [{ farm_id: geographic.id, reasons: ['geographic_farm_retired'] }] });
      expect(await snapshot()).toEqual(before);
    }
  });

  it('runs on a database that never got the farm_terrain column (the old root /v1 farm image)', async () => {
    const farm = await seed();
    // A private schema keeps the shared test tables intact.
    const schema = `no_terrain_${randomUUID().replaceAll('-', '')}`;
    await pool.query(`CREATE SCHEMA ${schema}`);
    const scoped = new pg.Pool({ connectionString: DSN, max: 2, options: `-c search_path=${schema}` });
    try {
      await pool.query(`CREATE TABLE ${schema}.farms (LIKE public.farms INCLUDING DEFAULTS INCLUDING CONSTRAINTS)`);
      await pool.query(`CREATE TABLE ${schema}.farm_snapshots (LIKE public.farm_snapshots INCLUDING DEFAULTS)`);
      await pool.query(`INSERT INTO ${schema}.farms SELECT * FROM public.farms`);
      await pool.query(`ALTER TABLE ${schema}.farms DROP COLUMN farm_terrain`);
      expect(await migrateDomain(scoped, { plot: sets, contentVersion: CV }))
        .toMatchObject({ status: 'ready', eligible: [farm.id], blocked: [] });
      expect(await migrateDomain(scoped, { plot: sets, contentVersion: CV, apply: true }))
        .toMatchObject({ status: 'applied', migrated: 1 });
      expect((await scoped.query('SELECT domain_version FROM farms')).rows).toEqual([{ domain_version: DOMAIN_VERSION }]);
    } finally {
      await scoped.end();
      await pool.query(`DROP SCHEMA ${schema} CASCADE`);
    }
  });

  it('also refuses mismatched content on a current-domain farm', async () => {
    await seed();
    const other = await seed(DOMAIN_VERSION);
    await pool.query('UPDATE farms SET content_version = $1 WHERE id = $2', ['old-content', other.id]);
    expect(await migrateDomain(pool, { plot: sets, contentVersion: CV, apply: true }))
      .toMatchObject({ status: 'refused', migrated: 0,
        blocked: [{ farm_id: other.id, reasons: ['content_version_mismatch'] }] });
  });

  it.each(['7', '8', '9', '10', '11', '12', '13'])('upgrades domain %s resource trails without changing their unclaimed state or history', async domain => {
    const farm = await seed(domain);
    await addHistory(farm);
    await pool.query('UPDATE farms SET content_version = $1 WHERE id = $2', ['previous-bundle-content', farm.id]);
    const before = await snapshot();
    const report = await migrateDomain(pool, { plot: sets, contentVersion: CV, previousContentVersion: 'previous-bundle-content', apply: true });
    expect(report).toMatchObject({ status: 'applied', migrated: 1, to_domain_version: DOMAIN_VERSION });
    expect(await snapshot()).toEqual({ ...before, farm_snapshots: [], farms: (before.farms as Record<string, unknown>[])
      .map(row => ({ ...row, state: equipmentState(row.state), domain_version: DOMAIN_VERSION, content_version: CV })) });
  });

  it('continues a migrated farm through a saved display plan and replays each command without duplicate costs', async () => {
    const farm = await seed('11');
    const state = startJourney(farm.state, content);
    state.journey!.facts.push('workbench', 'planter_crafted', 'side_path', 'crafted_lantern',
      'shared_meal', 'project_terrace_0', 'project_terrace_1');
    state.journey!.materials = { stone: 4, fiber: 2 };
    state.journey!.workshop = { sequence: 0, stock: {}, displays: {} };
    const initial = reconcileJourney(state, content);
    await pool.query('UPDATE farms SET state = $1 WHERE id = $2', [initial, farm.id]);
    await addHistory(farm);
    const before = await snapshot();
    expect(await migrateDomain(pool, { plot: sets, contentVersion: CV, apply: true })).toMatchObject({ status: 'applied', migrated: 1 });
    expect(await snapshot()).toEqual({ ...before, farm_snapshots: [], farms: (before.farms as Record<string, unknown>[])
      .map(row => ({ ...row, state: equipmentState(row.state), domain_version: DOMAIN_VERSION })) });

    const plan = { idempotency_key: 'plan-fountain', base_version: 0, type: 'plan_journey_display' as const,
      payload: { project: 'terrace', slot: 2, item: 'fountain', sequence: 0 } };
    expect(await store.applyCommand(farm.owner_id, plan, { type: 'plan_journey_display', ...plan.payload }))
      .toMatchObject({ kind: 'applied' });
    const reload = new PgStore({ pool, content, contentVersion: CV, timezone: () => SH, plot: sets, now: () => NOW });
    const planned = (await reload.farmById(farm.id))!;
    expect(planned.version).toBe(1);
    expect(planned.state.journey!.workshop!.planned).toEqual({ project: 'terrace', slot: 2, item: 'fountain' });
    expect(planned.state.journey!.materials).toEqual(initial.journey!.materials);
    expect(planned.state.inventory).toEqual(initial.inventory);
    expect(planned.state.wallet).toBe(initial.wallet);
    const plannedSnapshot = await snapshot();
    expect(await reload.applyCommand(farm.owner_id, plan, { type: 'plan_journey_display', ...plan.payload }))
      .toMatchObject({ kind: 'replayed' });
    expect(await snapshot()).toEqual(plannedSnapshot);

    const craft = { idempotency_key: 'craft-fountain', base_version: 1, type: 'craft_journey_item' as const,
      payload: { item: 'fountain', sequence: 1 } };
    expect(await reload.applyCommand(farm.owner_id, craft, { type: 'craft_journey_item', ...craft.payload }))
      .toMatchObject({ kind: 'applied' });
    const made = (await reload.farmById(farm.id))!;
    expect(made.state.journey!.materials).toEqual({ stone: 0, fiber: 0 });
    expect(made.state.journey!.workshop!.stock.fountain).toBe(1);
    expect(made.state.journey!.workshop!.planned).toEqual(planned.state.journey!.workshop!.planned);
    const craftedSnapshot = await snapshot();
    expect(await reload.applyCommand(farm.owner_id, craft, { type: 'craft_journey_item', ...craft.payload }))
      .toMatchObject({ kind: 'replayed' });
    expect(await snapshot()).toEqual(craftedSnapshot);

    const display = { idempotency_key: 'place-fountain', base_version: 2, type: 'display_journey_item' as const,
      payload: { item: 'fountain', project: 'terrace', slot: 2, sequence: 2 } };
    expect(await reload.applyCommand(farm.owner_id, display, { type: 'display_journey_item', ...display.payload }))
      .toMatchObject({ kind: 'applied' });
    const placed = (await reload.farmById(farm.id))!;
    expect(placed.version).toBe(3);
    expect(placed.state.journey!.workshop).toEqual({ sequence: 3, stock: { ...made.state.journey!.workshop!.stock, fountain: 0 }, displays: { terrace: ['', '', 'fountain'] } });
    const placedSnapshot = await snapshot();
    expect(await reload.applyCommand(farm.owner_id, display, { type: 'display_journey_item', ...display.payload }))
      .toMatchObject({ kind: 'replayed' });
    expect(await snapshot()).toEqual(placedSnapshot);
  });

  it('preserves domain 12 history and a tracked request across store reload and delivery retries', async () => {
    const farm = await seed('12');
    const state = startJourney(farm.state, content);
    state.inventory.produce.L = 2;
    const initial = reconcileJourney(state, content);
    await pool.query('UPDATE farms SET state = $1 WHERE id = $2', [initial, farm.id]);
    await addHistory(farm);
    const before = await snapshot();
    expect(await migrateDomain(pool, { plot: sets, contentVersion: CV, apply: true })).toMatchObject({ status: 'applied', migrated: 1 });
    expect(await snapshot()).toEqual({ ...before, farm_snapshots: [], farms: (before.farms as Record<string, unknown>[])
      .map(row => ({ ...row, state: equipmentState(row.state), domain_version: DOMAIN_VERSION })) });

    const pin = { idempotency_key: 'track-leaves', base_version: 0, type: 'track_journey_opportunity' as const,
      payload: { slot: 'nursery', sequence: 0, tracking: true } };
    expect(await store.applyCommand(farm.owner_id, pin, { type: pin.type, ...pin.payload })).toMatchObject({ kind: 'applied' });
    const reload = new PgStore({ pool, content, contentVersion: CV, timezone: () => SH, plot: sets, now: () => NOW });
    const pinned = (await reload.farmById(farm.id))!;
    expect(pinned.version).toBe(1);
    expect(pinned.state.journey!.tracked_opportunity).toEqual({ slot: 'nursery', sequence: 0 });
    expect(pinned.state.inventory).toEqual(initial.inventory);
    expect(pinned.state.wallet).toBe(initial.wallet);
    const afterPin = await snapshot();
    expect(await reload.applyCommand(farm.owner_id, pin, { type: pin.type, ...pin.payload })).toMatchObject({ kind: 'replayed' });
    expect(await snapshot()).toEqual(afterPin);

    const deliver = { idempotency_key: 'deliver-leaves', base_version: 1, type: 'fulfill_opportunity' as const,
      payload: { slot: 'nursery', sequence: 0 } };
    expect(await reload.applyCommand(farm.owner_id, deliver, { type: deliver.type, ...deliver.payload })).toMatchObject({ kind: 'applied' });
    const done = (await reload.farmById(farm.id))!;
    expect(done.version).toBe(2);
    expect(done.state.journey!.tracked_opportunity).toBeUndefined();
    expect(done.state.journey!.opportunities.nursery.sequence).toBe(1);
    expect(done.state.inventory.produce.L).toBe(0);
    expect(done.state.wallet).toBe(initial.wallet + 18);
    expect(done.state.journey!.contributions!.leaves).toBe(1);
    const afterDelivery = await snapshot();
    expect(await reload.applyCommand(farm.owner_id, deliver, { type: deliver.type, ...deliver.payload })).toMatchObject({ kind: 'replayed' });
    expect(await reload.applyCommand(farm.owner_id, pin, { type: pin.type, ...pin.payload })).toMatchObject({ kind: 'replayed' });
    expect(await snapshot()).toEqual(afterDelivery);
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
      await expect(migrateDomain(pool, { plot: sets, contentVersion: CV, apply: true })).rejects.toThrow('injected migration failure');
      expect(await snapshot()).toEqual(before);
    } finally {
      await pool.query('DROP TRIGGER reject_domain_test ON farms');
      await pool.query('DROP FUNCTION reject_domain_test()');
    }
    expect(await migrateDomain(pool, { plot: sets, contentVersion: CV, apply: true })).toMatchObject({ migrated: 2 });
  });

  it('waits for an existing writer and preserves its committed state before migrating', async () => {
    const farm = await seed();
    const writer = await pool.connect();
    let migration: ReturnType<typeof migrateDomain> | undefined;
    try {
      await writer.query('BEGIN');
      await writer.query('SELECT id FROM farms WHERE id = $1 FOR UPDATE', [farm.id]);
      const pid = (await writer.query('SELECT pg_backend_pid() AS pid')).rows[0].pid as number;
      migration = migrateDomain(pool, { plot: sets, contentVersion: CV, apply: true });
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

  it('blocks a new command until migration commits, then applies it with the current domain', async () => {
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
      migration = migrateDomain(pool, { plot: sets, contentVersion: CV, apply: true });
      const migratorPid = await waitForBlocked(pid);
      command = store.applyCommand(farm.owner_id, envelope('during-migration'),
        { type: 'till_cells', cell_ids: [cells[0]] });
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

  it.each(['2', '3', '4', '5', '6', '8', '20', '21', '22', '23', '24'])('accepts the exact previous content hash for domain %s while preserving state and history', async domain => {
    const farm = await seed(domain);
    await addHistory(farm);
    const previous = contentVersion(DEFAULT_CONTENT_DIR, true);
    await pool.query('UPDATE farms SET content_version = $1 WHERE id = $2', [previous, farm.id]);
    const before = await snapshot();
    expect(await migrateDomain(pool, { plot: sets, contentVersion: CV, previousContentVersion: previous, apply: true }))
      .toMatchObject({ status: 'applied', migrated: 1 });
    expect(await snapshot()).toEqual({ ...before, farm_snapshots: [], farms: (before.farms as Record<string, unknown>[])
      .map(row => ({ ...row, state: equipmentState(row.state), content_version: CV, domain_version: DOMAIN_VERSION })) });
  });
});
