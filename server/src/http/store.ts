/**
 * 存储抽象。HTTP 层只认这个接口，Task 7 用 PostgreSQL 实现它，测试用内存实现。
 *
 * 这不是为了「可插拔数据库」，而是为了让 HTTP 层的测试不依赖真库，同时让**事务语义**
 * 成为接口的一部分：`applyCommand` 的实现必须自己保证行锁 + 幂等 + 版本，接口不给
 * 调用方任何绕过它的余地。
 */
import type { Command, CommandEnvelope } from '../domain/commands.js';
import type { FarmRow } from './dto.js';

export interface PlayerRow { id: string; install_key_hmac: string }
export interface TokenRow { id: string; player_id: string; token_hash: string; last_used_at: number }

export interface CommandRecord {
  idempotency_key: string;
  payload_hash: string;
  outcome: 'applied' | 'rejected';
  result: unknown;
}

export type ApplyOutcome =
  | { kind: 'applied'; body: unknown }
  | { kind: 'rejected'; code: string; detail?: string }
  | { kind: 'replayed'; record: CommandRecord }
  | { kind: 'idempotency_mismatch' }
  | { kind: 'version_conflict'; farm: FarmRow }
  | { kind: 'version_mismatch' }
  | { kind: 'no_farm' };

export interface Store {
  /** 同 install_key 返回同一 player；每次调用签发新 token 并淘汰超出上限的旧 token。 */
  authAnonymous(installKeyHmac: string): Promise<{ player: PlayerRow; token: string }>;
  revokeToken(tokenHash: string): Promise<void>;
  revokeAllTokens(playerId: string): Promise<void>;
  rotateInstallKey(playerId: string, newHmac: string): Promise<void>;
  playerByToken(tokenHash: string, now: number): Promise<PlayerRow | null>;
  playerHmac(playerId: string): Promise<string | null>;

  farmByOwner(ownerId: string): Promise<FarmRow | null>;
  createFarm(args: {
    ownerId: string; idempotencyKey: string; payloadHash: string;
    regionId: string; layoutPatchId: string; blueprintRevision: number;
    build: () => FarmRow;
  }): Promise<{ kind: 'created' | 'replayed'; farm: FarmRow } | { kind: 'idempotency_mismatch' }>;

  /** 事务内：行锁 → 幂等查表 → 版本门控 → 采样时间 → reducer → 写日志与状态。 */
  applyCommand(ownerId: string, env: CommandEnvelope, cmd: Command): Promise<ApplyOutcome>;
}
