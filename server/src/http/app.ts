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
}

interface Regions {
  regions: { id: string; timezone: string; placement_bounds?: PlacementBounds;
    candidates: { layout_patch_id: string; revision: number }[] }[];
}

/** Nearby 列表上限：横向列表放不下更多，且越长越像在暴露整个城市的用户名单。 */
export const NEARBY_LIMIT = 20;

export async function buildApp(deps: AppDeps): Promise<FastifyInstance> {
  const app = Fastify({ logger: false });
  await app.register(rateLimit, { global: false });
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
    return reply.send({ ...userView(user), server_time: deps.now() });
  });

  /** CCPA / GDPR 访问请求：账号 + 身份 + 各模块登记的导出，一份 JSON 附件。 */
  app.get('/v1/users/me/export', async (req, reply) => {
    if (!accountsReady()) return notConfigured(reply);
    const r = await identityFromToken(bearer(req));
    if ('error' in r) return unauthenticated(reply, r.error);
    const user = await deps.accounts!.userByFirebaseUid(r.identity.uid);
    if (!user) return reply.code(404).send({ code: 'NO_ACCOUNT', server_time: deps.now() });
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
    return { user };
  };
  const socialGuard = async (req: FastifyRequest, reply: FastifyReply): Promise<UserRow | null> => {
    if (!deps.social) { await reply.code(503).send({ code: 'SOCIAL_NOT_CONFIGURED', server_time: deps.now() }); return null; }
    const c = await currentUser(req);
    if ('user' in c) return c.user;
    await reply.code(c.status).send(c.body);
    return null;
  };
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
    if (!p) return reply.code(404).send({ code: 'NOT_FOUND', server_time: deps.now() });
    const self = p.user_id === me.id;
    const [counts, relation] = await Promise.all([deps.social!.counts(p.user_id), deps.social!.relation(me.id, p.user_id)]);
    return reply.send({ ...publicProfileView(p, counts, relation, self), server_time: deps.now() });
  });

  const followTarget = async (req: FastifyRequest, reply: FastifyReply, me: UserRow): Promise<string | null> => {
    const p = await resolveProfile(paramId(req), me);
    if (!p) { await reply.code(404).send({ code: 'NOT_FOUND', server_time: deps.now() }); return null; }
    if (p.user_id === me.id) { await reply.code(400).send({ code: 'SELF_FOLLOW', server_time: deps.now() }); return null; }
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
    if (post && canSeePost(post, me.id, await deps.social!.relation(me.id, post.author_id))) return post;
    await reply.code(404).send({ code: 'NOT_FOUND', server_time: deps.now() });
    return null;
  };
  const pageQuery = (req: FastifyRequest): { cursor: string | null; limit: number } => {
    const q = req.query as Record<string, unknown>;
    return { cursor: typeof q.cursor === 'string' ? q.cursor : null, limit: clampLimit(q.limit) };
  };

  app.post('/v1/posts', async (req, reply) => {
    const me = await feedGuard(req, reply); if (!me) return;
    const v = validatePost(req.body);
    if (!v.ok) return reply.code(400).send({ code: 'SCHEMA', field: v.field, reason: v.reason, server_time: deps.now() });
    const r = await deps.feed!.createPost({ id: randomUUID(), authorId: me.id, idempotencyKey: v.idempotencyKey, text: v.text, images: v.images, now: deps.now() });
    const [view] = await postViews(me, [r.post]);
    return reply.code(r.created ? 201 : 200).send({ ...view, created: r.created, server_time: deps.now() });
  });

  /** 时间线 = 我 + 我关注的人的动态。 */
  app.get('/v1/feed', async (req, reply) => {
    const me = await feedGuard(req, reply); if (!me) return;
    const { cursor, limit } = pageQuery(req);
    const page = await deps.feed!.timeline(me.id, cursor, limit);
    return reply.send({ items: await postViews(me, page.items), next_cursor: page.next_cursor, server_time: deps.now() });
  });

  /** 某人的动态：本人或关注了他的人；否则 403 FOLLOW_REQUIRED（资料本身可见，只是动态要先关注）。 */
  app.get('/v1/users/:id/posts', async (req, reply) => {
    const me = await feedGuard(req, reply); if (!me) return;
    const p = await resolveProfile(paramId(req), me);
    if (!p) return reply.code(404).send({ code: 'NOT_FOUND', server_time: deps.now() });
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
    const cards = await authorCards(page.items.map(c => c.author_id));
    return reply.send({ items: page.items.map(c => commentView(c, cards.get(c.author_id)!)), next_cursor: page.next_cursor, server_time: deps.now() });
  });

  app.post('/v1/posts/:id/comments', async (req, reply) => {
    const me = await feedGuard(req, reply); if (!me) return;
    const post = await visiblePost(req, reply, me, paramId(req)); if (!post) return;
    const v = validateComment(req.body);
    if (!v.ok) return reply.code(400).send({ code: 'SCHEMA', field: v.field, reason: v.reason, server_time: deps.now() });
    const c = await deps.feed!.addComment({ id: randomUUID(), postId: post.id, authorId: me.id, text: v.text, now: deps.now() });
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

  app.get('/v1/healthz', async (_req, reply) => reply.send({
    ok: true, db: true, accounts: accountsReady(), social: Boolean(deps.social), feed: Boolean(deps.feed), git_sha: deps.gitSha ?? 'dev',
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
