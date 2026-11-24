/**
 * 地块认领的 PostgreSQL 实现（表结构见 db/schema.sql 的 parcel_claims）。
 * 抢同一块地：主键 (community_id, layer, parcel_id) 让并发 INSERT 只有一条成功；
 * 一人一块：player_id 上 kind='free' 的部分唯一索引。两者都用 ON CONFLICT DO NOTHING 接住，
 * 再读一次判断是哪条规则挡住的。
 */
import type pg from 'pg';
import type { FarmOutcome, ParcelFarmState } from './farm.js';
import { sameParcel, type ClaimOutcome, type EnterOutcome, type FarmUpdateOutcome, type OwnedParcel, type OwnerQuery, type ParcelClaim, type ParcelStore, type ReclaimedParcel } from './store.js';

const rowToParcel = (r: Record<string, unknown>): OwnedParcel => ({
  community_id: r.community_id as string,
  layer: r.layer as number,
  parcel_id: r.parcel_id as string,
  dataset_version: r.dataset_version as string,
  center: { lat: r.center_lat as number, lng: r.center_lng as number },
  player_id: r.player_id as string,
  claimed_at: Number(r.claimed_at),
  farm_version: r.farm_version as number,
  farm: r.farm_state as ParcelFarmState,
  updated_at: Number(r.updated_at),
});

export class PgParcelStore implements ParcelStore {
  constructor(private pool: pg.Pool) {}

  async mine(playerId: string) {
    const r = await this.pool.query("SELECT * FROM parcel_claims WHERE player_id = $1 AND kind = 'free'", [playerId]);
    return r.rows[0] ? rowToParcel(r.rows[0]) : null;
  }

  async claim(playerId: string, claim: ParcelClaim, farm: ParcelFarmState, now: number): Promise<ClaimOutcome> {
    // 两次读之间别人可能刚放弃（仅测试配置）；重试几次，仍判不出就按已被占处理。
    for (let attempt = 0; attempt < 3; attempt++) {
      const inserted = await this.pool.query(
        `INSERT INTO parcel_claims (community_id, layer, parcel_id, player_id, kind, dataset_version, center_lat, center_lng,
           claimed_at, farm_version, farm_state, updated_at)
         VALUES ($1, $2, $3, $4, 'free', $5, $6, $7, $8, 0, $9, $8)
         ON CONFLICT DO NOTHING RETURNING *`,
        [claim.community_id, claim.layer, claim.parcel_id, playerId, claim.dataset_version, claim.center.lat, claim.center.lng, now, JSON.stringify(farm)]);
      if (inserted.rows[0]) return { kind: 'claimed', parcel: rowToParcel(inserted.rows[0]) };
      const own = await this.mine(playerId);
      if (own) return { kind: sameParcel(own, claim) ? 'already_mine' : 'player_has_parcel', parcel: own };
      const taken = await this.pool.query('SELECT 1 FROM parcel_claims WHERE community_id = $1 AND layer = $2 AND parcel_id = $3',
        [claim.community_id, claim.layer, claim.parcel_id]);
      if (taken.rowCount) return { kind: 'parcel_taken' };
    }
    return { kind: 'parcel_taken' };
  }

  async owners(communityId: string, layer: number, query: OwnerQuery) {
    const select = `SELECT c.parcel_id, c.player_id, u.display_name FROM parcel_claims c
      JOIN players p ON p.id = c.player_id LEFT JOIN users u ON u.id = p.user_id
      WHERE c.community_id = $1 AND c.layer = $2`;
    const r = 'ids' in query
      ? await this.pool.query(`${select} AND c.parcel_id = ANY($3::text[]) ORDER BY c.parcel_id`, [communityId, layer, query.ids])
      : await this.pool.query(`${select} AND c.center_lng BETWEEN $3 AND $5 AND c.center_lat BETWEEN $4 AND $6 ORDER BY c.parcel_id LIMIT $7`,
        [communityId, layer, ...query.bbox, query.limit]);
    return r.rows.map(row => ({ parcel_id: row.parcel_id as string, player_id: row.player_id as string, nickname: (row.display_name ?? null) as string | null }));
  }

