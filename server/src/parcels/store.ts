/**
 * 动态农场地块的存储（C-31）。认领的两条规则由存储保证，不靠先查后写：
 * 同一社区同一层的一块地只有一行（谁先插入谁得），每个玩家只有一条免费认领。
 * PostgreSQL 实现靠主键与部分唯一索引，内存实现在单线程里按同样顺序判断。
 */
import type { FarmOutcome, ParcelFarmState } from './farm.js';

/** 本版不分层，所有认领都在第 0 层；列先留着，分层时不改存档结构。 */
export const DEFAULT_LAYER = 0;

export interface GeoPoint { lat: number; lng: number }
export interface ParcelClaim {
  community_id: string;
  layer: number;
  parcel_id: string;
  dataset_version: string;
  /** 地块中心点，只用于按区域查询归属；归属判定只看 parcel_id。 */
  center: GeoPoint;
}
export interface OwnedParcel extends ParcelClaim {
  player_id: string;
  claimed_at: number;
  farm_version: number;
  farm: ParcelFarmState;
  updated_at: number;
}
export interface ParcelOwner { parcel_id: string; player_id: string; nickname: string | null }

export type ClaimOutcome =
  /** already_mine：同一玩家重复认领同一块（如网络重试），原样返回。 */
  | { kind: 'claimed' | 'already_mine'; parcel: OwnedParcel }
  | { kind: 'player_has_parcel'; parcel: OwnedParcel }
  | { kind: 'parcel_taken' };

export type FarmUpdateOutcome =
  | { kind: 'applied'; parcel: OwnedParcel }
  | { kind: 'rejected'; index: number; code: string; detail?: Record<string, unknown>; parcel: OwnedParcel }
  | { kind: 'version_conflict'; parcel: OwnedParcel }
  | { kind: 'no_parcel' };

/** 收回的地块（C-100）：原行加上认领者最后一次活动的时间和收回时间，原样存进 parcel_reclaims。 */
export interface ReclaimedParcel extends OwnedParcel { last_active_at: number; reclaimed_at: number }

/** 认领者的活动情况：是否游客（没有账号），最后一次登录或用 token 的时间。 */
export interface PlayerActivity { guest: boolean; last_active_at: number }

export type EnterOutcome = { kind: 'entered'; granted: boolean; parcel: OwnedParcel } | { kind: 'no_parcel' };

/** bbox 与客户端 GeoJSON 一致：[west, south, east, north]。 */
export type OwnerQuery = { ids: string[] } | { bbox: [number, number, number, number]; limit: number };

export interface ParcelStore {
  /** 玩家的免费地块；没有返回 null。 */
  mine(playerId: string): Promise<OwnedParcel | null>;
  claim(playerId: string, claim: ParcelClaim, farm: ParcelFarmState, now: number): Promise<ClaimOutcome>;
  /** 已被认领的地块及认领者昵称；没出现在结果里的就是无人认领。 */
  owners(communityId: string, layer: number, query: OwnerQuery): Promise<ParcelOwner[]>;
  /** 行锁内：版本门控 → apply → 写回并加一。apply 失败整批不写。apply 拿到的 parcel 是锁住的那一行（本人地块编号由此而来）。 */
  updateFarm(playerId: string, baseVersion: number, apply: (farm: ParcelFarmState, parcel: OwnedParcel) => FarmOutcome, now: number): Promise<FarmUpdateOutcome>;
  /** 进入自家地块：行锁内调用 grant，返回新状态就写回并加版本，返回 null（已发过）就不写。 */
  enter(playerId: string, grant: (farm: ParcelFarmState) => ParcelFarmState | null, now: number): Promise<EnterOutcome>;
  /** 放弃免费地块（仅测试配置开放），地块内状态一并删除。 */
  abandon(playerId: string): Promise<OwnedParcel | null>;
  /**
   * 闲置回收（C-100）：认领者是游客，且最后一次活动（登录或用 token，取较晚的）早于 cutoff 的地块，
   * 最多 limit 块。地块从 parcel_claims 删掉、整行存进 parcel_reclaims，之后谁都可以重新认领。
   * 有账号的玩家的地块不收。正被写入（行锁被占）的地块这一轮跳过。
   */
  reclaimIdle(cutoff: number, now: number, limit: number): Promise<ReclaimedParcel[]>;
}

const keyOf = (c: Pick<ParcelClaim, 'community_id' | 'layer' | 'parcel_id'>) => `${c.community_id}\n${c.layer}\n${c.parcel_id}`;

