/**
 * 资料 + 关注（D4-a）。规则来自 Gensen_US/en-us/Gensen-follow-feature-requirements.md v1.2：
 * 单向关注、无需批准、不能关注自己、数量不限；互关 = 密友；取关只降级不通知；粉丝列表永远
 * 公开，「我关注的」列表与计数可用隐私开关对他人隐藏；新粉丝聚合成一个带未读的入口。
 *
 * 资料放独立表而不是 users：users 是账号（身份、邮箱），资料是用户自己编辑、别人能看的东西，
 * 两者的读写权限与生命周期都不同。
 */
import type { AccountModule } from './accounts.js';

export interface ProfileRow {
  user_id: string;
  /** 小写 3–20 位 [a-z0-9_]，全局唯一；可为空（还没起）。 */
  handle: string | null;
  display_name: string;
  bio: string;
  /** 客户端 AvatarConfig 的字典，服务端不解释，只限大小。 */
  avatar: Record<string, unknown> | null;
  following_visible: boolean;
  created_at: number;
  updated_at: number;
}

export interface FollowRow {
  follower_id: string;
  followee_id: string;
  created_at: number;
  /** 被关注者是否已在「新粉丝」页看过这条。 */
  seen: boolean;
}

export interface Relation {
  following: boolean;
  followed_by: boolean;
  close_friends: boolean;
}

export interface Page<T> { items: T[]; next_cursor: string | null }

export interface ProfilePatch {
  display_name?: string;
  handle?: string | null;
  bio?: string;
  avatar?: Record<string, unknown> | null;
  following_visible?: boolean;
}

export interface SocialStore {
  /** 没有资料就建一份（首次登录），有就原样返回。 */
  ensureProfile(userId: string, displayName: string, now: number): Promise<ProfileRow>;
  profile(userId: string): Promise<ProfileRow | null>;
  profileByHandle(handle: string): Promise<ProfileRow | null>;
  /** 返回 'HANDLE_TAKEN' 表示 handle 撞了别人；null 表示没有资料。 */
  updateProfile(userId: string, patch: ProfilePatch, now: number): Promise<ProfileRow | 'HANDLE_TAKEN' | null>;
  profiles(userIds: string[]): Promise<Map<string, ProfileRow>>;

  /** 幂等；followee 不存在返回 missing。调用方保证 follower ≠ followee。 */
  follow(followerId: string, followeeId: string, now: number): Promise<{ created: boolean; missing?: boolean }>;
  unfollow(followerId: string, followeeId: string): Promise<{ removed: boolean }>;
  relation(a: string, b: string): Promise<Relation>;
  counts(userId: string): Promise<{ followers: number; following: number }>;
  /** 按关注时间倒序，游标分页。 */
  following(userId: string, cursor: string | null, limit: number): Promise<Page<FollowRow>>;
  followers(userId: string, cursor: string | null, limit: number): Promise<Page<FollowRow>>;
  unseenFollowerCount(userId: string): Promise<number>;
  /** 互相关注的人（= 好友）。B5 位置只在好友之间可见。 */
  mutualFollows(userId: string): Promise<string[]>;
  markFollowersSeen(userId: string): Promise<void>;

  /** 删号级联：资料与两个方向的关注都删。 */
  deleteUser(userId: string): Promise<void>;
}

export const DISPLAY_NAME_MAX = 30;
export const BIO_MAX = 160;
export const HANDLE_RE = /^[a-z0-9_]{3,20}$/;
export const AVATAR_MAX_BYTES = 4096;
export const LIST_LIMIT_DEFAULT = 20;
export const LIST_LIMIT_MAX = 50;

/** 控制字符（含换行）一律不要：昵称里的换行会把列表撑坏，零宽/控制符是冒充别人的常用手段。 */
const hasControl = (s: string): boolean => /[\x00-\x1f\x7f]/.test(s);

export type PatchResult = { ok: true; patch: ProfilePatch } | { ok: false; field: string; reason: string };

