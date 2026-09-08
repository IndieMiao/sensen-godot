/**
 * D7 推送：设备 token 表 + 离线通知（FCM HTTP v1，APNs 由 FCM 代投）。
 *
 * 为什么不引 firebase-admin：它只是替我们做「服务账号 JWT → OAuth2 access token → POST」
 * 这三步，而我们已经有 JWT 校验与 HTTP 客户端；引进来会把一整套 Google SDK 依赖带进
 * 生产镜像。这里把接口留成可注入的 Sender，接真 FCM 与接测试替身是同一个口子。
 *
 * 内容规矩（E2）：通知正文里**不放消息内容**，只放「谁发来一条消息」。点开由客户端
 * 自己按 seq 补拉——省得消息正文经过 Google 的推送通道，也免了锁屏泄露。
 */
import type { AccountModule } from './accounts.js';

export type Platform = 'ios' | 'android';

export interface DeviceRow {
  user_id: string;
  token: string;
  platform: Platform;
  updated_at: number;
}

export interface DeviceStore {
  /** 同一个 token 换人登录时归属要跟着换（同设备切账号）。 */
  upsert(userId: string, token: string, platform: Platform, now: number): Promise<DeviceRow>;
  remove(token: string): Promise<void>;
  tokensFor(userIds: string[]): Promise<DeviceRow[]>;
  deleteUser(userId: string): Promise<void>;
}

/** 一条要发的通知。data 里只放路由用的 id，不放正文。 */
export interface Notification {
  title: string;
  body: string;
  data: Record<string, string>;
}

export interface PushSender {
  /** 返回失效（应从表里删掉）的 token。 */
  send(tokens: DeviceRow[], n: Notification): Promise<{ sent: number; invalid: string[] }>;
}

export const nullSender: PushSender = { async send() { return { sent: 0, invalid: [] }; } };

export const TOKEN_MAX = 4096;
export const PLATFORMS: Platform[] = ['ios', 'android'];

export type RegisterInput = { ok: true; token: string; platform: Platform } | { ok: false; field: string };

export function validateRegister(body: unknown): RegisterInput {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) return { ok: false, field: 'body' };
  const b = body as Record<string, unknown>;
  if (typeof b.token !== 'string' || b.token.trim().length < 8 || b.token.length > TOKEN_MAX) return { ok: false, field: 'token' };
  if (typeof b.platform !== 'string' || !PLATFORMS.includes(b.platform as Platform)) return { ok: false, field: 'platform' };
  return { ok: true, token: b.token.trim(), platform: b.platform as Platform };
}

/** 一条新消息该给谁推：会话成员里除发送者之外、当前不在线的人。 */
export function offlineRecipients(memberIds: string[], senderId: string, isOnline: (id: string) => boolean): string[] {
  return memberIds.filter(id => id !== senderId && !isOnline(id));
}

/** 通知文案：只说「谁来了消息」，不带正文（E2）。 */
export function messageNotification(senderName: string, conversationId: string, kind: string): Notification {
  const who = senderName.trim().length > 0 ? senderName.trim() : 'Someone';
  return {
    title: who,
    body: kind === 'image' ? 'Sent you a photo' : 'Sent you a message',
    data: { type: 'im_message', conversation_id: conversationId },
  };
}

/** 删号级联：设备 token 是个人数据，删号一并清掉；导出只给平台与时间，不给 token 本身。 */
export function pushAccountModule(store: DeviceStore): AccountModule {
  return {
    name: 'push',
    export: async (userId) => (await store.tokensFor([userId])).map(d => ({ platform: d.platform, updated_at: d.updated_at })),
    del: (userId) => store.deleteUser(userId),
  };
}
