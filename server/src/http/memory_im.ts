/** 内存 ImStore：HTTP 层测试用；语义与 PgImStore 保持一致（im_conformance）。 */
import { randomUUID } from 'node:crypto';
import { pairKey, type ConversationRow, type ImStore, type MemberRow, type MessageRow, type UserEvent } from './im.js';
import type { Moderation } from './feed.js';

export class MemoryImStore implements ImStore {
  private convs = new Map<string, ConversationRow>();
  private memberRows: MemberRow[] = [];
  private pairs = new Map<string, string>();
  private msgs = new Map<string, MessageRow>();
  private events: UserEvent[] = [];
  private nextSeq = new Map<string, number>();

  async getOrCreateDm(a: string, b: string, now: number) {
    const [lo, hi] = pairKey(a, b);
    const key = `${lo}|${hi}`;
    const existing = this.pairs.get(key);
    if (existing) return { conversation: { ...this.convs.get(existing)! }, created: false };
    const c: ConversationRow = { id: randomUUID(), kind: 'dm', title: null, created_by: a, created_at: now, last_seq: 0, last_message_at: null };
    this.convs.set(c.id, c);
    this.pairs.set(key, c.id);
    for (const u of [a, b]) this.memberRows.push({ conversation_id: c.id, user_id: u, joined_at: now, last_read_seq: 0 });
    return { conversation: { ...c }, created: true };
  }
  async createGroup(a: { id: string; title: string; creatorId: string; memberIds: string[]; now: number }) {
    const c: ConversationRow = { id: a.id, kind: 'group', title: a.title, created_by: a.creatorId, created_at: a.now, last_seq: 0, last_message_at: null };
    this.convs.set(c.id, c);
    for (const u of [a.creatorId, ...a.memberIds.filter(x => x !== a.creatorId)]) this.memberRows.push({ conversation_id: c.id, user_id: u, joined_at: a.now, last_read_seq: 0 });
    return { ...c };
  }
  async conversation(id: string) { const c = this.convs.get(id); return c ? { ...c } : null; }
  async members(conversationId: string) { return this.memberRows.filter(m => m.conversation_id === conversationId).map(m => ({ ...m })); }
  async isMember(conversationId: string, userId: string) { return this.memberRows.some(m => m.conversation_id === conversationId && m.user_id === userId); }
  async addMembers(conversationId: string, userIds: string[], now: number) {
    const added: string[] = [];
    for (const u of userIds) if (!(await this.isMember(conversationId, u))) { this.memberRows.push({ conversation_id: conversationId, user_id: u, joined_at: now, last_read_seq: 0 }); added.push(u); }
    return added;
  }
  async removeMember(conversationId: string, userId: string) {
    const before = this.memberRows.length;
    this.memberRows = this.memberRows.filter(m => !(m.conversation_id === conversationId && m.user_id === userId));
    return this.memberRows.length < before;
  }
  async conversationsOf(userId: string) {
    const out = this.memberRows.filter(m => m.user_id === userId).map(m => {
      const c = this.convs.get(m.conversation_id)!;
      const last = [...this.msgs.values()].filter(x => x.conversation_id === c.id).sort((x, y) => y.seq - x.seq)[0] ?? null;
      return { conversation: { ...c }, member: { ...m }, last_message: last ? { ...last } : null };
    });
    return out.sort((x, y) => (y.conversation.last_message_at ?? y.conversation.created_at) - (x.conversation.last_message_at ?? x.conversation.created_at) || (y.conversation.id < x.conversation.id ? -1 : 1));
  }
  private allocate(userId: string): number {
    const n = (this.nextSeq.get(userId) ?? 0) + 1;
    this.nextSeq.set(userId, n);
    return n;
  }
  async appendMessage(a: { id: string; conversationId: string; senderId: string; clientId: string; kind: MessageRow['kind']; body: Record<string, unknown>; now: number; moderation: Moderation }) {
    const dup = [...this.msgs.values()].find(m => m.conversation_id === a.conversationId && m.sender_id === a.senderId && m.client_id === a.clientId);
    if (dup) return { message: { ...dup }, created: false, events: [] };
    const c = this.convs.get(a.conversationId)!;
    c.last_seq += 1;
    c.last_message_at = a.now;
    const m: MessageRow = { id: a.id, conversation_id: a.conversationId, seq: c.last_seq, sender_id: a.senderId, client_id: a.clientId, kind: a.kind,
      body: { ...a.body }, created_at: a.now, deleted_at: null, moderation_status: a.moderation.status, moderation_categories: [...a.moderation.categories] };
    this.msgs.set(m.id, m);
    const events = await this.pushEvent((await this.members(a.conversationId)).map(x => x.user_id), 'message',
      { conversation_id: m.conversation_id, message_id: m.id, message_seq: m.seq, sender_id: m.sender_id, kind: m.kind, body: m.body, created_at: m.created_at }, a.now);
    return { message: { ...m }, created: true, events };
  }
  async messages(conversationId: string, beforeSeq: number | null, limit: number) {
    return [...this.msgs.values()].filter(m => m.conversation_id === conversationId && (beforeSeq === null || m.seq < beforeSeq))
      .sort((x, y) => y.seq - x.seq).slice(0, limit).map(m => ({ ...m }));
  }
  async message(id: string) { const m = this.msgs.get(id); return m ? { ...m } : null; }
  async deleteMessage(id: string, now: number) {
    const m = this.msgs.get(id);
    if (!m || m.deleted_at !== null) return false;
    m.deleted_at = now; m.body = {};
    return true;
  }
  async markRead(conversationId: string, userId: string, seq: number) {
    const m = this.memberRows.find(x => x.conversation_id === conversationId && x.user_id === userId);
    if (!m) return { changed: false, last_read_seq: 0 };
    const c = this.convs.get(conversationId)!;
    const target = Math.min(seq, c.last_seq);
    if (target <= m.last_read_seq) return { changed: false, last_read_seq: m.last_read_seq };
    m.last_read_seq = target;
    return { changed: true, last_read_seq: target };
  }
  async dmExchange(conversationId: string, a: string, b: string) {
    const rows = [...this.msgs.values()].filter(m => m.conversation_id === conversationId);
    return { a_count: rows.filter(m => m.sender_id === a).length, b_count: rows.filter(m => m.sender_id === b).length };
  }
  async pushEvent(userIds: string[], type: string, payload: Record<string, unknown>, now: number) {
    const out: UserEvent[] = [];
    for (const u of userIds) { const e: UserEvent = { user_id: u, seq: this.allocate(u), type, payload: { ...payload }, created_at: now }; this.events.push(e); out.push({ ...e }); }
    return out;
  }
  async eventsSince(userId: string, sinceSeq: number, limit: number) {
    return this.events.filter(e => e.user_id === userId && e.seq > sinceSeq).sort((x, y) => x.seq - y.seq).slice(0, limit).map(e => ({ ...e, payload: { ...e.payload } }));
  }
  async latestSeq(userId: string) { return this.nextSeq.get(userId) ?? 0; }
  async deleteUser(userId: string) {
    for (const m of this.msgs.values()) if (m.sender_id === userId && m.deleted_at === null) { m.deleted_at = Date.now(); m.body = {}; }
    this.memberRows = this.memberRows.filter(m => m.user_id !== userId);
    // 单聊整体撤掉（对方那一侧的成员行也要删，否则会话列表里留一个没有会话的幽灵）；群聊保留。
    for (const [k, cid] of [...this.pairs]) if (k.split('|').includes(userId)) {
      this.pairs.delete(k); this.convs.delete(cid);
      this.memberRows = this.memberRows.filter(m => m.conversation_id !== cid);
      for (const [id, m] of [...this.msgs]) if (m.conversation_id === cid) this.msgs.delete(id);
    }
    this.events = this.events.filter(e => e.user_id !== userId);
    this.nextSeq.delete(userId);
  }
  async exportUser(userId: string) {
    return { messages: [...this.msgs.values()].filter(m => m.sender_id === userId && m.deleted_at === null).sort((x, y) => x.created_at - y.created_at).map(m => ({ ...m })) };
  }
}
