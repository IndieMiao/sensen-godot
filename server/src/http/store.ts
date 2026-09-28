import type { FishingPresenceReader } from '../domain/fishing.js';
/**
 * 存储抽象。HTTP 层只认这个接口，Task 7 用 PostgreSQL 实现它，测试用内存实现。
 *
 * 这不是为了「可插拔数据库」，而是为了让 HTTP 层的测试不依赖真库，同时让**事务语义**
 * 成为接口的一部分：`applyCommand` 的实现必须自己保证行锁 + 幂等 + 版本，接口不给
 * 调用方任何绕过它的余地。
 */
import type { Command, CommandEnvelope } from '../domain/commands.js';
import type { FarmRow } from './dto.js';
import type { RealtimePersistence } from '../realtime/model.js';
import type { RelocationConfirm, RelocationDraft, RelocationOutcome } from '../domain/farm_relocation.js';

/** `user_id` 为空就是游客（install_key 匿名身份）：只能浏览，不能建农场或写入（决定 2）。 */
export interface PlayerRow { id: string; install_key_hmac: string; user_id?: string | null }

/** 账号（SGODOT-135）。每个账号恰好对应一个"账号玩家"行，农场与联机仍按 player id 走。 */
export interface UserRow {
  id: string;
  email: string | null;
  email_verified: boolean;
  password_hash: string | null;
  created_at: number;
  last_seen_at: number;
}

/** 删号墓碑：不带 FK、不留邮箱，只够证明"删过"和排 Apple revocation 队列。 */
export interface DeletionRecord {
  user_id: string;
  provider_uid: string;
  requested_at: number;
  source: 'app' | 'web';
  apple_revocation: 'pending' | 'n/a';
}

export type SaveCodeOutcome = { kind: 'saved' } | { kind: 'cooldown'; retry_after_ms: number };
export type ConsumeCodeOutcome = 'ok' | 'invalid' | 'expired' | 'locked';
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
  /** `farm` 是**当前**农场行：applied 的重放要用它重建视图，而不是回放一份过期快照。 */
  | { kind: 'replayed'; record: CommandRecord; farm: FarmRow }
  | { kind: 'idempotency_mismatch' }
  | { kind: 'version_conflict'; farm: FarmRow }
  | { kind: 'version_mismatch' }
  | { kind: 'no_farm' };

export interface Store extends RealtimePersistence {
  /** 同 install_key 返回同一 player；每次调用签发新 token 并淘汰超出上限的旧 token。 */
  authAnonymous(installKeyHmac: string): Promise<{ player: PlayerRow; token: string }>;
  revokeToken(tokenHash: string): Promise<void>;
  revokeAllTokens(playerId: string): Promise<void>;
  rotateInstallKey(playerId: string, newHmac: string): Promise<void>;
  playerByToken(tokenHash: string, now: number): Promise<PlayerRow | null>;
  playerHmac(playerId: string): Promise<string | null>;

  // —— 账号（SGODOT-135） ——
  /** 建邮箱账号（含 email 身份行）。邮箱已被占用返回 email_taken，不覆盖。 */
  createEmailUser(email: string, passwordHash: string, now: number): Promise<{ kind: 'created'; user: UserRow } | { kind: 'email_taken' }>;
  userByEmail(email: string): Promise<UserRow | null>;
  userById(userId: string): Promise<UserRow | null>;
  setUserPassword(userId: string, passwordHash: string): Promise<void>;
  markEmailVerified(userId: string): Promise<void>;
  /** 找或建账号玩家并签发 token（同 authAnonymous 的上限与淘汰规则）。 */
  authUser(userId: string, now: number): Promise<{ player: PlayerRow; token: string }>;
  /** 账号玩家的全部 token 撤销（改密、删号后用）。 */
  revokeUserTokens(userId: string): Promise<void>;
  saveEmailCode(email: string, purpose: string, codeHash: string, now: number, ttlMs: number, resendMs: number): Promise<SaveCodeOutcome>;
  /** 校验并消费验证码。错码计次，达上限作废。 */
  consumeEmailCode(email: string, purpose: string, codeHash: string, now: number, maxAttempts: number): Promise<ConsumeCodeOutcome>;
  /** 删账号：用户行、账号玩家及其农场 / token / 命令 / 快照 / 联机状态全部级联；写墓碑。 */
  deleteUser(userId: string, tombstone: DeletionRecord): Promise<boolean>;
  deletion(userId: string): Promise<DeletionRecord | null>;

  farmByOwner(ownerId: string): Promise<FarmRow | null>;
  saveRelocationPreview(ownerId: string, draft: RelocationDraft): Promise<{ code?: string }>;
  confirmFarmRelocation(ownerId: string, input: RelocationConfirm): Promise<RelocationOutcome>;
  createFarm(args: {
    ownerId: string; idempotencyKey: string; payloadHash: string;
    regionId: string; layoutPatchId: string; blueprintRevision: number;
    build: () => FarmRow | Promise<FarmRow>;
  }): Promise<{ kind: 'created' | 'replayed'; farm: FarmRow } | { kind: 'idempotency_mismatch' }>;

  /** 事务内：行锁 → 幂等查表 → 版本门控 → 采样时间 → reducer → 写日志与状态。 */
  applyCommand(ownerId: string, env: CommandEnvelope, cmd: Command, fishingPresence?: FishingPresenceReader): Promise<ApplyOutcome>;

  // —— G2 访问骨架 ——
  farmById(farmId: string): Promise<FarmRow | null>;
  /**
   * 同城开放访问的农场，排除调用者自己。按 created_at 排序而不是 updated_at：
   * 后者会把「谁刚上线」暴露给整个列表。
   */
  nearby(regionId: string, excludeOwnerId: string, limit: number): Promise<{ count: number; farms: FarmRow[] }>;
  /** 每座城市的公开农场数（城市气泡与选城推荐用）；只数 visit_access='anyone'，与 nearby 口径一致。 */
  cityFarmCounts(): Promise<Map<string, number>>;
  /**
   * 按 15 分钟槽取或建快照。同槽复用；跨槽用 build() 重算，内容不变则 revision 不动。
   * `build` 产出的 body 里 snapshot_revision / snapshot_taken_at 都是占位 0，调用方用返回值覆盖——
   * 时间戳进了 body，跨槽就永远"内容变了"。
   */
  snapshotGetOrCreate(farmId: string, slot: number, build: (current: FarmRow) => object):
    Promise<{ revision: number; taken_at: number; body: object; farm: FarmRow }>;
  /** 幂等写入系统农场（预置访客农场）。已存在就什么都不做。 */
  ensureSystemFarm(playerHmac: string, farm: FarmRow): Promise<void>;
}
