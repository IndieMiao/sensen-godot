import { PondCatalog, POND_CELL_DEG } from '../ponds/catalog.js';
/**
 * Fastify 应用。测试用 `app.inject`，不起真实端口。
 *
 * 错误码映射见 spec §7.4；所有响应带 `server_time`，命令响应里的 `server_time` 就是这次
 * 事务采样的 `effectiveNow`（Codex 三审 O-M1）。
 */
import { loadPlot, type PlotLayout } from '../domain/plot.js';
import Fastify, { type FastifyInstance, type FastifyRequest } from 'fastify';
import rateLimit from '@fastify/rate-limit';
import { parseBlueprint, validate } from 'blueprint-core';
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import type { Command, CommandEnvelope } from '../domain/commands.js';
import { isQaCommand } from '../domain/commands.js';
import { contentVersion, loadContent, type Content } from '../domain/content.js';
import { derive } from '../domain/derive.js';
import { effectiveNow as qaNow } from '../domain/qa.js';
import type { Ctx } from '../domain/reducer.js';
import { DOMAIN_VERSION } from '../domain/version.js';
import { installKeyHmac, isValidInstallKey, safeEqualHex, tokenHash } from './auth.js';
import { networkKey } from './network.js';
import { currentOwnerFarmView, nearbyEntry, snapshotSlot, visitorSnapshot, type FarmRow } from './dto.js';
import { avatarRef } from './avatar_ref.js';
import { initialFarmState } from '../domain/farm_factory.js';
import { ensureBag } from '../domain/bag.js';
import { startJourney } from '../domain/journey.js';
import { payloadHash } from './hash.js';
import type { Store } from './store.js';
import { isFarmLocation, withinPlacementBounds, type FarmLocation, type PlacementBounds } from './farm_location.js';
import { registerOnline } from '../realtime/gateway.js';
import type { VoiceConfig, VoiceMedia } from '../realtime/voice.js';
import { CityCatalog, cityView } from '../geography/cities.js';
import type { IpLocator } from '../geography/ip_locator.js';
import { registerAccounts, type AccountRouteDeps } from '../accounts/routes.js';
import { createLogMailer, type Mailer } from '../accounts/mailer.js';
import type { PlayerRow } from './store.js';
import { registerParcelRoutes, type ParcelRouteDeps } from '../parcels/routes.js';

export interface AppDeps {
  store: Store;
  content: Content;
  contentVersion: string;
  blueprintDir: string;
  regionsFile: string;
  pepper: string;
  now: () => number;
  gitSha?: string;
  /** Only these reverse proxies may supply the client IP used by login rate limits. */
  trustedProxies?: string[];
  /** 哪些 player 建出来的农场带 qa 标记；客户端不能自设。 */
  qaPlayerIds?: Set<string>;
  /** Compatibility switch for the archived G3 QA journey. */
  legacyGameplay?: boolean;
  /** HTTP replicas can disable room ownership and route WSS to a dedicated realtime process. */
  realtimeEnabled?: boolean;
  pondCatalog?: PondCatalog;
  voice?: VoiceConfig;
  voiceMedia?: VoiceMedia;
  /** 覆写农场地面布局；默认读 content.farm_plot 的 default_layout。 */
  plot?: PlotLayout;
  /** Global city directory; defaults to data/cities.tsv plus the curated regions file. */
  cities?: CityCatalog;
  /** Coarse IP geolocation for the city picker's default. Absent means no suggestion. */
  ipLocator?: IpLocator;
  /**
   * Development and legacy QA only: let guest (install_key) tokens create farms and play.
   * Production leaves it off — guests browse, accounts write (2026-09-28 decision 2).
   */
  guestWrites?: boolean;
  /** Verification and reset codes; defaults to logging them. */
  mailer?: Mailer;
  /** Addresses in this domain use qaEmailCode and receive no mail. */
  qaEmailDomain?: string;
  qaEmailCode?: string;
  /** Sign in with Apple verification; absent means the endpoint answers 503. */
  apple?: AccountRouteDeps['apple'];
  appleRevoker?: AccountRouteDeps['appleRevoker'];
  google?: AccountRouteDeps['google'];
  /** Invite-only accounts (C-96): no self sign-up by email, Apple or Google; existing accounts still sign in. */
  signupClosed?: boolean;
  /** New anonymous players per network per hour (C-100); defaults to ANONYMOUS_SIGNUPS_PER_NETWORK_HOUR. */
  anonymousSignupsPerNetworkHour?: number;
  /** Dynamic farm parcel claims and parcel farms (C-31); absent leaves the /v1/parcels routes out. */
  parcels?: Omit<ParcelRouteDeps, 'now'>;
}

