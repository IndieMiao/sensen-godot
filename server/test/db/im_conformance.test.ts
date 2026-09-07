/** MemoryImStore 与 PgImStore 的一致性；PG 部分没有 TEST_DATABASE_URL 时跳过。 */
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import pg from 'pg';
import { randomUUID } from 'node:crypto';
import type { ImStore } from '../../src/http/im.js';
import { MemoryImStore } from '../../src/http/memory_im.js';
import { PgImStore } from '../../src/db/pg_im.js';
import { migrate, truncateAll } from '../../src/db/migrate.js';

const DSN = process.env.TEST_DATABASE_URL;
if (process.env.CI === '1' && !DSN) throw new Error('CI 下必须设置 TEST_DATABASE_URL');

let pool: pg.Pool | undefined;
beforeAll(async () => { if (!DSN) return; pool = new pg.Pool({ connectionString: DSN, max: 5 }); await migrate(pool); });
afterAll(async () => { await pool?.end(); });

const T0 = Date.UTC(2026, 8, 7, 12, 0, 0);
const OK = { status: 'approved' as const, categories: [] as string[] };
async function mkUser(): Promise<string> {
  const id = randomUUID();
  if (pool) await pool.query('INSERT INTO users (id, email, email_verified, created_at, last_seen_at) VALUES ($1, NULL, false, $2, $2)', [id, T0]);
  return id;
}
const impls: [string, () => Promise<ImStore>][] = [
  ['memory', async () => new MemoryImStore()],
  ...(DSN ? [['pg', async () => { await truncateAll(pool!); return new PgImStore(pool!); }] as [string, () => Promise<ImStore>]] : []),
];
const msg = (s: ImStore, conv: string, sender: string, clientId: string, now: number, text = clientId) =>
  s.appendMessage({ id: randomUUID(), conversationId: conv, senderId: sender, clientId, kind: 'text', body: { text }, now, moderation: OK });

describe.each(impls)('ImStore[%s]', (_name, make) => {
  let s: ImStore;
  beforeEach(async () => { s = await make(); });

  it('单聊找或建：两个方向同一会话，并发只建一个；成员两人', async () => {
    const a = await mkUser(); const b = await mkUser();
    const rs = await Promise.all([s.getOrCreateDm(a, b, T0), s.getOrCreateDm(b, a, T0), s.getOrCreateDm(a, b, T0)]);
    expect(new Set(rs.map(r => r.conversation.id)).size).toBe(1);
    expect(rs.filter(r => r.created)).toHaveLength(1);
    const c = rs[0].conversation;
    expect((await s.members(c.id)).map(m => m.user_id).sort()).toEqual([a, b].sort());
    expect(await s.isMember(c.id, a)).toBe(true);
    expect(await s.isMember(c.id, randomUUID())).toBe(false);
    expect(await s.conversation('garbage')).toBeNull();
  });

  it('消息：会话 seq 递增、扇出到每个成员的 inbox（用户级 seq）、client_id 重放不扇出；历史倒序分页', async () => {
    const a = await mkUser(); const b = await mkUser();
    const c = (await s.getOrCreateDm(a, b, T0)).conversation;
    const m1 = await msg(s, c.id, a, 'c1', T0);
    expect(m1.created).toBe(true); expect(m1.message.seq).toBe(1);
    expect(m1.events.map(e => [e.user_id, e.seq, e.type]).sort()).toEqual([[a, 1, 'message'], [b, 1, 'message']].sort());
    const dup = await msg(s, c.id, a, 'c1', T0 + 1, 'changed');
    expect(dup.created).toBe(false); expect(dup.message.id).toBe(m1.message.id); expect(dup.events).toEqual([]);
    const m2 = await msg(s, c.id, b, 'c2', T0 + 2);
    expect(m2.message.seq).toBe(2);
    expect((await s.conversation(c.id))!).toMatchObject({ last_seq: 2, last_message_at: T0 + 2 });
    expect((await s.eventsSince(a, 0, 10)).map(e => e.seq)).toEqual([1, 2]);
    expect(await s.latestSeq(a)).toBe(2);
    expect((await s.eventsSince(a, 1, 10)).map(e => e.payload.message_id)).toEqual([m2.message.id]);
    const m3 = await msg(s, c.id, a, 'c3', T0 + 3);
    expect((await s.messages(c.id, null, 2)).map(m => m.seq)).toEqual([3, 2]);
    expect((await s.messages(c.id, 2, 10)).map(m => m.seq)).toEqual([1]);
    expect(await s.dmExchange(c.id, a, b)).toEqual({ a_count: 2, b_count: 1 });
    expect(await s.deleteMessage(m3.message.id, T0 + 9)).toBe(true);
    expect(await s.deleteMessage(m3.message.id, T0 + 9)).toBe(false);
    expect((await s.message(m3.message.id))!).toMatchObject({ deleted_at: T0 + 9, body: {} });
    const list = await s.conversationsOf(b);
    expect(list).toHaveLength(1);
    expect(list[0].last_message!.seq).toBe(3);
  });

  it('已读：夹到 last_seq、不倒退；群：建 / 拉人 / 退；pushEvent；删号清空内容并撤单聊；导出', async () => {
    const a = await mkUser(); const b = await mkUser(); const c = await mkUser();
    const g = await s.createGroup({ id: randomUUID(), title: 'g', creatorId: a, memberIds: [b, a], now: T0 });
    expect((await s.members(g.id)).map(m => m.user_id).sort()).toEqual([a, b].sort());
    expect(await s.addMembers(g.id, [c, b], T0 + 1)).toEqual([c]);
    await msg(s, g.id, a, 'm1', T0 + 2); await msg(s, g.id, c, 'm2', T0 + 3);
    expect(await s.markRead(g.id, b, 99)).toEqual({ changed: true, last_read_seq: 2 });
    expect(await s.markRead(g.id, b, 1)).toEqual({ changed: false, last_read_seq: 2 });
    expect(await s.markRead(g.id, randomUUID(), 1)).toEqual({ changed: false, last_read_seq: 0 });
    const ev = await s.pushEvent([a, b], 'read', { conversation_id: g.id, user_id: b, seq: 2 }, T0 + 4);
    expect(ev.map(e => e.type)).toEqual(['read', 'read']);
    expect(await s.removeMember(g.id, b)).toBe(true);
    expect(await s.removeMember(g.id, b)).toBe(false);
    const d = (await s.getOrCreateDm(a, c, T0 + 5)).conversation;
    await msg(s, d.id, a, 'secret', T0 + 6);
    expect((await s.exportUser(a)).messages.map(m => m.body.text)).toEqual(['m1', 'secret']);
    await s.deleteUser(a);
    expect(await s.conversation(d.id)).toBeNull();
    expect((await s.conversationsOf(c)).map(x => x.conversation.id)).toEqual([g.id]);
    expect((await s.messages(g.id, null, 10)).find(m => m.sender_id === a)).toMatchObject({ body: {} });
    expect(await s.latestSeq(a)).toBe(0);
    expect((await s.exportUser(a)).messages).toEqual([]);
  });
});
