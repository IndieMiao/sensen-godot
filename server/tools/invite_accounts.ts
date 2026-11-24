/**
 * 动态农场正式服的邀请账号（C-96）：建号、列出、重置密码、停用。只连 DATABASE_URL，不跑迁移、不读 .env。
 * 用法见 src/accounts/invite_cli.ts 的 INVITE_USAGE 和 server/deploy/dynamicfarm/README.md。
 */
import pg from 'pg';
import { runInviteCli } from '../src/accounts/invite_cli.js';

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  console.error('需要 DATABASE_URL');
  process.exit(2);
}
const pool = new pg.Pool({ connectionString, max: 1, connectionTimeoutMillis: 5000 });
try {
  process.exitCode = await runInviteCli(process.argv.slice(2), {
    pool, env: process.env, cwd: process.cwd(), stdoutIsTTY: Boolean(process.stdout.isTTY),
    stdout: text => { process.stdout.write(text); }, stderr: text => { process.stderr.write(text); }, now: () => Date.now(),
  });
} finally {
  await pool.end();
}
