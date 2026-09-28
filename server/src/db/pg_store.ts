import { plotForFarm } from '../geography/farm_terrain.js';
import { relocateFarmState, relocationAvailable, relocationBlocked, relocationCommandMatches, relocationConfirmError, relocationEnvelope,
  RelocationError, type RelocationConfirm, type RelocationDraft, type RelocationOutcome } from '../domain/farm_relocation.js';
import type { FishingPresenceReader } from '../domain/fishing.js';
/**
 * PostgreSQL 实现。**单写者**靠一句 `SELECT ... FOR UPDATE`：同一农场的命令被行锁串行化，
 * 不同农场并行。
 *
 * `applyCommand` 里的步骤顺序与 spec §7.3 的伪代码逐条对应，顺序本身是被测对象
 * （test/db/concurrency.test.ts）。
 */
import type { PlotLayout } from '../domain/plot.js';
import { randomUUID } from 'node:crypto';
import { changeDirectory } from '../realtime/directory.js';
import { applyEffects, type Checkpoint, type DirectoryAction, type DirectoryPlayer, type PartyHome, type Effect, type Expedition, type Party } from '../realtime/model.js';
import type pg from 'pg';
import type { Command, CommandEnvelope } from '../domain/commands.js';
import type { Content } from '../domain/content.js';
import { apply, makeCtx, type Ctx } from '../domain/reducer.js';
import { effectiveNow as qaNow } from '../domain/qa.js';
import { DOMAIN_VERSION, STATE_SCHEMA_VERSION } from '../domain/version.js';
import { MAX_ACTIVE_TOKENS, TOKEN_IDLE_MS, newToken, tokenHash } from '../http/auth.js';
import { currentOwnerFarmView, type FarmRow } from '../http/dto.js';
import { canonicalJson, commandRecordResult, payloadHash } from '../http/hash.js';
import type { ApplyOutcome, CommandRecord, ConsumeCodeOutcome, DeletionRecord, PlayerRow, Store, UserRow } from '../http/store.js';

export interface PgStoreDeps {
  pool: pg.Pool;
  content: Content;
  contentVersion: string;
  timezone: (regionId: string) => string;
  plot: PlotLayout;
  now: () => number;
}

const rowToFarm = (r: Record<string, unknown>): FarmRow => ({
  id: r.id as string,
  owner_id: r.owner_id as string,
  region_id: r.region_id as string,
  layout_patch_id: r.layout_patch_id as string,
  blueprint_revision: r.blueprint_revision as number,
  ...(r.farm_terrain ? { farm_terrain: r.farm_terrain as FarmRow['farm_terrain'] } : {}),
  ...(r.location ? { location: r.location as FarmRow['location'] } : {}),
  relocation_available: r.relocation_available === true,
  relocation_used: r.relocation_used === true,
  relocation_draft: (r.relocation_draft ?? null) as FarmRow['relocation_draft'],
  version: r.version as number,
  location_visible: r.location_visible as boolean,
  visit_access: r.visit_access as 'only_me' | 'anyone',
  state: r.state as FarmRow['state'],
});

const rowToUser = (r: Record<string, unknown>): UserRow => ({
  id: r.id as string, email: (r.email ?? null) as string | null, email_verified: r.email_verified === true,
  password_hash: (r.password_hash ?? null) as string | null, created_at: Number(r.created_at), last_seen_at: Number(r.last_seen_at),
});

export class PgStore implements Store {
  constructor(private d: PgStoreDeps) {}

  async realtimeLoad(key: string): Promise<Checkpoint | null> {
    const result = await this.d.pool.query('SELECT revision, commit_id, state, rescued FROM online_rooms WHERE id=$1', [key]);
    const row = result.rows[0];
    return row ? { revision: row.revision, commit: row.commit_id, mine: row.state, rescued: row.rescued } : null;
  }

