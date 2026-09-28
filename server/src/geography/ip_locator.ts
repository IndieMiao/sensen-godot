/**
 * IP 粗定位：选城页的默认城市（2026-09-28 决定 3：先不申请定位权限）。
 *
 * 只取城市级坐标，结果不落库、不写日志——它只用来预填一张"你好像在东京"的确认卡，
 * 用户点确认才算选城。数据库是 DB-IP City Lite（CC BY 4.0，月更），路径由 IP_CITY_DB 指定；
 * 没配就不给建议，选城页照常手选。
 */
import { isIP } from 'node:net';
import maxmind, { type CityResponse, type Reader } from 'maxmind';

export type IpLocator = (ip: string) => Promise<{ lat: number; lng: number } | null>;

const PRIVATE = [/^10\./, /^127\./, /^192\.168\./, /^172\.(1[6-9]|2\d|3[01])\./, /^169\.254\./, /^::1$/, /^f[cd]/i, /^fe80/i];

export async function createMmdbIpLocator(file: string): Promise<IpLocator> {
  const reader: Reader<CityResponse> = await maxmind.open<CityResponse>(file);
  return async ip => {
    const address = ip.startsWith('::ffff:') ? ip.slice(7) : ip;
    if (!isIP(address) || PRIVATE.some(re => re.test(address))) return null;
    const hit = reader.get(address);
    const lat = hit?.location?.latitude, lng = hit?.location?.longitude;
    return typeof lat === 'number' && typeof lng === 'number' ? { lat, lng } : null;
  };
}
