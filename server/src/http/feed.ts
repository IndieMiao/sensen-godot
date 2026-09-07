/**
 * feed（D4-b）：图文动态 + 点赞 + 一级评论。08-30 调研 §6.4：Must = 图文 + 点赞，Should = 一级评论。
 *
 * 可见性照 Follow Feature Requirements §3.2：**关注了作者才看得到作者的动态**，密友与单向关注
 * 同一规则，不看关注方向的另一边。作者自己总能看自己的。时间线 = 我 + 我关注的人的动态，按发布
 * 时间倒序，键集分页。
 *
 * 图片这里只存引用（R2 对象 key，D4-c 接上传前客户端拿不到合法 key，所以先只能发纯文字）；
 * 服务端不解释 key，只限数量与长度。删除是软删（deleted_at）：E1 审核与举报要能回看。
 */
import type { AccountModule } from './accounts.js';
import { decodeCursor, encodeCursor } from './social.js';
import type { Page, Relation } from './social.js';

export type { Page };

export interface PostRow {
  id: string;
  author_id: string;
  text: string;
  images: PostImage[];
  like_count: number;
  comment_count: number;
  created_at: number;
  deleted_at: number | null;
}
export interface PostImage { key: string; w?: number; h?: number }
export interface CommentRow {
  id: string;
  post_id: string;
  author_id: string;
  text: string;
  created_at: number;
  deleted_at: number | null;
}

export interface FeedStore {
  /** 同一作者同一 idempotency_key 只建一条；重放返回 created=false 与原帖。 */
  createPost(args: { id: string; authorId: string; idempotencyKey: string; text: string; images: PostImage[]; now: number }):
    Promise<{ post: PostRow; created: boolean }>;
  post(id: string): Promise<PostRow | null>;
  /** 软删；只有作者能删——调用方校验。返回是否真的删了（已删 / 不存在 false）。 */
  deletePost(id: string, authorId: string, now: number): Promise<boolean>;
  /** 我 + 我关注的人的动态，倒序键集分页。 */
  timeline(viewerId: string, cursor: string | null, limit: number): Promise<Page<PostRow>>;
  /** 某人的动态（可见性由调用方判定）。 */
  byAuthor(authorId: string, cursor: string | null, limit: number): Promise<Page<PostRow>>;
  like(postId: string, userId: string, now: number): Promise<{ created: boolean }>;
  unlike(postId: string, userId: string): Promise<{ removed: boolean }>;
  likedBy(postIds: string[], userId: string): Promise<Set<string>>;
  addComment(args: { id: string; postId: string; authorId: string; text: string; now: number }): Promise<CommentRow>;
  comment(id: string): Promise<CommentRow | null>;
  /** 评论按时间正序（对话顺序），键集分页。 */
  comments(postId: string, cursor: string | null, limit: number): Promise<Page<CommentRow>>;
  /** 软删；作者或帖主可删——调用方校验。 */
  deleteComment(id: string, now: number): Promise<boolean>;
  /** 删号级联：帖子、评论、点赞全删（硬删：账号都没了，审核回看的对象也没了）。 */
  deleteUser(userId: string): Promise<void>;
  /** 导出：帖子与评论原文。 */
  exportUser(userId: string): Promise<{ posts: PostRow[]; comments: CommentRow[] }>;
}

export const POST_TEXT_MAX = 2000;
export const COMMENT_TEXT_MAX = 500;
export const POST_IMAGES_MAX = 9;
export const IMAGE_KEY_RE = /^[A-Za-z0-9_\-./]{1,200}$/;

const hasBadControl = (s: string): boolean => /[\x00-\x09\x0b-\x1f\x7f]/.test(s);

export type PostInput = { ok: true; text: string; images: PostImage[]; idempotencyKey: string } | { ok: false; field: string; reason: string };

export function validatePost(body: unknown): PostInput {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) return { ok: false, field: 'body', reason: 'OBJECT' };
  const b = body as Record<string, unknown>;
  if (typeof b.idempotency_key !== 'string' || b.idempotency_key.length === 0 || b.idempotency_key.length > 64)
    return { ok: false, field: 'idempotency_key', reason: 'FORMAT' };
  const text = typeof b.text === 'string' ? b.text.trim() : '';
  if (b.text !== undefined && typeof b.text !== 'string') return { ok: false, field: 'text', reason: 'STRING' };
  if ([...text].length > POST_TEXT_MAX || hasBadControl(text)) return { ok: false, field: 'text', reason: 'LENGTH' };
  const images: PostImage[] = [];
  if (b.images !== undefined) {
    if (!Array.isArray(b.images) || b.images.length > POST_IMAGES_MAX) return { ok: false, field: 'images', reason: 'COUNT' };
    for (const im of b.images) {
      if (typeof im !== 'object' || im === null) return { ok: false, field: 'images', reason: 'OBJECT' };
      const r = im as Record<string, unknown>;
      // 只认相对对象 key：`..` 与开头的 `/` 都是拼 URL 时的路径穿越。
      if (typeof r.key !== 'string' || !IMAGE_KEY_RE.test(r.key) || r.key.includes('..') || r.key.startsWith('/'))
        return { ok: false, field: 'images', reason: 'KEY' };
      const out: PostImage = { key: r.key };
      for (const dim of ['w', 'h'] as const) {
        if (r[dim] !== undefined) {
          if (!Number.isInteger(r[dim]) || (r[dim] as number) <= 0 || (r[dim] as number) > 20000) return { ok: false, field: 'images', reason: 'SIZE' };
          out[dim] = r[dim] as number;
        }
      }
      images.push(out);
    }
  }
  // 纯空帖没有意义：文字和图片至少有一样。
  if (text.length === 0 && images.length === 0) return { ok: false, field: 'text', reason: 'EMPTY' };
  return { ok: true, text, images, idempotencyKey: b.idempotency_key };
}

export function validateComment(body: unknown): { ok: true; text: string } | { ok: false; field: string; reason: string } {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) return { ok: false, field: 'body', reason: 'OBJECT' };
  const b = body as Record<string, unknown>;
  if (typeof b.text !== 'string') return { ok: false, field: 'text', reason: 'STRING' };
  const text = b.text.trim();
  if (text.length === 0 || [...text].length > COMMENT_TEXT_MAX || hasBadControl(text)) return { ok: false, field: 'text', reason: 'LENGTH' };
  return { ok: true, text };
}

/** 谁能看这条：作者本人，或关注了作者的人。 */
export const canSeePost = (post: PostRow, viewerId: string, relationToAuthor: Relation): boolean =>
  post.author_id === viewerId || relationToAuthor.following;

export interface AuthorCard { user_id: string; display_name: string; handle: string | null; avatar: Record<string, unknown> | null }

export function postView(p: PostRow, author: AuthorCard, liked: boolean) {
  return {
    id: p.id, author, text: p.text, images: p.images,
    like_count: p.like_count, comment_count: p.comment_count, liked, created_at: p.created_at,
  };
}

export function commentView(c: CommentRow, author: AuthorCard) {
  return { id: c.id, post_id: c.post_id, author, text: c.text, created_at: c.created_at };
}

export { decodeCursor, encodeCursor };

export function feedAccountModule(store: FeedStore): AccountModule {
  return {
    name: 'feed',
    export: (userId) => store.exportUser(userId),
    del: (userId) => store.deleteUser(userId),
  };
}
