/** 内存 SocialStore：HTTP 层测试用；语义与 PgSocialStore 保持一致（social_conformance）。 */
import { decodeCursor, encodeCursor, relationOf, type FollowRow, type Page, type ProfilePatch, type ProfileRow, type SocialStore } from './social.js';

export class MemorySocialStore implements SocialStore {
  private profilesById = new Map<string, ProfileRow>();
  private follows: FollowRow[] = [];
  /** 哪些 user id 是存在的：follow 时校验 followee，模拟 PG 的外键。 */
  constructor(private readonly userExists: (id: string) => Promise<boolean> = async () => true) {}

  async ensureProfile(userId: string, displayName: string, now: number) {
    let p = this.profilesById.get(userId);
    if (!p) {
      p = { user_id: userId, handle: null, display_name: displayName, bio: '', avatar: null, following_visible: true, created_at: now, updated_at: now };
      this.profilesById.set(userId, p);
    }
    return { ...p };
  }
  async profile(userId: string) { const p = this.profilesById.get(userId); return p ? { ...p } : null; }
  async profileByHandle(handle: string) {
    for (const p of this.profilesById.values()) if (p.handle === handle) return { ...p };
    return null;
  }
  async updateProfile(userId: string, patch: ProfilePatch, now: number) {
    const p = this.profilesById.get(userId);
    if (!p) return null;
    if (patch.handle !== undefined && patch.handle !== null)
      for (const o of this.profilesById.values()) if (o.user_id !== userId && o.handle === patch.handle) return 'HANDLE_TAKEN';
    if (patch.display_name !== undefined) p.display_name = patch.display_name;
    if (patch.handle !== undefined) p.handle = patch.handle;
    if (patch.bio !== undefined) p.bio = patch.bio;
    if (patch.avatar !== undefined) p.avatar = patch.avatar;
    if (patch.following_visible !== undefined) p.following_visible = patch.following_visible;
    p.updated_at = now;
    return { ...p };
  }
  async profiles(userIds: string[]) {
    const out = new Map<string, ProfileRow>();
    for (const id of userIds) { const p = this.profilesById.get(id); if (p) out.set(id, { ...p }); }
    return out;
  }

  async follow(followerId: string, followeeId: string, now: number) {
    if (!(await this.userExists(followeeId))) return { created: false, missing: true };
    if (this.follows.some(f => f.follower_id === followerId && f.followee_id === followeeId)) return { created: false };
    this.follows.push({ follower_id: followerId, followee_id: followeeId, created_at: now, seen: false });
    return { created: true };
  }
  async unfollow(followerId: string, followeeId: string) {
    const before = this.follows.length;
    this.follows = this.follows.filter(f => !(f.follower_id === followerId && f.followee_id === followeeId));
    return { removed: this.follows.length < before };
  }
  async relation(a: string, b: string) {
    const following = this.follows.some(f => f.follower_id === a && f.followee_id === b);
    const followedBy = this.follows.some(f => f.follower_id === b && f.followee_id === a);
    return relationOf(following, followedBy);
  }
  async counts(userId: string) {
    return {
      followers: this.follows.filter(f => f.followee_id === userId).length,
      following: this.follows.filter(f => f.follower_id === userId).length,
    };
  }
  async mutualFollows(userId: string) {
    const out: string[] = [];
    for (const f of this.follows)
      if (f.follower_id === userId && this.follows.some(g => g.follower_id === f.followee_id && g.followee_id === userId)) out.push(f.followee_id);
    return out;
  }
  async following(userId: string, cursor: string | null, limit: number) {
    return this.page(this.follows.filter(f => f.follower_id === userId), f => f.followee_id, cursor, limit);
  }
  async followers(userId: string, cursor: string | null, limit: number) {
    return this.page(this.follows.filter(f => f.followee_id === userId), f => f.follower_id, cursor, limit);
  }
  private page(rows: FollowRow[], other: (f: FollowRow) => string, cursor: string | null, limit: number): Page<FollowRow> {
    const c = decodeCursor(cursor);
    const sorted = rows
      .filter(f => !c || f.created_at < c.createdAt || (f.created_at === c.createdAt && other(f) < c.id))
      .sort((x, y) => y.created_at - x.created_at || (other(y) < other(x) ? -1 : other(y) > other(x) ? 1 : 0));
    const items = sorted.slice(0, limit).map(f => ({ ...f }));
    const last = items[items.length - 1];
    return { items, next_cursor: sorted.length > limit && last ? encodeCursor(last.created_at, other(last)) : null };
  }
  async unseenFollowerCount(userId: string) {
    return this.follows.filter(f => f.followee_id === userId && !f.seen).length;
  }
  async markFollowersSeen(userId: string) {
    for (const f of this.follows) if (f.followee_id === userId) f.seen = true;
  }
  async deleteUser(userId: string) {
    this.profilesById.delete(userId);
    this.follows = this.follows.filter(f => f.follower_id !== userId && f.followee_id !== userId);
  }
}
