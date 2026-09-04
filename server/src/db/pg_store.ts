/**
 * PostgreSQL 实现。**单写者**靠一句 `SELECT ... FOR UPDATE`：同一农场的命令被行锁串行化，
 * 不同农场并行。
 *
 * `applyCommand` 里的步骤顺序与 spec §7.3 的伪代码逐条对应，顺序本身是被测对象
 * （test/db/concurrency.test.ts）。
 */
import { randomUUID } from 'node:crypto';
import type pg from 'pg';
import type { Command, CommandEnvelope } from '../domain/commands.js';
import type { Content } from '../domain/content.js';
import { derive } from '../domain/derive.js';
import { apply, makeCtx, type Ctx } from '../domain/reducer.js';
import { DOMAIN_VERSION, STATE_SCHEMA_VERSION } from '../domain/version.js';
import { MAX_ACTIVE_TOKENS, TOKEN_IDLE_MS, newToken, tokenHash } from '../http/auth.js';
import { ownerFarmView, type FarmRow } from '../http/dto.js';
import { payloadHash } from '../http/hash.js';
import type { ApplyOutcome, CommandRecord, PlayerRow, Store } from '../http/store.js';

export interface PgStoreDeps {
  pool: pg.Pool;
  content: Content;
  contentVersion: string;
  timezone: (regionId: string) => string;
  blueprint: (layoutPatchId: string, revision: number) => Ctx['blueprint'];
  now: () => number;
}

const rowToFarm = (r: Record<string, unknown>): FarmRow => ({
  id: r.id as string,
  owner_id: r.owner_id as string,
  region_id: r.region_id as string,
  layout_patch_id: r.layout_patch_id as string,
  blueprint_revision: r.blueprint_revision as number,
  version: r.version as number,
  location_visible: r.location_visible as boolean,
  visit_access: r.visit_access as 'only_me' | 'anyone',
  state: r.state as FarmRow['state'],
});

export class PgStore implements Store {
  constructor(private d: PgStoreDeps) {}

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
      return { player: { id, install_key_hmac: hmac }, token };
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
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
      `SELECT t.player_id, t.last_used_at, p.install_key_hmac
         FROM tokens t JOIN players p ON p.id = t.player_id WHERE t.token_hash = $1`, [hash]);
    if (!r.rowCount) return null;
    const row = r.rows[0];
    if (now - Number(row.last_used_at) > TOKEN_IDLE_MS) {
      await this.d.pool.query('DELETE FROM tokens WHERE token_hash = $1', [hash]);
      return null;
    }
    await this.d.pool.query('UPDATE tokens SET last_used_at = $2 WHERE token_hash = $1', [hash, now]);
    return { id: row.player_id as string, install_key_hmac: row.install_key_hmac as string };
  }

  async farmByOwner(ownerId: string): Promise<FarmRow | null> {
    const r = await this.d.pool.query('SELECT * FROM farms WHERE owner_id = $1', [ownerId]);
    return r.rowCount ? rowToFarm(r.rows[0]) : null;
  }

  async createFarm(args: Parameters<Store['createFarm']>[0]) {
    const now = this.d.now();
    const client = await this.d.pool.connect();
    try {
      await client.query('BEGIN');
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
      const farm = args.build();
      await client.query(
        `INSERT INTO farms (id, owner_id, region_id, layout_patch_id, blueprint_revision,
           blueprint_checksum, content_version, domain_version, state_schema_version,
           version, state, visit_access, location_visible, created_at, updated_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,0,$10,$11,$12,$13,$13)`,
        [farm.id, farm.owner_id, farm.region_id, farm.layout_patch_id, farm.blueprint_revision,
          '', this.d.contentVersion, DOMAIN_VERSION, STATE_SCHEMA_VERSION,
          JSON.stringify(farm.state), farm.visit_access, farm.location_visible, now]);
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

  async applyCommand(ownerId: string, env: CommandEnvelope, cmd: Command): Promise<ApplyOutcome> {
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
          ? { kind: 'replayed', record: p }
          : { kind: 'idempotency_mismatch' };
      }

      // 3. 新命令才做版本门控（fail closed，不静默换规则去算老农场）。
      if (row.content_version !== this.d.contentVersion
        || row.domain_version !== DOMAIN_VERSION
        || row.state_schema_version !== STATE_SCHEMA_VERSION) {
        await client.query('ROLLBACK');
        return { kind: 'version_mismatch' };
      }

      // 4. 锁后采样，单调 clamp。
      const effectiveNow = Math.max(this.d.now(), farm.state.clock.last_effective_now);

      if (env.base_version !== farm.version) {
        await client.query('COMMIT');
        return { kind: 'version_conflict', farm };
      }

      const tz = this.d.timezone(farm.region_id);
      const ctx = makeCtx(farm.state, effectiveNow, tz,
        this.d.content, this.d.blueprint(farm.layout_patch_id, farm.blueprint_revision));
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
      const body = ownerFarmView(
        { ...farm, ...settings, state: nextState, version: farm.version + 1 },
        derive(nextState, effectiveNow, tz, this.d.content), effectiveNow);
      await this.logCommand(client, farm.id, env, hash, 'applied', body, effectiveNow);
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
    client: pg.PoolClient, farmId: string, env: CommandEnvelope, hash: string,
    outcome: 'applied' | 'rejected', result: unknown, effectiveNow: number,
  ) {
    await client.query(
      `INSERT INTO commands (farm_id, idempotency_key, base_version, type, payload, payload_hash,
         outcome, result, effective_now, content_version, domain_version, applied_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$9)`,
      [farmId, env.idempotency_key, env.base_version, env.type, JSON.stringify(env.payload ?? {}),
        hash, outcome, JSON.stringify(result), effectiveNow, this.d.contentVersion, DOMAIN_VERSION]);
  }
}

/** 两个设置字段在列上而不是 state 里。 */
function settingsPatch(cmd: Command, farm: FarmRow) {
  return {
    visit_access: cmd.type === 'set_visit_access' ? cmd.access : farm.visit_access,
    location_visible: cmd.type === 'set_location_visible' ? cmd.visible : farm.location_visible,
  };
}
