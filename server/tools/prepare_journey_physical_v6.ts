import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { parseEnv } from 'node:util';
import { createHash } from 'node:crypto';
import pg from 'pg';
import { migrateDomain } from '../src/db/domain_migration.js';
import { contentVersion, DEFAULT_CONTENT_DIR } from '../src/domain/content.js';

const env = parseEnv(readFileSync(new URL('../.env', import.meta.url), 'utf8'));
const source = 'sensen_farm_journey_physical_v5';
const target = 'sensen_farm_journey_physical_v6';
const evidence = new URL('../../output/journey-physical-v6/', import.meta.url);
mkdirSync(evidence, { recursive: true });
const address = new URL(env.TEST_DATABASE_URL);
const admin = new pg.Pool({ connectionString: address.toString(), max: 1 });
try {
  if ((await admin.query('SELECT 1 FROM pg_database WHERE datname = $1', [target])).rowCount)
    throw new Error('The v6 copy already exists; it has not been changed');
  if ((await admin.query('SELECT 1 FROM pg_stat_activity WHERE datname = $1', [source])).rowCount)
    throw new Error('Stop the v5 test service before copying its database');
  await admin.query('CREATE DATABASE sensen_farm_journey_physical_v6 WITH TEMPLATE sensen_farm_journey_physical_v5');
} finally { await admin.end(); }

address.pathname = '/' + target;
const copy = new pg.Pool({ connectionString: address.toString(), max: 1 });
address.pathname = '/' + source;
const original = new pg.Pool({ connectionString: address.toString(), max: 1 });
async function fingerprint(pool: pg.Pool) {
  const result: Record<string, { rows: number; sha256: string }> = {};
  for (const table of ['players', 'tokens', 'farms', 'farm_creations', 'commands', 'farm_snapshots']) {
    const columns = table === 'farms' ? "to_jsonb(t) - 'domain_version' - 'content_version'" : 'to_jsonb(t)';
    const rows = (await pool.query(`SELECT ${columns} AS data FROM ${table} t ORDER BY (${columns})::text`)).rows;
    result[table] = { rows: rows.length, sha256: createHash('sha256').update(JSON.stringify(rows)).digest('hex') };
  }
  return result;
}
try {
  const before = await fingerprint(copy);
  const originalBefore = await fingerprint(original);
  if (JSON.stringify(before) !== JSON.stringify(originalBefore)) throw new Error('Copied state differs from original');
  const versions = (await copy.query('SELECT id, version, domain_version, content_version FROM farms ORDER BY id')).rows;
  const options = { contentVersion: contentVersion(DEFAULT_CONTENT_DIR), previousContentVersion: '0e9d1a28c3f4013e' };
  const preview = await migrateDomain(copy, options);
  if (preview.status === 'refused') throw new Error('Migration preview refused; v5 remains unchanged');
  const migration = await migrateDomain(copy, { ...options, apply: true });
  const after = await fingerprint(copy);
  const originalAfter = await fingerprint(original);
  const report = { source, target, versions, migration, before, after,
    state_and_history_preserved: JSON.stringify(before) === JSON.stringify(after),
    source_unchanged: JSON.stringify(originalBefore) === JSON.stringify(originalAfter) };
  writeFileSync(new URL('database-copy.json', evidence), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ target, migrated: migration.migrated, status: migration.status,
    state_and_history_preserved: report.state_and_history_preserved, source_unchanged: report.source_unchanged }));
  if (migration.status !== 'applied' || !report.state_and_history_preserved || !report.source_unchanged)
    throw new Error('Copy verification failed; do not launch the new service');
} finally { await copy.end(); await original.end(); }
