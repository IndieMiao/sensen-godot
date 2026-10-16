/**
 * The `Near you` address table (SGODOT-303, q(188) ①; src/p0/ip_city.ts) from DB-IP City Lite's CSV, at image build:
 *   npx tsx tools/ip_near_table.ts <dbip-city-lite-YYYY-MM.csv.gz> <out.bin>
 * Each address range is given the open home city nearest its point (home_city.ts nearestOpen, the rule the server
 * would apply), and neighbouring ranges of the same city are merged. Rebuilt with the image, so it follows the open list.
 */
import { createReadStream, writeFileSync } from 'node:fs';
import { createInterface } from 'node:readline';
import { createGunzip } from 'node:zlib';
import { loadP0Content } from '../src/p0/content.js';
import { homeCities, nearestOpen } from '../src/p0/home_city.js';
import { MAGIC, NONE, v4Num, v6Top } from '../src/p0/ip_city.js';

const [input, out] = process.argv.slice(2);
if (!input || !out) { console.error('usage: ip_near_table.ts <csv.gz> <out.bin>'); process.exit(2); }
const c = loadP0Content();
const cities = homeCities(c).open.map(r => r.id);
const index = new Map(cities.map((id, i) => [id, i]));
const memo = new Map<string, number>();
/** The nearest open city's index for a point (memoised at 0.01°: points repeat across ranges). */
const near = (lat: number, lng: number) => {
  const k = `${lat.toFixed(2)},${lng.toFixed(2)}`;
  let i = memo.get(k);
  if (i === undefined) { const r = nearestOpen(c, { lat, lng }); i = r ? index.get(r.id) ?? NONE : NONE; memo.set(k, i); }
  return i;
};
type Entry = { start: number[]; city: number };   // v4: [n]; v6: [hi, lo]
const v4: Entry[] = [], v6: Entry[] = [];
let v4End = -1;
let v6End: [number, number] | null = null;
const after = ([hi, lo]: [number, number]): [number, number] => lo === 0xffffffff ? [hi + 1, 0] : [hi, lo + 1];
const same = (a: number[], b: number[]) => a.length === b.length && a.every((x, i) => x === b[i]);
let rows = 0;
for await (const line of createInterface({ input: createReadStream(input).pipe(createGunzip()), crlfDelay: Infinity })) {
  const cols = line.split(','), lat = Number(cols[cols.length - 2]), lng = Number(cols[cols.length - 1]);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
  rows++;
  // DB-IP's unknown ranges (country ZZ: reserved and shared address space) sit at 0, 0: no city, not the one nearest
  // the Gulf of Guinea
  const city = cols[2] === 'ZZ' || (lat === 0 && lng === 0) ? NONE : near(lat, lng);
  if (cols[0].includes(':')) {
    const s = v6Top(cols[0]), e = v6Top(cols[1]);
    if (v6End && s[0] === v6End[0] && s[1] <= v6End[1]) { v6End = e[0] > v6End[0] || e[1] > v6End[1] ? e : v6End; continue; }   // /64 already seen
    const contiguous = !!v6End && same(s, after(v6End));
    if (v6End && !contiguous) v6.push({ start: after(v6End), city: NONE });
    const last = v6[v6.length - 1];
    if (!last || last.city !== city) v6.push({ start: s, city });
    v6End = e;
  } else {
    const s = v4Num(cols[0]), e = v4Num(cols[1]);
    if (v4End >= 0 && s !== v4End + 1) v4.push({ start: [v4End + 1], city: NONE });
    const last = v4[v4.length - 1];
    if (!last || last.city !== city) v4.push({ start: [s], city });
    v4End = e;
  }
}
// past the last range: nobody (DB-IP covers the whole space today; a shorter file must not lend its last city onward)
if (v4End >= 0 && v4End < 0xffffffff) v4.push({ start: [v4End + 1], city: NONE });
if (v6End && !(v6End[0] === 0xffffffff && v6End[1] === 0xffffffff)) v6.push({ start: after(v6End), city: NONE });
const header = Buffer.from(JSON.stringify({ cities, v4: v4.length, v6: v6.length, rows }), 'utf8');
const buf = Buffer.alloc(MAGIC.length + 4 + header.length + v4.length * 6 + v6.length * 10);
let o = buf.write(MAGIC, 0, 'latin1');
o = buf.writeUInt32LE(header.length, o); o += header.copy(buf, o);
for (const e of v4) { o = buf.writeUInt32LE(e.start[0], o); o = buf.writeUInt16LE(e.city, o); }
for (const e of v6) { o = buf.writeUInt32LE(e.start[0], o); o = buf.writeUInt32LE(e.start[1], o); o = buf.writeUInt16LE(e.city, o); }
writeFileSync(out, buf);
console.log(JSON.stringify({ out, cities: cities.length, rows, v4: v4.length, v6: v6.length, mb: Math.round(buf.length / 1e5) / 10 }));
