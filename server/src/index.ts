/** 进程入口：读 env → 迁移 → 起 server。 */
import type { PlotLayout } from './domain/plot.js';
import path from 'node:path';
import pg from 'pg';
import { buildApp, loadBlueprint, plotFor } from './http/app.js';
import { PgStore } from './db/pg_store.js';
import { migrate } from './db/migrate.js';
import { contentVersion, loadContent } from './domain/content.js';
import type { Ctx } from './domain/reducer.js';
import { PRESET_SPECS, buildPresetFarm, presetHmac } from './domain/presets.js';
import { voiceConfig } from './realtime/voice.js';

const need = (k: string): string => {
  const v = process.env[k];
  if (!v) { console.error(`缺少环境变量 ${k}`); process.exit(1); }
  return v;
};

const ROOT = process.env.ASSET_ROOT ?? path.resolve(process.cwd(), '..');
const CONTENT_DIR = path.join(ROOT, 'assets', 'farm', 'data');
const BLUEPRINT_DIR = path.join(ROOT, 'assets', 'blueprints');

const content = loadContent(CONTENT_DIR);
const cv = contentVersion(CONTENT_DIR);

const regions = JSON.parse(
  await import('node:fs').then(fs => fs.readFileSync(path.join(CONTENT_DIR, 'regions.json'), 'utf8')),
) as { regions: { id: string; timezone: string; candidates: { layout_patch_id: string; revision: number }[] }[] };

// 启动时校验全部在架蓝图；任一不过直接退出（spec §5.2），不带病上线。
// 蓝图只负责街道与地图叠加；农场地面属性来自 content.farm_plot。
const shippedBlueprints = new Set<string>();
for (const r of regions.regions)
  for (const c of r.candidates) {
    if (!loadBlueprint(BLUEPRINT_DIR, c.layout_patch_id, c.revision)) {
      console.error(`蓝图校验失败 ${c.layout_patch_id} r${c.revision}`); process.exit(1);
    }
    shippedBlueprints.add(`${c.layout_patch_id}@${c.revision}`);
  }
const plot = plotFor(content);

const pool = new pg.Pool({ connectionString: need('DATABASE_URL'), max: 10 });
await migrate(pool);

const store = new PgStore({
  pool, content, contentVersion: cv,
  timezone: id => regions.regions.find(r => r.id === id)?.timezone ?? 'UTC',
  plot,
  now: () => Date.now(),
});

// 预置访客农场：幂等播种（PRD §8.4）。缺蓝图就跳过那一座并告警，不阻塞启动。
for (const spec of PRESET_SPECS) {
  const tz = regions.regions.find(r => r.id === spec.region)?.timezone;
  if (!shippedBlueprints.has(`${spec.layout}@${spec.revision}`) || !tz) {
    console.warn(`预置农场 ${spec.layout} 缺蓝图或地区，跳过`); continue;
  }
  await store.ensureSystemFarm(presetHmac(spec.id ?? spec.layout), buildPresetFarm(spec, plot, content, tz, Date.now()));
}

const app = await buildApp({
  store, content, contentVersion: cv,
  blueprintDir: BLUEPRINT_DIR, regionsFile: path.join(CONTENT_DIR, 'regions.json'),
  pepper: need('TOKEN_PEPPER'), now: () => Date.now(),
  plot,
  gitSha: process.env.GIT_SHA,
  trustedProxies: (process.env.TRUSTED_PROXIES ?? '').split(',').map(value => value.trim()).filter(Boolean),
  qaPlayerIds: new Set((process.env.QA_PLAYER_IDS ?? '').split(',').filter(Boolean)),
  realtimeEnabled: process.env.REALTIME_ENABLED !== '0',
  voice: voiceConfig(process.env),
});

// Only one room writer may serve this database. HTTP-only replicas set REALTIME_ENABLED=0.
// A lost lock connection closes the gateway instead of allowing two authorities to diverge.
if (process.env.REALTIME_ENABLED !== '0') {
  const lease = await pool.connect();
  const locked = await lease.query('SELECT pg_try_advisory_lock(735920160) AS locked');
  if (!locked.rows[0].locked) {
    lease.release();
    await app.close();
    throw new Error('A realtime owner is already running for this database');
  }
  lease.on('error', () => { void app.close(); });
  app.addHook('onClose', async () => {
    try { await lease.query('SELECT pg_advisory_unlock(735920160)'); } finally { lease.release(); }
  });
}

const port = Number(process.env.PORT ?? 3000);
await app.listen({ port, host: '0.0.0.0' });
console.log(`farm-server listening on ${port} content=${cv}`);
