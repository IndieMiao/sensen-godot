/** Explicit domain upgrade. Preserve save state and historical command results. */
import type pg from 'pg';
import { DOMAIN_VERSION, STATE_SCHEMA_VERSION } from '../domain/version.js';

const FROM_DOMAIN_VERSION = '1,2,3,4,5,6,7,8,9,10,11,12';
const TO_DOMAIN_VERSION = '13';
const SCHEMA_VERSION = 1;
const VERSION_ROWS = `SELECT id AS farm_id, content_version, domain_version, state_schema_version
  FROM farms ORDER BY id`;

interface VersionRow {
  farm_id: string;
  content_version: string;
  domain_version: string;
  state_schema_version: number;
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
}

export interface DomainMigrationOptions {
  contentVersion: string;
  previousContentVersion?: string;
  apply?: boolean;
}

function inspect(rows: VersionRow[], options: DomainMigrationOptions): DomainMigrationReport {
  const report: DomainMigrationReport = {
    mode: options.apply ? 'apply' : 'dry-run', status: 'ready',
    from_domain_version: FROM_DOMAIN_VERSION, to_domain_version: TO_DOMAIN_VERSION,
    content_version: options.contentVersion, state_schema_version: SCHEMA_VERSION,
    eligible: [], already_current: [], blocked: [], migrated: 0,
  };
  for (const row of rows) {
    const reasons: string[] = [];
    const allowedContent = row.domain_version === TO_DOMAIN_VERSION
      ? [options.contentVersion] : [options.contentVersion, options.previousContentVersion];
    if (!allowedContent.includes(row.content_version)) reasons.push('content_version_mismatch');
    if (row.state_schema_version !== SCHEMA_VERSION) reasons.push('state_schema_version_mismatch');
    if (!['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', TO_DOMAIN_VERSION].includes(row.domain_version))
      reasons.push('unknown_domain_version');
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
  if (DOMAIN_VERSION !== TO_DOMAIN_VERSION || STATE_SCHEMA_VERSION !== SCHEMA_VERSION)
    throw new Error('This migration only supports domain 1/2/3/4/5/6/7/8/9/10/11/12 -> 13 with state schema 1');
  if (!options.apply) {
    const rows = await pool.query<VersionRow>(VERSION_ROWS);
    return inspect(rows.rows, options);
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL lock_timeout = '5s'");
    // Block inserts as well as commands while inspecting the whole set; plain reads remain available.
    await client.query('LOCK TABLE farms IN EXCLUSIVE MODE');
    const rows = await client.query<VersionRow>(`${VERSION_ROWS} FOR UPDATE`);
    const report = inspect(rows.rows, options);
    if (report.blocked.length) {
      await client.query('ROLLBACK');
      return report;
    }
    if (report.eligible.length) {
      const updated = await client.query(
        `UPDATE farms SET domain_version = $1, content_version = $6
          WHERE id = ANY($2::uuid[]) AND domain_version = ANY($3::text[])
            AND content_version = ANY($4::text[]) AND state_schema_version = $5`,
        [TO_DOMAIN_VERSION, report.eligible, ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12'],
          [options.contentVersion, options.previousContentVersion].filter(Boolean), SCHEMA_VERSION, options.contentVersion],
      );
      if (updated.rowCount !== report.eligible.length)
        throw new Error('Farm versions changed during domain migration');
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
