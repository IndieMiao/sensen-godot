/** PostgreSQL FeedStore。计数列在同一事务里增减；时间线是 posts ⋈ follows 的一条查询。 */
import type pg from 'pg';
import { decodeCursor, encodeCursor, type CommentRow, type FeedStore, type Page, type PostImage, type PostRow } from '../http/feed.js';

const isUuid = (s: string): boolean => /^[0-9a-f-]{36}$/i.test(s);
const rowToPost = (r: Record<string, unknown>): PostRow => ({
  id: r.id as string, author_id: r.author_id as string, text: r.text as string,
  images: (r.images as PostImage[]) ?? [], like_count: Number(r.like_count), comment_count: Number(r.comment_count),
  created_at: Number(r.created_at), deleted_at: r.deleted_at === null || r.deleted_at === undefined ? null : Number(r.deleted_at),
});
const rowToComment = (r: Record<string, unknown>): CommentRow => ({
  id: r.id as string, post_id: r.post_id as string, author_id: r.author_id as string, text: r.text as string,
  created_at: Number(r.created_at), deleted_at: r.deleted_at === null || r.deleted_at === undefined ? null : Number(r.deleted_at),
});

export class PgFeedStore implements FeedStore {
  constructor(private readonly pool: pg.Pool) {}

  async createPost(a: { id: string; authorId: string; idempotencyKey: string; text: string; images: PostImage[]; now: number }) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const ins = await client.query(
        `INSERT INTO posts (id, author_id, idempotency_key, text, images, like_count, comment_count, created_at, deleted_at)
         VALUES ($1, $2, $3, $4, $5::jsonb, 0, 0, $6, NULL)
         ON CONFLICT (author_id, idempotency_key) DO NOTHING RETURNING *`,
        [a.id, a.authorId, a.idempotencyKey, a.text, JSON.stringify(a.images), a.now]);
      if (ins.rowCount) { await client.query('COMMIT'); return { post: rowToPost(ins.rows[0]), created: true }; }
      const prev = await client.query('SELECT * FROM posts WHERE author_id = $1 AND idempotency_key = $2', [a.authorId, a.idempotencyKey]);
      await client.query('COMMIT');
      return { post: rowToPost(prev.rows[0]), created: false };
    } catch (e) { await client.query('ROLLBACK'); throw e; } finally { client.release(); }
  }
  async post(id: string) {
    if (!isUuid(id)) return null;
    const r = await this.pool.query('SELECT * FROM posts WHERE id = $1 AND deleted_at IS NULL', [id]);
    return r.rowCount ? rowToPost(r.rows[0]) : null;
  }
  async deletePost(id: string, authorId: string, now: number) {
    if (!isUuid(id)) return false;
    const r = await this.pool.query('UPDATE posts SET deleted_at = $3 WHERE id = $1 AND author_id = $2 AND deleted_at IS NULL', [id, authorId, now]);
    return (r.rowCount ?? 0) > 0;
  }
  async timeline(viewerId: string, cursor: string | null, limit: number) {
    const c = decodeCursor(cursor);
    const args: unknown[] = [viewerId, limit + 1];
    let where = `deleted_at IS NULL AND (author_id = $1 OR author_id IN (SELECT followee_id FROM follows WHERE follower_id = $1))`;
    if (c) { args.push(c.createdAt, c.id); where += ` AND (created_at, id) < ($3, $4::uuid)`; }
    const r = await this.pool.query(`SELECT * FROM posts WHERE ${where} ORDER BY created_at DESC, id DESC LIMIT $2`, args);
    return this.slice(r.rows.map(rowToPost), limit);
  }
  async byAuthor(authorId: string, cursor: string | null, limit: number) {
    if (!isUuid(authorId)) return { items: [], next_cursor: null };
    const c = decodeCursor(cursor);
    const args: unknown[] = [authorId, limit + 1];
    let where = `deleted_at IS NULL AND author_id = $1`;
    if (c) { args.push(c.createdAt, c.id); where += ` AND (created_at, id) < ($3, $4::uuid)`; }
    const r = await this.pool.query(`SELECT * FROM posts WHERE ${where} ORDER BY created_at DESC, id DESC LIMIT $2`, args);
    return this.slice(r.rows.map(rowToPost), limit);
  }
  private slice(rows: PostRow[], limit: number): Page<PostRow> {
    const items = rows.slice(0, limit);
    const last = items[items.length - 1];
    return { items, next_cursor: rows.length > limit && last ? encodeCursor(last.created_at, last.id) : null };
  }
  async like(postId: string, userId: string, now: number) {
    if (!isUuid(postId)) return { created: false };
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const p = await client.query('SELECT id FROM posts WHERE id = $1 AND deleted_at IS NULL FOR UPDATE', [postId]);
      if (!p.rowCount) { await client.query('ROLLBACK'); return { created: false }; }
      const ins = await client.query(
        'INSERT INTO post_likes (post_id, user_id, created_at) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING', [postId, userId, now]);
      if (ins.rowCount) await client.query('UPDATE posts SET like_count = like_count + 1 WHERE id = $1', [postId]);
      await client.query('COMMIT');
      return { created: (ins.rowCount ?? 0) > 0 };
    } catch (e) { await client.query('ROLLBACK'); throw e; } finally { client.release(); }
  }
  async unlike(postId: string, userId: string) {
    if (!isUuid(postId)) return { removed: false };
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const del = await client.query('DELETE FROM post_likes WHERE post_id = $1 AND user_id = $2', [postId, userId]);
      if (del.rowCount) await client.query('UPDATE posts SET like_count = greatest(like_count - 1, 0) WHERE id = $1', [postId]);
      await client.query('COMMIT');
      return { removed: (del.rowCount ?? 0) > 0 };
    } catch (e) { await client.query('ROLLBACK'); throw e; } finally { client.release(); }
  }
  async likedBy(postIds: string[], userId: string) {
    if (postIds.length === 0) return new Set<string>();
    const r = await this.pool.query('SELECT post_id FROM post_likes WHERE user_id = $1 AND post_id = ANY($2::uuid[])', [userId, postIds]);
    return new Set(r.rows.map(x => x.post_id as string));
  }
  async addComment(a: { id: string; postId: string; authorId: string; text: string; now: number }) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const ins = await client.query(
        `INSERT INTO post_comments (id, post_id, author_id, text, created_at, deleted_at) VALUES ($1, $2, $3, $4, $5, NULL) RETURNING *`,
        [a.id, a.postId, a.authorId, a.text, a.now]);
      await client.query('UPDATE posts SET comment_count = comment_count + 1 WHERE id = $1', [a.postId]);
      await client.query('COMMIT');
      return rowToComment(ins.rows[0]);
    } catch (e) { await client.query('ROLLBACK'); throw e; } finally { client.release(); }
  }
  async comment(id: string) {
    if (!isUuid(id)) return null;
    const r = await this.pool.query('SELECT * FROM post_comments WHERE id = $1 AND deleted_at IS NULL', [id]);
    return r.rowCount ? rowToComment(r.rows[0]) : null;
  }
  async comments(postId: string, cursor: string | null, limit: number): Promise<Page<CommentRow>> {
    if (!isUuid(postId)) return { items: [], next_cursor: null };
    const c = decodeCursor(cursor);
    const args: unknown[] = [postId, limit + 1];
    let where = `post_id = $1 AND deleted_at IS NULL`;
    if (c) { args.push(c.createdAt, c.id); where += ` AND (created_at, id) > ($3, $4::uuid)`; }
    const r = await this.pool.query(`SELECT * FROM post_comments WHERE ${where} ORDER BY created_at ASC, id ASC LIMIT $2`, args);
    const rows = r.rows.map(rowToComment);
    const items = rows.slice(0, limit);
    const last = items[items.length - 1];
    return { items, next_cursor: rows.length > limit && last ? encodeCursor(last.created_at, last.id) : null };
  }
  async deleteComment(id: string, now: number) {
    if (!isUuid(id)) return false;
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const upd = await client.query('UPDATE post_comments SET deleted_at = $2 WHERE id = $1 AND deleted_at IS NULL RETURNING post_id', [id, now]);
      if (upd.rowCount) await client.query('UPDATE posts SET comment_count = greatest(comment_count - 1, 0) WHERE id = $1', [upd.rows[0].post_id]);
      await client.query('COMMIT');
      return (upd.rowCount ?? 0) > 0;
    } catch (e) { await client.query('ROLLBACK'); throw e; } finally { client.release(); }
  }
  async deleteUser(userId: string) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      // 先把这个人在别人帖子上的点赞与评论从计数里扣掉，再让外键级联删行。
      await client.query(
        `UPDATE posts p SET like_count = greatest(p.like_count - l.n, 0)
           FROM (SELECT post_id, count(*) AS n FROM post_likes WHERE user_id = $1 GROUP BY post_id) l WHERE p.id = l.post_id`, [userId]);
      await client.query(
        `UPDATE posts p SET comment_count = greatest(p.comment_count - c.n, 0)
           FROM (SELECT post_id, count(*) AS n FROM post_comments WHERE author_id = $1 AND deleted_at IS NULL GROUP BY post_id) c WHERE p.id = c.post_id`, [userId]);
      await client.query('DELETE FROM post_likes WHERE user_id = $1', [userId]);
      await client.query('DELETE FROM post_comments WHERE author_id = $1', [userId]);
      await client.query('DELETE FROM posts WHERE author_id = $1', [userId]);
      await client.query('COMMIT');
    } catch (e) { await client.query('ROLLBACK'); throw e; } finally { client.release(); }
  }
  async exportUser(userId: string) {
    const [p, c] = await Promise.all([
      this.pool.query('SELECT * FROM posts WHERE author_id = $1 ORDER BY created_at, id', [userId]),
      this.pool.query('SELECT * FROM post_comments WHERE author_id = $1 ORDER BY created_at, id', [userId]),
    ]);
    return { posts: p.rows.map(rowToPost), comments: c.rows.map(rowToComment) };
  }
}
