/**
 * 好友位置（B5 地图主页 / E2 数据卫生）。
 *
 * 规则：只在 App 前台且地图页可见时上报（When-In-Use）；只有互相关注的人能看到彼此的位置；
 * 非好友一律不下发（比「降精度」更严——MVP 先不做陌生人附近）；超过 LOCATION_MAX_AGE_MS 没更新的
 * 位置不下发；删号时位置一并删。服务端只存最新一条，不存轨迹。
 */
import type { AccountModule } from './accounts.js';

export interface LocationRow {
  user_id: string;
  lat: number;
  lng: number;
  /** 米；客户端没给就 null。 */
  accuracy_m: number | null;
  updated_at: number;
}

export interface LocationStore {
  upsert(userId: string, lat: number, lng: number, accuracyM: number | null, now: number): Promise<LocationRow>;
  remove(userId: string): Promise<void>;
  get(userId: string): Promise<LocationRow | null>;
  many(userIds: string[]): Promise<Map<string, LocationRow>>;
}

/** 24 小时没更新的位置当作「不在线」，不再给好友看。 */
export const LOCATION_MAX_AGE_MS = 24 * 60 * 60 * 1000;
/** 一次最多下发多少个好友位置。 */
export const FRIENDS_LIMIT = 200;
/** 精度上限：再差的定位也没意义，夹住免得客户端画出跨城的圈。 */
export const ACCURACY_MAX_M = 50_000;

export type LocationInput = { ok: true; lat: number; lng: number; accuracy_m: number | null } | { ok: false; field: string; reason: string };

export function validateLocation(body: unknown): LocationInput {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) return { ok: false, field: 'body', reason: 'OBJECT' };
  const b = body as Record<string, unknown>;
  const lat = Number(b.lat);
  const lng = Number(b.lng);
  if (typeof b.lat !== 'number' || !Number.isFinite(lat) || lat < -90 || lat > 90) return { ok: false, field: 'lat', reason: 'RANGE' };
  if (typeof b.lng !== 'number' || !Number.isFinite(lng) || lng < -180 || lng > 180) return { ok: false, field: 'lng', reason: 'RANGE' };
  let accuracy: number | null = null;
  if (b.accuracy_m !== undefined && b.accuracy_m !== null) {
    const a = Number(b.accuracy_m);
    if (typeof b.accuracy_m !== 'number' || !Number.isFinite(a) || a < 0) return { ok: false, field: 'accuracy_m', reason: 'RANGE' };
    accuracy = Math.min(a, ACCURACY_MAX_M);
  }
  return { ok: true, lat, lng, accuracy_m: accuracy };
}

export interface FriendCard { display_name: string; handle: string | null; avatar: Record<string, unknown> | null }

export function friendLocationView(row: LocationRow, card: FriendCard | undefined) {
  return {
    user_id: row.user_id,
    display_name: card?.display_name ?? '',
    handle: card?.handle ?? null,
    avatar: card?.avatar ?? null,
    lat: row.lat, lng: row.lng, accuracy_m: row.accuracy_m, updated_at: row.updated_at,
  };
}

export const isFresh = (row: LocationRow, now: number): boolean => now - row.updated_at <= LOCATION_MAX_AGE_MS;

/** 删号级联与数据导出：位置是个人数据，导出给一条，删号删掉。 */
export function locationAccountModule(store: LocationStore): AccountModule {
  return {
    name: 'location',
    export: (userId) => store.get(userId),
    del: (userId) => store.remove(userId),
  };
}