  async realtimeCommit(key: string, expected: number, commit: string, mine: Expedition, effects: Effect[]) {
    const client = await this.d.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 72))', [key]);
      const prior = (await client.query('SELECT * FROM online_rooms WHERE id=$1 FOR UPDATE', [key])).rows[0];
      const owners = [...new Set(effects.map(e => e.player))].sort();
      const rows = await client.query('SELECT * FROM farms WHERE owner_id=ANY($1::uuid[]) ORDER BY owner_id FOR UPDATE', [owners]);
      if (rows.rows.length !== owners.length) throw new Error('NO_FARM');
      if (prior?.commit_id === commit) {
        await client.query('COMMIT');
        return { checkpoint: { revision: prior.revision, commit, mine: prior.state as Expedition, rescued: prior.rescued }, farms: rows.rows.map(rowToFarm) };
      }
      if ((prior?.revision ?? 0) !== expected) throw new Error('ROOM_CONFLICT');
      for (const row of rows.rows) {
        if (row.domain_version !== DOMAIN_VERSION || row.content_version !== this.d.contentVersion)
          throw new Error('VERSION_MISMATCH');
      }
      const rescued: string[] = [];
      const farms = rows.rows.map(row => applyEffects(rowToFarm(row), effects, this.d.content, rescued));
      if (farms.length) await client.query(`UPDATE farms AS f SET state=data.state, version=data.version, updated_at=$2
        FROM jsonb_to_recordset($1::jsonb) AS data(id uuid, state jsonb, version int) WHERE f.id=data.id`,
        [JSON.stringify(farms.map(f => ({ id: f.id, state: f.state, version: f.version }))), this.d.now()]);
      const checkpoint = { revision: expected + 1, commit, mine, rescued };
      await client.query(`INSERT INTO online_rooms(id, revision, commit_id, state, updated_at, rescued) VALUES($1,$2,$3,$4,$5,$6)
        ON CONFLICT(id) DO UPDATE SET revision=$2, commit_id=$3, state=$4, updated_at=$5, rescued=$6`,
        [key, checkpoint.revision, commit, JSON.stringify(mine), this.d.now(), JSON.stringify(rescued)]);
      await client.query('COMMIT');
      return { checkpoint, farms };
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally { client.release(); }
  }

  async realtimeDirectory(player: string, action: DirectoryAction = 'get', value = '') {
    if (action === 'get') {
      const row = (await this.d.pool.query(`SELECT op.instance_id, op.party_farm_access, p.state AS party
        FROM online_players op LEFT JOIN online_parties p ON p.id=op.party_id WHERE op.player_id=$1`, [player])).rows[0];
      return { instance: row?.instance_id ?? '', party: (row?.party as Party | undefined) ?? null,
        farm_access: Boolean(row?.party && row.party_farm_access === row.party.id) };
    }
    const client = await this.d.pool.connect();
    try {
      await client.query('BEGIN');
      // Party operations are infrequent. One transaction lock makes join/transfer/kick atomic.
      await client.query('SELECT pg_advisory_xact_lock(735920161)');
      const own = (await client.query('SELECT * FROM online_players WHERE player_id=$1', [player])).rows[0];
      const records = await client.query('SELECT * FROM online_parties WHERE id=$1 OR code=$2', [own?.party_id ?? '', value.toUpperCase()]);
      const parties = new Map<string, Party>(records.rows.map(row => [row.id, row.state]));
      const ids = [...new Set([player, ...records.rows.flatMap(row => (row.state as Party).members)])];
      const members = await client.query('SELECT * FROM online_players WHERE player_id=ANY($1::uuid[])', [ids]);
      const players = new Map<string, DirectoryPlayer>(members.rows.map(row =>
        [row.player_id, { instance: row.instance_id, party: row.party_id, farm_access: row.party_farm_access }]));
      const before = new Map([...players].map(([id, entry]) => [id, JSON.stringify(entry)]));
      const result = changeDirectory(players, parties, player, action, value);
      const changed = [...players].filter(([id, entry]) => before.get(id) !== JSON.stringify(entry)).map(([player_id, entry]) =>
        ({ player_id, instance_id: entry.instance, party_id: entry.party, party_farm_access: entry.farm_access ?? '' }));
      if (changed.length) await client.query(`INSERT INTO online_players(player_id, instance_id, party_id, party_farm_access)
        SELECT player_id, instance_id, party_id, party_farm_access FROM jsonb_to_recordset($1::jsonb)
        AS input(player_id uuid, instance_id text, party_id text, party_farm_access text)
        ON CONFLICT(player_id) DO UPDATE SET instance_id=EXCLUDED.instance_id, party_id=EXCLUDED.party_id,
        party_farm_access=EXCLUDED.party_farm_access`, [JSON.stringify(changed)]);
      for (const row of records.rows) if (!parties.has(row.id)) await client.query('DELETE FROM online_parties WHERE id=$1', [row.id]);
      for (const party of parties.values()) await client.query(`INSERT INTO online_parties(id, code, state) VALUES($1,$2,$3)
        ON CONFLICT(id) DO UPDATE SET state=$3`, [party.id, party.code, JSON.stringify(party)]);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally { client.release(); }
  }

  async realtimeHomes(players: string[]): Promise<PartyHome[]> {
    return (await this.d.pool.query(`SELECT f.id, f.owner_id, f.region_id, f.layout_patch_id, f.blueprint_revision,
      f.visit_access, COALESCE(op.party_farm_access, '') AS party_farm_access
      FROM farms f LEFT JOIN online_players op ON op.player_id=f.owner_id WHERE f.owner_id=ANY($1::uuid[])`, [players])).rows;
  }

  async authAnonymous(hmac: string) {
    const now = this.d.now();
    const client = await this.d.pool.connect();
    try {
      await client.query('BEGIN');
      // 必须用 upsert 而不是「先查后插」：首次登录时 SELECT ... FOR UPDATE 锁不住一行
      // 不存在的记录，并发的第一次登录会同时走到 INSERT 上撞唯一键
      //（2026-09-04 真库并发测试抓到，内存实现掩盖了这个竞态）。
      const upsert = await client.query(
        `INSERT INTO players (id, install_key_hmac, created_at, last_seen_at) VALUES ($1,$2,$3,$3)
           ON CONFLICT (install_key_hmac) DO UPDATE SET last_seen_at = EXCLUDED.last_seen_at
         RETURNING id`,
        [randomUUID(), hmac, now]);
      const id = upsert.rows[0].id as string;
      const token = newToken();
      await client.query(
        'INSERT INTO tokens (id, player_id, token_hash, created_at, last_used_at) VALUES ($1,$2,$3,$4,$4)',
        [randomUUID(), id, tokenHash(token), now]);
      // 上限与淘汰在同一事务里做，否则并发签发会突破 5 个（Codex 三审 O-M2）。
      await client.query(
        `DELETE FROM tokens WHERE player_id = $1 AND id NOT IN (
           SELECT id FROM tokens WHERE player_id = $1 ORDER BY last_used_at DESC, id DESC LIMIT $2)`,
        [id, MAX_ACTIVE_TOKENS]);
      await client.query('COMMIT');
      return { player: { id, install_key_hmac: hmac, user_id: null }, token };
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  }

  // —— 账号（SGODOT-135） ——
  async createEmailUser(email: string, passwordHash: string, now: number) {
    const client = await this.d.pool.connect();
    try {
      await client.query('BEGIN');
      const inserted = await client.query(
        `INSERT INTO users (id, email, email_verified, password_hash, created_at, last_seen_at) VALUES ($1,$2,false,$3,$4,$4)
           ON CONFLICT (email) DO NOTHING RETURNING *`, [randomUUID(), email, passwordHash, now]);
      if (!inserted.rowCount) { await client.query('ROLLBACK'); return { kind: 'email_taken' as const }; }
      const user = rowToUser(inserted.rows[0]);
      await client.query(`INSERT INTO user_identities (provider, provider_uid, user_id, sign_in_provider, created_at)
        VALUES ('email', $1, $2, 'password', $3)`, [email, user.id, now]);
      await client.query('COMMIT');
      return { kind: 'created' as const, user };
    } catch (e) {
      await client.query('ROLLBACK');
      if ((e as { code?: string }).code === '23505') return { kind: 'email_taken' as const };
      throw e;
    } finally { client.release(); }
  }
  async userByEmail(email: string) {
    const r = await this.d.pool.query('SELECT * FROM users WHERE email = $1', [email]);
    return r.rowCount ? rowToUser(r.rows[0]) : null;
  }
  async userById(userId: string) {
    if (!/^[0-9a-f-]{36}$/i.test(userId)) return null;
    const r = await this.d.pool.query('SELECT * FROM users WHERE id = $1', [userId]);
    return r.rowCount ? rowToUser(r.rows[0]) : null;
  }
  async setUserPassword(userId: string, passwordHash: string) {
    await this.d.pool.query('UPDATE users SET password_hash = $2 WHERE id = $1', [userId, passwordHash]);
  }
  async markEmailVerified(userId: string) {
    await this.d.pool.query('UPDATE users SET email_verified = true WHERE id = $1', [userId]);
  }
  async authUser(userId: string, now: number) {
    const client = await this.d.pool.connect();
    try {
      await client.query('BEGIN');
      const user = await client.query('UPDATE users SET last_seen_at = $2 WHERE id = $1 RETURNING id', [userId, now]);
      if (!user.rowCount) throw new Error('NO_ACCOUNT');
      // Upsert on user_id: concurrent first sign-ins from two devices land on the same account player.
      const upsert = await client.query(
        `INSERT INTO players (id, install_key_hmac, created_at, last_seen_at, user_id) VALUES ($1,$2,$3,$3,$4)
           ON CONFLICT (user_id) DO UPDATE SET last_seen_at = EXCLUDED.last_seen_at RETURNING id, install_key_hmac`,
        [randomUUID(), 'account:' + userId, now, userId]);
      const id = upsert.rows[0].id as string;
      const token = newToken();
      await client.query('INSERT INTO tokens (id, player_id, token_hash, created_at, last_used_at) VALUES ($1,$2,$3,$4,$4)',
        [randomUUID(), id, tokenHash(token), now]);
      await client.query(
        `DELETE FROM tokens WHERE player_id = $1 AND id NOT IN (
           SELECT id FROM tokens WHERE player_id = $1 ORDER BY last_used_at DESC, id DESC LIMIT $2)`, [id, MAX_ACTIVE_TOKENS]);
      await client.query('COMMIT');
      return { player: { id, install_key_hmac: upsert.rows[0].install_key_hmac as string, user_id: userId }, token };
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally { client.release(); }
  }
  async revokeUserTokens(userId: string) {
    await this.d.pool.query('DELETE FROM tokens WHERE player_id IN (SELECT id FROM players WHERE user_id = $1)', [userId]);
  }
  async saveEmailCode(email: string, purpose: string, hash: string, now: number, ttlMs: number, resendMs: number) {
    // One statement: a concurrent resend either replaces an expired cooldown or sees the fresh row.
    const r = await this.d.pool.query(
      `INSERT INTO email_codes (email, purpose, code_hash, expires_at, sent_at, attempts) VALUES ($1,$2,$3,$4,$5,0)
         ON CONFLICT (email, purpose) DO UPDATE SET code_hash = EXCLUDED.code_hash, expires_at = EXCLUDED.expires_at,
           sent_at = EXCLUDED.sent_at, attempts = 0
         WHERE email_codes.sent_at <= $5 - $6
       RETURNING sent_at`, [email, purpose, hash, now + ttlMs, now, resendMs]);
    if (r.rowCount) return { kind: 'saved' as const };
    const prior = await this.d.pool.query('SELECT sent_at FROM email_codes WHERE email = $1 AND purpose = $2', [email, purpose]);
    const sent = Number(prior.rows[0]?.sent_at ?? now);
    return { kind: 'cooldown' as const, retry_after_ms: Math.max(0, resendMs - (now - sent)) };
  }
  async consumeEmailCode(email: string, purpose: string, hash: string, now: number, maxAttempts: number): Promise<ConsumeCodeOutcome> {
    const client = await this.d.pool.connect();
    try {
      await client.query('BEGIN');
      const r = await client.query('SELECT * FROM email_codes WHERE email = $1 AND purpose = $2 FOR UPDATE', [email, purpose]);
      const row = r.rows[0];
      let outcome: ConsumeCodeOutcome;
      if (!row) outcome = 'invalid';
      else if (Number(row.expires_at) < now) outcome = 'expired';
      else if (row.attempts >= maxAttempts) outcome = 'locked';
      else if (row.code_hash !== hash) outcome = 'invalid';
      else outcome = 'ok';
      if (row && (outcome !== 'invalid' || row.attempts + 1 >= maxAttempts))
        await client.query('DELETE FROM email_codes WHERE email = $1 AND purpose = $2', [email, purpose]);
      else if (row) await client.query('UPDATE email_codes SET attempts = attempts + 1 WHERE email = $1 AND purpose = $2', [email, purpose]);
      await client.query('COMMIT');
      return outcome;
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally { client.release(); }
  }
  async deleteUser(userId: string, tombstone: DeletionRecord) {
    const players = await this.d.pool.query('SELECT id FROM players WHERE user_id = $1', [userId]);
    for (const row of players.rows) await this.realtimeDirectory(row.id as string, 'leave').catch(() => undefined);
    const client = await this.d.pool.connect();
    try {
      await client.query('BEGIN');
      const user = await client.query('DELETE FROM users WHERE id = $1 RETURNING email', [userId]);
      if (!user.rowCount) { await client.query('ROLLBACK'); return false; }
      // players.user_id cascades; farms, tokens, commands, snapshots and online rows cascade from players.
      if (user.rows[0].email) await client.query('DELETE FROM email_codes WHERE email = $1', [user.rows[0].email]);
      await client.query(`INSERT INTO account_deletions (user_id, provider_uid, requested_at, source, apple_revocation)
        VALUES ($1,$2,$3,$4,$5) ON CONFLICT (user_id) DO NOTHING`,
        [tombstone.user_id, tombstone.provider_uid, tombstone.requested_at, tombstone.source, tombstone.apple_revocation]);
      await client.query('COMMIT');
      return true;
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally { client.release(); }
  }
  async deletion(userId: string) {
    if (!/^[0-9a-f-]{36}$/i.test(userId)) return null;
    const r = await this.d.pool.query('SELECT * FROM account_deletions WHERE user_id = $1', [userId]);
    if (!r.rowCount) return null;
    const row = r.rows[0];
    return { user_id: row.user_id, provider_uid: row.provider_uid, requested_at: Number(row.requested_at),
      source: row.source, apple_revocation: row.apple_revocation } as DeletionRecord;
  }

  async revokeToken(hash: string) {
    await this.d.pool.query('DELETE FROM tokens WHERE token_hash = $1', [hash]);
  }
  async revokeAllTokens(playerId: string) {
    await this.d.pool.query('DELETE FROM tokens WHERE player_id = $1', [playerId]);
  }
  async rotateInstallKey(playerId: string, newHmac: string) {
    await this.d.pool.query('UPDATE players SET install_key_hmac = $2 WHERE id = $1', [playerId, newHmac]);
  }
  async playerHmac(playerId: string) {
    const r = await this.d.pool.query('SELECT install_key_hmac FROM players WHERE id = $1', [playerId]);
    return r.rowCount ? (r.rows[0].install_key_hmac as string) : null;
  }

  async playerByToken(hash: string, now: number): Promise<PlayerRow | null> {
    const r = await this.d.pool.query(
      `SELECT t.player_id, t.last_used_at, p.install_key_hmac, p.user_id
         FROM tokens t JOIN players p ON p.id = t.player_id WHERE t.token_hash = $1`, [hash]);
    if (!r.rowCount) return null;
    const row = r.rows[0];
    if (now - Number(row.last_used_at) > TOKEN_IDLE_MS) {
      await this.d.pool.query('DELETE FROM tokens WHERE token_hash = $1', [hash]);
      return null;
    }
    await this.d.pool.query('UPDATE tokens SET last_used_at = $2 WHERE token_hash = $1', [hash, now]);
    return { id: row.player_id as string, install_key_hmac: row.install_key_hmac as string, user_id: (row.user_id ?? null) as string | null };
  }

  async farmByOwner(ownerId: string): Promise<FarmRow | null> {
    const r = await this.d.pool.query('SELECT * FROM farms WHERE owner_id = $1', [ownerId]);
    return r.rowCount ? rowToFarm(r.rows[0]) : null;
  }

  async farmById(farmId: string): Promise<FarmRow | null> {
    if (!/^[0-9a-f-]{36}$/i.test(farmId)) return null; // 非 uuid 直接当不存在，别让 pg 抛类型错
    const r = await this.d.pool.query('SELECT * FROM farms WHERE id = $1', [farmId]);
    return r.rowCount ? rowToFarm(r.rows[0]) : null;
  }

  async cityFarmCounts() {
    const r = await this.d.pool.query(`SELECT region_id, count(*)::int AS n FROM farms WHERE visit_access = 'anyone' GROUP BY region_id`);
    return new Map(r.rows.map(row => [row.region_id as string, row.n as number]));
  }

  async nearby(regionId: string, excludeOwnerId: string, limit: number) {
    const where = `region_id = $1 AND visit_access = 'anyone' AND owner_id <> $2`;
    const [count, rows] = await Promise.all([
      this.d.pool.query(`SELECT count(*)::int AS n FROM farms WHERE ${where}`, [regionId, excludeOwnerId]),
      this.d.pool.query(`SELECT * FROM farms WHERE ${where} ORDER BY created_at, id LIMIT $3`,
        [regionId, excludeOwnerId, limit]),
    ]);
    return { count: count.rows[0].n as number, farms: rows.rows.map(rowToFarm) };
  }

  async saveRelocationPreview(ownerId: string, draft: RelocationDraft) {
    const client = await this.d.pool.connect();
    try {
      await client.query('BEGIN');
      const row = (await client.query('SELECT * FROM farms WHERE owner_id=$1 FOR UPDATE', [ownerId])).rows[0];
      let code: string | undefined;
      if (!row) code = 'NO_FARM';
      else {
        const farm = rowToFarm(row);
        if (row.domain_version !== DOMAIN_VERSION || row.content_version !== this.d.contentVersion
          || row.state_schema_version !== STATE_SCHEMA_VERSION) code = 'VERSION_MISMATCH';
        else if (!relocationAvailable(farm)) code = 'RELOCATION_UNAVAILABLE';
        else if (relocationBlocked(farm, this.d.now(), this.d.content)) code = 'RELOCATION_BUSY';
        else if (farm.version !== draft.base_version || farm.region_id !== draft.region_id) code = 'RELOCATION_CONFLICT';
      }
      if (!code) await client.query('UPDATE farms SET relocation_draft=$2 WHERE owner_id=$1', [ownerId, JSON.stringify(draft)]);
      await client.query('COMMIT');
      return code ? { code } : {};
    } catch (error) { await client.query('ROLLBACK'); throw error; }
    finally { client.release(); }
  }

  async confirmFarmRelocation(ownerId: string, input: RelocationConfirm): Promise<RelocationOutcome> {
    const client = await this.d.pool.connect();
    try {
      await client.query('BEGIN');
      const row = (await client.query('SELECT * FROM farms WHERE owner_id=$1 FOR UPDATE', [ownerId])).rows[0];
      if (!row) { await client.query('ROLLBACK'); return { kind: 'rejected', code: 'NO_FARM' }; }
      const farm = rowToFarm(row), env = relocationEnvelope(input), hash = payloadHash(env);
      const prior = (await client.query('SELECT * FROM commands WHERE farm_id=$1 AND idempotency_key=$2', [farm.id, input.idempotency_key])).rows[0];
      if (prior) {
        await client.query('COMMIT');
        if (prior.payload_hash !== hash) return { kind: 'rejected', code: 'IDEMPOTENCY_MISMATCH' };
        return prior.outcome === 'applied' ? { kind: 'replayed', farm } : { kind: 'rejected', code: prior.result.code };
      }
      if (row.domain_version !== DOMAIN_VERSION || row.content_version !== this.d.contentVersion || row.state_schema_version !== STATE_SCHEMA_VERSION) {
        await client.query('ROLLBACK'); return { kind: 'rejected', code: 'VERSION_MISMATCH' };
      }
      const now = this.d.now();
      const reject = async (code: string): Promise<RelocationOutcome> => {
        await this.logCommand(client, farm.id, env, hash, 'rejected', { code }, now);
        await client.query('COMMIT'); return { kind: 'rejected', code };
      };
      const code = relocationConfirmError(farm, input, now, this.d.content);
      if (code) return await reject(code);
      const draft = farm.relocation_draft!;
      let moved;
      try { moved = relocateFarmState(farm.state, plotForFarm({ farm_terrain: draft.farm_terrain }, this.d.plot), this.d.content); }
      catch (error) { if (error instanceof RelocationError) return await reject(error.code); throw error; }
      const result = await client.query(`UPDATE farms SET state=$2, location=$3, farm_terrain=$4,
        layout_patch_id=$5, blueprint_revision=$6, blueprint_checksum=$7, version=version+1,
        relocation_available=false, relocation_used=true, relocation_draft=NULL, updated_at=$8 WHERE id=$1 RETURNING *`,
      [farm.id, JSON.stringify(moved.state), JSON.stringify(draft.location), JSON.stringify(draft.farm_terrain),
        draft.farm_terrain.layout_id, draft.farm_terrain.plot.revision, draft.farm_terrain.plot.checksum, now]);
      await client.query('DELETE FROM farm_snapshots WHERE farm_id=$1', [farm.id]);
      await this.logCommand(client, farm.id, env, hash, 'applied', { version: farm.version + 1, events: [{ type: 'farm_relocated' }] }, now);
      await client.query('COMMIT');
      return { kind: 'applied', farm: rowToFarm(result.rows[0]) };
    } catch (error) { await client.query('ROLLBACK'); throw error; }
    finally { client.release(); }
  }

  async snapshotGetOrCreate(farmId: string, slot: number, build: (current: FarmRow) => object) {
    const client = await this.d.pool.connect();
    try {
      await client.query('BEGIN');
      // Same lock order as relocation: an in-flight old read must not recreate a stale snapshot after commit.
      const saved = (await client.query('SELECT * FROM farms WHERE id=$1 FOR UPDATE', [farmId])).rows[0];
      if (!saved) throw new Error('NO_FARM');
      const farm = rowToFarm(saved);
      const prev = await client.query('SELECT * FROM farm_snapshots WHERE farm_id = $1 FOR UPDATE', [farmId]);
      if (prev.rowCount && Number(prev.rows[0].snapshot_taken_at) === slot) {
        await client.query('COMMIT');
        return { revision: prev.rows[0].snapshot_revision as number, taken_at: slot, body: prev.rows[0].body as object, farm };
      }
      const body = build(farm);
      const old = prev.rowCount ? prev.rows[0] : null;
      const changed = !old || canonicalJson(old.body) !== canonicalJson(body);
      const revision = old ? (changed ? (old.snapshot_revision as number) + 1 : old.snapshot_revision as number) : 1;
      await client.query(
        `INSERT INTO farm_snapshots (farm_id, snapshot_revision, snapshot_taken_at, body,
           blueprint_revision, content_version, domain_version)
         VALUES ($1,$2,$3,$4,$5,$6,$7)
         ON CONFLICT (farm_id) DO UPDATE SET snapshot_revision = EXCLUDED.snapshot_revision,
           snapshot_taken_at = EXCLUDED.snapshot_taken_at, body = EXCLUDED.body,
           blueprint_revision = EXCLUDED.blueprint_revision, content_version = EXCLUDED.content_version,
           domain_version = EXCLUDED.domain_version`,
        [farmId, revision, slot, JSON.stringify(body), farm.blueprint_revision,
          this.d.contentVersion, DOMAIN_VERSION]);
      await client.query('COMMIT');
      return { revision, taken_at: slot, body, farm };
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  }

  async ensureSystemFarm(playerHmac: string, farm: FarmRow) {
    const now = this.d.now();
    const client = await this.d.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(
        `INSERT INTO players (id, install_key_hmac, created_at, last_seen_at) VALUES ($1,$2,$3,$3)
           ON CONFLICT (install_key_hmac) DO NOTHING`, [farm.owner_id, playerHmac, now]);
      await client.query(
        `INSERT INTO farms (id, owner_id, region_id, layout_patch_id, blueprint_revision,
           blueprint_checksum, content_version, domain_version, state_schema_version,
           version, state, visit_access, location_visible, created_at, updated_at, location, farm_terrain)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,0,$10,$11,$12,$13,$13,$14,$15)
         ON CONFLICT (id) DO NOTHING`,
        [farm.id, farm.owner_id, farm.region_id, farm.layout_patch_id, farm.blueprint_revision,
          '', this.d.contentVersion, DOMAIN_VERSION, STATE_SCHEMA_VERSION,
          JSON.stringify(farm.state), farm.visit_access, farm.location_visible, now,
          farm.location ? JSON.stringify(farm.location) : null, farm.farm_terrain ? JSON.stringify(farm.farm_terrain) : null]);
      await client.query('COMMIT');
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  }

  async createFarm(args: Parameters<Store['createFarm']>[0]) {
    const now = this.d.now();
    const client = await this.d.pool.connect();
    try {
      await client.query('BEGIN');
      // The creation record does not exist on first use; lock its existing owner to serialize retries.
      await client.query('SELECT id FROM players WHERE id = $1 FOR UPDATE', [args.ownerId]);
      const prior = await client.query(
        'SELECT * FROM farm_creations WHERE player_id = $1 FOR UPDATE', [args.ownerId]);
      if (prior.rowCount) {
        const p = prior.rows[0];
        if (p.idempotency_key !== args.idempotencyKey || p.payload_hash !== args.payloadHash) {
          await client.query('ROLLBACK');
          return { kind: 'idempotency_mismatch' as const };
        }
        const f = await client.query('SELECT * FROM farms WHERE id = $1', [p.farm_id]);
        await client.query('COMMIT');
        return { kind: 'replayed' as const, farm: rowToFarm(f.rows[0]) };
      }
      const farm = await args.build();
      await client.query(
        `INSERT INTO farms (id, owner_id, region_id, layout_patch_id, blueprint_revision,
           blueprint_checksum, content_version, domain_version, state_schema_version,
           version, state, visit_access, location_visible, created_at, updated_at, location, farm_terrain)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,0,$10,$11,$12,$13,$13,$14,$15)`,
        [farm.id, farm.owner_id, farm.region_id, farm.layout_patch_id, farm.blueprint_revision,
          '', this.d.contentVersion, DOMAIN_VERSION, STATE_SCHEMA_VERSION,
          JSON.stringify(farm.state), farm.visit_access, farm.location_visible, now,
          farm.location ? JSON.stringify(farm.location) : null, farm.farm_terrain ? JSON.stringify(farm.farm_terrain) : null]);
      await client.query(
        `INSERT INTO farm_creations (player_id, idempotency_key, payload_hash, farm_id, created_at)
         VALUES ($1,$2,$3,$4,$5)`,
        [args.ownerId, args.idempotencyKey, args.payloadHash, farm.id, now]);
      await client.query('COMMIT');
      return { kind: 'created' as const, farm };
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  }

  async applyCommand(ownerId: string, env: CommandEnvelope, cmd: Command, fishingPresence?: FishingPresenceReader): Promise<ApplyOutcome> {
    const client = await this.d.pool.connect();
    try {
      await client.query('BEGIN');
      // 1. 行锁：同农场串行，不同农场并行。
      const fr = await client.query('SELECT * FROM farms WHERE owner_id = $1 FOR UPDATE', [ownerId]);
      if (!fr.rowCount) { await client.query('ROLLBACK'); return { kind: 'no_farm' }; }
      const row = fr.rows[0];
      const farm = rowToFarm(row);
      const hash = payloadHash(env);

      // 2. 幂等查表**先于**版本门控：旧命令的重试要能拿回已提交结果，不该先撞 503。
      const prior = await client.query(
        `SELECT idempotency_key, payload_hash, outcome, result FROM commands
           WHERE farm_id = $1 AND idempotency_key = $2`, [farm.id, env.idempotency_key]);
      if (prior.rowCount) {
        const p = prior.rows[0] as CommandRecord;
        await client.query('COMMIT');
        return p.payload_hash === hash
          ? { kind: 'replayed', record: p, farm }
          : { kind: 'idempotency_mismatch' };
      }

      // 3. 新命令才做版本门控（fail closed，不静默换规则去算老农场）。
      if (row.content_version !== this.d.contentVersion
        || row.domain_version !== DOMAIN_VERSION
        || row.state_schema_version !== STATE_SCHEMA_VERSION) {
        await client.query('ROLLBACK');
        return { kind: 'version_mismatch' };
      }

      if (!relocationCommandMatches(farm, env)) {
        await this.logCommand(client, farm.id, env, hash, 'rejected', { code: 'FARM_RELOCATED' }, this.d.now());
        await client.query('COMMIT');
        return { kind: 'rejected', code: 'FARM_RELOCATED' };
      }

      // 4. 锁后采样，先过 QA 时间变换，再单调 clamp。
      //    变换必须在 clamp 之前：QA 农场把倍率调回 1 时有效时间不该倒退，
      //    clamp 是那条保证；正式农场 qa 为恒等变换，这一步是 no-op。
      const realNow = this.d.now();
      const effectiveNow = Math.max(qaNow(farm.state.qa, realNow), farm.state.clock.last_effective_now);

      if (env.base_version !== farm.version) {
        await client.query('COMMIT');
        return { kind: 'version_conflict', farm };
      }

      const tz = this.d.timezone(farm.region_id);
      const ctx = makeCtx(farm.state, effectiveNow, tz,
        this.d.content, plotForFarm(farm, this.d.plot), realNow, farm.id);
      ctx.fishingPresence = fishingPresence?.();
      const r = apply(farm.state, cmd, ctx);

      if (!r.ok) {
        // 失败也落日志，并推进 last_effective_now（版本不变）。
        const bumped = { ...farm.state, clock: { ...farm.state.clock, last_effective_now: effectiveNow } };
        await client.query('UPDATE farms SET state = $2, updated_at = $3 WHERE id = $1',
          [farm.id, JSON.stringify(bumped), effectiveNow]);
        await this.logCommand(client, farm.id, env, hash, 'rejected',
          { code: r.code, detail: r.detail }, effectiveNow);
        await client.query('COMMIT');
        return { kind: 'rejected', code: r.code, detail: r.detail };
      }

      const nextState = { ...r.state, clock: { ...r.state.clock, last_effective_now: effectiveNow } };
      const settings = settingsPatch(cmd, farm);
      await client.query(
        `UPDATE farms SET state = $2, version = version + 1, updated_at = $3,
           visit_access = $4, location_visible = $5 WHERE id = $1`,
        [farm.id, JSON.stringify(nextState), effectiveNow, settings.visit_access, settings.location_visible]);
      const body = { ...currentOwnerFarmView(
        { ...farm, ...settings, state: nextState, version: farm.version + 1 },
        effectiveNow, tz, this.d.content, ctx.plot), events: r.events };
      // 日志只记版本与事件，**不记整份农场**：自由格子种田下一份状态可达几十 KB，
      // 而 commands 表每条命令一行且永久保留。重放时用当前农场行重建视图——
      // 那也更正确：客户端的预测层是整体覆盖，喂它一份过期快照会把状态往回倒。
      await this.logCommand(client, farm.id, env, hash, 'applied',
        { version: farm.version + 1, events: r.events }, effectiveNow);
      await client.query('COMMIT');
      return { kind: 'applied', body };
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  }

  private async logCommand(
    client: pg.PoolClient, farmId: string, env: Omit<CommandEnvelope, 'type'> & { type: string }, hash: string,
    outcome: 'applied' | 'rejected', result: unknown, effectiveNow: number,
  ) {
    await client.query(
      `INSERT INTO commands (farm_id, idempotency_key, base_version, type, payload, payload_hash,
         outcome, result, effective_now, content_version, domain_version, applied_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$9)`,
      [farmId, env.idempotency_key, env.base_version, env.type, JSON.stringify(env.payload ?? {}),
        hash, outcome, JSON.stringify(commandRecordResult(env, result)), effectiveNow, this.d.contentVersion, DOMAIN_VERSION]);
  }
}

/** 两个设置字段在列上而不是 state 里。 */
function settingsPatch(cmd: Command, farm: FarmRow) {
  return {
    visit_access: cmd.type === 'set_visit_access' ? cmd.access : farm.visit_access,
    location_visible: cmd.type === 'set_location_visible' ? cmd.visible : farm.location_visible,
  };
}