interface Regions {
  regions: { id: string; timezone: string; placement_bounds?: PlacementBounds;
    candidates: { layout_patch_id: string; revision: number }[] }[];
}

/**
 * 匿名建号（新安装第一次 /v1/auth/anonymous）每个网络每小时的上限（C-95#2、C-100）。已有玩家再次登录不占这个额度，
 * 只受每个安装每小时 10 次的登录限制。网络的口径见 network.ts：IPv4 按地址，IPv6 按 /64。
 */
export const ANONYMOUS_SIGNUPS_PER_NETWORK_HOUR = 10;

/** Nearby 列表上限：横向列表放不下更多，且越长越像在暴露整个城市的用户名单。 */
export const NEARBY_LIMIT = 20;

export async function buildApp(deps: AppDeps): Promise<FastifyInstance> {
  const app = Fastify({ logger: process.env.HTTP_LOG === '1', trustProxy: deps.trustedProxies?.length ? deps.trustedProxies : false });
  await app.register(rateLimit, { global: false });
  const regions = JSON.parse(readFileSync(deps.regionsFile, 'utf8')) as Regions;
  const cities = deps.cities ?? CityCatalog.fromRegionsFile(deps.regionsFile);
  const seenBlueprints = new Set<string>();
  const ownerView = (farm: FarmRow, now: number, timezone: string) => {
    // 地理蓝图仍须存在（它决定街道与地图叠加），但农场地面属性来自 farm_plot，与它无关。
    const key = `${farm.layout_patch_id}@${farm.blueprint_revision}`;
    if (!seenBlueprints.has(key)) {
      if (!loadBlueprint(deps.blueprintDir, farm.layout_patch_id, farm.blueprint_revision))
        throw Object.assign(new Error('Farm blueprint is unavailable'), {
          statusCode: 422, code: 'BLUEPRINT_MISMATCH',
        });
      seenBlueprints.add(key);
    }
    return currentOwnerFarmView(farm, now, timezone, deps.content, deps.plot ?? plotFor(deps.content));
  };

  const auth = async (req: FastifyRequest): Promise<PlayerRow | null> => {
    const raw = req.headers.authorization;
    if (!raw?.startsWith('Bearer ')) return null;
    return deps.store.playerByToken(tokenHash(raw.slice(7)), deps.now());
  };
  const isGuest = (p: PlayerRow) => !p.user_id && !deps.guestWrites;
  /** Writes need an account; a guest token is authenticated but read-only. */
  const writer = async (req: FastifyRequest, reply: { code: (n: number) => { send: (b: object) => unknown } }): Promise<PlayerRow | null> => {
    const p = await auth(req);
    if (!p) { reply.code(401).send({ code: 'UNAUTHENTICATED' }); return null; }
    if (isGuest(p)) { reply.code(401).send({ code: 'LOGIN_REQUIRED' }); return null; }
    return p;
  };
  /** Realtime (farm rooms, parties, travel, voice) is for accounts only; guests are simply not authenticated there. */
  const accountAuth = async (req: FastifyRequest): Promise<PlayerRow | null> => {
    const p = await auth(req);
    return p && !isGuest(p) ? p : null;
  };

  const ponds = deps.pondCatalog ?? new PondCatalog();
  const online = deps.realtimeEnabled !== false ? registerOnline(app, { ...deps, pondCatalog: ponds, cities }, accountAuth) : null;
  app.get('/v1/ponds', async (req, reply) => {
    const region = (req.query as { region_id?: unknown }).region_id;
    const city = typeof region === 'string' ? cities.get(region) : null;
    if (!city) return reply.code(400).send({ code: 'SCHEMA' });
    return { version: 1, catalog_revision: ponds.revision, available: Boolean(online), locations: ponds.list(city.id) };
  });
  // Map directory by fixed cells ("y:x" = floor(lat / 0.5), floor(lng / 0.5)); the client asks only for
  // cells it has not cached, so panning inside the same cells costs nothing.
  app.get('/v1/ponds/cells', { config: { rateLimit: { max: 240, timeWindow: '1 minute' } } }, async (req, reply) => {
    const raw = (req.query as { cells?: unknown }).cells;
    const keys = typeof raw === 'string' && raw.length <= 400 ? [...new Set(raw.split(','))] : [];
    const parsed = keys.map(k => /^(-?\d{1,3}):(-?\d{1,3})$/.exec(k)).filter(m => m !== null) as RegExpExecArray[];
    if (!keys.length || keys.length > 25 || parsed.length !== keys.length
      || parsed.some(m => Math.abs(Number(m[1])) > 180 || Math.abs(Number(m[2])) > 360)) return reply.code(400).send({ code: 'SCHEMA' });
    reply.header('cache-control', 'public, max-age=300');
    return { version: 2, catalog_revision: ponds.revision, available: Boolean(online), cell_deg: POND_CELL_DEG,
      cells: Object.fromEntries(parsed.map(m => [m[0], ponds.cell(Number(m[1]), Number(m[2]))])) };
  });

  const installationLoginLimit = app.createRateLimit({ max: 10, timeWindow: '1 hour', keyGenerator: req => {
    const key = (req.body as { install_key?: unknown })?.install_key;
    return isValidInstallKey(key) ? 'installation:' + installKeyHmac(key, deps.pepper) : 'invalid:' + req.ip;
  } });

  // Counted before the player exists, so concurrent first sign-ins from one network each use a unit:
  // at most the limit of new players can be created per window, never more.
  const anonymousSignupLimit = app.createRateLimit({ max: deps.anonymousSignupsPerNetworkHour ?? ANONYMOUS_SIGNUPS_PER_NETWORK_HOUR,
    timeWindow: '1 hour', keyGenerator: req => 'network:' + networkKey(req.ip) });

  app.post('/v1/auth/anonymous', {
    // A shared NAT must not prevent 300 returning players from signing in together; new players per network are
    // bounded separately below (C-100).
    config: { rateLimit: { max: 600, timeWindow: '1 hour' } },
  }, async (req, reply) => {
    const quota = await installationLoginLimit(req);
    if (!quota.isAllowed && quota.isExceeded) return reply.code(429).header('retry-after', quota.ttlInSeconds).send({ code: 'RATE_LIMITED' });
    const body = req.body as { install_key?: unknown };
    if (!isValidInstallKey(body?.install_key))
      return reply.code(400).send({ code: 'SCHEMA', message: 'install_key 需为 32 位十六进制' });
    const hmac = installKeyHmac(body.install_key, deps.pepper);
    if (!await deps.store.installationKnown(hmac)) {
      const signups = await anonymousSignupLimit(req);
      if (!signups.isAllowed && signups.isExceeded)
        return reply.code(429).header('retry-after', signups.ttlInSeconds).send({ code: 'RATE_LIMITED' });
    }
    const { player, token } = await deps.store.authAnonymous(hmac);
    return reply.send({ player_id: player.id, token, server_time: deps.now() });
  });

  app.delete('/v1/auth/token', async (req, reply) => {
    const raw = req.headers.authorization;
    if (!raw?.startsWith('Bearer ')) return reply.code(401).send({ code: 'UNAUTHENTICATED' });
    await deps.store.revokeToken(tokenHash(raw.slice(7)));
    return reply.send({ ok: true, server_time: deps.now() });
  });

  app.delete('/v1/auth/tokens', async (req, reply) => {
    const p = await auth(req);
    if (!p) return reply.code(401).send({ code: 'UNAUTHENTICATED' });
    await deps.store.revokeAllTokens(p.id);
    return reply.send({ ok: true, server_time: deps.now() });
  });

  /**
   * 换绑安装密钥。**同时需要有效 token 与当前 install_key**：只要 token 的话，拿到
   * install_key 的人可以先登录再抢先换绑，把真正的用户锁在外面（Codex 三审 V3-C2）。
   * 成功后撤销包含调用者在内的全部会话。
   */
  app.post('/v1/auth/rotate-install-key', async (req, reply) => {
    const p = await auth(req);
    if (!p) return reply.code(401).send({ code: 'UNAUTHENTICATED' });
    const body = req.body as { current_install_key?: unknown; new_install_key?: unknown };
    if (!isValidInstallKey(body?.current_install_key) || !isValidInstallKey(body?.new_install_key))
      return reply.code(400).send({ code: 'SCHEMA' });
    const stored = await deps.store.playerHmac(p.id);
    if (!stored || !safeEqualHex(stored, installKeyHmac(body.current_install_key, deps.pepper)))
      return reply.code(401).send({ code: 'UNAUTHENTICATED', message: 'current_install_key 不匹配' });
    await deps.store.rotateInstallKey(p.id, installKeyHmac(body.new_install_key, deps.pepper));
    await deps.store.revokeAllTokens(p.id);
    return reply.send({ ok: true, server_time: deps.now() });
  });

  /** 只给 id / timezone / candidates——名字、中心点由客户端从本地 regions.json 取（决策②）。 */
  app.get('/v1/regions', async (_req, reply) => reply.send({
    farm_placement_version: 1,
    regions: regions.regions.map(r => ({
      id: r.id, timezone: r.timezone,
      placement_bounds: r.placement_bounds,
      candidates: r.candidates.map(c => ({ layout_patch_id: c.layout_patch_id, revision: c.revision })),
    })),
    server_time: deps.now(),
  }));

  app.post('/v1/farms', async (req, reply) => {
    const p = await writer(req, reply);
    if (!p) return;
    // Geographic farms (generated from map data at the picked point) are retired (SGODOT-304 / 342).
    if ((req.body as { generation_version?: unknown } | undefined)?.generation_version !== undefined)
      return reply.code(410).send({ code: 'FARM_GENERATION_RETIRED' });
    const b = req.body as { idempotency_key?: string; region_id?: string; layout_patch_id?: string;
      blueprint_revision?: number; location?: unknown };
    if (!b?.idempotency_key || !b.region_id || !b.layout_patch_id || !Number.isInteger(b.blueprint_revision))
      return reply.code(400).send({ code: 'SCHEMA' });
    const region = regions.regions.find(r => r.id === b.region_id);
    const cand = region?.candidates.find(c => c.layout_patch_id === b.layout_patch_id);
    if (!region || !cand) return reply.code(400).send({ code: 'SCHEMA', message: '未知候选' });
    if (b.location !== undefined && !isFarmLocation(b.location))
      return reply.code(400).send({ code: 'INVALID_LOCATION', message: '位置需为有效经纬度' });
    if (b.location !== undefined && !withinPlacementBounds(b.location as FarmLocation, region.placement_bounds))
      return reply.code(422).send({ code: 'LOCATION_OUTSIDE_REGION', message: '请选择当前城市范围内的位置' });
    const location = b.location as FarmLocation | undefined;
    // 只接受 regions.json 当前 revision：旧 revision 用的是当时的 canonical 文法（V3-I2）。
    if (cand.revision !== b.blueprint_revision)
      return reply.code(422).send({ code: 'STALE_REVISION', message: `当前 revision 为 ${cand.revision}` });

    const bp = loadBlueprint(deps.blueprintDir, b.layout_patch_id, b.blueprint_revision);
    if (!bp) return reply.code(422).send({ code: 'BLUEPRINT_MISMATCH' });

    const now = deps.now();
    const hash = payloadHash({
      idempotency_key: b.idempotency_key, base_version: 0, type: 'create_farm',
      payload: { region_id: b.region_id, layout_patch_id: b.layout_patch_id, blueprint_revision: b.blueprint_revision,
        ...(location ? { location } : {}) },
    });
    const res = await deps.store.createFarm({
      ownerId: p.id, idempotencyKey: b.idempotency_key, payloadHash: hash,
      regionId: b.region_id, layoutPatchId: b.layout_patch_id, blueprintRevision: b.blueprint_revision,
      build: () => buildFarmRow(p.id, region.id, region.timezone, bp, deps, now, location),
    });
    if (res.kind === 'idempotency_mismatch')
      return reply.code(409).send({ code: 'IDEMPOTENCY_MISMATCH' });
    const effectiveNow = Math.max(qaNow(res.farm.state.qa, now), res.farm.state.clock.last_effective_now);
    return reply.code(res.kind === 'created' ? 201 : 200).send(ownerView(res.farm, effectiveNow, region.timezone));
  });

  app.get('/v1/farms/me', async (req, reply) => {
    const p = await auth(req);
    if (!p) return reply.code(401).send({ code: 'UNAUTHENTICATED' });
    // Guests own nothing: pre-account anonymous farms are not carried over (decision 4).
    const farm = isGuest(p) ? null : await deps.store.farmByOwner(p.id);
    if (!farm) return reply.code(404).send({ code: 'NO_FARM' });
    const tz = cities.timezone(farm.region_id);
    // 读路径同样先 clamp 成 max(采样, last) 再 derive，但**不写回**：时钟回拨时读取结果
    // 不会倒退（Codex 三审 O-I3）。
    // 读路径也要过 QA 变换，否则加速后的农场在 GET 里看到的是没加速的时间。
    const now = Math.max(qaNow(farm.state.qa, deps.now()), farm.state.clock.last_effective_now);
    return reply.send(ownerView(farm, now, tz));
  });

  app.post('/v1/farms/me/commands', async (req, reply) => {
    const p = await writer(req, reply);
    if (!p) return;
    const env = req.body as CommandEnvelope;
    if (!env?.idempotency_key || typeof env.type !== 'string' || !Number.isInteger(env.base_version))
      return reply.code(400).send({ code: 'SCHEMA' });
    if (env.payload !== undefined && (!env.payload || typeof env.payload !== 'object'
      || Array.isArray(env.payload) || Object.hasOwn(env.payload, 'type')))
      return reply.code(400).send({ code: 'SCHEMA' });
    const farm = await deps.store.farmByOwner(p.id);
    if (!farm) return reply.code(404).send({ code: 'NO_FARM' });
    if (isQaCommand(env.type) && !deps.qaPlayerIds?.has(p.id))
      return reply.code(403).send({ code: 'QA_ONLY' });

    const cmd = { ...(env.payload ?? {}), type: env.type } as Command;
    const fishingCommand = ['cast_fishing', 'hook_fishing', 'finish_fishing', 'cancel_fishing'].includes(cmd.type);
    const applyCommand = async () => {
      const result = await deps.store.applyCommand(p.id, env, cmd, () => online?.fishingPresence(p.id) ?? null);
      if (fishingCommand && (result.kind === 'applied' || result.kind === 'replayed' && result.record.outcome === 'applied')) {
        const current = await deps.store.farmByOwner(p.id);
        if (current) online?.syncFishing(current);
      }
      return result;
    };
    const out = fishingCommand && online ? await online.withFishingCommand(applyCommand) : await applyCommand();
    switch (out.kind) {
      case 'applied':
        return reply.send({ outcome: 'applied', ...(out.body as object) });
      case 'replayed': {
        // 命令日志只存 {version, events}；applied 的重放在这里用**当前**农场行重建视图。
        // 回放一份写命令时的旧快照会让客户端的整体覆盖式预测层把状态往回倒。
        const stored = (out.record.result as { version?: number; events?: unknown[] } | null) ?? {};
        if (out.record.outcome !== 'applied')
          return reply.send({ outcome: 'replayed', replayed_outcome: out.record.outcome,
            ...stored, server_time: deps.now() });
        const tz = cities.timezone(out.farm.region_id);
        const now = Math.max(qaNow(out.farm.state.qa, deps.now()), out.farm.state.clock.last_effective_now);
        return reply.send({ outcome: 'replayed', replayed_outcome: 'applied',
          ...currentOwnerFarmView(out.farm, now, tz, deps.content, deps.plot ?? plotFor(deps.content)),
          events: stored.events ?? [], server_time: deps.now() });
      }
      case 'rejected':
        return reply.code(422).send({ outcome: 'rejected', code: out.code, detail: out.detail, server_time: deps.now() });
      case 'idempotency_mismatch':
        return reply.code(409).send({ code: 'IDEMPOTENCY_MISMATCH', server_time: deps.now() });
      case 'version_conflict': {
        const tz = cities.timezone(out.farm.region_id);
        const now = Math.max(qaNow(out.farm.state.qa, deps.now()),
          out.farm.state.clock.last_effective_now);
        return reply.code(409).send({ code: 'VERSION_CONFLICT',
          ...ownerView(out.farm, now, tz) });
      }
      case 'version_mismatch':
        return reply.code(503).send({ code: 'VERSION_MISMATCH', server_time: deps.now() });
      default:
        return reply.code(404).send({ code: 'NO_FARM' });
    }
  });

  // —— G2 访问骨架（spec §7.5 四种组合）——
  app.get('/v1/nearby', async (req, reply) => {
    const p = await auth(req);
    if (!p) return reply.code(401).send({ code: 'UNAUTHENTICATED' });
    const regionId = cities.get(String((req.query as Record<string, unknown>).region_id ?? ''))?.id ?? '';
    if (!regionId) return reply.code(400).send({ code: 'SCHEMA' });
    const { count, farms } = await deps.store.nearby(regionId, p.id, NEARBY_LIMIT);
    return reply.send({
      region_id: regionId, count,
      entries: farms.map(f => nearbyEntry(f, avatarRef(f))),
      server_time: deps.now(),
    });
  });

  app.get('/v1/farms/:farm_id/snapshot', async (req, reply) => {
    const p = await auth(req);
    if (!p) return reply.code(401).send({ code: 'UNAUTHENTICATED' });
    const farm = await deps.store.farmById(String((req.params as Record<string, string>).farm_id));
    // 不存在与不开放都是 404：区分它们就等于告诉访客「这座农场存在但拒绝你」。
    if (!farm || (farm.visit_access !== 'anyone' && !(online && farm.owner_id !== p.id && await online.travel.canVisitFarm(p.id, farm))))
      return reply.code(404).send({ code: 'NOT_FOUND' });
    const tz = cities.timezone(farm.region_id);
    const real = deps.now();
    // 槽按真实墙钟切：快照节流是给访客看的节奏，与主人的 QA 时钟无关。
    const slot = snapshotSlot(real);
    // body 里**不放** taken_at / revision（都传 0）：Store 用 body 判「内容有没有变」，
    // 时间戳进了 body 就每槽都"变了"，revision 会跟着槽号一路涨。
    const snap = await deps.store.snapshotGetOrCreate(farm.id, slot,
      current => visitorSnapshot(current, derive(current.state,
        Math.max(qaNow(current.state.qa, real), current.state.clock.last_effective_now), tz, deps.content), 0, 0, undefined, avatarRef(current)));
    const current = snap.farm;
    if (current.visit_access !== 'anyone' && !(online && current.owner_id !== p.id && await online.travel.canVisitFarm(p.id, current)))
      return reply.code(404).send({ code: 'NOT_FOUND' });
    // Location privacy takes effect immediately, including a cached snapshot from this time slot.
    const body = { ...snap.body } as Record<string, unknown>;
    delete body.region_id;
    delete body.location;
    return reply.send({
      ...body,
      ...(current.location_visible ? { region_id: current.region_id, ...(current.location ? { location: current.location } : {}) } : {}),
      snapshot_revision: snap.revision, snapshot_taken_at: snap.taken_at, server_time: real,
    });
  });

  if (deps.parcels) registerParcelRoutes(app, { ...deps.parcels, now: deps.now }, { auth, writer });

  registerAccounts(app, {
    store: deps.store, pepper: deps.pepper, now: deps.now, mailer: deps.mailer ?? createLogMailer(),
    qaEmailDomain: deps.qaEmailDomain, qaEmailCode: deps.qaEmailCode, apple: deps.apple, appleRevoker: deps.appleRevoker, google: deps.google,
    signupClosed: deps.signupClosed,
    closeSessions: async playerId => { online?.closePlayer(playerId); },
    beforeDelete: async playerId => { await online?.forgetPlayer(playerId); },
  }, auth);

  // —— 全球城市（SGODOT-136 B0）：公开目录数据，不要求登录。 ——
  app.get('/v1/cities', { config: { rateLimit: { max: 600, timeWindow: '1 minute' } } }, async (_req, reply) => {
    const counts = await deps.store.cityFarmCounts();
    const seen = new Set<string>();
    const list = [];
    for (const c of cities.curatedCities()) { seen.add(c.id); list.push(cityView(c, counts.get(c.id) ?? 0)); }
    const popular = [...counts.entries()].filter(([id, n]) => n > 0 && !seen.has(id)).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
    for (const [id, n] of popular.slice(0, 50)) { const c = cities.get(id); if (c) list.push(cityView(c, n)); }
    return reply.send({ cities: list, server_time: deps.now() });
  });
  app.get('/v1/cities/search', { config: { rateLimit: { max: 120, timeWindow: '1 minute' } } }, async (req, reply) => {
    const q = (req.query as { q?: unknown }).q;
    if (typeof q !== 'string' || q.length > 64) return reply.code(400).send({ code: 'SCHEMA' });
    return reply.send({ cities: cities.search(q).map(c => cityView(c)), server_time: deps.now() });
  });
  app.get('/v1/cities/suggest', { config: { rateLimit: { max: 60, timeWindow: '1 minute' } } }, async (req, reply) => {
    let city = null;
    try {
      const point = deps.ipLocator ? await deps.ipLocator(req.ip) : null;
      city = point ? cities.resolve(point) : null;
    } catch { city = null; }
    return reply.send({ city: city ? cityView(city) : null, source: city ? 'ip' : 'none', server_time: deps.now() });
  });
  app.post('/v1/cities/resolve', { config: { rateLimit: { max: 120, timeWindow: '1 minute' } } }, async (req, reply) => {
    const body = req.body as { location?: unknown } | undefined;
    if (!isFarmLocation(body?.location)) return reply.code(400).send({ code: 'INVALID_LOCATION' });
    const city = cities.resolve(body.location);
    if (!city) return reply.code(404).send({ code: 'NO_CITY', server_time: deps.now() });
    return reply.send({ city: cityView(city), server_time: deps.now() });
  });
  app.get('/v1/cities/:city_id', async (req, reply) => {
    const city = cities.get(String((req.params as Record<string, string>).city_id));
    if (!city) return reply.code(404).send({ code: 'NOT_FOUND', server_time: deps.now() });
    const count = (await deps.store.cityFarmCounts()).get(city.id) ?? 0;
    return reply.send({ city: cityView(city, count), server_time: deps.now() });
  });

  app.get('/v1/healthz', async (_req, reply) => reply.send({
    ok: true, db: true, git_sha: deps.gitSha ?? 'dev',
    content_version: deps.contentVersion, domain_version: DOMAIN_VERSION,
    server_time: deps.now(),
  }));

  return app;
}


