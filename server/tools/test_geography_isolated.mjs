import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { parseEnv } from 'node:util';
import pg from 'pg';

const database = 'sensen_farm_geography_test_20260921';
const settings = parseEnv(readFileSync(new URL('../.env', import.meta.url), 'utf8'));
if (!settings.TEST_DATABASE_URL) throw new Error('TEST_DATABASE_URL is required');
const address = new URL(settings.TEST_DATABASE_URL);
const admin = new pg.Pool({ connectionString: address.toString(), max: 1 });
try {
  if (!(await admin.query('SELECT 1 FROM pg_database WHERE datname=$1', [database])).rowCount)
    await admin.query('CREATE DATABASE "sensen_farm_geography_test_20260921"');
} finally { await admin.end(); }
address.pathname = '/' + database;
console.log('Running in isolated database ' + database);
const child = spawn('pnpm', ['test', ...process.argv.slice(2)], { cwd: new URL('..', import.meta.url), stdio: 'inherit',
  env: { ...process.env, TEST_DATABASE_URL: address.toString() } });
child.once('error', error => { console.error(error.message); process.exitCode = 1; });
child.once('exit', code => process.exitCode = code ?? 1);
