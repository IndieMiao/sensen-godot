import { readFileSync, writeFileSync } from 'node:fs';
import { parseEnv } from 'node:util';
import { createHash } from 'node:crypto';
import pg from 'pg';
import { migrateDomain } from '../src/db/domain_migration.js';
import { contentVersion, DEFAULT_CONTENT_DIR } from '../src/domain/content.js';

const env = parseEnv(readFileSync(new URL('../.env', import.meta.url), 'utf8'));
const target = 'sensen_farm_journey_physical_v4';
const source = 'sensen_farm_journey_playtest';
const address = new URL(env.TEST_DATABASE_URL);
const admin = new pg.Pool({ connectionString: address.toString(), max: 1 });
try {
  if ((await admin.query('SELECT 1 FROM pg_database WHERE datname = $1', [target])).rowCount)
    throw new Error('The physical test copy already exists; it has not been changed');
  if ((await admin.query('SELECT 1 FROM pg_stat_activity WHERE datname = $1', [source])).rowCount)
    throw new Error('The source playtest database is in use; it has not been changed');
  await admin.query('CREATE DATABASE sensen_farm_journey_physical_v4 WITH TEMPLATE sensen_farm_journey_playtest');
} finally {
  await admin.end();
}

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
  const migration = await migrateDomain(copy, { contentVersion: contentVersion(DEFAULT_CONTENT_DIR),
    previousContentVersion: '8492f383f6f939b9', apply: true });
  const after = await fingerprint(copy);
  const unchanged = await fingerprint(original);
  const report = { source, target, migration, before, after,
    state_and_history_preserved: JSON.stringify(before) === JSON.stringify(after),
    source_matches_copy: JSON.stringify(before) === JSON.stringify(unchanged) };
  writeFileSync(new URL('../../output/journey-physical-v4/database-copy.json', import.meta.url), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ source, target, migrated: migration.migrated, status: migration.status,
    state_and_history_preserved: report.state_and_history_preserved, source_matches_copy: report.source_matches_copy }));
  if (migration.status !== 'applied' || !report.state_and_history_preserved || !report.source_matches_copy) process.exitCode = 1;
} finally {
  await copy.end();
  await original.end();
}
