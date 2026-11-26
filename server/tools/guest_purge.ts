/**
 * 删除游客号（C-146，Q-265）：预演、备份、核对、删除、恢复。只连 DATABASE_URL，不跑迁移、不读 .env。
 * 用法见 src/ops/guest_purge.ts 的 GUEST_PURGE_USAGE 和 server/deploy/dynamicfarm/README.md。
 */
import { readFileSync } from 'node:fs';
import pg from 'pg';
import { runGuestPurgeCli } from '../src/ops/guest_purge.js';

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  console.error('需要 DATABASE_URL');
  process.exit(2);
}
const pool = new pg.Pool({ connectionString, max: 1, connectionTimeoutMillis: 5000 });
try {
  process.exitCode = await runGuestPurgeCli(process.argv.slice(2), {
    pool, cwd: process.cwd(), stdoutIsTTY: Boolean(process.stdout.isTTY),
    stdout: text => { process.stdout.write(text); }, stderr: text => { process.stderr.write(text); },
    readStdin: () => readFileSync(0, 'utf8'), now: () => Date.now(),
  });
} finally {
  await pool.end();
}
