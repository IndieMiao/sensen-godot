/** MemoryFeedStore 与 PgFeedStore 的一致性；PG 部分没有 TEST_DATABASE_URL 时跳过，CI 下必须有。 */
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import pg from 'pg';
import { randomUUID } from 'node:crypto';
import type { FeedStore } from '../../src/http/feed.js';
import type { SocialStore } from '../../src/http/social.js';
import { MemoryFeedStore } from '../../src/http/memory_feed.js';
import { MemorySocialStore } from '../../src/http/memory_social.js';
import { PgFeedStore } from '../../src/db/pg_feed.js';
import { PgSocialStore } from '../../src/db/pg_social.js';
import { migrate, truncateAll } from '../../src/db/migrate.js';

const DSN = process.env.TEST_DATABASE_URL;
if (process.env.CI === '1' && !DSN) throw new Error('CI 下必须设置 TEST_DATABASE_URL');

let pool: pg.Pool | undefined;
beforeAll(async () => {
  if (!DSN) return;
  pool = new pg.Pool({ connectionString: DSN, max: 5 });
  await migrate(pool);
});
afterAll(async () => { await pool?.end(); });

const T0 = Date.UTC(2026, 8, 7, 10, 0, 0);
const known = new Set<string>();
async function mkUser(): Promise<string> {
  const id = randomUUID();
  known.add(id);
  if (pool) await pool.query('INSERT INTO users (id, email, email_verified, created_at, last_seen_at) VALUES ($1, NULL, false, $2, $2)', [id, T0]);
  return id;
}

type Impl = { feed: FeedStore; social: SocialStore };
const impls: [string, () => Promise<Impl>][] = [
  ['memory', async () => {
    const social = new MemorySocialStore(async id => known.has(id));
    const feed = new MemoryFeedStore(async v => (await social.following(v, null, 1000)).items.map(f => f.followee_id));
    return { feed, social };
  }],
  ...(DSN ? [['pg', async () => { await truncateAll(pool!); return { feed: new PgFeedStore(pool!), social: new PgSocialStore(pool!) }; }] as [string, () => Promise<Impl>]] : []),
];

const OK = { status: 'approved' as const, categories: [] as string[] };
const mkPost = (feed: FeedStore, authorId: string, key: string, now: number, text = key) =>
  feed.createPost({ id: randomUUID(), authorId, idempotencyKey: key, text, images: [], now, moderation: OK });

