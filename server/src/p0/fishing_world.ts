/**
 * Fishing part 2 (SGODOT-283, plan §6.2.5–6.2.7, 李白 q(109)): what swims in a pond at a given moment. Pure functions of
 * the content, the pond's city cluster and the time, so every player sees the same pond and the client can work the same
 * answer out for its cards (modules/p0/p0_fish_world.gd mirrors this file; the shared vectors keep the two in step).
 *   - the pool: the fish whose habitats include the pond's template, global or one of the city's 2 regional fish, inside
 *     their time window; weight global 1 / regional 2 (4 with a lure) × time × weather; an empty tier falls one tier down
 *   - time of day: dawn/dusk 05–08 and 17–20, night 20–05, in the pond's city
 *   - weather: one per city per day (sun 50 / rain 30 / wind 20), hashed from the cluster and the city's date, which
 *     turns at 04:00 there (a rainy night stays one night)
 *   - the city's 2 regional fish: hand-picked for a few cities, else hashed; the first from the low tier and able to bite
 *     in a Pond all day
 */
import { createHash } from 'node:crypto';
import type { Fish, FishSite, P0Content } from './content.js';
import { clusterById, clusterOf, writtenCluster, HOME_ALIAS } from './travel.js';

export type Daypart = 'day' | 'dawn_dusk' | 'night';
export type Weather = 'sun' | 'rain' | 'wind';

/** fishing.regional (assets/p0/content/fish_p1.json): §6.2.5's groups and hand-picked cities, the windows. */
export interface RegionalRules {
  groups: Record<string, { low: string[]; high: string[] }>;
  curated: Record<string, string[]>;
  time_windows: Record<'dawn_dusk' | 'night', [number, number][]>;
  weather?: { odds: Record<Weather, number>; rollover_hour: number };
  seed?: string;
}

const rules = (c: P0Content): RegionalRules | undefined => (c.fishing as { regional?: RegionalRules }).regional;
const DEFAULT_ODDS: Record<Weather, number> = { sun: 50, rain: 30, wind: 20 };
const WEATHERS: Weather[] = ['sun', 'rain', 'wind'];

/** A [0, 1) number from a key, the same on every server and in the client (sha256's first 4 bytes). */
export function hash01(key: string): number {
  return createHash('sha256').update(key).digest().readUInt32BE(0) / 4294967296;
}

