/** 进程入口：读 env → 迁移 → 起 server。 */
import path from 'node:path';
import pg from 'pg';
import { buildApp, blueprintSets, loadBlueprint } from './http/app.js';
import { PgStore } from './db/pg_store.js';
import { PgAccountStore } from './db/pg_accounts.js';
import { PgSocialStore } from './db/pg_social.js';
import { socialAccountModule } from './http/social.js';
import { PgFeedStore } from './db/pg_feed.js';
import { feedAccountModule } from './http/feed.js';
import { s3ConfigFromEnv } from './http/uploads.js';
import { LocalUploadStore } from './http/local_uploads.js';
import { PgModerationStore } from './db/pg_moderation.js';
import { OpenAiModerator, moderationAccountModule } from './http/moderation.js';
import { PgImStore } from './db/pg_im.js';
import { imAccountModule } from './http/im.js';
import { SocketHub } from './http/ws_gateway.js';
import { CachedJwks, googleJwksFetcher } from './http/firebase_token.js';
import { migrate } from './db/migrate.js';
import { contentVersion, loadContent } from './domain/content.js';
import type { Ctx } from './domain/reducer.js';
import { PRESET_SPECS, buildPresetFarm, presetHmac } from './domain/presets.js';

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
const bpCache = new Map<string, Ctx['blueprint']>();
for (const r of regions.regions)
  for (const c of r.candidates) {
    const bp = loadBlueprint(BLUEPRINT_DIR, c.layout_patch_id, c.revision);
    if (!bp) { console.error(`蓝图校验失败 ${c.layout_patch_id} r${c.revision}`); process.exit(1); }
    bpCache.set(`${c.layout_patch_id}@${c.revision}`, blueprintSets(bp));
  }

const pool = new pg.Pool({ connectionString: need('DATABASE_URL'), max: 10 });
await migrate(pool);

const store = new PgStore({
  pool, content, contentVersion: cv,
  timezone: id => regions.regions.find(r => r.id === id)?.timezone ?? 'UTC',
  blueprint: (id, rev) => bpCache.get(`${id}@${rev}`)!,
  now: () => Date.now(),
});

// 预置访客农场：幂等播种（PRD §8.4）。缺蓝图就跳过那一座并告警，不阻塞启动。
for (const spec of PRESET_SPECS) {
  const sets = bpCache.get(`${spec.layout}@${spec.revision}`);
  const tz = regions.regions.find(r => r.id === spec.region)?.timezone;
  if (!sets || !tz) { console.warn(`预置农场 ${spec.layout} 缺蓝图或地区，跳过`); continue; }
  await store.ensureSystemFarm(presetHmac(spec.layout), buildPresetFarm(spec, sets, content, tz, Date.now()));
}

// D2 账号服务：没配 FIREBASE_PROJECT_ID 就只告警不退出——农场路由不依赖它。
const firebaseProjectId = process.env.FIREBASE_PROJECT_ID;
if (!firebaseProjectId) console.warn('未设置 FIREBASE_PROJECT_ID：账号路由返回 503');
const jwks = new CachedJwks(googleJwksFetcher(), () => Date.now());
const social = new PgSocialStore(pool);
const feed = new PgFeedStore(pool);
const uploads = s3ConfigFromEnv(process.env);
const moderation = new PgModerationStore(pool);
const im = new PgImStore(pool);
const wsHub = new SocketHub();
const textModerator = process.env.OPENAI_API_KEY ? new OpenAiModerator(process.env.OPENAI_API_KEY) : undefined;
if (!textModerator) console.warn('未设置 OPENAI_API_KEY：文本不做前置过滤，全部进人工复审队列');
const localUploads = !uploads && process.env.UPLOAD_LOCAL_DIR ? new LocalUploadStore(process.env.UPLOAD_LOCAL_DIR) : undefined;
if (!uploads && !localUploads) console.warn('未设置 R2_*，也没设 UPLOAD_LOCAL_DIR：图片直传路由返回 503');
if (localUploads) console.warn(`图片走开发期本地存储 ${localUploads.dir}（不是 R2）`);

const app = await buildApp({
  store, content, contentVersion: cv,
  accounts: new PgAccountStore(pool),
  social, feed, uploads, localUploads, moderation, textModerator, im, wsHub,
  adminUserIds: new Set((process.env.ADMIN_USER_IDS ?? '').split(',').map(x => x.trim()).filter(Boolean)),
  accountModules: [socialAccountModule(social), feedAccountModule(feed), moderationAccountModule(moderation), imAccountModule(im)],
  firebase: firebaseProjectId ? { projectId: firebaseProjectId, keys: jwks.keys, refreshKeys: jwks.refresh } : undefined,
  blueprintDir: BLUEPRINT_DIR, regionsFile: path.join(CONTENT_DIR, 'regions.json'),
  pepper: need('TOKEN_PEPPER'), now: () => Date.now(),
  blueprint: (id, rev) => bpCache.get(`${id}@${rev}`),
  gitSha: process.env.GIT_SHA,
  qaPlayerIds: new Set((process.env.QA_PLAYER_IDS ?? '').split(',').filter(Boolean)),
});

const port = Number(process.env.PORT ?? 3000);
await app.listen({ port, host: '0.0.0.0' });
console.log(`farm-server listening on ${port} content=${cv} accounts=${firebaseProjectId ? 'on' : 'off'}`);
