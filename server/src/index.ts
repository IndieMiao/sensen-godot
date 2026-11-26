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
import { CityCatalog } from './geography/cities.js';
import { createMmdbIpLocator, type IpLocator } from './geography/ip_locator.js';
import { mailerFromEnv } from './accounts/mailer.js';
import { appleJwksFetcher } from './accounts/apple_token.js';
import { appleRevokerFromEnv } from './accounts/apple_revoke.js';
import { googleIdJwksFetcher } from './accounts/google_token.js';
import { CachedJwks } from './accounts/firebase_token.js';
import { PgParcelStore } from './parcels/pg_store.js';
import { loadParcelRules } from './parcels/rules.js';
import { parcelGuestWritesFromEnv, parcelReselectFromEnv } from './parcels/routes.js';
import { parcelIdleDaysFromEnv, scheduleIdleReclaim } from './parcels/reclaim.js';
import { loadStarterZones, starterZoneSwitchFromEnv } from './parcels/starter_zone.js';
import { signupClosedFromEnv } from './accounts/routes.js';
import { anonymousSignupLimitsFromEnv } from './http/signup_limits.js';
import { accountLimitsFromEnv } from './accounts/limits.js';

const need = (k: string): string => {
  const v = process.env[k];
  if (!v) { console.error(`缺少环境变量 ${k}`); process.exit(1); }
  return v;
};

const signupClosed = signupClosedFromEnv(process.env);
if (signupClosed === null) { console.error('ACCOUNT_SIGNUP 只能是 open 或 closed'); process.exit(1); }
const parcelGuestWrites = parcelGuestWritesFromEnv(process.env);
if (parcelGuestWrites === null) { console.error('PARCEL_GUEST_WRITES 只能是 0 或 1'); process.exit(1); }
const parcelIdleDays = parcelIdleDaysFromEnv(process.env);
if (parcelIdleDays === null) { console.error('PARCEL_IDLE_RECLAIM_DAYS 只能是 0–3650 的整数'); process.exit(1); }
const starterZoneSwitch = starterZoneSwitchFromEnv(process.env);
if (starterZoneSwitch === null) { console.error('PARCEL_STARTER_ZONE 只能是 0 或 1（不设则按配置文件）'); process.exit(1); }
const anonymousSignupLimits = anonymousSignupLimitsFromEnv(process.env);
if ('invalid' in anonymousSignupLimits) { console.error(`${anonymousSignupLimits.invalid} 只能是 1–1000000 的整数`); process.exit(1); }
const accountLimits = accountLimitsFromEnv(process.env);
if ('invalid' in accountLimits) { console.error(`${accountLimits.invalid} 只能是 1–1000000 的整数`); process.exit(1); }

const ROOT = process.env.ASSET_ROOT ?? path.resolve(process.cwd(), '..');
const CONTENT_DIR = path.join(ROOT, 'assets', 'farm', 'data');
const BLUEPRINT_DIR = path.join(ROOT, 'assets', 'blueprints');
// C-130: the starter zone file must parse, or the server does not start (a broken file must not silently open the
// whole city or refuse every claim).
const starterZones = loadStarterZones(CONTENT_DIR, starterZoneSwitch);

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
const cities = CityCatalog.fromRegionsFile(path.join(CONTENT_DIR, 'regions.json'));
let ipLocator: IpLocator | undefined;
if (process.env.IP_CITY_DB) {
  try { ipLocator = await createMmdbIpLocator(process.env.IP_CITY_DB); }
  catch (error) { console.warn(`IP 城市库不可用，选城页不给默认城市：${(error as Error).message}`); }
}

const pool = new pg.Pool({ connectionString: need('DATABASE_URL'), max: 10 });
await migrate(pool);

const store = new PgStore({
  pool, content, contentVersion: cv,
  timezone: id => cities.timezone(id),
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

/** APPLE_BUNDLE_IDS lists the iOS bundle ids allowed as token audience; empty turns Apple sign-in off. */
function appleConfig() {
  const audiences = (process.env.APPLE_BUNDLE_IDS ?? 'app.gensen.maps').split(',').map(v => v.trim()).filter(Boolean);
  if (!audiences.length) return undefined;
  const jwks = new CachedJwks(appleJwksFetcher(), () => Date.now());
  return { audiences, keys: jwks.keys, refreshKeys: jwks.refresh };
}

/** GOOGLE_CLIENT_IDS lists the OAuth Web client ids Android asks tokens for; empty turns Google sign-in off. */
function googleConfig() {
  const audiences = (process.env.GOOGLE_CLIENT_IDS ?? '105022638066-s710gs2tsaikbkhbtvstdino7cq661go.apps.googleusercontent.com')
    .split(',').map(v => v.trim()).filter(Boolean);
  if (!audiences.length) return undefined;
  const jwks = new CachedJwks(googleIdJwksFetcher(), () => Date.now());
  return { audiences, keys: jwks.keys, refreshKeys: jwks.refresh };
}

const parcelStore = new PgParcelStore(pool);
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
  cities, ipLocator,
  mailer: mailerFromEnv(process.env),
  qaEmailDomain: process.env.QA_EMAIL_DOMAIN, qaEmailCode: process.env.QA_EMAIL_CODE,
  apple: appleConfig(),
  appleRevoker: appleRevokerFromEnv(process.env, () => Date.now()),
  google: googleConfig(),
  // Dynamic farm production (C-96) sets ACCOUNT_SIGNUP=closed: invite accounts only, no self sign-up.
  signupClosed,
  // Only a development server may let guests write; production keeps guests read-only.
  guestWrites: process.env.GUEST_WRITES === '1',
  // New anonymous players per hour by network, IPv6 /48 and in total (C-100, C-120); defaults 10 / 50 / 1000.
  anonymousSignupLimits,
  // Login attempts per email+network and per email from unknown networks; verification mail per recipient and in total (C-132).
  accountLimits,
  // Dynamic farm parcels (C-31). "Abandon and pick again" is for the internal test server only: it stays off unless
  // DYNAMIC_FARM_RESELECT=1 is set there; production never sets it.
  // Install-and-play (C-100): PARCEL_GUEST_WRITES=1 lets guests claim, enter and save their own parcel only. Off unless set.
  // Starter zone (C-130): while on, players without a parcel may only claim inside it; PARCEL_STARTER_ZONE=0/1 overrides the file.
  parcels: { store: parcelStore, rules: loadParcelRules(CONTENT_DIR), reselect: parcelReselectFromEnv(process.env), guestWrites: parcelGuestWrites,
    starterZones },
});
// Guests' parcels idle over PARCEL_IDLE_RECLAIM_DAYS (default 30, 0 = never) return to the map (C-100).
const stopReclaim = scheduleIdleReclaim(parcelStore, parcelIdleDays, () => Date.now(), line => console.log(line));
app.addHook('onClose', async () => { stopReclaim(); });

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
console.log(`farm-server listening on ${port} content=${cv} cities=${cities.size} ip_city=${ipLocator ? 'on' : 'off'} guest_writes=${process.env.GUEST_WRITES === '1'} parcel_reselect=${parcelReselectFromEnv(process.env)} parcel_guest_writes=${parcelGuestWrites} parcel_idle_days=${parcelIdleDays} anonymous_signups=${anonymousSignupLimits.perNetwork}/${anonymousSignupLimits.perBlock}/${anonymousSignupLimits.total} starter_zone=${starterZones.enabled ? starterZones.zones.map(z => z.id).join(',') || 'none' : 'off'} signup=${signupClosed ? 'closed' : 'open'}`);
