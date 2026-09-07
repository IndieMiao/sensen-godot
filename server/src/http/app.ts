/**
 * Fastify 应用。测试用 `app.inject`，不起真实端口。
 *
 * 错误码映射见 spec §7.4；所有响应带 `server_time`，命令响应里的 `server_time` 就是这次
 * 事务采样的 `effectiveNow`（Codex 三审 O-M1）。
 */
import Fastify, { type FastifyInstance, type FastifyReply, type FastifyRequest } from 'fastify';
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
import { currentOwnerFarmView, nearbyEntry, snapshotSlot, visitorSnapshot, type FarmRow } from './dto.js';
import { avatarRef } from './avatar_ref.js';
import { initialFarmState } from '../domain/farm_factory.js';
import { payloadHash } from './hash.js';
import type { Store } from './store.js';
import { isFarmLocation, withinPlacementBounds, type FarmLocation, type PlacementBounds } from './farm_location.js';
import { IdTokenError, verifyFirebaseIdToken, type FirebaseIdentity, type KeySource } from './firebase_token.js';
import { appleRevocationFor, userView, type AccountModule, type AccountStore, type UserRow } from './accounts.js';
import { clampLimit, defaultDisplayName, ownProfileView, publicProfileView, userCard, validatePatch,
  type FollowRow, type ProfileRow, type SocialStore } from './social.js';
import { canSeePost, commentView, postView, validateComment, validatePost, type AuthorCard, type FeedStore, type PostRow } from './feed.js';
import { UPLOAD_CONTENT_TYPES, UPLOAD_MAX_BYTES, ownsKey, presignUpload, publicUrl, validateUploadRequest, type S3Config } from './uploads.js';
import type { LocalUploadStore } from './local_uploads.js';
import { ADMIN_ACTIONS, NullModerator, REPORT_AUTO_HIDE, decide, reportView, validateReport,
  type ModerationStore, type TextModerator } from './moderation.js';
import { HISTORY_LIMIT_MAX, SYNC_LIMIT_MAX, conversationView, greetingBlocked, messageView, uniqueIds, validateGroup, validateMessage,
  type ConversationRow, type ImStore, type LiveHub, type PeerCard, type UserEvent, memberView } from './im.js';
import { registerImGateway, type SocketHub } from './ws_gateway.js';

export interface AppDeps {
  store: Store;
  content: Content;
  contentVersion: string;
  blueprintDir: string;
  regionsFile: string;
  pepper: string;
  now: () => number;
  gitSha?: string;
  /** 哪些 player 建出来的农场带 qa 标记；客户端不能自设。 */
  qaPlayerIds?: Set<string>;
  blueprint?: (id: string, revision: number) => Ctx['blueprint'] | undefined;
  /** D2 账号服务。accounts 与 firebase 都给才启用；缺一个账号路由一律 503 ACCOUNTS_NOT_CONFIGURED。 */
  accounts?: AccountStore;
  firebase?: { projectId: string; keys: KeySource; refreshKeys?: KeySource };
  /** 后续模块在这里登记导出与级联删除，见 accounts.ts。 */
  accountModules?: AccountModule[];
  /** D4-a 资料 + 关注；缺省时相关路由 503 SOCIAL_NOT_CONFIGURED。 */
  social?: SocialStore;
  /** D4-b feed；需要 social 判可见性。缺省时相关路由 503 FEED_NOT_CONFIGURED。 */
  feed?: FeedStore;
  /** D4-c 图片直传（R2 / S3 兼容）；缺省时 POST /v1/uploads 503 UPLOADS_NOT_CONFIGURED。 */
  uploads?: S3Config;
  /** 没有 R2 时的开发期本地存储（二选一；两个都给以 R2 为准）。 */
  localUploads?: LocalUploadStore;
  /** D6 举报 / 拉黑 / 封禁 / 复审队列；缺省时相关路由 503 MODERATION_NOT_CONFIGURED。 */
  moderation?: ModerationStore;
  /** D6 文本前置过滤；缺省 = NullModerator（不拦，但全部进人工队列）。 */
  textModerator?: TextModerator;
  /** 能看 /v1/admin/* 的自有 user id。 */
  adminUserIds?: Set<string>;
  /** D3 IM；需要 social 判关系。缺省时相关路由 503 IM_NOT_CONFIGURED。 */
  im?: ImStore;
  /** 在线推送落点；缺省不推，客户端靠 sync 补拉。测试用 RecordingHub。 */
  liveHub?: LiveHub;
  /** 真 WS 网关：给了就注册 /v1/im/ws，并作为 liveHub 的默认值。 */
  wsHub?: SocketHub;
  /** 服务端 ping 间隔（测试缩短）。 */
  wsPingIntervalMs?: number;
}

interface Regions {
  regions: { id: string; timezone: string; placement_bounds?: PlacementBounds;
    candidates: { layout_patch_id: string; revision: number }[] }[];
}

/** Nearby 列表上限：横向列表放不下更多，且越长越像在暴露整个城市的用户名单。 */
export const NEARBY_LIMIT = 20;