export function loadBlueprint(dir: string, id: string, rev: number) {
  try {
    const file = path.join(dir, id, `r${rev}`, 'farm_blueprint.json');
    const bp = parseBlueprint(JSON.parse(readFileSync(file, 'utf8')));
    // 校验先于 checksum：checksum 只证明没被改过，不证明合法。
    if (validate(bp).length > 0) return null;
    return bp;
  } catch {
    return null;
  }
}

function buildFarmRow(
  ownerId: string, regionId: string, timezone: string,
  bp: ReturnType<typeof parseBlueprint>, deps: AppDeps, now: number,
  location?: FarmLocation,
): FarmRow {
  let state = initialFarmState(deps.content, deps.plot ?? plotFor(deps.content), timezone, now);
  if (!deps.legacyGameplay && !deps.qaPlayerIds?.has(ownerId)) {
    state = startJourney(state, deps.content);
    ensureBag(state, deps.content);
  }
  return {
    id: cryptoRandomId(), owner_id: ownerId, region_id: regionId,
    layout_patch_id: bp.layout_patch_id, blueprint_revision: bp.revision,
    ...(location ? { location } : {}),
    version: 0, location_visible: true, visit_access: 'only_me', state,
  };
}

/** 农场地面来自 farm_plot.json，与地理蓝图无关；后者仍负责街道、地图叠加与选城。 */
export function plotFor(content: Content, layoutId?: string): PlotLayout {
  return loadPlot(content.farm_plot, layoutId);
}

const cryptoRandomId = (): string => randomUUID();

export { contentVersion, loadContent };
