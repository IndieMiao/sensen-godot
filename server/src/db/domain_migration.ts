/** Explicit domain upgrade. Preserve save state and historical command results. */
import type pg from 'pg';
import { ensureBag } from '../domain/bag.js';
import { loadContent, DEFAULT_CONTENT_DIR, type Content } from '../domain/content.js';
import { DOMAIN_VERSION, STATE_SCHEMA_VERSION } from '../domain/version.js';
import { upgradeFreeFarmState } from '../domain/free_farm_migration.js';
import type { PlotLayout } from '../domain/plot.js';

const FROM_DOMAIN_VERSION = '1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27';
const TO_DOMAIN_VERSION = '28';
const SCHEMA_VERSION = 1;
/** A database whose service never ran the 2026-09-21 schema (the old root /v1 farm image) has no farm_terrain column. */
const TERRAIN_COLUMN = `SELECT 1 FROM information_schema.columns
  WHERE table_schema = current_schema() AND table_name = 'farms' AND column_name = 'farm_terrain'`;
const versionRows = async (db: pg.Pool | pg.PoolClient) => {
  const geographic = (await db.query(TERRAIN_COLUMN)).rowCount ? 'farm_terrain IS NOT NULL' : 'false';
  return `SELECT id AS farm_id, content_version, domain_version, state_schema_version,
    ${geographic} AS geographic FROM farms ORDER BY id`;
};

interface VersionRow {
  farm_id: string;
  content_version: string;
  domain_version: string;
  state_schema_version: number;
  /** Generated from map data; that generator is retired (SGODOT-304), so these rows cannot be upgraded. */
  geographic: boolean;
}

export interface DomainMigrationReport {
  mode: 'dry-run' | 'apply';
  status: 'ready' | 'refused' | 'applied';
  from_domain_version: string;
  to_domain_version: string;
  content_version: string;
  state_schema_version: number;
  eligible: string[];
  already_current: string[];
  blocked: (VersionRow & { reasons: string[] })[];
  migrated: number;
  relocated_cells: number;
  cancelled_farm_casts: number;
}

export interface DomainMigrationOptions {
  plot: PlotLayout;
  content?: Content;
  decorationFootprints?: Record<string, [number, number]>;
  contentVersion: string;
  previousContentVersion?: string;
  apply?: boolean;
}

function inspect(rows: VersionRow[], options: DomainMigrationOptions): DomainMigrationReport {
  const report: DomainMigrationReport = {
    mode: options.apply ? 'apply' : 'dry-run', status: 'ready',
    from_domain_version: FROM_DOMAIN_VERSION, to_domain_version: TO_DOMAIN_VERSION,
    content_version: options.contentVersion, state_schema_version: SCHEMA_VERSION,
    eligible: [], already_current: [], blocked: [], migrated: 0, relocated_cells: 0,
    cancelled_farm_casts: 0,
  };
  for (const row of rows) {
    const reasons: string[] = [];
    const allowedContent = row.domain_version === TO_DOMAIN_VERSION
      ? [options.contentVersion] : [options.contentVersion, options.previousContentVersion];
    if (!allowedContent.includes(row.content_version)) reasons.push('content_version_mismatch');
    if (row.state_schema_version !== SCHEMA_VERSION) reasons.push('state_schema_version_mismatch');
    if (![...FROM_DOMAIN_VERSION.split(','), TO_DOMAIN_VERSION].includes(row.domain_version))
      reasons.push('unknown_domain_version');
    if (row.geographic && row.domain_version !== TO_DOMAIN_VERSION) reasons.push('geographic_farm_retired');
    if (reasons.length) report.blocked.push({ ...row, reasons });
    else if (row.domain_version !== TO_DOMAIN_VERSION) report.eligible.push(row.farm_id);
    else report.already_current.push(row.farm_id);
  }
  if (report.blocked.length) report.status = 'refused';
  return report;
}

export async function migrateDomain(
  pool: pg.Pool, options: DomainMigrationOptions,
): Promise<DomainMigrationReport> {
  if (!options.contentVersion) throw new Error('contentVersion is required');
  if (!options.plot) throw new Error('Target farm layout is required');
  if (DOMAIN_VERSION !== TO_DOMAIN_VERSION || STATE_SCHEMA_VERSION !== SCHEMA_VERSION)
    throw new Error('This migration only supports domain 1..27 -> 28 with state schema 1');
  if (!options.apply) {
    const rows = await pool.query<VersionRow>(await versionRows(pool));
    return inspect(rows.rows, options);
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL lock_timeout = '5s'");
    // Block inserts as well as commands while inspecting the whole set; plain reads remain available.
    await client.query('LOCK TABLE farms IN EXCLUSIVE MODE');
    const rows = await client.query<VersionRow>(`${await versionRows(client)} FOR UPDATE`);
    const report = inspect(rows.rows, options);
    if (report.blocked.length) {
      await client.query('ROLLBACK');
      return report;
    }
    if (report.eligible.length) {
      const equipmentContent = options.content ?? loadContent(DEFAULT_CONTENT_DIR);
      const saves = await client.query('SELECT id, state, domain_version FROM farms WHERE id = ANY($1::uuid[])', [report.eligible]);
      for (const row of saves.rows) {
        // Current crops, inventory, equipment, facilities and coordinates stay put.
        const upgraded = ['22', '23', '24', '25', '26', '27'].includes(row.domain_version) ? structuredClone(row.state)
          : upgradeFreeFarmState(row.state, options.plot, options.decorationFootprints);
        report.relocated_cells += Object.keys(upgraded.cells).filter(id => !Object.hasOwn(row.state.cells, id)).length;
        if (!['25', '26', '27'].includes(row.domain_version)) ensureBag(upgraded, equipmentContent);
        if (upgraded.fishing?.active?.site === 'farm_pond') {
          upgraded.fishing.last = { sequence: upgraded.fishing.sequence, outcome: 'cancelled' };
          upgraded.fishing.active = null;
          report.cancelled_farm_casts++;
        }
        if (JSON.stringify(upgraded) !== JSON.stringify(row.state))
          await client.query('UPDATE farms SET state = $2 WHERE id = $1', [row.id, JSON.stringify(upgraded)]);
      }
      const updated = await client.query(
        `UPDATE farms SET domain_version = $1, content_version = $6
          WHERE id = ANY($2::uuid[]) AND domain_version = ANY($3::text[])
            AND content_version = ANY($4::text[]) AND state_schema_version = $5`,
        [TO_DOMAIN_VERSION, report.eligible, FROM_DOMAIN_VERSION.split(','),
          [options.contentVersion, options.previousContentVersion].filter(Boolean), SCHEMA_VERSION, options.contentVersion],
      );
      if (updated.rowCount !== report.eligible.length)
        throw new Error('Farm versions changed during domain migration');
      // Visitor caches must not keep pre-upgrade cells; they are rebuilt from the upgraded saves.
      // These are derived snapshots, not command/creation history.
      await client.query('DELETE FROM farm_snapshots WHERE farm_id = ANY($1::uuid[])', [report.eligible]);
      report.migrated = updated.rowCount;
    }
    await client.query('COMMIT');
    report.status = 'applied';
    return report;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}
