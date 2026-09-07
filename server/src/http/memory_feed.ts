/** 内存 FeedStore：HTTP 层测试用；语义与 PgFeedStore 保持一致（feed_conformance）。 */
import { decodeCursor, encodeCursor, type CommentRow, type FeedStore, type Page, type PostImage, type PostRow } from './feed.js';

export class MemoryFeedStore implements FeedStore {
  private posts = new Map<string, PostRow>();
  private creations = new Map<string, string>(); // author:key -> post id
  private likes = new Set<string>();             // post:user
  private likeRows: { post_id: string; user_id: string; created_at: number }[] = [];
  private commentsById = new Map<string, CommentRow>();
  /** 时间线需要知道 viewer 关注谁：由调用方注入（测试里指向 MemorySocialStore）。 */
  constructor(private readonly followees: (viewerId: string) => Promise<string[]>) {}

  async createPost(a: { id: string; authorId: string; idempotencyKey: string; text: string; images: PostImage[]; now: number }) {
    const k = `${a.authorId}:${a.idempotencyKey}`;
    const existing = this.creations.get(k);
    if (existing) return { post: { ...this.posts.get(existing)! }, created: false };
    const post: PostRow = { id: a.id, author_id: a.authorId, text: a.text, images: a.images.map(i => ({ ...i })),
      like_count: 0, comment_count: 0, created_at: a.now, deleted_at: null };
    this.posts.set(post.id, post);
    this.creations.set(k, post.id);
    return { post: { ...post }, created: true };
  }
  async post(id: string) {
    const p = this.posts.get(id);
    return p && p.deleted_at === null ? { ...p } : null;
  }
  async deletePost(id: string, authorId: string, now: number) {
    const p = this.posts.get(id);
    if (!p || p.author_id !== authorId || p.deleted_at !== null) return false;
    p.deleted_at = now;
    return true;
  }
  async timeline(viewerId: string, cursor: string | null, limit: number) {
    const authors = new Set([viewerId, ...(await this.followees(viewerId))]);
    return this.page([...this.posts.values()].filter(p => p.deleted_at === null && authors.has(p.author_id)), cursor, limit);
  }
  async byAuthor(authorId: string, cursor: string | null, limit: number) {
    return this.page([...this.posts.values()].filter(p => p.deleted_at === null && p.author_id === authorId), cursor, limit);
  }
  private page(rows: PostRow[], cursor: string | null, limit: number): Page<PostRow> {
    const c = decodeCursor(cursor);
    const sorted = rows
      .filter(p => !c || p.created_at < c.createdAt || (p.created_at === c.createdAt && p.id < c.id))
      .sort((x, y) => y.created_at - x.created_at || (y.id < x.id ? -1 : y.id > x.id ? 1 : 0));
    const items = sorted.slice(0, limit).map(p => ({ ...p }));
    const last = items[items.length - 1];
    return { items, next_cursor: sorted.length > limit && last ? encodeCursor(last.created_at, last.id) : null };
  }
  async like(postId: string, userId: string, now: number) {
    const p = this.posts.get(postId);
    if (!p || p.deleted_at !== null) return { created: false };
    const k = `${postId}:${userId}`;
    if (this.likes.has(k)) return { created: false };
    this.likes.add(k);
    this.likeRows.push({ post_id: postId, user_id: userId, created_at: now });
    p.like_count += 1;
    return { created: true };
  }
  async unlike(postId: string, userId: string) {
    const k = `${postId}:${userId}`;
    if (!this.likes.delete(k)) return { removed: false };
    this.likeRows = this.likeRows.filter(l => !(l.post_id === postId && l.user_id === userId));
    const p = this.posts.get(postId);
    if (p) p.like_count -= 1;
    return { removed: true };
  }
  async likedBy(postIds: string[], userId: string) {
    return new Set(postIds.filter(id => this.likes.has(`${id}:${userId}`)));
  }
  async addComment(a: { id: string; postId: string; authorId: string; text: string; now: number }) {
    const c: CommentRow = { id: a.id, post_id: a.postId, author_id: a.authorId, text: a.text, created_at: a.now, deleted_at: null };
    this.commentsById.set(c.id, c);
    const p = this.posts.get(a.postId);
    if (p) p.comment_count += 1;
    return { ...c };
  }
  async comment(id: string) {
    const c = this.commentsById.get(id);
    return c && c.deleted_at === null ? { ...c } : null;
  }
  async comments(postId: string, cursor: string | null, limit: number): Promise<Page<CommentRow>> {
    const c = decodeCursor(cursor);
    const sorted = [...this.commentsById.values()]
      .filter(x => x.post_id === postId && x.deleted_at === null)
      .filter(x => !c || x.created_at > c.createdAt || (x.created_at === c.createdAt && x.id > c.id))
      .sort((x, y) => x.created_at - y.created_at || (x.id < y.id ? -1 : x.id > y.id ? 1 : 0));
    const items = sorted.slice(0, limit).map(x => ({ ...x }));
    const last = items[items.length - 1];
    return { items, next_cursor: sorted.length > limit && last ? encodeCursor(last.created_at, last.id) : null };
  }
  async deleteComment(id: string, now: number) {
    const c = this.commentsById.get(id);
    if (!c || c.deleted_at !== null) return false;
    c.deleted_at = now;
    const p = this.posts.get(c.post_id);
    if (p) p.comment_count -= 1;
    return true;
  }
  async deleteUser(userId: string) {
    for (const [id, p] of this.posts) if (p.author_id === userId) { this.posts.delete(id); for (const [cid, c] of this.commentsById) if (c.post_id === id) this.commentsById.delete(cid); }
    for (const [cid, c] of this.commentsById) if (c.author_id === userId) { this.commentsById.delete(cid); const p = this.posts.get(c.post_id); if (p && c.deleted_at === null) p.comment_count -= 1; }
    for (const l of this.likeRows.filter(l => l.user_id === userId)) { const p = this.posts.get(l.post_id); if (p) p.like_count -= 1; this.likes.delete(`${l.post_id}:${userId}`); }
    this.likeRows = this.likeRows.filter(l => l.user_id !== userId);
    for (const k of [...this.creations.keys()]) if (k.startsWith(`${userId}:`)) this.creations.delete(k);
  }
  async exportUser(userId: string) {
    return {
      posts: [...this.posts.values()].filter(p => p.author_id === userId).map(p => ({ ...p })),
      comments: [...this.commentsById.values()].filter(c => c.author_id === userId).map(c => ({ ...c })),
    };
  }
}