const formats = new Map<string, Intl.DateTimeFormat>();
/** The wall clock in a time zone at an instant: [year, month, day, hour] as numbers. */
export function localClock(tz: string, at: number): { y: number; m: number; d: number; h: number } {
  let f = formats.get(tz);
  if (!f) {
    f = new Intl.DateTimeFormat('en-US', { timeZone: tz, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit' });
    formats.set(tz, f);
  }
  const p = Object.fromEntries(f.formatToParts(at).map(x => [x.type, x.value]));
  return { y: +p.year, m: +p.month, d: +p.day, h: +p.hour };
}

/** The cluster a pond is in (its own field, its city's, or the home city's), and that cluster's time zone and climate. */
export function pondCity(c: P0Content, place: string): { cluster: string; tz: string; climate: string } {
  const cluster = clusterOf(c, place) ?? writtenCluster(c);
  const cl = clusterById(c, cluster);
  const home = cluster === writtenCluster(c);
  return {
    cluster,
    tz: cl?.timezone ?? (home ? c.profile.timezone : undefined) ?? 'UTC',
    climate: titleCase(cl?.climate ?? (home ? c.profile.climate : '') ?? ''),
  };
}
const titleCase = (s: string) => (s ? s[0].toUpperCase() + s.slice(1).toLowerCase() : s);

/** §6.2.1: dawn/dusk 05–08 and 17–20, night 20–05 (fish_p1.json time_windows), by the pond's local hour. */
export function daypart(c: P0Content, tz: string, at: number): Daypart {
  const h = localClock(tz, at).h;
  const w = rules(c)?.time_windows ?? { dawn_dusk: [[5, 8], [17, 20]], night: [[20, 24], [0, 5]] };
  const inside = (spans: [number, number][]) => spans.some(([a, b]) => h >= a && h < b);
  if (inside(w.night)) return 'night';
  if (inside(w.dawn_dusk)) return 'dawn_dusk';
  return 'day';
}

/** The city's date for weather, turning at 04:00 local (李白 q(109): a night's rain stays one night). */
export function weatherDate(c: P0Content, tz: string, at: number): string {
  const turn = rules(c)?.weather?.rollover_hour ?? 4;
  const k = localClock(tz, at - turn * 3_600_000);
  return `${k.y}-${String(k.m).padStart(2, '0')}-${String(k.d).padStart(2, '0')}`;
}

/** §6.2.7: one weather per city per day, the same for everyone, sun 50 / rain 30 / wind 20. */
export function weatherOn(c: P0Content, cluster: string, date: string): Weather {
  const odds = rules(c)?.weather?.odds ?? DEFAULT_ODDS;
  let roll = hash01(`${rules(c)?.seed ?? 'gensen'}:weather:${cluster}:${date}`) * WEATHERS.reduce((n, w) => n + (odds[w] ?? 0), 0);
  for (const w of WEATHERS) { roll -= odds[w] ?? 0; if (roll < 0) return w; }
  return 'sun';
}

export function weatherAt(c: P0Content, cluster: string, tz: string, at: number): Weather {
  return weatherOn(c, cluster, weatherDate(c, tz, at));
}

/** A fish's time rule: a multiplier per window (`{night: 2}`), or a window it only bites in (`night_only`). */
type TimeRule = Partial<Record<'dawn_dusk' | 'night', number>> | 'night_only' | 'dawn_dusk_only' | undefined;
const timeOf = (f: Fish): TimeRule => (f as Fish & { time?: TimeRule }).time;
const weatherMult = (f: Fish, w: Weather): number => (f as Fish & { weather?: Partial<Record<Weather, number>> }).weather?.[w] ?? 1;

/** In the pool at this time of day at all (`*_only` fish leave it outside their window). */
export function bitesAt(f: Fish, part: Daypart): boolean {
  const t = timeOf(f);
  if (t === 'night_only') return part === 'night';
  if (t === 'dawn_dusk_only') return part === 'dawn_dusk';
  return true;
}
const timeMult = (f: Fish, part: Daypart): number => {
  const t = timeOf(f);
  return t && typeof t === 'object' && part !== 'day' ? t[part] ?? 1 : 1;
};

/** A low-tier fish that can be a city's first regional fish: in a Pond all day (李白 q(109)). */
const pondAllDay = (f: Fish | undefined) => !!f && f.where.includes('pond') && typeof timeOf(f) !== 'string';

/**
 * §6.2.5: the city's 2 regional fish. Hand-picked cities (curated, by city name) keep theirs; elsewhere the cluster's
 * climate group gives the first from its low tier (only fish that bite in a Pond all day) and the second from all the
 * rest, both by a hash of the cluster id. A cluster without a climate group (unknown climate) has none.
 */
export function regionalFish(c: P0Content, cluster: string): string[] {
  const r = rules(c);
  if (!r) return [];
  for (const [city, fish] of Object.entries(r.curated)) {
    if ((HOME_ALIAS[city] ?? `city:${city}`) === cluster || clusterById(c, cluster)?.name.toLowerCase() === city) return [...fish];
  }
  const climate = titleCase(clusterById(c, cluster)?.climate ?? (cluster === writtenCluster(c) ? c.profile.climate : '') ?? '');
  const g = r.groups[climate];
  if (!g) return [];
  const byId = (id: string) => c.fish.find(f => f.id === id);
  const firsts = g.low.filter(id => pondAllDay(byId(id)));
  if (!firsts.length) return [];
  const first = firsts[Math.floor(hash01(`${r.seed ?? 'gensen'}:regional:${cluster}:1`) * firsts.length)];
  const rest = [...g.low, ...g.high].filter(id => id !== first);
  const second = rest[Math.floor(hash01(`${r.seed ?? 'gensen'}:regional:${cluster}:2`) * rest.length)];
  return second ? [first, second] : [first];
}

export interface PoolFish { fish: Fish; weight: number }
export interface Pond { cluster: string; tz: string; part: Daypart; weather: Weather; regional: string[] }

/** The pond's city, time of day, weather and regional fish at an instant. */
export function pondAt(c: P0Content, place: string, at: number): Pond {
  const { cluster, tz } = pondCity(c, place);
  return { cluster, tz, part: daypart(c, tz, at), weather: weatherAt(c, cluster, tz, at), regional: regionalFish(c, cluster) };
}

/** The site's template as a habitat word (Pond → pond). */
export const habitat = (site: FishSite): string => site.template.toLowerCase();

/**
 * §6.2.6: the fish this pond can give, by rarity tier (index 0 = Common), each with its weight. A fish is in when its
 * habitats include the template, it is global or one of the city's 2 regional fish, and it bites at this time of day.
 * Regional fish weigh 2 (with a bait whose regional_mult is 2, 4).
 */
export function poolAt(c: P0Content, site: FishSite, pond: Pond, regionalMult = 1): PoolFish[][] {
  const where = habitat(site);
  const tiers: PoolFish[][] = site.weights.map(() => []);
  for (const f of c.fish) {
    const regional = (f as Fish & { regional?: boolean }).regional === true;
    if (!f.where.includes(where)) continue;
    if (regional && !pond.regional.includes(f.id)) continue;
    if (!bitesAt(f, pond.part)) continue;
    const weight = (regional ? 2 * regionalMult : 1) * timeMult(f, pond.part) * weatherMult(f, pond.weather);
    tiers[f.rarity - 1]?.push({ fish: f, weight });
  }
  return tiers;
}

/** Every fish a pond can ever give (any time, any weather): the pond card's Details list and the "can be got" checks. */
export function everFish(c: P0Content, site: FishSite, cluster: string): Fish[] {
  const where = habitat(site), regional = regionalFish(c, cluster);
  return c.fish.filter(f => f.where.includes(where) && ((f as Fish & { regional?: boolean }).regional !== true || regional.includes(f.id)));
}

/** Every fish id some pond of the content can give, any time (a site's template × the pond's city): what "a pond or
 * river has it" means for requests, map markers and the regional request pool (苏烈's obtainable, #224). */
export function pondFishIds(c: P0Content, place?: string): Set<string> {
  const ids = new Set<string>();
  for (const [id, p] of Object.entries(c.fishing.places)) {
    if (place && id !== place) continue;
    const site = c.fishing.sites[p.site];
    if (site) for (const f of everFish(c, site, pondCity(c, id).cluster)) ids.add(f.id);
  }
  return ids;
}

/** The hour words the UI writes (283 e61cda10): Dawn (morning dawn/dusk window), Dusk (evening one), Day, Night. */
export function timeWord(c: P0Content, tz: string, at: number): 'Dawn' | 'Dusk' | 'Day' | 'Night' {
  const part = daypart(c, tz, at);
  if (part === 'night') return 'Night';
  if (part === 'day') return 'Day';
  return localClock(tz, at).h < 12 ? 'Dawn' : 'Dusk';
}

/** The next three days' weather in the pond's city (the Lv3 Forecast, 283 e61cda10): [{day: 'Sat', weather}], the days
 * turning at 04:00 there, today excluded. */
export function forecast(c: P0Content, cluster: string, tz: string, at: number): { day: string; weather: Weather }[] {
  const today = weatherDate(c, tz, at);
  const base = Date.parse(`${today}T12:00:00Z`);
  return [1, 2, 3].map(n => {
    const d = new Date(base + n * 86_400_000);
    const date = d.toISOString().slice(0, 10);
    return { day: d.toLocaleDateString('en-US', { weekday: 'short', timeZone: 'UTC' }), weather: weatherOn(c, cluster, date) };
  });
}
