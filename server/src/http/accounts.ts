/**
 * 账号存储抽象（D2 / SGODOT-76）。
 *
 * 社交主线的用户主键是自有的 uuid，Firebase uid 只是一条「身份」记录——将来换掉
 * Firebase 或者一个人绑多个登录方式，都不用动业务表里的 user_id。
 *
 * `players` 是农场分支的匿名玩家，两者暂不关联；合并留给农场并回主线时再做。
 */
import type { FirebaseIdentity } from './firebase_token.js';

export interface UserRow {
  id: string;
  email: string | null;
  email_verified: boolean;
  created_at: number;
  last_seen_at: number;
}

export interface IdentityRow {
  provider: 'firebase';
  provider_uid: string;
  user_id: string;
  sign_in_provider: string | null;
  created_at: number;
}

/**
 * 删号墓碑。不带 FK（用户行已删），只留 uid 与时间：够证明「删过」和排 Apple
 * revocation 的队列，不留邮箱等 PII。
 */
export interface DeletionRecord {
  user_id: string;
  provider_uid: string;
  requested_at: number;
  source: 'app' | 'web';
  apple_revocation: 'pending' | 'n/a';
}

export interface AccountStore {
  /**
   * 按 Firebase uid 找或建用户。已存在则刷新 last_seen_at 与邮箱字段（邮箱验证状态以
   * Firebase 为准）；不存在则建。并发的首次登录必须落到同一个用户。
   */
  signIn(identity: FirebaseIdentity, now: number): Promise<{ user: UserRow; created: boolean }>;
  userByFirebaseUid(uid: string): Promise<UserRow | null>;
  userById(id: string): Promise<UserRow | null>;
  identitiesOf(userId: string): Promise<IdentityRow[]>;
  /** 删用户行（身份级联）并写墓碑。用户不存在返回 false。 */
  deleteUser(userId: string, tombstone: DeletionRecord): Promise<boolean>;
  deletion(userId: string): Promise<DeletionRecord | null>;
}

/**
 * 后续模块（资料 / IM / feed / 关注 / 位置 / 推送 token / 举报）在这里登记自己的
 * 导出与级联删除。删号时按登记顺序逐个跑 `del`，任一失败整个删号返回 500 且用户
 * 保留——宁可让用户再点一次，也不能留下一半数据然后说「已删除」。
 */
export interface AccountModule {
  name: string;
  export?: (userId: string) => Promise<unknown>;
  del?: (userId: string) => Promise<void>;
}

export function userView(u: UserRow) {
  return {
    user_id: u.id,
    email: u.email,
    email_verified: u.email_verified,
    created_at: u.created_at,
    last_seen_at: u.last_seen_at,
  };
}

/** Apple 要求删号时撤销其 token；没拿到 Apple client secret 前先记 pending，队列稍后处理。 */
export const appleRevocationFor = (signInProvider: string | undefined): DeletionRecord['apple_revocation'] =>
  signInProvider === 'apple.com' ? 'pending' : 'n/a';
