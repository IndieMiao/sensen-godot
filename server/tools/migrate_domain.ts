/** Run explicitly with MIGRATION_DATABASE_URL; this CLI never loads .env or migrates schema. */
import path from 'node:path';
import { parseArgs } from 'node:util';
import pg from 'pg';
import { migrateDomain } from '../src/db/domain_migration.js';
import { DEFAULT_CONTENT_DIR, contentVersion, loadContent } from '../src/domain/content.js';

async function main(): Promise<void> {
  const { values } = parseArgs({
    options: { apply: { type: 'boolean', default: false }, help: { type: 'boolean', default: false } },
  });
  if (values.help) {
    console.log('Usage: MIGRATION_DATABASE_URL=<dsn> pnpm exec tsx tools/migrate_domain.ts [--apply]');
    console.log('Defaults to dry-run. Uses ASSET_ROOT when set; never loads .env or runs schema migration.');
    return;
  }
  const connectionString = process.env.MIGRATION_DATABASE_URL;
  if (!connectionString) throw new Error('MIGRATION_DATABASE_URL must be explicitly set');
  const contentDir = process.env.ASSET_ROOT
    ? path.join(process.env.ASSET_ROOT, 'assets', 'farm', 'data') : DEFAULT_CONTENT_DIR;
  loadContent(contentDir);
  const currentContentVersion = contentVersion(contentDir);
  const pool = new pg.Pool({ connectionString, max: 1, connectionTimeoutMillis: 5000 });
  try {
    const report = await migrateDomain(pool, { contentVersion: currentContentVersion, apply: values.apply });
    console.log(JSON.stringify(report, null, 2));
    if (report.status === 'refused') process.exitCode = 2;
  } finally {
    await pool.end();
  }
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : 'Domain migration failed');
  process.exitCode = 1;
});
