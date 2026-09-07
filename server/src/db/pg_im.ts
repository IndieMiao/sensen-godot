/** PostgreSQL ImStore。appendMessage 在一个事务里：锁会话行 → 分配 seq → 写消息 → 扇出成员 inbox。 */
import { randomUUID } from 'node:crypto';
import type pg from 'pg';
import { pairKey, type ConversationRow, type ImStore, type MemberRow, type MessageRow, type UserEvent } from '../http/im.js';
import type { Moderation } from '../http/feed.js';
import type { ModerationStatus } from '../http/moderation.js';

const isUuid = (s: string): boolean => /^[0-9a-f-]{36}$/i.test(s);
const rowToConv = (r: Record<string, unknown>): ConversationRow => ({
  id: r.id as string, kind: r.kind as ConversationRow['kind'], title: (r.title as string | null) ?? null, created_by: r.created_by as string,
  created_at: Number(r.created_at), last_seq: Number(r.last_seq), last_message_at: r.last_message_at == null ? null : Number(r.last_message_at),
});
const rowToMember = (r: Record<string, unknown>): MemberRow => ({
  conversation_id: r.conversation_id as string, user_id: r.user_id as string, joined_at: Number(r.joined_at), last_read_seq: Number(r.last_read_seq),
});
const rowToMsg = (r: Record<string, unknown>): MessageRow => ({
  id: r.id as string, conversation_id: r.conversation_id as string, seq: Number(r.seq), sender_id: r.sender_id as string, client_id: r.client_id as string,
  kind: r.kind as MessageRow['kind'], body: (r.body as Record<string, unknown>) ?? {}, created_at: Number(r.created_at),
  deleted_at: r.deleted_at == null ? null : Number(r.deleted_at),
  moderation_status: (r.moderation_status as ModerationStatus) ?? 'approved', moderation_categories: (r.moderation_categories as string[]) ?? [],
});
const rowToEvent = (r: Record<string, unknown>): UserEvent => ({
  user_id: r.user_id as string, seq: Number(r.seq), type: r.type as string, payload: (r.payload as Record<string, unknown>) ?? {}, created_at: Number(r.created_at),
});

export class PgImStore implements ImStore {
  constructor(private readonly pool: pg.Pool) {}

