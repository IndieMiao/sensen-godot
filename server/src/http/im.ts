/**
 * IM（D3，自建极简版；08-30 调研 §4.2）。消息落 PostgreSQL 而不是 Mongo：D0 已定「统一 Node + 现有
 * PG」，Demo 量级下 JSONB 行足够，少一套数据库要运维。
 *
 * 同步模型：每个会话有自己的 seq（消息顺序）；每个用户有一条 **inbox 事件流**（user_events，
 * 用户级单调 seq），会话里的每条消息都扇出成每个成员 inbox 里的一条事件。客户端只记一个
 * last_seq（WsClient 就是这么做的）：在线时走 WS 推事件，断线回来 GET /v1/im/sync?since=last_seq
 * 补拉。离线走推送（D7）。
 *
 * 陌生人规则照 Follow Feature Requirements §3.3：双方都没关注对方时，先开口的人只能发一条，
 * 直到对方回复；曾经互相发过消息的不受限。拉黑双向：不能建单聊、不能发。
 */
import type { AccountModule } from './accounts.js';
import type { Moderation } from './feed.js';
import type { ModerationStatus } from './moderation.js';
import type { Relation } from './social.js';

export interface ConversationRow {
  id: string;
  kind: 'dm' | 'group';
  title: string | null;
  created_by: string;
  created_at: number;
  last_seq: number;
  last_message_at: number | null;
}
export interface MemberRow { conversation_id: string; user_id: string; joined_at: number; last_read_seq: number }
export interface MessageRow {
  id: string;
  conversation_id: string;
  seq: number;
  sender_id: string;
  client_id: string;
  kind: 'text' | 'image' | 'system';
  body: Record<string, unknown>;
  created_at: number;
  deleted_at: number | null;
  moderation_status: ModerationStatus;
  moderation_categories: string[];
}
export interface UserEvent { user_id: string; seq: number; type: string; payload: Record<string, unknown>; created_at: number }

export interface ImStore {
  getOrCreateDm(a: string, b: string, now: number): Promise<{ conversation: ConversationRow; created: boolean }>;
  createGroup(args: { id: string; title: string; creatorId: string; memberIds: string[]; now: number }): Promise<ConversationRow>;
  conversation(id: string): Promise<ConversationRow | null>;
  members(conversationId: string): Promise<MemberRow[]>;
  isMember(conversationId: string, userId: string): Promise<boolean>;
  /** 返回真正新加进去的。 */
  addMembers(conversationId: string, userIds: string[], now: number): Promise<string[]>;
  removeMember(conversationId: string, userId: string): Promise<boolean>;
  /** 我的会话，按最近消息倒序。 */
  conversationsOf(userId: string): Promise<{ conversation: ConversationRow; member: MemberRow; last_message: MessageRow | null }[]>;
  /**
   * 事务：分配会话 seq → 写消息 → 给每个成员（含发送者）的 inbox 追加事件。
   * 同发送者同 client_id 重放返回原消息且不再扇出。
   */
  appendMessage(args: { id: string; conversationId: string; senderId: string; clientId: string; kind: MessageRow['kind'];
    body: Record<string, unknown>; now: number; moderation: Moderation }): Promise<{ message: MessageRow; created: boolean; events: UserEvent[] }>;
  /** 会话历史：seq 倒序，before_seq 之前的。 */
  messages(conversationId: string, beforeSeq: number | null, limit: number): Promise<MessageRow[]>;
  message(id: string): Promise<MessageRow | null>;
  deleteMessage(id: string, now: number): Promise<boolean>;
  markRead(conversationId: string, userId: string, seq: number): Promise<{ changed: boolean; last_read_seq: number }>;
  /** 单聊里双方各发过几条（陌生人规则）。 */
  dmExchange(conversationId: string, a: string, b: string): Promise<{ a_count: number; b_count: number }>;
  /** 给一组用户的 inbox 追加一条非消息事件（已读回执、成员变化…）。 */
  pushEvent(userIds: string[], type: string, payload: Record<string, unknown>, now: number): Promise<UserEvent[]>;
  eventsSince(userId: string, sinceSeq: number, limit: number): Promise<UserEvent[]>;
  latestSeq(userId: string): Promise<number>;
  deleteUser(userId: string): Promise<void>;
  exportUser(userId: string): Promise<{ messages: MessageRow[] }>;
}

/** 在线推送的落点：WS 网关实现它；测试用记录器。 */
export interface LiveHub {
  publish(events: UserEvent[]): void;
}

export const MESSAGE_TEXT_MAX = 4000;
export const GROUP_TITLE_MAX = 60;
export const GROUP_MEMBERS_MAX = 50;
export const SYNC_LIMIT_MAX = 200;
export const HISTORY_LIMIT_MAX = 100;

const hasBadControl = (s: string): boolean => /[\x00-\x09\x0b-\x1f\x7f]/.test(s);

export type MessageInput =
  | { ok: true; clientId: string; kind: 'text' | 'image'; body: Record<string, unknown>; text: string }
  | { ok: false; field: string; reason: string };

