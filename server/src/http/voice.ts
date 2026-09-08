/**
 * D5 语音房：房间 + 麦位 + LiveKit token 签发。
 *
 * 分工：**谁能说话由我们定，音频传输交给 LiveKit**。服务端签的 JWT 里 `canPublish`
 * 就是上下麦的开关——下麦不是客户端自己静音，而是换一把不允许发布的 token，客户端
 * 就算改了本地代码也推不上流。房间状态（谁在麦上、谁被静音）在我们库里，LiveKit 只当管道。
 *
 * 不引 livekit-server-sdk：它做的就是「HS256 签一个带 video grant 的 JWT」，我们已经有
 * crypto；引进来只是多一层依赖。
 */
import { createHmac } from 'node:crypto';
import type { AccountModule } from './accounts.js';

export const ROOM_TITLE_MAX = 40;
export const STAGE_MAX = 8;           // 麦位数（含房主）
export const ROOM_MEMBERS_MAX = 50;   // 房间总人数上限
export const TOKEN_TTL_S = 3600;

export type Role = 'host' | 'speaker' | 'listener';

export interface RoomRow {
  id: string;
  title: string;
  host_id: string;
  created_at: number;
  closed_at: number | null;
}

export interface RoomMemberRow {
  room_id: string;
  user_id: string;
  role: Role;
  /** 房主静音了这个人：他自己上不了麦，直到房主放开。 */
  muted: boolean;
  joined_at: number;
}

export interface VoiceStore {
  createRoom(row: RoomRow): Promise<RoomRow>;
  room(roomId: string): Promise<RoomRow | null>;
  openRooms(limit: number): Promise<RoomRow[]>;
  closeRoom(roomId: string, now: number): Promise<void>;
  join(roomId: string, userId: string, role: Role, now: number): Promise<RoomMemberRow>;
  leave(roomId: string, userId: string): Promise<void>;
  members(roomId: string): Promise<RoomMemberRow[]>;
  member(roomId: string, userId: string): Promise<RoomMemberRow | null>;
  setRole(roomId: string, userId: string, role: Role): Promise<RoomMemberRow | null>;
  setMuted(roomId: string, userId: string, muted: boolean): Promise<RoomMemberRow | null>;
  roomsOf(userId: string): Promise<RoomRow[]>;
  deleteUser(userId: string): Promise<void>;
}

export interface LiveKitConfig { url: string; apiKey: string; apiSecret: string }

export function liveKitFromEnv(env: Record<string, string | undefined>): LiveKitConfig | undefined {
  const url = env.LIVEKIT_URL, apiKey = env.LIVEKIT_API_KEY, apiSecret = env.LIVEKIT_API_SECRET;
  return url && apiKey && apiSecret ? { url, apiKey, apiSecret } : undefined;
}

const b64url = (s: string | Buffer): string => Buffer.from(s as never).toString('base64url');

/**
 * LiveKit access token（HS256）。canPublish 由角色决定：
 * 房主 / 麦上可发布，听众只订阅。被房主静音的人一律不可发布。
 */
export function signAccessToken(cfg: LiveKitConfig, opts: {
  identity: string; name?: string; room: string; canPublish: boolean; nowMs: number; ttlS?: number;
}): string {
  const iat = Math.floor(opts.nowMs / 1000);
  const header = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const payload = b64url(JSON.stringify({
    iss: cfg.apiKey, sub: opts.identity, name: opts.name ?? '',
    nbf: iat, iat, exp: iat + (opts.ttlS ?? TOKEN_TTL_S),
    video: {
      room: opts.room, roomJoin: true,
      canPublish: opts.canPublish, canSubscribe: true, canPublishData: true,
    },
  }));
  const sig = createHmac('sha256', cfg.apiSecret).update(`${header}.${payload}`).digest('base64url');
  return `${header}.${payload}.${sig}`;
}

export const canPublishFor = (role: Role, muted: boolean): boolean => !muted && role !== 'listener';

export type CreateRoomInput = { ok: true; title: string } | { ok: false; field: string };

export function validateRoom(body: unknown): CreateRoomInput {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) return { ok: false, field: 'body' };
  const t = (body as Record<string, unknown>).title;
  if (typeof t !== 'string') return { ok: false, field: 'title' };
  const title = t.trim();
  if (title.length < 1 || [...title].length > ROOM_TITLE_MAX || /[\x00-\x1f\x7f]/.test(title))
    return { ok: false, field: 'title' };
  return { ok: true, title };
}

/** 麦位满了没有。房主永远占一个。 */
export const stageFull = (members: RoomMemberRow[]): boolean =>
  members.filter(m => m.role !== 'listener').length >= STAGE_MAX;

export interface MemberCard { display_name: string; handle: string | null; avatar: Record<string, unknown> | null }

export function memberView(m: RoomMemberRow, card: MemberCard | undefined) {
  return {
    user_id: m.user_id, role: m.role, muted: m.muted, joined_at: m.joined_at,
    display_name: card?.display_name ?? '', handle: card?.handle ?? null, avatar: card?.avatar ?? null,
  };
}

export function roomView(r: RoomRow, members: RoomMemberRow[], hostCard: MemberCard | undefined) {
  return {
    id: r.id, title: r.title, host_id: r.host_id, host_name: hostCard?.display_name ?? '',
    member_count: members.length, speaker_count: members.filter(m => m.role !== 'listener').length,
    created_at: r.created_at, closed: r.closed_at !== null,
  };
}

/** 删号级联：本人建的房关掉，本人从各房退出。语音不留内容，导出只给参与过的房间 id。 */
export function voiceAccountModule(store: VoiceStore): AccountModule {
  return {
    name: 'voice',
    export: async (userId) => (await store.roomsOf(userId)).map(r => ({ room_id: r.id, title: r.title })),
    del: (userId) => store.deleteUser(userId),
  };
}