  async updateFarm(playerId: string, baseVersion: number, apply: (farm: ParcelFarmState, parcel: OwnedParcel) => FarmOutcome, now: number): Promise<FarmUpdateOutcome> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const r = await client.query("SELECT * FROM parcel_claims WHERE player_id = $1 AND kind = 'free' FOR UPDATE", [playerId]);
      if (!r.rows[0]) { await client.query('ROLLBACK'); return { kind: 'no_parcel' }; }
      const row = rowToParcel(r.rows[0]);
      if (row.farm_version !== baseVersion) { await client.query('ROLLBACK'); return { kind: 'version_conflict', parcel: row }; }
      const out = apply(structuredClone(row.farm), row);
      if (!out.ok) { await client.query('ROLLBACK'); return { kind: 'rejected', index: out.index, code: out.code, detail: out.detail, parcel: row }; }
      const updated = await client.query(
        `UPDATE parcel_claims SET farm_state = $4, farm_version = farm_version + 1, updated_at = $5
         WHERE community_id = $1 AND layer = $2 AND parcel_id = $3 RETURNING *`,
        [row.community_id, row.layer, row.parcel_id, JSON.stringify(out.state), now]);
      await client.query('COMMIT');
      return { kind: 'applied', parcel: rowToParcel(updated.rows[0]) };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  async enter(playerId: string, grant: (farm: ParcelFarmState) => ParcelFarmState | null, now: number): Promise<EnterOutcome> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const r = await client.query("SELECT * FROM parcel_claims WHERE player_id = $1 AND kind = 'free' FOR UPDATE", [playerId]);
      if (!r.rows[0]) { await client.query('ROLLBACK'); return { kind: 'no_parcel' }; }
      const row = rowToParcel(r.rows[0]);
      const next = grant(structuredClone(row.farm));
      if (!next) { await client.query('ROLLBACK'); return { kind: 'entered', granted: false, parcel: row }; }
      const updated = await client.query(
        `UPDATE parcel_claims SET farm_state = $4, farm_version = farm_version + 1, updated_at = $5
         WHERE community_id = $1 AND layer = $2 AND parcel_id = $3 RETURNING *`,
        [row.community_id, row.layer, row.parcel_id, JSON.stringify(next), now]);
      await client.query('COMMIT');
      return { kind: 'entered', granted: true, parcel: rowToParcel(updated.rows[0]) };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  async abandon(playerId: string) {
    const r = await this.pool.query("DELETE FROM parcel_claims WHERE player_id = $1 AND kind = 'free' RETURNING *", [playerId]);
    return r.rows[0] ? rowToParcel(r.rows[0]) : null;
  }

  /**
   * 一条语句完成挑选、删除和存档：挑选时锁住地块行（SKIP LOCKED，正在写的跳过），删除和写入 parcel_reclaims 同在这一条语句里，
   * 要么都成，要么都不成。最后活动时间 = GREATEST(players.last_seen_at, 该玩家 token 的最大 last_used_at)；
   * 两者都早于 cutoff 才算闲置，tokens 有 (player_id, last_used_at) 索引。
   */
  async reclaimIdle(cutoff: number, now: number, limit: number): Promise<ReclaimedParcel[]> {
    const r = await this.pool.query(
      `WITH idle AS (
         SELECT c.community_id, c.layer, c.parcel_id,
                GREATEST(p.last_seen_at, COALESCE((SELECT max(t.last_used_at) FROM tokens t WHERE t.player_id = p.id), 0)) AS last_active_at
           FROM parcel_claims c JOIN players p ON p.id = c.player_id
          WHERE p.user_id IS NULL AND p.last_seen_at < $1
            AND NOT EXISTS (SELECT 1 FROM tokens t WHERE t.player_id = p.id AND t.last_used_at >= $1)
          ORDER BY c.updated_at, c.parcel_id
          LIMIT $3
          FOR UPDATE OF c SKIP LOCKED
       ), gone AS (
         DELETE FROM parcel_claims c USING idle i
          WHERE c.community_id = i.community_id AND c.layer = i.layer AND c.parcel_id = i.parcel_id
         RETURNING c.*, i.last_active_at
       )
       INSERT INTO parcel_reclaims (community_id, layer, parcel_id, player_id, kind, dataset_version, center_lat, center_lng,
         claimed_at, farm_version, farm_state, updated_at, last_active_at, reclaimed_at)
       SELECT community_id, layer, parcel_id, player_id, kind, dataset_version, center_lat, center_lng,
         claimed_at, farm_version, farm_state, updated_at, last_active_at, $2 FROM gone
       RETURNING *`,
      [cutoff, now, limit]);
    return r.rows.map(row => ({ ...rowToParcel(row), last_active_at: Number(row.last_active_at), reclaimed_at: Number(row.reclaimed_at) }));
  }
}
