/**
 * 动态农场地块接口（C-31）。身份沿用 /v1/auth 的 Bearer token：读接口游客也能用，
 * 认领、地块内命令和放弃需要账号（开发服 GUEST_WRITES=1 时游客也可写），与 /v1/farms 一致。
 * 接口与表结构说明见 docs/plans/C-31.md。
 */
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import type { PlayerRow } from '../http/store.js';
import { applyFarmCommands, emptyFarm, parseFarmCommands, welcome, withEconomy } from './farm.js';
import { communityOf, type ParcelRules } from './rules.js';
import { DEFAULT_LAYER, type OwnedParcel, type ParcelStore } from './store.js';

export interface ParcelRouteDeps {
  store: ParcelStore;
  rules: ParcelRules;
  now: () => number;
  /** “放弃并重选”只在内部测试服打开（DYNAMIC_FARM_RESELECT=1）；正式配置不设，调用被拒。 */
  reselect: boolean;
}

interface Auth {
  auth: (req: FastifyRequest) => Promise<PlayerRow | null>;
  writer: (req: FastifyRequest, reply: FastifyReply) => Promise<PlayerRow | null>;
}

/** 只有显式 DYNAMIC_FARM_RESELECT=1 才打开“放弃并重选”；没设、设成别的值都按正式配置关闭。 */
export const parcelReselectFromEnv = (env: Record<string, string | undefined>): boolean => env.DYNAMIC_FARM_RESELECT === '1';

export const PARCEL_ID_RE = /^p-[A-Za-z0-9_*-]{1,98}$/;
export const MAX_IDS = 200;
/** 区域查询的范围与条数上限：够一屏地图，又不至于一次拉出整座城的认领名单。 */
export const MAX_BBOX_SPAN_DEG = 0.25;
export const BBOX_LIMIT = 500;

const isNum = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v);
/** 与客户端 parcel_metadata 一致：GeoJSON 顺序 [lng, lat]。 */
const parseCenter = (v: unknown): { lat: number; lng: number } | null =>
  Array.isArray(v) && v.length === 2 && isNum(v[0]) && isNum(v[1]) && Math.abs(v[0]) <= 180 && Math.abs(v[1]) <= 85
    ? { lng: v[0], lat: v[1] } : null;

function parseBbox(raw: unknown): [number, number, number, number] | null {
  if (typeof raw !== 'string' || raw.length > 120) return null;
  const parts = raw.split(',').map(Number);
  if (parts.length !== 4 || !parts.every(Number.isFinite)) return null;
  const [w, s, e, n] = parts;
  if (Math.abs(w) > 180 || Math.abs(e) > 180 || Math.abs(s) > 85 || Math.abs(n) > 85 || w >= e || s >= n) return null;
  if (e - w > MAX_BBOX_SPAN_DEG || n - s > MAX_BBOX_SPAN_DEG) return null;
  return [w, s, e, n];
}

const parcelView = (p: OwnedParcel) => ({
  community_id: p.community_id, layer: p.layer, parcel_id: p.parcel_id, dataset_version: p.dataset_version,
  center: [p.center.lng, p.center.lat], claimed_at: p.claimed_at, farm_version: p.farm_version, farm: withEconomy(p.farm),
});

