import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { parseEnv } from 'node:util';
import pg from 'pg';

const database = 'sensen_farm_journey_inventory_test_20260914';
const env = parseEnv(readFileSync(new URL('../.env', import.meta.url), 'utf8'));
const address = new URL(env.TEST_DATABASE_URL);
const admin = new pg.Pool({ connectionString: address.toString(), max: 1 });
try {
  if (!(await admin.query('SELECT 1 FROM pg_database WHERE datname = $1', [database])).rowCount)
    await admin.query(`CREATE DATABASE "${database}"`);
} finally {
  await admin.end();
}
address.pathname = '/' + database;
console.log(`Running inventory regression in isolated database ${database}`);
const child = spawn('pnpm', ['test', ...process.argv.slice(2)], {
  cwd: new URL('..', import.meta.url), stdio: 'inherit',
  env: { ...process.env, TEST_DATABASE_URL: address.toString() },
});
child.once('error', error => { console.error(error.message); process.exitCode = 1; });
child.once('exit', code => { process.exitCode = code ?? 1; });
