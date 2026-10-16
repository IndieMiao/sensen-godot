/**
 * The home pick's `Near you` row (SGODOT-303, q(188) ①): the open city nearest the player's address, a city-level
 * guess that never asks for location permission. Made from DB-IP City Lite (CC BY 4.0, credited in Settings › Licenses
 * › Map data) at image build time (tools/ip_near_table.ts, server/deploy/p0/Dockerfile): each address range already
 * names its nearest open home city, so the server holds a small table (about 11 MB for 13 cities, under the 256 MB
 * container) instead of the 127 MB location database, and never calls out. The game server neither stores nor logs the
 * address or the guess (Caddy's access log in front of it keeps addresses as it always has). Farther than
 * home.near_max_km from every open city (q(205) ②), or without the table, there is no guess.
 *
 * File (little-endian): `P0IPNEAR1\n`, a uint32 header length and the JSON header {cities: [cluster id …], v4, v6},
 * then v4 entries [start uint32, city uint16] and v6 entries [start's top 64 bits as hi uint32 + lo uint32, city uint16],
 * each sorted by start, a range running to the next entry's start; city 0xFFFF = no city (an address DB-IP lacks).
 */
import { readFileSync } from 'node:fs';
import { isIP } from 'node:net';

export type IpNear = (ip: string) => string | null;
export const MAGIC = 'P0IPNEAR1\n';
export const NONE = 0xffff;
const V4 = 6, V6 = 10;

/** Private, loopback, link-local and unique-local addresses: no place to guess. */
const PRIVATE = [/^10\./, /^127\./, /^192\.168\./, /^172\.(1[6-9]|2\d|3[01])\./, /^169\.254\./, /^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\./,
  /^::1$/, /^f[cd]/i, /^fe80/i];   // 100.64.0.0/10: carrier-grade NAT

/** An IPv6 address's top 64 bits as [hi, lo] uint32. */
export function v6Top(address: string): [number, number] {
  const [head, tail = ''] = address.split('::');
  const a = head ? head.split(':') : [], b = tail ? tail.split(':') : [];
  const words = [...a, ...Array(8 - a.length - b.length).fill('0'), ...b].map(w => parseInt(w || '0', 16));
  return [((words[0] << 16) | words[1]) >>> 0, ((words[2] << 16) | words[3]) >>> 0];
}
export const v4Num = (address: string) => address.split('.').reduce((n, p) => n * 256 + Number(p), 0);

export function openIpNear(file: string): IpNear {
  const buf = readFileSync(file);
  if (buf.toString('latin1', 0, MAGIC.length) !== MAGIC) throw new Error(`${file}: not a P0 address table`);
  const len = buf.readUInt32LE(MAGIC.length), start = MAGIC.length + 4;
  const head = JSON.parse(buf.toString('utf8', start, start + len)) as { cities: string[]; v4: number; v6: number };
  const v4At = start + len, v6At = v4At + head.v4 * V4;
  /** The last entry whose start ≤ the key (binary search). */
  const find = (n: number, at: (i: number) => number) => {
    let lo = 0, hi = n - 1, hit = -1;
    while (lo <= hi) { const mid = (lo + hi) >> 1; if (at(mid) <= 0) { hit = mid; lo = mid + 1; } else hi = mid - 1; }
    return hit;
  };
  const city = (i: number) => (i === NONE ? null : head.cities[i] ?? null);
  return ip => {
    const address = ip.startsWith('::ffff:') ? ip.slice(7) : ip;
    const kind = isIP(address);
    if (!kind || PRIVATE.some(re => re.test(address))) return null;
    if (kind === 4) {
      const key = v4Num(address);
      const i = find(head.v4, k => buf.readUInt32LE(v4At + k * V4) - key);
      return i < 0 ? null : city(buf.readUInt16LE(v4At + i * V4 + 4));
    }
    const [hi, lo] = v6Top(address);
    const i = find(head.v6, k => { const o = v6At + k * V6, h = buf.readUInt32LE(o); return h !== hi ? h - hi : buf.readUInt32LE(o + 4) - lo; });
    return i < 0 ? null : city(buf.readUInt16LE(v6At + i * V6 + 8));
  };
}