export function validateMessage(body: unknown): MessageInput {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) return { ok: false, field: 'body', reason: 'OBJECT' };
  const b = body as Record<string, unknown>;
  if (typeof b.client_id !== 'string' || b.client_id.length === 0 || b.client_id.length > 64) return { ok: false, field: 'client_id', reason: 'FORMAT' };
  const kind = b.kind ?? 'text';
  if (kind === 'text') {
    if (typeof b.text !== 'string') return { ok: false, field: 'text', reason: 'STRING' };
    const text = b.text.trim();
    if (text.length === 0 || [...text].length > MESSAGE_TEXT_MAX || hasBadControl(text)) return { ok: false, field: 'text', reason: 'LENGTH' };
    return { ok: true, clientId: b.client_id, kind: 'text', body: { text }, text };
  }
  if (kind === 'image') {
    const im = b.image;
    if (typeof im !== 'object' || im === null) return { ok: false, field: 'image', reason: 'OBJECT' };
    const r = im as Record<string, unknown>;
    if (typeof r.key !== 'string' || !/^[A-Za-z0-9_\-./]{1,200}$/.test(r.key) || r.key.includes('..') || r.key.startsWith('/'))
      return { ok: false, field: 'image', reason: 'KEY' };
    const out: Record<string, unknown> = { key: r.key };
    for (const dim of ['w', 'h'] as const) if (r[dim] !== undefined) {
      if (!Number.isInteger(r[dim]) || (r[dim] as number) <= 0 || (r[dim] as number) > 20000) return { ok: false, field: 'image', reason: 'SIZE' };
      out[dim] = r[dim];
    }
    const caption = typeof b.text === 'string' ? b.text.trim() : '';
    if ([...caption].length > MESSAGE_TEXT_MAX || hasBadControl(caption)) return { ok: false, field: 'text', reason: 'LENGTH' };
    if (caption) out.text = caption;
    return { ok: true, clientId: b.client_id, kind: 'image', body: out, text: caption };
  }
  return { ok: false, field: 'kind', reason: 'UNKNOWN' };
}

export function validateGroup(body: unknown): { ok: true; title: string; memberIds: string[] } | { ok: false; field: string; reason: string } {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) return { ok: false, field: 'body', reason: 'OBJECT' };
  const b = body as Record<string, unknown>;
  const title = typeof b.title === 'string' ? b.title.trim() : '';
  if (title.length === 0 || [...title].length > GROUP_TITLE_MAX || hasBadControl(title)) return { ok: false, field: 'title', reason: 'LENGTH' };
  const ids = uniqueIds(b.member_ids);
  if (!ids || ids.length === 0 || ids.length > GROUP_MEMBERS_MAX) return { ok: false, field: 'member_ids', reason: 'COUNT' };
  return { ok: true, title, memberIds: ids };
}

export function uniqueIds(v: unknown): string[] | null {
  if (!Array.isArray(v)) return null;
  const out: string[] = [];
  for (const x of v) {
    if (typeof x !== 'string' || !/^[0-9a-f-]{36}$/i.test(x)) return null;
    if (!out.includes(x)) out.push(x);
  }
  return out;
}

/** 陌生人规则：先开口的一方在对方回复前只能发一条。 */
export function greetingBlocked(relation: Relation, exchange: { a_count: number; b_count: number }): boolean {
  if (relation.following || relation.followed_by) return false;
  return exchange.b_count === 0 && exchange.a_count >= 1;
}

export function messageView(m: MessageRow) {
  return {
    id: m.id, conversation_id: m.conversation_id, seq: m.seq, sender_id: m.sender_id, client_id: m.client_id,
    kind: m.deleted_at === null ? m.kind : 'system',
    body: m.deleted_at === null ? m.body : { deleted: true },
    created_at: m.created_at, deleted: m.deleted_at !== null,
  };
}

export interface PeerCard { user_id: string; display_name: string; handle: string | null; avatar: Record<string, unknown> | null }

/** peerReadSeq：单聊里对方的已读进度（已读回执的初始值；之后靠 `read` 事件推进），群聊为 null。 */
export function conversationView(c: ConversationRow, me: MemberRow, last: MessageRow | null, peer: PeerCard | null, memberCount: number, peerReadSeq: number | null = null) {
  return {
    id: c.id, kind: c.kind, title: c.title, peer, member_count: memberCount, peer_read_seq: peerReadSeq,
    last_seq: c.last_seq, last_read_seq: me.last_read_seq, unread: Math.max(0, c.last_seq - me.last_read_seq),
    last_message: last ? messageView(last) : null, last_message_at: c.last_message_at, created_at: c.created_at,
  };
}

/** 成员列表：资料卡 + 入群时间 + 已读进度（群聊的「N 人已读」和气泡上的昵称都从这来）。 */
export function memberView(m: MemberRow, card: PeerCard | undefined) {
  return { user_id: m.user_id, display_name: card?.display_name ?? '', handle: card?.handle ?? null, avatar: card?.avatar ?? null,
    joined_at: m.joined_at, last_read_seq: m.last_read_seq };
}

export const pairKey = (a: string, b: string): [string, string] => (a < b ? [a, b] : [b, a]);

export function imAccountModule(store: ImStore): AccountModule {
  return { name: 'im', export: (userId) => store.exportUser(userId), del: (userId) => store.deleteUser(userId) };
}

/** 测试与单机默认：记录发布，不推。 */
export class RecordingHub implements LiveHub {
  published: UserEvent[] = [];
  publish(events: UserEvent[]): void { this.published.push(...events); }
}