export const sameParcel = (a: Pick<ParcelClaim, 'community_id' | 'layer' | 'parcel_id'>, b: Pick<ParcelClaim, 'community_id' | 'layer' | 'parcel_id'>) =>
  keyOf(a) === keyOf(b);

/** 内存实现：HTTP 测试与本地开发用。nickname 由外部提供（账号表在 MemoryStore 里）。 */
export class MemoryParcelStore implements ParcelStore {
  private rows = new Map<string, OwnedParcel>();
  /** 测试读回用：收回存档。 */
  readonly reclaimed: ReclaimedParcel[] = [];
  constructor(private nickname: (playerId: string) => Promise<string | null> = async () => null,
    private activity: (playerId: string) => Promise<PlayerActivity | null> = async () => null) {}

  private byPlayer(playerId: string): OwnedParcel | undefined {
    return [...this.rows.values()].find(r => r.player_id === playerId);
  }

  async mine(playerId: string) {
    const row = this.byPlayer(playerId);
    return row ? structuredClone(row) : null;
  }

  async claim(playerId: string, claim: ParcelClaim, farm: ParcelFarmState, now: number): Promise<ClaimOutcome> {
    const own = this.byPlayer(playerId);
    if (own) return { kind: sameParcel(own, claim) ? 'already_mine' : 'player_has_parcel', parcel: structuredClone(own) };
    if (this.rows.has(keyOf(claim))) return { kind: 'parcel_taken' };
    const row: OwnedParcel = { ...structuredClone(claim), player_id: playerId, claimed_at: now, farm_version: 0, farm: structuredClone(farm), updated_at: now };
    this.rows.set(keyOf(claim), row);
    return { kind: 'claimed', parcel: structuredClone(row) };
  }

  async owners(communityId: string, layer: number, query: OwnerQuery) {
    let rows = [...this.rows.values()].filter(r => r.community_id === communityId && r.layer === layer);
    if ('ids' in query) rows = rows.filter(r => query.ids.includes(r.parcel_id));
    else {
      const [w, s, e, n] = query.bbox;
      rows = rows.filter(r => r.center.lat >= s && r.center.lat <= n && r.center.lng >= w && r.center.lng <= e);
    }
    rows.sort((a, b) => a.parcel_id < b.parcel_id ? -1 : a.parcel_id > b.parcel_id ? 1 : 0);
    if ('limit' in query) rows = rows.slice(0, query.limit);
    return Promise.all(rows.map(async r => ({ parcel_id: r.parcel_id, player_id: r.player_id, nickname: await this.nickname(r.player_id) })));
  }

  async updateFarm(playerId: string, baseVersion: number, apply: (farm: ParcelFarmState, parcel: OwnedParcel) => FarmOutcome, now: number): Promise<FarmUpdateOutcome> {
    const row = this.byPlayer(playerId);
    if (!row) return { kind: 'no_parcel' };
    if (row.farm_version !== baseVersion) return { kind: 'version_conflict', parcel: structuredClone(row) };
    const out = apply(structuredClone(row.farm), structuredClone(row));
    if (!out.ok) return { kind: 'rejected', index: out.index, code: out.code, detail: out.detail, parcel: structuredClone(row) };
    row.farm = out.state; row.farm_version += 1; row.updated_at = now;
    return { kind: 'applied', parcel: structuredClone(row) };
  }

  async enter(playerId: string, grant: (farm: ParcelFarmState) => ParcelFarmState | null, now: number): Promise<EnterOutcome> {
    const row = this.byPlayer(playerId);
    if (!row) return { kind: 'no_parcel' };
    const next = grant(structuredClone(row.farm));
    if (next) { row.farm = next; row.farm_version += 1; row.updated_at = now; }
    return { kind: 'entered', granted: Boolean(next), parcel: structuredClone(row) };
  }

  async abandon(playerId: string) {
    const row = this.byPlayer(playerId);
    if (!row) return null;
    this.rows.delete(keyOf(row));
    return structuredClone(row);
  }

  async reclaimIdle(cutoff: number, now: number, limit: number) {
    const out: ReclaimedParcel[] = [];
    const rows = [...this.rows.values()].sort((a, b) => a.updated_at - b.updated_at || (a.parcel_id < b.parcel_id ? -1 : 1));
    for (const row of rows) {
      if (out.length >= limit) break;
      const seen = await this.activity(row.player_id);
      if (!seen?.guest || seen.last_active_at >= cutoff) continue;
      this.rows.delete(keyOf(row));
      const gone = { ...structuredClone(row), last_active_at: seen.last_active_at, reclaimed_at: now };
      this.reclaimed.push(gone);
      out.push(structuredClone(gone));
    }
    return out;
  }
}