  async getOrCreateDm(a: string, b: string, now: number) {
    const [lo, hi] = pairKey(a, b);
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const found = await client.query('SELECT conversation_id FROM dm_pairs WHERE user_lo = $1 AND user_hi = $2 FOR UPDATE', [lo, hi]);
      if (found.rowCount) {
        const c = await client.query('SELECT * FROM conversations WHERE id = $1', [found.rows[0].conversation_id]);
        await client.query('COMMIT');
        return { conversation: rowToConv(c.rows[0]), created: false };
      }
      const id = randomUUID();
      const ins = await client.query(
        `INSERT INTO conversations (id, kind, title, created_by, created_at, last_seq, last_message_at) VALUES ($1, 'dm', NULL, $2, $3, 0, NULL) RETURNING *`, [id, a, now]);
      const pair = await client.query('INSERT INTO dm_pairs (user_lo, user_hi, conversation_id) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING', [lo, hi, id]);
      if (!pair.rowCount) {
        // 并发建同一对：让位给赢家。
        await client.query('DELETE FROM conversations WHERE id = $1', [id]);
        const w = await client.query('SELECT c.* FROM dm_pairs p JOIN conversations c ON c.id = p.conversation_id WHERE p.user_lo = $1 AND p.user_hi = $2', [lo, hi]);
        await client.query('COMMIT');
        return { conversation: rowToConv(w.rows[0]), created: false };
      }
      for (const u of [a, b]) await client.query('INSERT INTO conversation_members (conversation_id, user_id, joined_at, last_read_seq) VALUES ($1, $2, $3, 0)', [id, u, now]);
      await client.query('COMMIT');
      return { conversation: rowToConv(ins.rows[0]), created: true };
    } catch (e) { await client.query('ROLLBACK'); throw e; } finally { client.release(); }
  }
  async createGroup(a: { id: string; title: string; creatorId: string; memberIds: string[]; now: number }) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const ins = await client.query(
        `INSERT INTO conversations (id, kind, title, created_by, created_at, last_seq, last_message_at) VALUES ($1, 'group', $2, $3, $4, 0, NULL) RETURNING *`, [a.id, a.title, a.creatorId, a.now]);
      for (const u of [a.creatorId, ...a.memberIds.filter(x => x !== a.creatorId)])
        await client.query('INSERT INTO conversation_members (conversation_id, user_id, joined_at, last_read_seq) VALUES ($1, $2, $3, 0) ON CONFLICT DO NOTHING', [a.id, u, a.now]);
      await client.query('COMMIT');
      return rowToConv(ins.rows[0]);
    } catch (e) { await client.query('ROLLBACK'); throw e; } finally { client.release(); }
  }
  async conversation(id: string) {
    if (!isUuid(id)) return null;
    const r = await this.pool.query('SELECT * FROM conversations WHERE id = $1', [id]);
    return r.rowCount ? rowToConv(r.rows[0]) : null;
  }
  async members(conversationId: string) {
    if (!isUuid(conversationId)) return [];
    const r = await this.pool.query('SELECT * FROM conversation_members WHERE conversation_id = $1 ORDER BY joined_at, user_id', [conversationId]);
    return r.rows.map(rowToMember);
  }
  async isMember(conversationId: string, userId: string) {
    if (!isUuid(conversationId)) return false;
    const r = await this.pool.query('SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2', [conversationId, userId]);
    return (r.rowCount ?? 0) > 0;
  }
  async addMembers(conversationId: string, userIds: string[], now: number) {
    const added: string[] = [];
    for (const u of userIds) {
      const r = await this.pool.query('INSERT INTO conversation_members (conversation_id, user_id, joined_at, last_read_seq) VALUES ($1, $2, $3, 0) ON CONFLICT DO NOTHING', [conversationId, u, now]);
      if (r.rowCount) added.push(u);
    }
    return added;
  }
  async removeMember(conversationId: string, userId: string) {
    const r = await this.pool.query('DELETE FROM conversation_members WHERE conversation_id = $1 AND user_id = $2', [conversationId, userId]);
    return (r.rowCount ?? 0) > 0;
  }
  async conversationsOf(userId: string) {
    const r = await this.pool.query(
      `SELECT c.*, m.joined_at AS m_joined_at, m.last_read_seq AS m_last_read_seq,
              (SELECT row_to_json(x) FROM messages x WHERE x.conversation_id = c.id ORDER BY x.seq DESC LIMIT 1) AS last
         FROM conversation_members m JOIN conversations c ON c.id = m.conversation_id
        WHERE m.user_id = $1
        ORDER BY coalesce(c.last_message_at, c.created_at) DESC, c.id DESC`, [userId]);
    return r.rows.map(row => ({
      conversation: rowToConv(row),
      member: { conversation_id: row.id as string, user_id: userId, joined_at: Number(row.m_joined_at), last_read_seq: Number(row.m_last_read_seq) },
      last_message: row.last ? rowToMsg(row.last as Record<string, unknown>) : null,
    }));
  }
  private async fanOut(client: pg.PoolClient, userIds: string[], type: string, payload: Record<string, unknown>, now: number): Promise<UserEvent[]> {
    const out: UserEvent[] = [];
    for (const u of userIds) {
      const s = await client.query(
        `INSERT INTO user_event_seq (user_id, next_seq) VALUES ($1, 1)
         ON CONFLICT (user_id) DO UPDATE SET next_seq = user_event_seq.next_seq + 1 RETURNING next_seq`, [u]);
      const seq = Number(s.rows[0].next_seq);
      await client.query('INSERT INTO user_events (user_id, seq, type, payload, created_at) VALUES ($1, $2, $3, $4::jsonb, $5)', [u, seq, type, JSON.stringify(payload), now]);
      out.push({ user_id: u, seq, type, payload, created_at: now });
    }
    return out;
  }
  async appendMessage(a: { id: string; conversationId: string; senderId: string; clientId: string; kind: MessageRow['kind']; body: Record<string, unknown>; now: number; moderation: Moderation }) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const c = await client.query('SELECT * FROM conversations WHERE id = $1 FOR UPDATE', [a.conversationId]);
      const dup = await client.query('SELECT * FROM messages WHERE conversation_id = $1 AND sender_id = $2 AND client_id = $3', [a.conversationId, a.senderId, a.clientId]);
      if (dup.rowCount) { await client.query('COMMIT'); return { message: rowToMsg(dup.rows[0]), created: false, events: [] }; }
      const seq = Number(c.rows[0].last_seq) + 1;
      const ins = await client.query(
        `INSERT INTO messages (id, conversation_id, seq, sender_id, client_id, kind, body, created_at, deleted_at, moderation_status, moderation_categories)
         VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8, NULL, $9, $10::jsonb) RETURNING *`,
        [a.id, a.conversationId, seq, a.senderId, a.clientId, a.kind, JSON.stringify(a.body), a.now, a.moderation.status, JSON.stringify(a.moderation.categories)]);
      await client.query('UPDATE conversations SET last_seq = $2, last_message_at = $3 WHERE id = $1', [a.conversationId, seq, a.now]);
      const members = await client.query('SELECT user_id FROM conversation_members WHERE conversation_id = $1 ORDER BY joined_at, user_id', [a.conversationId]);
      const m = rowToMsg(ins.rows[0]);
      const events = await this.fanOut(client, members.rows.map(x => x.user_id as string), 'message',
        { conversation_id: m.conversation_id, message_id: m.id, message_seq: m.seq, sender_id: m.sender_id, kind: m.kind, body: m.body, created_at: m.created_at }, a.now);
      await client.query('COMMIT');
      return { message: m, created: true, events };
    } catch (e) { await client.query('ROLLBACK'); throw e; } finally { client.release(); }
  }
  async messages(conversationId: string, beforeSeq: number | null, limit: number) {
    if (!isUuid(conversationId)) return [];
    const args: unknown[] = [conversationId, limit];
    let where = 'conversation_id = $1';
    if (beforeSeq !== null) { args.push(beforeSeq); where += ' AND seq < $3'; }
    const r = await this.pool.query(`SELECT * FROM messages WHERE ${where} ORDER BY seq DESC LIMIT $2`, args);
    return r.rows.map(rowToMsg);
  }
  async message(id: string) {
    if (!isUuid(id)) return null;
    const r = await this.pool.query('SELECT * FROM messages WHERE id = $1', [id]);
    return r.rowCount ? rowToMsg(r.rows[0]) : null;
  }
  async deleteMessage(id: string, now: number) {
    if (!isUuid(id)) return false;
    const r = await this.pool.query(`UPDATE messages SET deleted_at = $2, body = '{}'::jsonb WHERE id = $1 AND deleted_at IS NULL`, [id, now]);
    return (r.rowCount ?? 0) > 0;
  }
  async markRead(conversationId: string, userId: string, seq: number) {
    if (!isUuid(conversationId)) return { changed: false, last_read_seq: 0 };
    const r = await this.pool.query(
      `UPDATE conversation_members m SET last_read_seq = least($3, c.last_seq)
         FROM conversations c WHERE c.id = m.conversation_id AND m.conversation_id = $1 AND m.user_id = $2 AND least($3, c.last_seq) > m.last_read_seq
       RETURNING m.last_read_seq`, [conversationId, userId, seq]);
    if (r.rowCount) return { changed: true, last_read_seq: Number(r.rows[0].last_read_seq) };
    const cur = await this.pool.query('SELECT last_read_seq FROM conversation_members WHERE conversation_id = $1 AND user_id = $2', [conversationId, userId]);
    return { changed: false, last_read_seq: cur.rowCount ? Number(cur.rows[0].last_read_seq) : 0 };
  }
  async dmExchange(conversationId: string, a: string, b: string) {
    const r = await this.pool.query(
      `SELECT count(*) FILTER (WHERE sender_id = $2)::int AS a_count, count(*) FILTER (WHERE sender_id = $3)::int AS b_count FROM messages WHERE conversation_id = $1`,
      [conversationId, a, b]);
    return { a_count: r.rows[0].a_count as number, b_count: r.rows[0].b_count as number };
  }
  async pushEvent(userIds: string[], type: string, payload: Record<string, unknown>, now: number) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const out = await this.fanOut(client, userIds, type, payload, now);
      await client.query('COMMIT');
      return out;
    } catch (e) { await client.query('ROLLBACK'); throw e; } finally { client.release(); }
  }
  async eventsSince(userId: string, sinceSeq: number, limit: number) {
    const r = await this.pool.query('SELECT * FROM user_events WHERE user_id = $1 AND seq > $2 ORDER BY seq LIMIT $3', [userId, sinceSeq, limit]);
    return r.rows.map(rowToEvent);
  }
  async latestSeq(userId: string) {
    const r = await this.pool.query('SELECT next_seq FROM user_event_seq WHERE user_id = $1', [userId]);
    return r.rowCount ? Number(r.rows[0].next_seq) : 0;
  }
  async deleteUser(userId: string) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(`UPDATE messages SET deleted_at = $2, body = '{}'::jsonb WHERE sender_id = $1 AND deleted_at IS NULL`, [userId, Date.now()]);
      await client.query('DELETE FROM conversation_members WHERE user_id = $1', [userId]);
      // 单聊整体删掉：账号没了，对方那边的会话也没有落脚点；群聊保留（消息已清空内容）。
      await client.query('DELETE FROM conversations WHERE id IN (SELECT conversation_id FROM dm_pairs WHERE user_lo = $1 OR user_hi = $1)', [userId]);
      await client.query('DELETE FROM dm_pairs WHERE user_lo = $1 OR user_hi = $1', [userId]);
      await client.query('DELETE FROM user_events WHERE user_id = $1', [userId]);
      await client.query('DELETE FROM user_event_seq WHERE user_id = $1', [userId]);
      await client.query('COMMIT');
    } catch (e) { await client.query('ROLLBACK'); throw e; } finally { client.release(); }
  }
  async exportUser(userId: string) {
    const r = await this.pool.query('SELECT * FROM messages WHERE sender_id = $1 AND deleted_at IS NULL ORDER BY created_at, seq', [userId]);
    return { messages: r.rows.map(rowToMsg) };
  }
}
