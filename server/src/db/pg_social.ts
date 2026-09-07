/** PostgreSQL SocialStore。列表用 (created_at, 对方 id) 键集分页，不用 OFFSET。 */
import type pg from 'pg';
import { decodeCursor, encodeCursor, relationOf, type FollowRow, type Page, type ProfilePatch, type ProfileRow, type SocialStore } from '../http/social.js';

const rowToProfile = (r: Record<string, unknown>): ProfileRow => ({
  user_id: r.user_id as string,
  handle: (r.handle as string | null) ?? null,
  display_name: r.display_name as string,
  bio: r.bio as string,
  avatar: (r.avatar as Record<string, unknown> | null) ?? null,
  following_visible: r.following_visible as boolean,
  created_at: Number(r.created_at),
  updated_at: Number(r.updated_at),
});
const rowToFollow = (r: Record<string, unknown>): FollowRow => ({
  follower_id: r.follower_id as string, followee_id: r.followee_id as string,
  created_at: Number(r.created_at), seen: r.seen as boolean,
});
const isUuid = (s: string): boolean => /^[0-9a-f-]{36}$/i.test(s);

export class PgSocialStore implements SocialStore {
  constructor(private readonly pool: pg.Pool) {}

  async ensureProfile(userId: string, displayName: string, now: number) {
    const r = await this.pool.query(
      `INSERT INTO profiles (user_id, handle, display_name, bio, avatar, following_visible, created_at, updated_at)
       VALUES ($1, NULL, $2, '', NULL, true, $3, $3)
       ON CONFLICT (user_id) DO UPDATE SET user_id = EXCLUDED.user_id
       RETURNING *`, [userId, displayName, now]);
    return rowToProfile(r.rows[0]);
  }
  async profile(userId: string) {
    if (!isUuid(userId)) return null;
    const r = await this.pool.query('SELECT * FROM profiles WHERE user_id = $1', [userId]);
    return r.rowCount ? rowToProfile(r.rows[0]) : null;
  }
  async profileByHandle(handle: string) {
    const r = await this.pool.query('SELECT * FROM profiles WHERE handle = $1', [handle]);
    return r.rowCount ? rowToProfile(r.rows[0]) : null;
  }
  async updateProfile(userId: string, patch: ProfilePatch, now: number) {
    const sets: string[] = ['updated_at = $2'];
    const args: unknown[] = [userId, now];
    const put = (col: string, v: unknown) => { args.push(v); sets.push(`${col} = $${args.length}`); };
    if (patch.display_name !== undefined) put('display_name', patch.display_name);
    if (patch.handle !== undefined) put('handle', patch.handle);
    if (patch.bio !== undefined) put('bio', patch.bio);
    if (patch.avatar !== undefined) put('avatar', patch.avatar === null ? null : JSON.stringify(patch.avatar));
    if (patch.following_visible !== undefined) put('following_visible', patch.following_visible);
    try {
      const r = await this.pool.query(`UPDATE profiles SET ${sets.join(', ')} WHERE user_id = $1 RETURNING *`, args);
      return r.rowCount ? rowToProfile(r.rows[0]) : null;
    } catch (e) {
      if ((e as { code?: string }).code === '23505') return 'HANDLE_TAKEN';
      throw e;
    }
  }
  async profiles(userIds: string[]) {
    const out = new Map<string, ProfileRow>();
    if (userIds.length === 0) return out;
    const r = await this.pool.query('SELECT * FROM profiles WHERE user_id = ANY($1::uuid[])', [userIds]);
    for (const row of r.rows) { const p = rowToProfile(row); out.set(p.user_id, p); }
    return out;
  }

  async follow(followerId: string, followeeId: string, now: number) {
    if (!isUuid(followeeId)) return { created: false, missing: true };
    try {
      const r = await this.pool.query(
        `INSERT INTO follows (follower_id, followee_id, created_at, seen) VALUES ($1, $2, $3, false)
         ON CONFLICT DO NOTHING`, [followerId, followeeId, now]);
      return { created: (r.rowCount ?? 0) > 0 };
    } catch (e) {
      if ((e as { code?: string }).code === '23503') return { created: false, missing: true };
      throw e;
    }
  }
  async unfollow(followerId: string, followeeId: string) {
    if (!isUuid(followeeId)) return { removed: false };
    const r = await this.pool.query('DELETE FROM follows WHERE follower_id = $1 AND followee_id = $2', [followerId, followeeId]);
    return { removed: (r.rowCount ?? 0) > 0 };
  }
  async relation(a: string, b: string) {
    if (!isUuid(a) || !isUuid(b)) return relationOf(false, false);
    const r = await this.pool.query(
      `SELECT EXISTS(SELECT 1 FROM follows WHERE follower_id = $1 AND followee_id = $2) AS following,
              EXISTS(SELECT 1 FROM follows WHERE follower_id = $2 AND followee_id = $1) AS followed_by`, [a, b]);
    return relationOf(r.rows[0].following as boolean, r.rows[0].followed_by as boolean);
  }
  async counts(userId: string) {
    const r = await this.pool.query(
      `SELECT (SELECT count(*) FROM follows WHERE followee_id = $1)::int AS followers,
              (SELECT count(*) FROM follows WHERE follower_id = $1)::int AS following`, [userId]);
    return { followers: r.rows[0].followers as number, following: r.rows[0].following as number };
  }
  async mutualFollows(userId: string) {
    if (!isUuid(userId)) return [];
    const r = await this.pool.query(
      `SELECT a.followee_id FROM follows a
         JOIN follows b ON b.follower_id = a.followee_id AND b.followee_id = a.follower_id
        WHERE a.follower_id = $1`, [userId]);
    return r.rows.map(x => x.followee_id as string);
  }
  async following(userId: string, cursor: string | null, limit: number) {
    return this.page('follower_id', 'followee_id', userId, cursor, limit);
  }
  async followers(userId: string, cursor: string | null, limit: number) {
    return this.page('followee_id', 'follower_id', userId, cursor, limit);
  }
  private async page(me: string, other: string, userId: string, cursor: string | null, limit: number): Promise<Page<FollowRow>> {
    const c = decodeCursor(cursor);
    const args: unknown[] = [userId, limit + 1];
    let where = `${me} = $1`;
    if (c) { args.push(c.createdAt, c.id); where += ` AND (created_at, ${other}) < ($3, $4::uuid)`; }
    const r = await this.pool.query(
      `SELECT * FROM follows WHERE ${where} ORDER BY created_at DESC, ${other} DESC LIMIT $2`, args);
    const rows = r.rows.map(rowToFollow);
    const items = rows.slice(0, limit);
    const last = items[items.length - 1];
    const lastOther = last ? (other === 'followee_id' ? last.followee_id : last.follower_id) : '';
    return { items, next_cursor: rows.length > limit && last ? encodeCursor(last.created_at, lastOther) : null };
  }
  async unseenFollowerCount(userId: string) {
    const r = await this.pool.query('SELECT count(*)::int AS n FROM follows WHERE followee_id = $1 AND seen = false', [userId]);
    return r.rows[0].n as number;
  }
  async markFollowersSeen(userId: string) {
    await this.pool.query('UPDATE follows SET seen = true WHERE followee_id = $1 AND seen = false', [userId]);
  }
  async deleteUser(userId: string) {
    await this.pool.query('DELETE FROM follows WHERE follower_id = $1 OR followee_id = $1', [userId]);
    await this.pool.query('DELETE FROM profiles WHERE user_id = $1', [userId]);
  }
}