/** 只校验给了的字段；没给的不动。 */
export function validatePatch(body: unknown): PatchResult {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) return { ok: false, field: 'body', reason: 'OBJECT' };
  const b = body as Record<string, unknown>;
  const patch: ProfilePatch = {};
  if ('display_name' in b) {
    if (typeof b.display_name !== 'string') return { ok: false, field: 'display_name', reason: 'STRING' };
    const v = b.display_name.trim();
    if (v.length < 1 || [...v].length > DISPLAY_NAME_MAX || hasControl(v))
      return { ok: false, field: 'display_name', reason: 'LENGTH' };
    patch.display_name = v;
  }
  if ('handle' in b) {
    if (b.handle === null) patch.handle = null;
    else {
      if (typeof b.handle !== 'string') return { ok: false, field: 'handle', reason: 'STRING' };
      const v = b.handle.trim().toLowerCase();
      if (!HANDLE_RE.test(v)) return { ok: false, field: 'handle', reason: 'FORMAT' };
      patch.handle = v;
    }
  }
  if ('bio' in b) {
    if (typeof b.bio !== 'string') return { ok: false, field: 'bio', reason: 'STRING' };
    const v = b.bio.trim();
    if ([...v].length > BIO_MAX || /[\x00-\x09\x0b-\x1f\x7f]/.test(v)) return { ok: false, field: 'bio', reason: 'LENGTH' };
    patch.bio = v;
  }
  if ('avatar' in b) {
    if (b.avatar === null) patch.avatar = null;
    else {
      if (typeof b.avatar !== 'object' || Array.isArray(b.avatar)) return { ok: false, field: 'avatar', reason: 'OBJECT' };
      if (Buffer.byteLength(JSON.stringify(b.avatar), 'utf8') > AVATAR_MAX_BYTES) return { ok: false, field: 'avatar', reason: 'SIZE' };
      patch.avatar = b.avatar as Record<string, unknown>;
    }
  }
  if ('following_visible' in b) {
    if (typeof b.following_visible !== 'boolean') return { ok: false, field: 'following_visible', reason: 'BOOLEAN' };
    patch.following_visible = b.following_visible;
  }
  return { ok: true, patch };
}

/** 首次登录的默认昵称：邮箱本地部分，没有邮箱就 user_ + uid 片段。 */
export function defaultDisplayName(email: string | undefined, uid: string): string {
  const local = (email ?? '').split('@')[0].trim();
  const base = local.length > 0 ? local : `user_${uid.replace(/[^a-zA-Z0-9]/g, '').slice(0, 6)}`;
  return [...base].slice(0, DISPLAY_NAME_MAX).join('');
}

export function clampLimit(raw: unknown): number {
  const n = Number(raw);
  if (!Number.isInteger(n) || n <= 0) return LIST_LIMIT_DEFAULT;
  return Math.min(n, LIST_LIMIT_MAX);
}

// —— 游标：created_at:user_id 的 base64url，纯粹是「从哪之后继续」，不带任何权限信息 ——
export const encodeCursor = (createdAt: number, id: string): string =>
  Buffer.from(`${createdAt}:${id}`, 'utf8').toString('base64url');
export function decodeCursor(c: string | null | undefined): { createdAt: number; id: string } | null {
  if (!c) return null;
  const s = Buffer.from(c, 'base64url').toString('utf8');
  const i = s.indexOf(':');
  if (i <= 0) return null;
  const createdAt = Number(s.slice(0, i));
  const id = s.slice(i + 1);
  if (!Number.isFinite(createdAt) || !/^[0-9a-f-]{36}$/i.test(id)) return null;
  return { createdAt, id };
}

// —— 视图 ——
export const relationOf = (following: boolean, followedBy: boolean): Relation =>
  ({ following, followed_by: followedBy, close_friends: following && followedBy });

export function ownProfileView(p: ProfileRow, counts: { followers: number; following: number }, unseen: number) {
  return {
    user_id: p.user_id, handle: p.handle, display_name: p.display_name, bio: p.bio, avatar: p.avatar,
    following_visible: p.following_visible,
    followers_count: counts.followers, following_count: counts.following,
    new_followers_unread: unseen, updated_at: p.updated_at,
  };
}

/** 别人看到的资料。following_count 只在开了可见或看自己时给。 */
export function publicProfileView(
  p: ProfileRow, counts: { followers: number; following: number }, relation: Relation, self: boolean,
) {
  const showFollowing = self || p.following_visible;
  return {
    user_id: p.user_id, handle: p.handle, display_name: p.display_name, bio: p.bio, avatar: p.avatar,
    followers_count: counts.followers,
    ...(showFollowing ? { following_count: counts.following } : {}),
    following_visible: p.following_visible,
    relation,
  };
}

export function userCard(p: ProfileRow | undefined, userId: string, relation: Relation, followedAt: number) {
  return {
    user_id: userId,
    display_name: p?.display_name ?? '',
    handle: p?.handle ?? null,
    avatar: p?.avatar ?? null,
    relation, followed_at: followedAt,
  };
}

/** 删号级联与数据导出的登记项。 */
export function socialAccountModule(store: SocialStore): AccountModule {
  return {
    name: 'social',
    export: async (userId) => {
      const profile = await store.profile(userId);
      const following: string[] = [];
      const followers: string[] = [];
      let cursor: string | null = null;
      do {
        const page = await store.following(userId, cursor, LIST_LIMIT_MAX);
        following.push(...page.items.map(f => f.followee_id));
        cursor = page.next_cursor;
      } while (cursor);
      cursor = null;
      do {
        const page = await store.followers(userId, cursor, LIST_LIMIT_MAX);
        followers.push(...page.items.map(f => f.follower_id));
        cursor = page.next_cursor;
      } while (cursor);
      return { profile, following, followers };
    },
    del: (userId) => store.deleteUser(userId),
  };
}