export function registerParcelRoutes(app: FastifyInstance, deps: ParcelRouteDeps, { auth, writer }: Auth): void {
  const now = deps.now;

  app.get('/v1/parcels/mine', async (req, reply) => {
    const p = await auth(req);
    if (!p) return reply.code(401).send({ code: 'UNAUTHENTICATED' });
    const mine = await deps.store.mine(p.id);
    return reply.send({ parcel: mine ? parcelView(mine) : null, server_time: now() });
  });

  /** 认领：每人一块免费地，只能认领无主地块，认领后永久归属。重复认领自己那块返回 200。
   * 认领只建空农场；赠品在首次进入（/mine/enter）时发。 */
  app.post('/v1/parcels/claim', { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } }, async (req, reply) => {
    const p = await writer(req, reply);
    if (!p) return;
    const b = req.body as { dataset_version?: unknown; parcel_id?: unknown; center?: unknown } | undefined;
    const center = parseCenter(b?.center);
    if (typeof b?.dataset_version !== 'string' || typeof b.parcel_id !== 'string' || !PARCEL_ID_RE.test(b.parcel_id) || !center)
      return reply.code(400).send({ code: 'SCHEMA', server_time: now() });
    const community = communityOf(deps.rules, b.dataset_version);
    if (!community) return reply.code(422).send({ code: 'UNKNOWN_DATASET', server_time: now() });
    const at = now();
    const out = await deps.store.claim(p.id, {
      community_id: community, layer: DEFAULT_LAYER, parcel_id: b.parcel_id, dataset_version: b.dataset_version, center,
    }, emptyFarm(), at);
    switch (out.kind) {
      case 'claimed': return reply.code(201).send({ parcel: parcelView(out.parcel), server_time: at });
      case 'already_mine': return reply.send({ parcel: parcelView(out.parcel), server_time: at });
      case 'player_has_parcel': return reply.code(409).send({ code: 'ALREADY_CLAIMED', parcel: parcelView(out.parcel), server_time: at });
      default: return reply.code(409).send({ code: 'PARCEL_TAKEN', server_time: at });
    }
  });

  /**
   * 地块归属：ids=p-1,p-2（逐个回答 mine / other / none）或 bbox=西,南,东,北（只列出已被认领的）。
   * 别人的地块带对方昵称；游客或未设昵称时为 null。
   */
  app.get('/v1/parcels', { config: { rateLimit: { max: 240, timeWindow: '1 minute' } } }, async (req, reply) => {
    const p = await auth(req);
    if (!p) return reply.code(401).send({ code: 'UNAUTHENTICATED' });
    const q = req.query as { dataset_version?: unknown; ids?: unknown; bbox?: unknown };
    if (typeof q.dataset_version !== 'string' || (q.ids === undefined) === (q.bbox === undefined))
      return reply.code(400).send({ code: 'SCHEMA', server_time: now() });
    const community = communityOf(deps.rules, q.dataset_version);
    if (!community) return reply.code(422).send({ code: 'UNKNOWN_DATASET', server_time: now() });
    const ownerOf = (playerId: string) => playerId === p.id ? 'mine' : 'other';
    const base = { dataset_version: q.dataset_version, community_id: community, layer: DEFAULT_LAYER };
    if (q.ids !== undefined) {
      const ids = typeof q.ids === 'string' && q.ids.length <= MAX_IDS * 101 ? [...new Set(q.ids.split(','))] : [];
      if (!ids.length || ids.length > MAX_IDS || !ids.every(id => PARCEL_ID_RE.test(id))) return reply.code(400).send({ code: 'SCHEMA', server_time: now() });
      const found = new Map((await deps.store.owners(community, DEFAULT_LAYER, { ids })).map(o => [o.parcel_id, o]));
      return reply.send({ ...base, parcels: ids.map(id => {
        const o = found.get(id);
        return o ? { parcel_id: id, owner: ownerOf(o.player_id), nickname: o.nickname } : { parcel_id: id, owner: 'none', nickname: null };
      }), server_time: now() });
    }
    const bbox = parseBbox(q.bbox);
    if (!bbox) return reply.code(400).send({ code: 'SCHEMA', server_time: now() });
    const rows = await deps.store.owners(community, DEFAULT_LAYER, { bbox, limit: BBOX_LIMIT + 1 });
    return reply.send({ ...base, parcels: rows.slice(0, BBOX_LIMIT).map(o => ({ parcel_id: o.parcel_id, owner: ownerOf(o.player_id), nickname: o.nickname })),
      truncated: rows.length > BBOX_LIMIT, server_time: now() });
  });

  /**
   * 进入自家地块（客户端每次打开自己的地块都调用）：第一次发 welcome_gift（Q-39 锄头与萝卜种子、Q-40 首栋住宅蓝图），
   * granted=true；之后重开、重试都只返回当前状态，granted=false，不重发。
   */
  app.post('/v1/parcels/mine/enter', { config: { rateLimit: { max: 120, timeWindow: '1 minute' } } }, async (req, reply) => {
    const p = await writer(req, reply);
    if (!p) return;
    const at = now();
    const out = await deps.store.enter(p.id, farm => welcome(deps.rules, farm, at), at);
    if (out.kind === 'no_parcel') return reply.code(404).send({ code: 'NO_PARCEL', server_time: at });
    return reply.send({ granted: out.granted, parcel: parcelView(out.parcel), server_time: at });
  });

  /**
   * 地块内命令：{base_version, commands:[...]}，整批成功才写入，版本不符返回当前状态。
   * 同一请求重发（或同时发多次）时只有第一次的 base_version 对得上，其余 409，不会重复加钱或重复发放（C-58）。
   * 采集的“是否自家地块”按行锁内那一行的 parcel_id 判断，不看请求体。
   */
  app.post('/v1/parcels/mine/commands', { config: { rateLimit: { max: 240, timeWindow: '1 minute' } } }, async (req, reply) => {
    const p = await writer(req, reply);
    if (!p) return;
    const b = req.body as { base_version?: unknown; commands?: unknown } | undefined;
    const commands = parseFarmCommands(b?.commands);
    if (!Number.isInteger(b?.base_version) || !commands) return reply.code(400).send({ code: 'SCHEMA', server_time: now() });
    const at = now();
    const out = await deps.store.updateFarm(p.id, b!.base_version as number, (farm, parcel) => applyFarmCommands(deps.rules, farm, commands, at, { parcel_id: parcel.parcel_id }), at);
    switch (out.kind) {
      case 'applied': return reply.send({ parcel: parcelView(out.parcel), server_time: at });
      case 'rejected': return reply.code(422).send({ code: out.code, index: out.index, ...(out.detail ? { detail: out.detail } : {}),
        parcel: parcelView(out.parcel), server_time: at });
      case 'version_conflict': return reply.code(409).send({ code: 'VERSION_CONFLICT', parcel: parcelView(out.parcel), server_time: at });
      default: return reply.code(404).send({ code: 'NO_PARCEL', server_time: at });
    }
  });

  /** 放弃并重选：只在测试配置开放；正式配置一律 403，地块不动。 */
  app.post('/v1/parcels/mine/abandon', { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } }, async (req, reply) => {
    const p = await writer(req, reply);
    if (!p) return;
    if (!deps.reselect) return reply.code(403).send({ code: 'RESELECT_DISABLED', server_time: now() });
    const gone = await deps.store.abandon(p.id);
    if (!gone) return reply.code(404).send({ code: 'NO_PARCEL', server_time: now() });
    return reply.send({ abandoned: { community_id: gone.community_id, layer: gone.layer, parcel_id: gone.parcel_id }, server_time: now() });
  });
}