describe.each(impls)('FeedStore[%s]', (_name, make) => {
  let feed: FeedStore; let social: SocialStore;
  beforeEach(async () => { known.clear(); ({ feed, social } = await make()); });

  it('发帖幂等（同作者同 key）；不同作者同 key 各自一条；软删后取不到', async () => {
    const a = await mkUser(); const b = await mkUser();
    const p1 = await mkPost(feed, a, 'k', T0);
    const p2 = await mkPost(feed, a, 'k', T0 + 1, 'other');
    const p3 = await mkPost(feed, b, 'k', T0 + 2);
    expect(p1.created).toBe(true); expect(p2.created).toBe(false);
    expect(p2.post.id).toBe(p1.post.id); expect(p2.post.text).toBe('k');
    expect(p3.post.id).not.toBe(p1.post.id);
    expect(await feed.deletePost(p1.post.id, b, T0 + 3)).toBe(false); // 不是作者
    expect(await feed.deletePost(p1.post.id, a, T0 + 3)).toBe(true);
    expect(await feed.deletePost(p1.post.id, a, T0 + 4)).toBe(false);
    expect(await feed.post(p1.post.id)).toBeNull();
    expect(await feed.post('garbage')).toBeNull();
  });

  it('时间线 = 自己 + 关注的人，倒序键集分页；byAuthor 只看一个人', async () => {
    const me = await mkUser(); const f1 = await mkUser(); const other = await mkUser();
    await social.follow(me, f1, T0);
    const posts: string[] = [];
    for (let i = 0; i < 5; i++) posts.push((await mkPost(feed, i % 2 ? me : f1, `k${i}`, T0 + i)).post.id);
    await mkPost(feed, other, 'x', T0 + 10);
    const p1 = await feed.timeline(me, null, 2);
    expect(p1.items.map(p => p.id)).toEqual([posts[4], posts[3]]);
    const p2 = await feed.timeline(me, p1.next_cursor, 2);
    const p3 = await feed.timeline(me, p2.next_cursor, 2);
    expect([...p1.items, ...p2.items, ...p3.items].map(p => p.id)).toEqual([...posts].reverse());
    expect(p3.next_cursor).toBeNull();
    expect((await feed.byAuthor(me, null, 10)).items.map(p => p.id)).toEqual([posts[3], posts[1]]);
    expect((await feed.byAuthor('garbage', null, 10)).items).toEqual([]);
  });

  it('点赞幂等与计数；likedBy；评论正序分页与计数；删评论回退计数', async () => {
    const a = await mkUser(); const b = await mkUser();
    const p = (await mkPost(feed, a, 'k', T0)).post;
    expect(await feed.like(p.id, b, T0)).toEqual({ created: true });
    expect(await feed.like(p.id, b, T0)).toEqual({ created: false });
    expect(await feed.like(p.id, a, T0)).toEqual({ created: true });
    expect((await feed.post(p.id))!.like_count).toBe(2);
    expect(await feed.likedBy([p.id, randomUUID()], b)).toEqual(new Set([p.id]));
    expect(await feed.unlike(p.id, b)).toEqual({ removed: true });
    expect(await feed.unlike(p.id, b)).toEqual({ removed: false });
    expect((await feed.post(p.id))!.like_count).toBe(1);
    expect(await feed.like('garbage', b, T0)).toEqual({ created: false });
    const cs = [];
    for (let i = 0; i < 3; i++) cs.push(await feed.addComment({ id: randomUUID(), postId: p.id, authorId: b, text: `c${i}`, now: T0 + i, moderation: OK }));
    expect((await feed.post(p.id))!.comment_count).toBe(3);
    const l1 = await feed.comments(p.id, null, 2);
    expect(l1.items.map(c => c.text)).toEqual(['c0', 'c1']);
    const l2 = await feed.comments(p.id, l1.next_cursor, 2);
    expect(l2.items.map(c => c.text)).toEqual(['c2']);
    expect(l2.next_cursor).toBeNull();
    expect(await feed.deleteComment(cs[0].id, T0 + 9)).toBe(true);
    expect(await feed.deleteComment(cs[0].id, T0 + 9)).toBe(false);
    expect(await feed.comment(cs[0].id)).toBeNull();
    expect((await feed.post(p.id))!.comment_count).toBe(2);
  });

  it('删号：自己的帖子没了，别人帖子上的赞与评论计数回退；导出含帖子与评论', async () => {
    const a = await mkUser(); const b = await mkUser();
    const pa = (await mkPost(feed, a, 'a', T0)).post;
    const pb = (await mkPost(feed, b, 'b', T0)).post;
    await feed.like(pb.id, a, T0); await feed.like(pb.id, b, T0);
    await feed.addComment({ id: randomUUID(), postId: pb.id, authorId: a, text: 'hi', now: T0, moderation: OK });
    await feed.addComment({ id: randomUUID(), postId: pa.id, authorId: b, text: 'yo', now: T0, moderation: OK });
    const ex = await feed.exportUser(a);
    expect(ex.posts.map(p => p.id)).toEqual([pa.id]);
    expect(ex.comments.map(c => c.text)).toEqual(['hi']);
    await feed.deleteUser(a);
    expect(await feed.post(pa.id)).toBeNull();
    expect(await feed.post(pb.id)).toMatchObject({ like_count: 1, comment_count: 0 });
    // b 在 a 的帖子上的评论随帖子一起级联没了：账号都没了，帖子下的对话也没有落脚点。
    expect((await feed.exportUser(b)).comments).toHaveLength(0);
  });

  it('审核状态：pending 进队列且可见，hidden 只有作者的 byAuthor 能看，时间线排除，拉黑作者被剔除', async () => {
    const me = await mkUser(); const f = await mkUser(); const blocked = await mkUser();
    await social.follow(me, f, T0); await social.follow(me, blocked, T0);
    const pend = (await feed.createPost({ id: randomUUID(), authorId: f, idempotencyKey: 'p', text: 'p', images: [], now: T0 + 1, moderation: { status: 'pending', categories: [] } })).post;
    const hid = (await mkPost(feed, f, 'h', T0 + 2)).post;
    const fromBlocked = (await mkPost(feed, blocked, 'b', T0 + 3)).post;
    expect(await feed.setPostStatus(hid.id, 'hidden')).toBe(true);
    expect(await feed.setPostStatus(randomUUID(), 'hidden')).toBe(false);
    const tl = await feed.timeline(me, null, 10, [blocked]);
    expect(tl.items.map(p => p.id)).toEqual([pend.id]);
    expect((await feed.timeline(me, null, 10)).items.map(p => p.id)).toEqual([fromBlocked.id, pend.id]);
    expect((await feed.byAuthor(f, null, 10)).items.map(p => p.id)).toEqual([hid.id, pend.id]);
    const q = await feed.pendingReview(10);
    expect(q.posts.map(p => p.id)).toEqual([pend.id]);
    const c = await feed.addComment({ id: randomUUID(), postId: pend.id, authorId: me, text: 'c', now: T0 + 4, moderation: { status: 'pending', categories: ['x'] } });
    expect((await feed.pendingReview(10)).comments.map(x => x.id)).toEqual([c.id]);
    expect(await feed.setCommentStatus(c.id, 'hidden')).toBe(true);
    expect((await feed.comments(pend.id, null, 10)).items).toEqual([]);
    expect((await feed.post(pend.id))!.comment_count).toBe(1); // 隐藏不改计数，人工处置时再决定
  });
});
