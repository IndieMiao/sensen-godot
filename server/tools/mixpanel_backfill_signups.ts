/**
 * 把已有注册补发进 Mixpanel（C-203，可选，一次性；不会自动运行）。只连 DATABASE_URL，不跑迁移、不读 .env。
 * 用法：tsx tools/mixpanel_backfill_signups.ts [--since YYYY-MM-DD] [--send]
 *   不加 --send 只数一共会补发多少个账号；加了才发。需要 MIXPANEL_PROJECT_TOKEN、MIXPANEL_API_HOST（与服务端相同）。
 * 重复运行不会重复计数（去重键固定，见 src/analytics/backfill.ts）。发送失败只记日志，可以直接重跑。
 */
import { parseArgs } from 'node:util';
import pg from 'pg';
import { backfillSignups } from '../src/analytics/backfill.js';
import { MixpanelAnalytics, mixpanelConfigFromEnv } from '../src/analytics/mixpanel.js';

const { values } = parseArgs({ args: process.argv.slice(2), strict: true, options: { since: { type: 'string' }, send: { type: 'boolean', default: false } } });
const since = values.since ? Date.parse(values.since + 'T00:00:00Z') : 0;
if (Number.isNaN(since)) { console.error('--since 要写成 YYYY-MM-DD'); process.exit(2); }
const connectionString = process.env.DATABASE_URL;
if (!connectionString) { console.error('需要 DATABASE_URL'); process.exit(2); }
const config = mixpanelConfigFromEnv(process.env);
if (!config || 'invalid' in config) { console.error(config ? config.invalid : '需要 MIXPANEL_PROJECT_TOKEN 和 MIXPANEL_API_HOST'); process.exit(2); }

const pool = new pg.Pool({ connectionString, max: 1, connectionTimeoutMillis: 5000 });
const analytics = new MixpanelAnalytics({ ...config, log: line => console.error(line) });
try {
  const n = await backfillSignups(pool, analytics, { since, send: values.send });
  console.error(values.send ? `已补发 ${n} 个账号的 account_created（失败的批次见上面的日志，重跑不会重复计数）` : `共 ${n} 个账号；加 --send 才发`);
} finally {
  await analytics.close();
  await pool.end();
}