export async function buildApp(deps: AppDeps): Promise<FastifyInstance> {
  const app = Fastify({ logger: false });
  // 空 body 的 JSON 请求当 {}：移动端 HTTP 库常带 content-type 却不带 body（PUT /follow 之类），
  // Fastify 默认对此报 FST_ERR_CTP_EMPTY_JSON_BODY（2026-09-07 桌面 QA 实例撞到）。
  app.removeContentTypeParser('application/json');
  app.addContentTypeParser('application/json', { parseAs: 'string' }, (_req, body, done) => {
    const text = typeof body === 'string' ? body : String(body ?? '');
    if (text.trim() === '') { done(null, {}); return; }
    try { done(null, JSON.parse(text)); } catch (e) { done(Object.assign(e as Error, { statusCode: 400 }), undefined); }
  });
  await app.register(rateLimit, { global: false });
  /** 对外地址按请求算：局域网调试时服务端不知道自己的 IP。 */
  const baseUrlOf = (req: FastifyRequest): string => `${req.protocol}://${req.headers.host ?? 'localhost'}`;
  const regions = JSON.parse(readFileSync(deps.regionsFile, 'utf8')) as Regions;
  const blueprintCache = new Map<string, Ctx['blueprint']>();
  const ownerView = (farm: FarmRow, now: number, timezone: string) => {
    const key = `${farm.layout_patch_id}@${farm.blueprint_revision}`;
    let constraints = deps.blueprint?.(farm.layout_patch_id, farm.blueprint_revision)
      ?? blueprintCache.get(key);
    if (!constraints) {
      const bp = loadBlueprint(deps.blueprintDir, farm.layout_patch_id, farm.blueprint_revision);
      if (!bp) throw Object.assign(new Error('Farm blueprint is unavailable'), {
        statusCode: 422, code: 'BLUEPRINT_MISMATCH',
      });
      constraints = blueprintSets(bp);
      blueprintCache.set(key, constraints);
    }
    return currentOwnerFarmView(farm, now, timezone, deps.content, constraints);
  };

  const auth = async (req: FastifyRequest): Promise<{ id: string } | null> => {
    const raw = req.headers.authorization;
    if (!raw?.startsWith('Bearer ')) return null;
    return deps.store.playerByToken(tokenHash(raw.slice(7)), deps.now());
  };

  app.post('/v1/auth/anonymous', {
    config: { rateLimit: { max: 10, timeWindow: '1 hour' } },
  }, async (req, reply) => {
    const body = req.body as { install_key?: unknown };
    if (!isValidInstallKey(body?.install_key))
      return reply.code(400).send({ code: 'SCHEMA', message: 'install_key 需为 32 位十六进制' });
    const { player, token } = await deps.store.authAnonymous(installKeyHmac(body.install_key, deps.pepper));
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
    const p = await auth(req);
    if (!p) return reply.code(401).send({ code: 'UNAUTHENTICATED' });
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
    const farm = await deps.store.farmByOwner(p.id);
    if (!farm) return reply.code(404).send({ code: 'NO_FARM' });
    const tz = timezoneOf(regions, farm.region_id);
    // 读路径同样先 clamp 成 max(采样, last) 再 derive，但**不写回**：时钟回拨时读取结果
    // 不会倒退（Codex 三审 O-I3）。
    // 读路径也要过 QA 变换，否则加速后的农场在 GET 里看到的是没加速的时间。
    const now = Math.max(qaNow(farm.state.qa, deps.now()), farm.state.clock.last_effective_now);
    return reply.send(ownerView(farm, now, tz));
  });

  app.post('/v1/farms/me/commands', async (req, reply) => {
    const p = await auth(req);
    if (!p) return reply.code(401).send({ code: 'UNAUTHENTICATED' });
    const env = req.body as CommandEnvelope;
    if (!env?.idempotency_key || typeof env.type !== 'string' || !Number.isInteger(env.base_version))
      return reply.code(400).send({ code: 'SCHEMA' });
    const farm = await deps.store.farmByOwner(p.id);
    if (!farm) return reply.code(404).send({ code: 'NO_FARM' });
    if (isQaCommand(env.type) && !deps.qaPlayerIds?.has(p.id))
      return reply.code(403).send({ code: 'QA_ONLY' });

    const cmd = { type: env.type, ...(env.payload ?? {}) } as Command;
    const out = await deps.store.applyCommand(p.id, env, cmd);
    switch (out.kind) {
      case 'applied':
        return reply.send({ outcome: 'applied', ...(out.body as object) });
      case 'replayed':
        return reply.send({ outcome: 'replayed', replayed_outcome: out.record.outcome,
          ...(out.record.result as object ?? {}), server_time: deps.now() });
      case 'rejected':
        return reply.code(422).send({ outcome: 'rejected', code: out.code, detail: out.detail, server_time: deps.now() });
      case 'idempotency_mismatch':
        return reply.code(409).send({ code: 'IDEMPOTENCY_MISMATCH', server_time: deps.now() });
      case 'version_conflict': {
        const tz = timezoneOf(regions, out.farm.region_id);
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
    const regionId = String((req.query as Record<string, unknown>).region_id ?? '');
    if (!regions.regions.some(r => r.id === regionId)) return reply.code(400).send({ code: 'SCHEMA' });
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
    if (!farm || farm.visit_access !== 'anyone') return reply.code(404).send({ code: 'NOT_FOUND' });
    const tz = timezoneOf(regions, farm.region_id);
    const real = deps.now();
    const now = Math.max(qaNow(farm.state.qa, real), farm.state.clock.last_effective_now);
    // 槽按真实墙钟切：快照节流是给访客看的节奏，与主人的 QA 时钟无关。
    const slot = snapshotSlot(real);
    // body 里**不放** taken_at / revision（都传 0）：Store 用 body 判「内容有没有变」，
    // 时间戳进了 body 就每槽都"变了"，revision 会跟着槽号一路涨。
    const snap = await deps.store.snapshotGetOrCreate(farm.id, slot,
      () => visitorSnapshot(farm, derive(farm.state, now, tz, deps.content), 0, 0, undefined, avatarRef(farm)));
    // Location privacy takes effect immediately, including a cached snapshot from this time slot.
    const body = { ...snap.body } as Record<string, unknown>;
    delete body.region_id;
    delete body.location;
    return reply.send({
      ...body,
      ...(farm.location_visible ? { region_id: farm.region_id, ...(farm.location ? { location: farm.location } : {}) } : {}),
      snapshot_revision: snap.revision, snapshot_taken_at: snap.taken_at, server_time: real,
    });
  });

  // —— D2 账号服务（SGODOT-76）：每个请求都校验 Firebase ID token，不另发会话 token ——
  const accountsReady = (): boolean => Boolean(deps.accounts && deps.firebase);
  const notConfigured = (reply: FastifyReply) =>
    reply.code(503).send({ code: 'ACCOUNTS_NOT_CONFIGURED', server_time: deps.now() });
  const bearer = (req: FastifyRequest): string | undefined => {
    const raw = req.headers.authorization;
    return raw?.startsWith('Bearer ') ? raw.slice(7) : undefined;
  };
  type IdentityResult = { identity: FirebaseIdentity } | { error: string };
  const identityFromToken = async (token: unknown): Promise<IdentityResult> => {
    try {
      return { identity: await verifyFirebaseIdToken(token, {
        projectId: deps.firebase!.projectId, keys: deps.firebase!.keys,
        refreshKeys: deps.firebase!.refreshKeys, now: deps.now,
      }) };
    } catch (e) {
      if (e instanceof IdTokenError) return { error: e.code };
      throw e;
    }
  };
  /** 401 时把校验失败的原因带回去：客户端据此决定是刷新 token 还是重新登录。 */
  const unauthenticated = (reply: FastifyReply, reason: string) =>
    reply.code(401).send({ code: 'UNAUTHENTICATED', reason, server_time: deps.now() });

  /** 删号级联：模块按登记顺序删，任一失败整个失败且用户保留（accounts.ts 的约定）。 */
  const deleteAccount = async (identity: FirebaseIdentity, source: 'app' | 'web') => {
    const store = deps.accounts!;
    const user = await store.userByFirebaseUid(identity.uid);
    if (!user) return { deleted: false as const };
    for (const m of deps.accountModules ?? []) if (m.del) await m.del(user.id);
    const deleted = await store.deleteUser(user.id, {
      user_id: user.id, provider_uid: identity.uid, requested_at: deps.now(), source,
      apple_revocation: appleRevocationFor(identity.signInProvider),
    });
    return { deleted, user_id: user.id };
  };

  app.post('/v1/auth/firebase', {
    config: { rateLimit: { max: 60, timeWindow: '1 hour' } },
  }, async (req, reply) => {
    if (!accountsReady()) return notConfigured(reply);
    const body = req.body as { id_token?: unknown } | undefined;
    const r = await identityFromToken(body?.id_token ?? bearer(req));
    if ('error' in r)
      return reply.code(401).send({ code: 'INVALID_ID_TOKEN', reason: r.error, server_time: deps.now() });
    const { user, created } = await deps.accounts!.signIn(r.identity, deps.now());
    // 资料随账号一起就位：客户端登录后立刻能拿到自己的资料（M1 出口），不用再猜「有没有」。
    if (deps.social) await deps.social.ensureProfile(user.id, defaultDisplayName(r.identity.email, r.identity.uid), deps.now());
    return reply.code(created ? 201 : 200).send({ ...userView(user), created, server_time: deps.now() });
  });

  app.get('/v1/users/me', async (req, reply) => {
    if (!accountsReady()) return notConfigured(reply);
    const r = await identityFromToken(bearer(req));
    if ('error' in r) return unauthenticated(reply, r.error);
    const user = await deps.accounts!.userByFirebaseUid(r.identity.uid);
    if (!user) return reply.code(404).send({ code: 'NO_ACCOUNT', server_time: deps.now() });
    if (deps.moderation && await deps.moderation.isBanned(user.id)) return reply.code(403).send({ code: 'BANNED', server_time: deps.now() });
    return reply.send({ ...userView(user), server_time: deps.now() });
  });

  /** CCPA / GDPR 访问请求：账号 + 身份 + 各模块登记的导出，一份 JSON 附件。 */
  app.get('/v1/users/me/export', async (req, reply) => {
    if (!accountsReady()) return notConfigured(reply);
    const r = await identityFromToken(bearer(req));
    if ('error' in r) return unauthenticated(reply, r.error);
    const user = await deps.accounts!.userByFirebaseUid(r.identity.uid);
    if (!user) return reply.code(404).send({ code: 'NO_ACCOUNT', server_time: deps.now() });
    if (deps.moderation && await deps.moderation.isBanned(user.id)) return reply.code(403).send({ code: 'BANNED', server_time: deps.now() });
    const modules: Record<string, unknown> = {};
    for (const m of deps.accountModules ?? []) if (m.export) modules[m.name] = await m.export(user.id);
    const identities = (await deps.accounts!.identitiesOf(user.id)).map(i => ({
      provider: i.provider, provider_uid: i.provider_uid, sign_in_provider: i.sign_in_provider, created_at: i.created_at,
    }));
    reply.header('content-disposition', `attachment; filename="sensen-account-${user.id}.json"`);
    return reply.send({ exported_at: deps.now(), account: userView(user), identities, modules });
  });

  /** 应用内删号（Apple 5.1.1(v)）。幂等：已删或从未建过账号也返回 200，deleted=false。 */
  app.delete('/v1/users/me', async (req, reply) => {
    if (!accountsReady()) return notConfigured(reply);
    const r = await identityFromToken(bearer(req));
    if ('error' in r) return unauthenticated(reply, r.error);
    try {
      return reply.send({ ok: true, ...(await deleteAccount(r.identity, 'app')), server_time: deps.now() });
    } catch {
      return reply.code(500).send({ code: 'DELETE_FAILED', server_time: deps.now() });
    }
  });

  /**
   * 站外 Web 删号页（SSLAUNCH B4，Google Play 要求可在应用外删号）：网页用 Firebase JS
   * 登录后把 ID token POST 过来。与应用内删号同一条级联，只是墓碑 source 记 web。
   */
  app.post('/v1/account/delete', {
    config: { rateLimit: { max: 10, timeWindow: '1 hour' } },
  }, async (req, reply) => {
    if (!accountsReady()) return notConfigured(reply);
    const body = req.body as { id_token?: unknown } | undefined;
    const r = await identityFromToken(body?.id_token);
    if ('error' in r)
      return reply.code(401).send({ code: 'INVALID_ID_TOKEN', reason: r.error, server_time: deps.now() });
    try {
      return reply.send({ ok: true, ...(await deleteAccount(r.identity, 'web')), server_time: deps.now() });
    } catch {
      return reply.code(500).send({ code: 'DELETE_FAILED', server_time: deps.now() });
    }
  });

  // —— D4-a 资料 + 关注 ——
  type Current = { user: UserRow } | { status: number; body: object };
  const currentUser = async (req: FastifyRequest): Promise<Current> => {
    if (!accountsReady()) return { status: 503, body: { code: 'ACCOUNTS_NOT_CONFIGURED', server_time: deps.now() } };
    const r = await identityFromToken(bearer(req));
    if ('error' in r) return { status: 401, body: { code: 'UNAUTHENTICATED', reason: r.error, server_time: deps.now() } };
    const user = await deps.accounts!.userByFirebaseUid(r.identity.uid);
    if (!user) return { status: 404, body: { code: 'NO_ACCOUNT', server_time: deps.now() } };
    if (deps.moderation && await deps.moderation.isBanned(user.id)) return { status: 403, body: { code: 'BANNED', server_time: deps.now() } };
    return { user };
  };
  const socialGuard = async (req: FastifyRequest, reply: FastifyReply): Promise<UserRow | null> => {
    if (!deps.social) { await reply.code(503).send({ code: 'SOCIAL_NOT_CONFIGURED', server_time: deps.now() }); return null; }
    const c = await currentUser(req);
    if ('user' in c) return c.user;
    await reply.code(c.status).send(c.body);
    return null;
  };
  const blockedEither = async (a: string, b: string): Promise<boolean> =>
    a !== b && Boolean(deps.moderation) && await deps.moderation!.blockedEither(a, b);

  /** 路径里的用户：me / @handle / uuid。 */
  const resolveProfile = async (raw: string, me: UserRow): Promise<ProfileRow | null> => {
    if (raw === 'me') return deps.social!.profile(me.id);
    if (raw.startsWith('@')) return deps.social!.profileByHandle(raw.slice(1).toLowerCase());
    return deps.social!.profile(raw);
  };
  const paramId = (req: FastifyRequest): string => String((req.params as Record<string, string>).id ?? '');
  const cards = async (me: UserRow, rows: FollowRow[], pick: (f: FollowRow) => string) => {
    const ids = rows.map(pick);
    const profiles = await deps.social!.profiles(ids);
    // 每张卡一次 relation 查询：列表最多 50 条，MVP 先不合并。
    return Promise.all(rows.map(async f =>
      userCard(profiles.get(pick(f)), pick(f), await deps.social!.relation(me.id, pick(f)), f.created_at)));
  };

  app.get('/v1/users/me/profile', async (req, reply) => {
    const me = await socialGuard(req, reply); if (!me) return;
    const p = await deps.social!.profile(me.id);
    if (!p) return reply.code(404).send({ code: 'NO_PROFILE', server_time: deps.now() });
    const [counts, unseen] = await Promise.all([deps.social!.counts(me.id), deps.social!.unseenFollowerCount(me.id)]);
    return reply.send({ ...ownProfileView(p, counts, unseen), server_time: deps.now() });
  });

  app.put('/v1/users/me/profile', async (req, reply) => {
    const me = await socialGuard(req, reply); if (!me) return;
    const v = validatePatch(req.body);
    if (!v.ok) return reply.code(400).send({ code: 'SCHEMA', field: v.field, reason: v.reason, server_time: deps.now() });
    const r = await deps.social!.updateProfile(me.id, v.patch, deps.now());
    if (r === null) return reply.code(404).send({ code: 'NO_PROFILE', server_time: deps.now() });
    if (r === 'HANDLE_TAKEN') return reply.code(409).send({ code: 'HANDLE_TAKEN', server_time: deps.now() });
    const [counts, unseen] = await Promise.all([deps.social!.counts(me.id), deps.social!.unseenFollowerCount(me.id)]);
    return reply.send({ ...ownProfileView(r, counts, unseen), server_time: deps.now() });
  });

  app.get('/v1/users/:id/profile', async (req, reply) => {
    const me = await socialGuard(req, reply); if (!me) return;
    const p = await resolveProfile(paramId(req), me);
    if (!p || await blockedEither(me.id, p.user_id)) return reply.code(404).send({ code: 'NOT_FOUND', server_time: deps.now() });
    const self = p.user_id === me.id;
    const [counts, relation] = await Promise.all([deps.social!.counts(p.user_id), deps.social!.relation(me.id, p.user_id)]);
    return reply.send({ ...publicProfileView(p, counts, relation, self), server_time: deps.now() });
  });

  const followTarget = async (req: FastifyRequest, reply: FastifyReply, me: UserRow): Promise<string | null> => {
    const p = await resolveProfile(paramId(req), me);
    if (!p) { await reply.code(404).send({ code: 'NOT_FOUND', server_time: deps.now() }); return null; }
    if (p.user_id === me.id) { await reply.code(400).send({ code: 'SELF_FOLLOW', server_time: deps.now() }); return null; }
    if (await blockedEither(me.id, p.user_id)) { await reply.code(403).send({ code: 'BLOCKED', server_time: deps.now() }); return null; }
    return p.user_id;
  };

  app.put('/v1/users/:id/follow', async (req, reply) => {
    const me = await socialGuard(req, reply); if (!me) return;
    const target = await followTarget(req, reply, me); if (!target) return;
    const r = await deps.social!.follow(me.id, target, deps.now());
    if (r.missing) return reply.code(404).send({ code: 'NOT_FOUND', server_time: deps.now() });
    return reply.send({ ok: true, created: r.created, relation: await deps.social!.relation(me.id, target), server_time: deps.now() });
  });

  app.delete('/v1/users/:id/follow', async (req, reply) => {
    const me = await socialGuard(req, reply); if (!me) return;
    const target = await followTarget(req, reply, me); if (!target) return;
    const r = await deps.social!.unfollow(me.id, target);
    return reply.send({ ok: true, removed: r.removed, relation: await deps.social!.relation(me.id, target), server_time: deps.now() });
  });

  /** 我关注的人：别人看要过隐私开关；粉丝列表永远公开。 */
  app.get('/v1/users/:id/following', async (req, reply) => {
    const me = await socialGuard(req, reply); if (!me) return;
    const p = await resolveProfile(paramId(req), me);
    if (!p) return reply.code(404).send({ code: 'NOT_FOUND', server_time: deps.now() });
    if (p.user_id !== me.id && !p.following_visible)
      return reply.code(403).send({ code: 'FOLLOWING_PRIVATE', server_time: deps.now() });
    const q = req.query as Record<string, unknown>;
    const page = await deps.social!.following(p.user_id, typeof q.cursor === 'string' ? q.cursor : null, clampLimit(q.limit));
    return reply.send({ items: await cards(me, page.items, f => f.followee_id), next_cursor: page.next_cursor, server_time: deps.now() });
  });

  app.get('/v1/users/:id/followers', async (req, reply) => {
    const me = await socialGuard(req, reply); if (!me) return;
    const p = await resolveProfile(paramId(req), me);
    if (!p) return reply.code(404).send({ code: 'NOT_FOUND', server_time: deps.now() });
    const q = req.query as Record<string, unknown>;
    const page = await deps.social!.followers(p.user_id, typeof q.cursor === 'string' ? q.cursor : null, clampLimit(q.limit));
    return reply.send({ items: await cards(me, page.items, f => f.follower_id), next_cursor: page.next_cursor, server_time: deps.now() });
  });

  /** 「新粉丝」页：最近关注我的人，带未读数；读过即清。 */
  app.get('/v1/users/me/new-followers', async (req, reply) => {
    const me = await socialGuard(req, reply); if (!me) return;
    const q = req.query as Record<string, unknown>;
    const unread = await deps.social!.unseenFollowerCount(me.id);
    const page = await deps.social!.followers(me.id, typeof q.cursor === 'string' ? q.cursor : null, clampLimit(q.limit));
    const items = await cards(me, page.items, f => f.follower_id);
    await deps.social!.markFollowersSeen(me.id);
    return reply.send({ items, unread_count: unread, next_cursor: page.next_cursor, server_time: deps.now() });
  });

  // —— D4-b feed：图文动态 + 点赞 + 一级评论。可见性：作者本人或关注了作者的人 ——
  const feedGuard = async (req: FastifyRequest, reply: FastifyReply): Promise<UserRow | null> => {
    if (!deps.feed || !deps.social) { await reply.code(503).send({ code: 'FEED_NOT_CONFIGURED', server_time: deps.now() }); return null; }
    const c = await currentUser(req);
    if ('user' in c) return c.user;
    await reply.code(c.status).send(c.body);
    return null;
  };
  const authorCards = async (ids: string[]): Promise<Map<string, AuthorCard>> => {
    const profiles = await deps.social!.profiles([...new Set(ids)]);
    const out = new Map<string, AuthorCard>();
    for (const id of ids) {
      const p = profiles.get(id);
      out.set(id, { user_id: id, display_name: p?.display_name ?? '', handle: p?.handle ?? null, avatar: p?.avatar ?? null });
    }
    return out;
  };
  const postViews = async (me: UserRow, posts: PostRow[]) => {
    const [cards, liked] = await Promise.all([authorCards(posts.map(p => p.author_id)), deps.feed!.likedBy(posts.map(p => p.id), me.id)]);
    return posts.map(p => postView(p, cards.get(p.author_id)!, liked.has(p.id)));
  };
  /** 取帖并判可见性；不可见与不存在都答 404——区分它们等于告诉人「有这条但不给你看」。 */
  const visiblePost = async (req: FastifyRequest, reply: FastifyReply, me: UserRow, postId: string): Promise<PostRow | null> => {
    const post = await deps.feed!.post(postId);
    if (post && canSeePost(post, me.id, await deps.social!.relation(me.id, post.author_id)) && !(await blockedEither(me.id, post.author_id))) return post;
    await reply.code(404).send({ code: 'NOT_FOUND', server_time: deps.now() });
    return null;
  };
  const pageQuery = (req: FastifyRequest): { cursor: string | null; limit: number } => {
    const q = req.query as Record<string, unknown>;
    return { cursor: typeof q.cursor === 'string' ? q.cursor : null, limit: clampLimit(q.limit) };
  };

  /** 前置过滤：文字过 omni-moderation；带图先进人工队列（Rekognition 等 AWS 开户）。 */
  const moderator = (): TextModerator => deps.textModerator ?? new NullModerator();
  const moderateText = async (text: string) => (text.length === 0 ? { status: 'approved' as const, categories: [] as string[] } : decide(await moderator().check(text)));

  app.post('/v1/posts', async (req, reply) => {
    const me = await feedGuard(req, reply); if (!me) return;
    const v = validatePost(req.body);
    if (!v.ok) return reply.code(400).send({ code: 'SCHEMA', field: v.field, reason: v.reason, server_time: deps.now() });
    // 只能引用自己上传的图：key 必须在本人前缀下（uploads.ts newObjectKey）。
    if (v.images.some(im => !ownsKey(im.key, me.id)))
      return reply.code(400).send({ code: 'SCHEMA', field: 'images', reason: 'NOT_OWNED', server_time: deps.now() });
    const mod = await moderateText(v.text);
    if (mod.status === 'rejected')
      return reply.code(422).send({ code: 'MODERATION_REJECTED', categories: mod.categories, server_time: deps.now() });
    const moderation = v.images.length > 0 && mod.status === 'approved' ? { status: 'pending' as const, categories: [] as string[] } : mod;
    const r = await deps.feed!.createPost({ id: randomUUID(), authorId: me.id, idempotencyKey: v.idempotencyKey, text: v.text, images: v.images, now: deps.now(), moderation });
    const [view] = await postViews(me, [r.post]);
    return reply.code(r.created ? 201 : 200).send({ ...view, created: r.created, server_time: deps.now() });
  });

  /** 时间线 = 我 + 我关注的人的动态。 */
  app.get('/v1/feed', async (req, reply) => {
    const me = await feedGuard(req, reply); if (!me) return;
    const { cursor, limit } = pageQuery(req);
    const exclude = deps.moderation ? await deps.moderation.blockedIdsAround(me.id) : [];
    const page = await deps.feed!.timeline(me.id, cursor, limit, exclude);
    return reply.send({ items: await postViews(me, page.items), next_cursor: page.next_cursor, server_time: deps.now() });
  });

  /** 某人的动态：本人或关注了他的人；否则 403 FOLLOW_REQUIRED（资料本身可见，只是动态要先关注）。 */
  app.get('/v1/users/:id/posts', async (req, reply) => {
    const me = await feedGuard(req, reply); if (!me) return;
    const p = await resolveProfile(paramId(req), me);
    if (!p || await blockedEither(me.id, p.user_id)) return reply.code(404).send({ code: 'NOT_FOUND', server_time: deps.now() });
    if (p.user_id !== me.id && !(await deps.social!.relation(me.id, p.user_id)).following)
      return reply.code(403).send({ code: 'FOLLOW_REQUIRED', server_time: deps.now() });
    const { cursor, limit } = pageQuery(req);
    const page = await deps.feed!.byAuthor(p.user_id, cursor, limit);
    return reply.send({ items: await postViews(me, page.items), next_cursor: page.next_cursor, server_time: deps.now() });
  });

  app.get('/v1/posts/:id', async (req, reply) => {
    const me = await feedGuard(req, reply); if (!me) return;
    const post = await visiblePost(req, reply, me, paramId(req)); if (!post) return;
    const [view] = await postViews(me, [post]);
    return reply.send({ ...view, server_time: deps.now() });
  });

  app.delete('/v1/posts/:id', async (req, reply) => {
    const me = await feedGuard(req, reply); if (!me) return;
    const post = await deps.feed!.post(paramId(req));
    if (!post) return reply.code(404).send({ code: 'NOT_FOUND', server_time: deps.now() });
    if (post.author_id !== me.id) return reply.code(403).send({ code: 'FORBIDDEN', server_time: deps.now() });
    return reply.send({ ok: true, deleted: await deps.feed!.deletePost(post.id, me.id, deps.now()), server_time: deps.now() });
  });

  app.put('/v1/posts/:id/like', async (req, reply) => {
    const me = await feedGuard(req, reply); if (!me) return;
    const post = await visiblePost(req, reply, me, paramId(req)); if (!post) return;
    const r = await deps.feed!.like(post.id, me.id, deps.now());
    const fresh = await deps.feed!.post(post.id);
    return reply.send({ ok: true, liked: true, created: r.created, like_count: fresh?.like_count ?? post.like_count, server_time: deps.now() });
  });

  app.delete('/v1/posts/:id/like', async (req, reply) => {
    const me = await feedGuard(req, reply); if (!me) return;
    const post = await visiblePost(req, reply, me, paramId(req)); if (!post) return;
    const r = await deps.feed!.unlike(post.id, me.id);
    const fresh = await deps.feed!.post(post.id);
    return reply.send({ ok: true, liked: false, removed: r.removed, like_count: fresh?.like_count ?? post.like_count, server_time: deps.now() });
  });

  /** 一级评论，按时间正序。 */
  app.get('/v1/posts/:id/comments', async (req, reply) => {
    const me = await feedGuard(req, reply); if (!me) return;
    const post = await visiblePost(req, reply, me, paramId(req)); if (!post) return;
    const { cursor, limit } = pageQuery(req);
    const page = await deps.feed!.comments(post.id, cursor, limit);
    // 拉黑双向不可见也盖住评论；游标照常前进，少几条不补页。
    const blocked = new Set(deps.moderation ? await deps.moderation.blockedIdsAround(me.id) : []);
    const items = page.items.filter(c => !blocked.has(c.author_id));
    const cards = await authorCards(items.map(c => c.author_id));
    return reply.send({ items: items.map(c => commentView(c, cards.get(c.author_id)!)), next_cursor: page.next_cursor, server_time: deps.now() });
  });

  app.post('/v1/posts/:id/comments', async (req, reply) => {
    const me = await feedGuard(req, reply); if (!me) return;
    const post = await visiblePost(req, reply, me, paramId(req)); if (!post) return;
    const v = validateComment(req.body);
    if (!v.ok) return reply.code(400).send({ code: 'SCHEMA', field: v.field, reason: v.reason, server_time: deps.now() });
    const mod = await moderateText(v.text);
    if (mod.status === 'rejected')
      return reply.code(422).send({ code: 'MODERATION_REJECTED', categories: mod.categories, server_time: deps.now() });
    const c = await deps.feed!.addComment({ id: randomUUID(), postId: post.id, authorId: me.id, text: v.text, now: deps.now(), moderation: mod });
    const cards = await authorCards([me.id]);
    return reply.code(201).send({ ...commentView(c, cards.get(me.id)!), server_time: deps.now() });
  });

  /** 评论作者或帖主可删。 */
  app.delete('/v1/comments/:id', async (req, reply) => {
    const me = await feedGuard(req, reply); if (!me) return;
    const c = await deps.feed!.comment(paramId(req));
    if (!c) return reply.code(404).send({ code: 'NOT_FOUND', server_time: deps.now() });
    const post = await deps.feed!.post(c.post_id);
    if (c.author_id !== me.id && post?.author_id !== me.id) return reply.code(403).send({ code: 'FORBIDDEN', server_time: deps.now() });
    return reply.send({ ok: true, deleted: await deps.feed!.deleteComment(c.id, deps.now()), server_time: deps.now() });
  });

  /** D4-c：要一个预签名 PUT，客户端自己把图放到 R2。返回 key（发帖时引用）与 public_url。 */
  app.post('/v1/uploads', {
    config: { rateLimit: { max: 120, timeWindow: '1 hour' } },
  }, async (req, reply) => {
    const c = await currentUser(req);
    if (!('user' in c)) return reply.code(c.status).send(c.body);
    if (!deps.uploads && !deps.localUploads) return reply.code(503).send({ code: 'UPLOADS_NOT_CONFIGURED', server_time: deps.now() });
    const v = validateUploadRequest(req.body);
    if (!v.ok) return reply.code(400).send({ code: 'SCHEMA', field: v.field, reason: v.reason, server_time: deps.now() });
    if (deps.uploads) return reply.code(201).send({ ...presignUpload(deps.uploads, c.user.id, v, deps.now()), server_time: deps.now() });
    return reply.code(201).send({ ...deps.localUploads!.presign(c.user.id, v, deps.now(), baseUrlOf(req)), server_time: deps.now() });
  });

  // 开发期本地直传：PUT 原始字节（content-type 就是图片类型），GET 读回；R2 模式下 /v1/files 302 到公网地址。
  app.addContentTypeParser([...Object.keys(UPLOAD_CONTENT_TYPES), 'application/octet-stream'], { parseAs: 'buffer', bodyLimit: UPLOAD_MAX_BYTES }, (_req, body, done) => done(null, body));
  app.put('/v1/uploads/local/:token', async (req, reply) => {
    if (!deps.localUploads) return reply.code(404).send({ code: 'NOT_FOUND', server_time: deps.now() });
    const body = Buffer.isBuffer(req.body) ? req.body : Buffer.alloc(0);
    const r = await deps.localUploads.put(String((req.params as Record<string, string>).token ?? ''), body, String(req.headers['content-type'] ?? ''), deps.now());
    if (!r.ok) {
      const status = r.code === 'NOT_FOUND' ? 404 : r.code === 'EXPIRED' ? 410 : r.code === 'SIZE' ? 413 : 415;
      return reply.code(status).send({ code: r.code, server_time: deps.now() });
    }
    return reply.send({ ok: true, key: r.key, server_time: deps.now() });
  });
  /** 图片读取的统一入口：客户端永远请求 <api>/v1/files/<key>，不用知道存在哪。 */
  app.get('/v1/files/*', async (req, reply) => {
    const key = String((req.params as Record<string, string>)['*'] ?? '');
    if (deps.uploads) return reply.redirect(publicUrl(deps.uploads, key), 302);
    if (!deps.localUploads) return reply.code(404).send({ code: 'NOT_FOUND', server_time: deps.now() });
    const f = await deps.localUploads.read(key);
    if (!f) return reply.code(404).send({ code: 'NOT_FOUND', server_time: deps.now() });
    reply.header('cache-control', 'public, max-age=31536000, immutable');
    return reply.type(f.contentType).send(f.bytes);
  });

  // —— D6 / E1：拉黑、举报、封禁、管理队列 ——
  const moderationGuard = async (req: FastifyRequest, reply: FastifyReply): Promise<UserRow | null> => {
    if (!deps.moderation || !deps.social) { await reply.code(503).send({ code: 'MODERATION_NOT_CONFIGURED', server_time: deps.now() }); return null; }
    const c = await currentUser(req);
    if ('user' in c) return c.user;
    await reply.code(c.status).send(c.body);
    return null;
  };

  /** 拉黑：双向不可见 + 两个方向都取关。 */
  app.put('/v1/users/:id/block', async (req, reply) => {
    const me = await moderationGuard(req, reply); if (!me) return;
    const p = await resolveProfile(paramId(req), me);
    if (!p) return reply.code(404).send({ code: 'NOT_FOUND', server_time: deps.now() });
    if (p.user_id === me.id) return reply.code(400).send({ code: 'SELF_BLOCK', server_time: deps.now() });
    const r = await deps.moderation!.block(me.id, p.user_id, deps.now());
    await Promise.all([deps.social!.unfollow(me.id, p.user_id), deps.social!.unfollow(p.user_id, me.id)]);
    return reply.send({ ok: true, created: r.created, server_time: deps.now() });
  });

  app.delete('/v1/users/:id/block', async (req, reply) => {
    const me = await moderationGuard(req, reply); if (!me) return;
    const r = await deps.moderation!.unblock(me.id, paramId(req));
    return reply.send({ ok: true, removed: r.removed, server_time: deps.now() });
  });

  app.get('/v1/users/me/blocks', async (req, reply) => {
    const me = await moderationGuard(req, reply); if (!me) return;
    const rows = await deps.moderation!.blocks(me.id);
    const profiles = await deps.social!.profiles(rows.map(b => b.blocked_id));
    return reply.send({
      items: rows.map(b => ({ user_id: b.blocked_id, display_name: profiles.get(b.blocked_id)?.display_name ?? '',
        handle: profiles.get(b.blocked_id)?.handle ?? null, avatar: profiles.get(b.blocked_id)?.avatar ?? null, blocked_at: b.created_at })),
      server_time: deps.now(),
    });
  });

  /** 举报：目标须存在；同一人同一目标只记一条；不同举报人达到阈值先自动隐藏内容，等人工。 */
  app.post('/v1/reports', {
    config: { rateLimit: { max: 30, timeWindow: '1 hour' } },
  }, async (req, reply) => {
    const me = await moderationGuard(req, reply); if (!me) return;
    const v = validateReport(req.body);
    if (!v.ok) return reply.code(400).send({ code: 'SCHEMA', field: v.field, reason: v.reason, server_time: deps.now() });
    let ownerId: string | null = null;
    if (v.targetType === 'post') ownerId = (await deps.feed?.post(v.targetId))?.author_id ?? null;
    else if (v.targetType === 'comment') ownerId = (await deps.feed?.comment(v.targetId))?.author_id ?? null;
    else if (v.targetType === 'message') {
      // 只有会话成员能举报里面的消息；已撤回的不再受理。
      const m = await deps.im?.message(v.targetId);
      ownerId = m && m.deleted_at === null && (await deps.im!.isMember(m.conversation_id, me.id)) ? m.sender_id : null;
    } else ownerId = (await deps.accounts!.userById(v.targetId))?.id ?? null;
    if (!ownerId) return reply.code(404).send({ code: 'NOT_FOUND', server_time: deps.now() });
    if (ownerId === me.id) return reply.code(400).send({ code: 'SELF_REPORT', server_time: deps.now() });
    const r = await deps.moderation!.addReport({ id: randomUUID(), reporter_id: me.id, target_type: v.targetType, target_id: v.targetId, reason: v.reason, detail: v.detail, created_at: deps.now() });
    let autoHidden = false;
    if (r.created && r.distinctReporters >= REPORT_AUTO_HIDE) {
      if (v.targetType === 'post' && deps.feed) autoHidden = await deps.feed.setPostStatus(v.targetId, 'hidden');
      else if (v.targetType === 'comment' && deps.feed) autoHidden = await deps.feed.setCommentStatus(v.targetId, 'hidden');
      else if (v.targetType === 'message') autoHidden = await retractMessage(v.targetId);
    }
    return reply.code(r.created ? 201 : 200).send({ ...reportView(r.report), created: r.created, auto_hidden: autoHidden, server_time: deps.now() });
  });

  const adminGuard = async (req: FastifyRequest, reply: FastifyReply): Promise<UserRow | null> => {
    const me = await moderationGuard(req, reply); if (!me) return null;
    if (!deps.adminUserIds?.has(me.id)) { await reply.code(403).send({ code: 'FORBIDDEN', server_time: deps.now() }); return null; }
    return me;
  };

  app.get('/v1/admin/reports', async (req, reply) => {
    const me = await adminGuard(req, reply); if (!me) return;
    const rows = await deps.moderation!.openReports(clampLimit((req.query as Record<string, unknown>).limit));
    return reply.send({ items: rows.map(reportView), server_time: deps.now() });
  });

  /** 处置：dismiss 只结单；remove_content 下架并结同目标全部举报；ban_user 封作者（或被举报用户）+ 下架。 */
  app.post('/v1/admin/reports/:id/resolve', async (req, reply) => {
    const me = await adminGuard(req, reply); if (!me) return;
    const action = String((req.body as Record<string, unknown> | undefined)?.action ?? '');
    if (!ADMIN_ACTIONS.has(action)) return reply.code(400).send({ code: 'SCHEMA', field: 'action', server_time: deps.now() });
    const report = await deps.moderation!.report(paramId(req));
    if (!report) return reply.code(404).send({ code: 'NOT_FOUND', server_time: deps.now() });
    if (action === 'dismiss') {
      const r = await deps.moderation!.resolveReport(report.id, me.id, action, deps.now());
      return reply.send({ ok: true, resolved: r ? 1 : 0, server_time: deps.now() });
    }
    let subjectId: string | null = null;
    if (report.target_type === 'post') {
      const post = await deps.feed?.post(report.target_id);
      subjectId = post?.author_id ?? null;
      if (post) await deps.feed!.setPostStatus(post.id, 'hidden');
    } else if (report.target_type === 'comment') {
      const c = await deps.feed?.comment(report.target_id);
      subjectId = c?.author_id ?? null;
      if (c) await deps.feed!.setCommentStatus(c.id, 'hidden');
    } else if (report.target_type === 'message') {
      const m = await deps.im?.message(report.target_id);
      subjectId = m?.sender_id ?? null;
      if (m) await retractMessage(m.id);
    } else subjectId = report.target_id;
    if (action === 'ban_user' && subjectId) await deps.moderation!.ban(subjectId, `report:${report.id}:${report.reason}`, me.id, deps.now());
    const n = await deps.moderation!.resolveTarget(report.target_type, report.target_id, me.id, action, deps.now());
    return reply.send({ ok: true, resolved: n, banned: action === 'ban_user' ? subjectId : null, server_time: deps.now() });
  });

  app.get('/v1/admin/review', async (req, reply) => {
    const me = await adminGuard(req, reply); if (!me) return;
    if (!deps.feed) return reply.code(503).send({ code: 'FEED_NOT_CONFIGURED', server_time: deps.now() });
    const q = await deps.feed.pendingReview(clampLimit((req.query as Record<string, unknown>).limit));
    return reply.send({
      posts: q.posts.map(p => ({ id: p.id, author_id: p.author_id, text: p.text, images: p.images, created_at: p.created_at, categories: p.moderation_categories })),
      comments: q.comments.map(c => ({ id: c.id, post_id: c.post_id, author_id: c.author_id, text: c.text, created_at: c.created_at, categories: c.moderation_categories })),
      server_time: deps.now(),
    });
  });

  app.post('/v1/admin/review/:type/:id', async (req, reply) => {
    const me = await adminGuard(req, reply); if (!me) return;
    if (!deps.feed) return reply.code(503).send({ code: 'FEED_NOT_CONFIGURED', server_time: deps.now() });
    const { type, id } = req.params as Record<string, string>;
    const decision = String((req.body as Record<string, unknown> | undefined)?.decision ?? '');
    if (!['approve', 'hide'].includes(decision) || !['post', 'comment'].includes(type))
      return reply.code(400).send({ code: 'SCHEMA', server_time: deps.now() });
    const status = decision === 'approve' ? 'approved' : 'hidden';
    const ok = type === 'post' ? await deps.feed.setPostStatus(id, status) : await deps.feed.setCommentStatus(id, status);
    if (!ok) return reply.code(404).send({ code: 'NOT_FOUND', server_time: deps.now() });
    return reply.send({ ok: true, status, server_time: deps.now() });
  });

  // —— D3 IM：会话 / 消息 / 已读 / 增量同步 ——
  const imGuard = async (req: FastifyRequest, reply: FastifyReply): Promise<UserRow | null> => {
    if (!deps.im || !deps.social) { await reply.code(503).send({ code: 'IM_NOT_CONFIGURED', server_time: deps.now() }); return null; }
    const c = await currentUser(req);
    if ('user' in c) return c.user;
    await reply.code(c.status).send(c.body);
    return null;
  };
  const hub: LiveHub | undefined = deps.liveHub ?? deps.wsHub;
  const publish = (events: UserEvent[]) => { if (events.length) hub?.publish(events); };
  /** 审核下架一条消息：软删 + 推 message_deleted 给全部成员（与发送者撤回同一条路）。 */
  const retractMessage = async (messageId: string): Promise<boolean> => {
    const m = await deps.im?.message(messageId);
    if (!m || !deps.im) return false;
    const deleted = await deps.im.deleteMessage(m.id, deps.now());
    if (deleted) publish(await deps.im.pushEvent((await deps.im.members(m.conversation_id)).map(x => x.user_id), 'message_deleted', { conversation_id: m.conversation_id, message_id: m.id, message_seq: m.seq }, deps.now()));
    return deleted;
  };
  if (deps.wsHub && deps.im) await registerImGateway(app, deps.wsHub, currentUser, { now: deps.now, pingIntervalMs: deps.wsPingIntervalMs });
  const peerCardsOf = async (ids: string[]): Promise<Map<string, PeerCard>> => {
    const profiles = await deps.social!.profiles([...new Set(ids)]);
    const out = new Map<string, PeerCard>();
    for (const id of ids) { const p = profiles.get(id); out.set(id, { user_id: id, display_name: p?.display_name ?? '', handle: p?.handle ?? null, avatar: p?.avatar ?? null }); }
    return out;
  };
  /** 会话须存在且我是成员；否则一律 404（不暴露别人会话的存在）。 */
  const myConversation = async (reply: FastifyReply, me: UserRow, id: string): Promise<ConversationRow | null> => {
    const c = await deps.im!.conversation(id);
    if (c && await deps.im!.isMember(c.id, me.id)) return c;
    await reply.code(404).send({ code: 'NOT_FOUND', server_time: deps.now() });
    return null;
  };
  const conversationOut = async (me: UserRow, c: ConversationRow) => {
    const members = await deps.im!.members(c.id);
    const mine = members.find(m => m.user_id === me.id)!;
    const peerRow = c.kind === 'dm' ? members.find(m => m.user_id !== me.id) ?? null : null;
    const peer = peerRow ? (await peerCardsOf([peerRow.user_id])).get(peerRow.user_id)! : null;
    const last = (await deps.im!.messages(c.id, null, 1))[0] ?? null;
    return conversationView(c, mine, last, peer, members.length, peerRow?.last_read_seq ?? null);
  };

  app.post('/v1/im/dm', async (req, reply) => {
    const me = await imGuard(req, reply); if (!me) return;
    const other = String((req.body as Record<string, unknown> | undefined)?.user_id ?? '');
    if (!/^[0-9a-f-]{36}$/i.test(other)) return reply.code(400).send({ code: 'SCHEMA', field: 'user_id', server_time: deps.now() });
    if (other === me.id) return reply.code(400).send({ code: 'SELF_DM', server_time: deps.now() });
    if (!(await deps.accounts!.userById(other))) return reply.code(404).send({ code: 'NOT_FOUND', server_time: deps.now() });
    if (await blockedEither(me.id, other)) return reply.code(403).send({ code: 'BLOCKED', server_time: deps.now() });
    const r = await deps.im!.getOrCreateDm(me.id, other, deps.now());
    return reply.code(r.created ? 201 : 200).send({ ...(await conversationOut(me, r.conversation)), created: r.created, server_time: deps.now() });
  });

  /** 群成员校验：存在、不是自己、和我没有互相拉黑。 */
  const checkMembers = async (reply: FastifyReply, me: UserRow, ids: string[]): Promise<boolean> => {
    for (const id of ids) {
      if (id === me.id) continue;
      if (!(await deps.accounts!.userById(id))) { await reply.code(400).send({ code: 'SCHEMA', field: 'member_ids', reason: 'UNKNOWN_USER', user_id: id, server_time: deps.now() }); return false; }
      if (await blockedEither(me.id, id)) { await reply.code(403).send({ code: 'BLOCKED', user_id: id, server_time: deps.now() }); return false; }
    }
    return true;
  };

  app.post('/v1/im/groups', async (req, reply) => {
    const me = await imGuard(req, reply); if (!me) return;
    const v = validateGroup(req.body);
    if (!v.ok) return reply.code(400).send({ code: 'SCHEMA', field: v.field, reason: v.reason, server_time: deps.now() });
    if (!(await checkMembers(reply, me, v.memberIds))) return;
    const c = await deps.im!.createGroup({ id: randomUUID(), title: v.title, creatorId: me.id, memberIds: v.memberIds, now: deps.now() });
    publish(await deps.im!.pushEvent((await deps.im!.members(c.id)).map(m => m.user_id), 'conversation_created', { conversation_id: c.id, kind: 'group', title: c.title, by: me.id }, deps.now()));
    return reply.code(201).send({ ...(await conversationOut(me, c)), server_time: deps.now() });
  });

  app.post('/v1/im/groups/:id/members', async (req, reply) => {
    const me = await imGuard(req, reply); if (!me) return;
    const c = await myConversation(reply, me, paramId(req)); if (!c) return;
    if (c.kind !== 'group') return reply.code(400).send({ code: 'NOT_GROUP', server_time: deps.now() });
    const ids = uniqueIds((req.body as Record<string, unknown> | undefined)?.user_ids);
    if (!ids || ids.length === 0) return reply.code(400).send({ code: 'SCHEMA', field: 'user_ids', server_time: deps.now() });
    if (!(await checkMembers(reply, me, ids))) return;
    const added = await deps.im!.addMembers(c.id, ids, deps.now());
    if (added.length) publish(await deps.im!.pushEvent((await deps.im!.members(c.id)).map(m => m.user_id), 'members_added', { conversation_id: c.id, user_ids: added, by: me.id }, deps.now()));
    return reply.send({ ok: true, added, server_time: deps.now() });
  });

  app.delete('/v1/im/groups/:id/members/me', async (req, reply) => {
    const me = await imGuard(req, reply); if (!me) return;
    const c = await myConversation(reply, me, paramId(req)); if (!c) return;
    if (c.kind !== 'group') return reply.code(400).send({ code: 'NOT_GROUP', server_time: deps.now() });
    const removed = await deps.im!.removeMember(c.id, me.id);
    if (removed) publish(await deps.im!.pushEvent((await deps.im!.members(c.id)).map(m => m.user_id), 'member_left', { conversation_id: c.id, user_id: me.id }, deps.now()));
    return reply.send({ ok: true, removed, server_time: deps.now() });
  });

  app.get('/v1/im/conversations', async (req, reply) => {
    const me = await imGuard(req, reply); if (!me) return;
    const rows = await deps.im!.conversationsOf(me.id);
    const items = [];
    for (const r of rows) {
      const members = await deps.im!.members(r.conversation.id);
      const peerRow = r.conversation.kind === 'dm' ? members.find(m => m.user_id !== me.id) ?? null : null;
      const peer = peerRow ? (await peerCardsOf([peerRow.user_id])).get(peerRow.user_id)! : null;
      items.push(conversationView(r.conversation, r.member, r.last_message, peer, members.length, peerRow?.last_read_seq ?? null));
    }
    return reply.send({ items, server_time: deps.now() });
  });

  /** 成员列表：群聊气泡上的昵称、「N 人已读」都靠它；非成员 404。 */
  app.get('/v1/im/conversations/:id/members', async (req, reply) => {
    const me = await imGuard(req, reply); if (!me) return;
    const c = await myConversation(reply, me, paramId(req)); if (!c) return;
    const members = await deps.im!.members(c.id);
    const cards = await peerCardsOf(members.map(m => m.user_id));
    return reply.send({ items: members.map(m => memberView(m, cards.get(m.user_id))), server_time: deps.now() });
  });

  app.get('/v1/im/conversations/:id/messages', async (req, reply) => {
    const me = await imGuard(req, reply); if (!me) return;
    const c = await myConversation(reply, me, paramId(req)); if (!c) return;
    const q = req.query as Record<string, unknown>;
    const before = Number.isInteger(Number(q.before_seq)) && q.before_seq !== undefined ? Number(q.before_seq) : null;
    const limit = Math.min(clampLimit(q.limit), HISTORY_LIMIT_MAX);
    const rows = await deps.im!.messages(c.id, before, limit);
    return reply.send({ items: rows.map(messageView), server_time: deps.now() });
  });

  app.post('/v1/im/conversations/:id/messages', async (req, reply) => {
    const me = await imGuard(req, reply); if (!me) return;
    const c = await myConversation(reply, me, paramId(req)); if (!c) return;
    const v = validateMessage(req.body);
    if (!v.ok) return reply.code(400).send({ code: 'SCHEMA', field: v.field, reason: v.reason, server_time: deps.now() });
    if (v.kind === 'image' && !ownsKey(String(v.body.key), me.id))
      return reply.code(400).send({ code: 'SCHEMA', field: 'image', reason: 'NOT_OWNED', server_time: deps.now() });
    if (c.kind === 'dm') {
      const peer = (await deps.im!.members(c.id)).find(m => m.user_id !== me.id)?.user_id;
      if (!peer) return reply.code(410).send({ code: 'PEER_GONE', server_time: deps.now() });
      if (await blockedEither(me.id, peer)) return reply.code(403).send({ code: 'BLOCKED', server_time: deps.now() });
      const relation = await deps.social!.relation(me.id, peer);
      if (greetingBlocked(relation, await deps.im!.dmExchange(c.id, me.id, peer)))
        return reply.code(403).send({ code: 'GREETING_LIMIT', server_time: deps.now() });
    }
    const mod = await moderateText(v.text);
    if (mod.status === 'rejected') return reply.code(422).send({ code: 'MODERATION_REJECTED', categories: mod.categories, server_time: deps.now() });
    const r = await deps.im!.appendMessage({ id: randomUUID(), conversationId: c.id, senderId: me.id, clientId: v.clientId, kind: v.kind, body: v.body, now: deps.now(), moderation: mod });
    publish(r.events);
    return reply.code(r.created ? 201 : 200).send({ ...messageView(r.message), created: r.created, server_time: deps.now() });
  });

  /** 已读回执：单聊里推给对方；群聊只记自己的进度。 */
  app.post('/v1/im/conversations/:id/read', async (req, reply) => {
    const me = await imGuard(req, reply); if (!me) return;
    const c = await myConversation(reply, me, paramId(req)); if (!c) return;
    const seq = Number((req.body as Record<string, unknown> | undefined)?.seq);
    if (!Number.isInteger(seq) || seq < 0) return reply.code(400).send({ code: 'SCHEMA', field: 'seq', server_time: deps.now() });
    const r = await deps.im!.markRead(c.id, me.id, seq);
    // 单聊与群聊都广播：群里的「N 人已读」要实时推进，不能只靠进页时拉一次成员列表。
    if (r.changed) {
      const others = (await deps.im!.members(c.id)).filter(m => m.user_id !== me.id).map(m => m.user_id);
      publish(await deps.im!.pushEvent(others, 'read', { conversation_id: c.id, user_id: me.id, read_seq: r.last_read_seq }, deps.now()));
    }
    return reply.send({ ok: true, last_read_seq: r.last_read_seq, server_time: deps.now() });
  });

  app.delete('/v1/im/messages/:id', async (req, reply) => {
    const me = await imGuard(req, reply); if (!me) return;
    const m = await deps.im!.message(paramId(req));
    if (!m || !(await deps.im!.isMember(m.conversation_id, me.id))) return reply.code(404).send({ code: 'NOT_FOUND', server_time: deps.now() });
    if (m.sender_id !== me.id) return reply.code(403).send({ code: 'FORBIDDEN', server_time: deps.now() });
    const deleted = await deps.im!.deleteMessage(m.id, deps.now());
    if (deleted) publish(await deps.im!.pushEvent((await deps.im!.members(m.conversation_id)).map(x => x.user_id), 'message_deleted', { conversation_id: m.conversation_id, message_id: m.id, message_seq: m.seq }, deps.now()));
    return reply.send({ ok: true, deleted, server_time: deps.now() });
  });

  /** 增量同步：since 之后的 inbox 事件；latest_seq 让客户端知道有没有拉完。 */
  app.get('/v1/im/sync', async (req, reply) => {
    const me = await imGuard(req, reply); if (!me) return;
    const q = req.query as Record<string, unknown>;
    const since = Number.isInteger(Number(q.since)) && q.since !== undefined ? Math.max(0, Number(q.since)) : 0;
    const limit = Math.min(Number.isInteger(Number(q.limit)) && Number(q.limit) > 0 ? Number(q.limit) : SYNC_LIMIT_MAX, SYNC_LIMIT_MAX);
    const [events, latest] = await Promise.all([deps.im!.eventsSince(me.id, since, limit), deps.im!.latestSeq(me.id)]);
    return reply.send({ events: events.map(e => ({ seq: e.seq, type: e.type, ...e.payload, event_at: e.created_at })), latest_seq: latest, server_time: deps.now() });
  });

  app.get('/v1/healthz', async (_req, reply) => reply.send({
    ok: true, db: true, accounts: accountsReady(), social: Boolean(deps.social), feed: Boolean(deps.feed), uploads: Boolean(deps.uploads || deps.localUploads), uploads_mode: deps.uploads ? 'r2' : deps.localUploads ? 'local' : 'off', moderation: Boolean(deps.moderation), text_moderator: Boolean(deps.textModerator), im: Boolean(deps.im), ws: Boolean(deps.wsHub), git_sha: deps.gitSha ?? 'dev',
    content_version: deps.contentVersion, domain_version: DOMAIN_VERSION,
    server_time: deps.now(),
  }));

  return app;
}

const timezoneOf = (r: Regions, id: string): string =>
  r.regions.find(x => x.id === id)?.timezone ?? 'UTC';

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
  const state = initialFarmState(deps.content, blueprintSets(bp), timezone, now);
  return {
    id: cryptoRandomId(), owner_id: ownerId, region_id: regionId,
    layout_patch_id: bp.layout_patch_id, blueprint_revision: bp.revision,
    ...(location ? { location } : {}),
    version: 0, location_visible: true, visit_access: 'only_me', state,
  };
}

export function blueprintSets(bp: ReturnType<typeof parseBlueprint>): Ctx['blueprint'] {
  const cultivable = new Set<string>();
  bp.masks.cultivable.forEach((row, j) => {
    for (let i = 0; i < row.length; i++) if (row[i] === '1') cultivable.add(`${i},${j}`);
  });
  const reserved = new Set(bp.anchors.reserved_bed.cells.map(c => `${c[0]},${c[1]}`));
  return { cultivable, reserved };
}

const cryptoRandomId = (): string => randomUUID();

export { contentVersion, loadContent };
