/**
 * Wild sites (v4q(3), SGODOT-355; v4 §1.4–1.5, §3.3), offline only: the world's land from Natural Earth 10m (public
 * domain) rastered once, one site at most per grid cell on land, off the big lakes and away from every city, then every
 * type dealt out at once and the guarantees made good (a ruin per continent, abyss per region, quarries of different
 * side yield and veins of different main near every cluster, a geode within reach). A closed country (q(189)) has none. Used by tools/wild_sites_build.ts, which writes
 * server/data/wild_sites.json; the server only reads that table (src/p0/wild.ts).
 *
 * Deterministic: every draw is hash32(seed, site id, topic), and the guarantees walk the clusters in a fixed order, so
 * the same land, clusters and config give the same catalogue.
 */
import { distanceKm, type CityCluster } from '../src/p0/clusters.js';
import { hash32 } from '../src/p0/world.js';

export const TYPES = ['quarry', 'vein', 'geode', 'abyss', 'ruin', 'woodland', 'waterside', 'bloom'] as const;
export type WildType = typeof TYPES[number];
const MINES = new Set<WildType>(['quarry', 'vein', 'geode', 'abyss', 'ruin']);
/** What a guarantee may turn into a quarry, vein or geode: never a ruin or abyss, never another guarantee's site. */
const LOOSE = new Set<WildType>(['woodland', 'waterside', 'bloom']);

/** A mine type's rule. `mains`: a vein has one of them (iron or quartz, the guarantee wants both near); a quarry yields
 * them all (v4 §3.3, v4q(5) ②) and is told apart by its side yield (v4q(3) review B3). */
export interface MineRule { floors: [number, number]; mains: string[]; one_main?: boolean; main_from: number; open_to?: number }
export interface WildConfig {
  grid_deg: number; city_min_km: number; lat_range: [number, number]; raster_deg: number; tries: number; jitter_deg: number;
  coastal_km: number; lake_near_km: number; open: WildType[]; map: WildType[]; map_min_zoom: number;
  exclude_countries?: string[];
  shares: Partial<Record<WildType, number>>;
  near: { trip2_km: number; quarry: number; vein: number; geode_km: number };
  abyss: [number, number]; ruin: number;
  mines: Record<'quarry' | 'vein' | 'geode' | 'abyss' | 'ruin', MineRule>;
  sides: number; type_words: Record<WildType, string>;
  /** The names' words by climate band (Tropical / Subtropical / Temperate / Cool); 李白's own pool, not the ponds' (review ⑤). */
  words?: Record<string, string[] | string>;
}

export interface Site {
  id: string; row: number; col: number; lat: number; lng: number;
  type: WildType; main: string | null; side: number | null; floors: number | null;
  coastal: boolean; wet: boolean; near: string; climate: string; continent: string; country: string;
  word: string; locked: boolean;
}

// ---- land and lakes ------------------------------------------------------------------------------------------

type Ring = number[][];   // [lng, lat] pairs, GeoJSON order
type Polygon = Ring[];

/** The polygons of a GeoJSON FeatureCollection (Polygon and MultiPolygon). */
export function polygonsOf(geo: { features: { geometry: { type: string; coordinates: unknown } | null }[] }): Polygon[] {
  const out: Polygon[] = [];
  for (const f of geo.features) {
    if (!f.geometry) continue;
    if (f.geometry.type === 'Polygon') out.push(f.geometry.coordinates as Polygon);
    else if (f.geometry.type === 'MultiPolygon') out.push(...(f.geometry.coordinates as Polygon[]));
  }
  return out;
}

/** A global lat/lng grid of cells `deg` wide, 1 inside the polygons (even–odd over every ring, holes included). */
export class Raster {
  readonly w: number; readonly h: number; readonly data: Uint16Array;
  constructor(readonly deg: number) {
    this.w = Math.round(360 / deg); this.h = Math.round(180 / deg); this.data = new Uint16Array(this.w * this.h);
  }
  private rowOf(lat: number): number { return Math.min(this.h - 1, Math.max(0, Math.floor((lat + 90) / this.deg))); }
  private colOf(lng: number): number { return ((Math.floor((lng + 180) / this.deg) % this.w) + this.w) % this.w; }
  get(lat: number, lng: number): number { return this.data[this.rowOf(lat) * this.w + this.colOf(lng)]; }

  /** Scanline fill: each row's centre line crossed by every ring edge, cells between pairs of crossings set to value. */
  fill(polys: Polygon[], value = 1): this {
    const xs: number[][] = Array.from({ length: this.h }, () => []);
    for (const poly of polys) for (const ring of poly) {
      for (let i = 0; i < ring.length - 1; i++) {
        const [x0, y0] = ring[i], [x1, y1] = ring[i + 1];
        if (y0 === y1) continue;
        const lo = Math.min(y0, y1), hi = Math.max(y0, y1);
        for (let r = Math.max(0, Math.ceil((lo + 90) / this.deg - 0.5)); r < this.h; r++) {
          const y = -90 + (r + 0.5) * this.deg;
          if (y >= hi) break;
          if (y < lo) continue;
          xs[r].push(x0 + (y - y0) * (x1 - x0) / (y1 - y0));
        }
      }
    }
    for (let r = 0; r < this.h; r++) {
      const row = xs[r].sort((a, b) => a - b);
      for (let k = 0; k + 1 < row.length; k += 2) {
        const c0 = Math.max(0, Math.ceil((row[k] + 180) / this.deg - 0.5));
        const c1 = Math.min(this.w - 1, Math.floor((row[k + 1] + 180) / this.deg - 0.5));
        for (let c = c0; c <= c1; c++) this.data[r * this.w + c] = value;
      }
    }
    return this;
  }

  /** Is any cell within km of (lat, lng) `want`? Sampled on the raster's own step. */
  within(lat: number, lng: number, km: number, want: number): boolean {
    const step = this.deg, dLat = km / 111.2, dLng = km / (111.2 * Math.max(0.05, Math.cos(lat * Math.PI / 180)));
    for (let y = -dLat; y <= dLat + 1e-9; y += step) {
      for (let x = -dLng; x <= dLng + 1e-9; x += step) {
        if ((y / dLat) ** 2 + (x / dLng) ** 2 > 1) continue;
        if (this.get(lat + y, lng + x) === want) return true;
      }
    }
    return false;
  }

  /** The cell under (lat, lng) and its 8 neighbours all `want` (a point a cell clear of any edge). */
  clear(lat: number, lng: number, want: number): boolean {
    for (let y = -1; y <= 1; y++) for (let x = -1; x <= 1; x++) if (this.get(lat + y * this.deg, lng + x * this.deg) !== want) return false;
    return true;
  }
}

// ---- clusters, by 1° buckets ---------------------------------------------------------------------------------

export class ClusterIndex {
  private readonly b = new Map<string, CityCluster[]>();
  constructor(readonly all: CityCluster[]) {
    for (const c of all) {
      const k = `${Math.floor(c.lat)},${Math.floor(c.lng)}`;
      (this.b.get(k) ?? this.b.set(k, []).get(k)!).push(c);
    }
  }
  private ring(lat: number, lng: number, r: number): CityCluster[] {
    const out: CityCluster[] = [], y0 = Math.floor(lat), x0 = Math.floor(lng);
    for (let y = y0 - r; y <= y0 + r; y++) for (let x = x0 - r; x <= x0 + r; x++) {
      if (Math.max(Math.abs(y - y0), Math.abs(x - x0)) !== r) continue;
      const xx = ((x + 180) % 360 + 360) % 360 - 180;
      out.push(...(this.b.get(`${y},${xx}`) ?? []));
    }
    return out;
  }
  /** Any cluster centre within km? */
  anyWithin(lat: number, lng: number, km: number): boolean {
    const r = Math.ceil(km / (111.2 * Math.max(0.05, Math.cos(lat * Math.PI / 180)))) + 1;
    for (let i = 0; i <= r; i++) if (this.ring(lat, lng, i).some(c => distanceKm(c, { lat, lng }) < km)) return true;
    return false;
  }
  /** The nearest cluster centre (ties by id). */
  nearest(lat: number, lng: number): CityCluster {
    let best: CityCluster | null = null, bestKm = Infinity;
    for (let i = 0; i <= 180; i++) {
      for (const c of this.ring(lat, lng, i)) {
        const d = distanceKm(c, { lat, lng });
        if (d < bestKm || (d === bestKm && best && c.id < best.id)) { best = c; bestKm = d; }
      }
      // a ring i cells out is at least (i - 1) × 111 km × cos(lat) away
      if (best && (i - 1) * 111.2 * Math.max(0.05, Math.cos(Math.min(89, Math.abs(lat) + i) * Math.PI / 180)) > bestKm) break;
    }
    return best!;
  }
}

// ---- the cells -----------------------------------------------------------------------------------------------

const u01 = (seed: string, id: string, topic: string) => hash32(seed, id, topic) / 0x1_0000_0000;
export const siteId = (row: number, col: number) => `wd-${row}-${col}`;

/** Countries by raster value (1-based), from Natural Earth admin 0 (ISO_A2, else ISO_A2_EH for France and Norway). */
export function countryRaster(deg: number, geo: { features: { properties: Record<string, string>; geometry: { type: string; coordinates: unknown } | null }[] }) {
  const r = new Raster(deg), codes = [''];
  for (const f of geo.features) {
    const code = f.properties.ISO_A2 !== '-99' ? f.properties.ISO_A2 : f.properties.ISO_A2_EH;
    codes.push(code === '-99' ? '' : code);
    r.fill(polygonsOf({ features: [f] }), codes.length - 1);
  }
  return { at: (lat: number, lng: number) => codes[r.get(lat, lng)] ?? '' };
}

/** One site at most per grid cell: the first of `tries` hashed points (the first near the centre) that is on land a raster
 * cell clear of the sea, off the big lakes, city_min_km from every cluster centre and not in a closed country (q(189)). */
export function placeSites(cfg: WildConfig, seed: string, land: Raster, lakes: Raster, clusters: ClusterIndex,
  countryAt: (lat: number, lng: number) => string = () => ''): Site[] {
  const closed = new Set(cfg.exclude_countries ?? []);
  const out: Site[] = [], g = cfg.grid_deg;
  const r0 = Math.floor((cfg.lat_range[0] + 90) / g), r1 = Math.ceil((cfg.lat_range[1] + 90) / g);
  for (let row = r0; row < r1; row++) {
    for (let col = 0; col < Math.round(360 / g); col++) {
      const id = siteId(row, col), south = row * g - 90, west = col * g - 180;
      for (let t = 0; t < cfg.tries; t++) {
        const [dy, dx] = t === 0
          ? [g / 2 + (u01(seed, id, 'jy') - 0.5) * cfg.jitter_deg, g / 2 + (u01(seed, id, 'jx') - 0.5) * cfg.jitter_deg]
          : [0.05 * g + 0.9 * g * u01(seed, id, `y${t}`), 0.05 * g + 0.9 * g * u01(seed, id, `x${t}`)];
        const lat = +(south + dy).toFixed(4), lng = +(west + dx).toFixed(4);
        if (!land.clear(lat, lng, 1) || !lakes.clear(lat, lng, 0) || clusters.anyWithin(lat, lng, cfg.city_min_km)) continue;
        const country = countryAt(lat, lng);
        if (closed.has(country)) continue;
        const near = clusters.nearest(lat, lng);
        const coastal = land.within(lat, lng, cfg.coastal_km, 0);
        out.push({ id, row, col, lat, lng, type: 'woodland', main: null, side: null, floors: null, coastal,
          wet: coastal || lakes.within(lat, lng, cfg.lake_near_km, 1), near: near.id, climate: near.climate,
          continent: near.continent, country, word: '', locked: false });
        break;
      }
    }
  }
  return out;
}

// ---- types ---------------------------------------------------------------------------------------------------

/** Sites by grid cell, for the radius searches of the guarantees. */
export class SiteIndex {
  private readonly at = new Map<string, Site>();
  constructor(readonly sites: Site[], readonly g: number) { for (const s of sites) this.at.set(`${s.row},${s.col}`, s); }
  /** Sites within km of a point, nearest first (ties by id). */
  around(lat: number, lng: number, km: number): { s: Site; km: number }[] {
    const dr = Math.ceil(km / 111.2 / this.g) + 1, dc = Math.ceil(km / (111.2 * Math.max(0.05, Math.cos(lat * Math.PI / 180))) / this.g) + 1;
    const r0 = Math.floor((lat + 90) / this.g), c0 = Math.floor((lng + 180) / this.g), cols = Math.round(360 / this.g);
    const out: { s: Site; km: number }[] = [];
    for (let r = r0 - dr; r <= r0 + dr; r++) for (let c = c0 - Math.min(dc, cols / 2); c <= c0 + Math.min(dc, cols / 2); c++) {
      const s = this.at.get(`${r},${((c % cols) + cols) % cols}`);
      if (!s) continue;
      const d = distanceKm(s, { lat, lng });
      if (d <= km) out.push({ s, km: d });
    }
    return out.sort((a, b) => a.km - b.km || (a.s.id < b.s.id ? -1 : 1));
  }
}

function setMine(cfg: WildConfig, seed: string, s: Site, type: WildType, main?: string, side?: number): void {
  s.type = type;
  if (!MINES.has(type)) { s.main = s.side = s.floors = null; return; }
  const rule = cfg.mines[type as keyof WildConfig['mines']];
  s.main = rule.one_main ? main ?? rule.mains[hash32(seed, s.id, 'main') % rule.mains.length] : null;
  s.side = side ?? hash32(seed, s.id, 'side') % cfg.sides;
  s.floors = rule.floors[0] + hash32(seed, s.id, 'floors') % (rule.floors[1] - rule.floors[0] + 1);
}

/** The base draw: each site a type by its hash over the shares; a waterside away from water is woodland. */
export function drawTypes(cfg: WildConfig, seed: string, sites: Site[]): void {
  const order = Object.entries(cfg.shares) as [WildType, number][];
  const total = order.reduce((a, [, v]) => a + v, 0);
  for (const s of sites) {
    let u = u01(seed, s.id, 'type') * total, t: WildType = order[order.length - 1][0];
    for (const [k, v] of order) { if (u < v) { t = k; break; } u -= v; }
    if (t === 'waterside' && !s.wet) t = 'woodland';
    setMine(cfg, seed, s, t);
  }
}

export interface Shortfall { cluster: string; name: string; need: string; have: number; want: number }

/**
 * The guarantees, in this order: a ruin per continent and abyss per region (lowest hash in it), then for every cluster
 * (most people first, ties by id) quarries and veins of different main within trip2_km and a geode within geode_km — the
 * nearest loose site turned when short. A site used for a guarantee is locked: later ones never turn it.
 */
export function guarantee(cfg: WildConfig, seed: string, sites: Site[], clusters: CityCluster[]): Shortfall[] {
  const short: Shortfall[] = [];
  const byHash = (topic: string) => (a: Site, b: Site) => hash32(seed, a.id, topic) - hash32(seed, b.id, topic) || (a.id < b.id ? -1 : 1);
  const group = (key: (s: Site) => string) => {
    const m = new Map<string, Site[]>();
    for (const s of sites) (m.get(key(s)) ?? m.set(key(s), []).get(key(s))!).push(s);
    return [...m.entries()].sort(([a], [b]) => (a < b ? -1 : 1));
  };
  for (const [, list] of group(s => s.continent)) {
    for (const s of [...list].sort(byHash('ruin')).slice(0, cfg.ruin)) { setMine(cfg, seed, s, 'ruin'); s.locked = true; }
  }
  for (const [key, list] of group(s => `${s.continent}|${s.climate}|${s.coastal ? 'coast' : 'inland'}`)) {
    const n = cfg.abyss[0] + hash32(seed, key, 'abyss') % (cfg.abyss[1] - cfg.abyss[0] + 1);
    for (const s of list.filter(x => !x.locked).sort(byHash('abyss')).slice(0, n)) { setMine(cfg, seed, s, 'abyss'); s.locked = true; }
  }
  const index = new SiteIndex(sites, cfg.grid_deg);
  const order = [...clusters].sort((a, b) => b.population - a.population || (a.id < b.id ? -1 : 1));
  for (const cl of order) {
    const near = index.around(cl.lat, cl.lng, cfg.near.trip2_km);
    for (const kind of ['quarry', 'vein'] as const) {
      // what tells two apart: a vein's main (iron / quartz), a quarry's side yield (it yields every main, review B3)
      const rule = cfg.mines[kind], want = cfg.near[kind], got = new Map<string, Site>();
      const keyOf = (x: Site) => String(rule.one_main ? x.main : x.side);
      const keys = rule.one_main ? rule.mains : Array.from({ length: cfg.sides }, (_, i) => String(i));
      const turn = (x: Site, k: string) => (rule.one_main ? setMine(cfg, seed, x, kind, k) : setMine(cfg, seed, x, kind, undefined, Number(k)));
      // keep what is there: one site a key, locked ones first
      for (const { s } of [...near].sort((a, b) => Number(b.s.locked) - Number(a.s.locked))) {
        if (s.type === kind && !got.has(keyOf(s)) && got.size < want) got.set(keyOf(s), s);
      }
      // short: an unlocked same-kind site with a key already counted takes a missing one, then the nearest loose site
      const missing = () => keys.filter(k => !got.has(k)).sort((a, b) => hash32(seed, cl.id, `${kind}:${a}`) - hash32(seed, cl.id, `${kind}:${b}`));
      for (const { s } of near) {
        if (got.size >= want) break;
        if (s.locked || s.type !== kind || [...got.values()].includes(s)) continue;
        const k = missing()[0]; turn(s, k); got.set(k, s);
      }
      for (const { s } of near) {
        if (got.size >= want) break;
        if (s.locked || !LOOSE.has(s.type)) continue;
        const k = missing()[0]; turn(s, k); got.set(k, s);
      }
      for (const s of got.values()) s.locked = true;
      if (got.size < want) short.push({ cluster: cl.id, name: cl.name, need: kind, have: got.size, want });
    }
    const far = index.around(cl.lat, cl.lng, cfg.near.geode_km);
    const geode = far.find(x => x.s.type === 'geode');
    if (geode) geode.s.locked = true;
    else {
      const loose = far.find(x => !x.s.locked && LOOSE.has(x.s.type));
      if (loose) { setMine(cfg, seed, loose.s, 'geode'); loose.s.locked = true; }
      else short.push({ cluster: cl.id, name: cl.name, need: 'geode', have: 0, want: 1 });
    }
  }
  return short;
}

/** Names: a word of the climate band's pool and the type word, never the same name twice within 300 km. */
export function nameSites(cfg: WildConfig, seed: string, sites: Site[], words: Record<string, string[] | string> = cfg.words ?? {}): void {
  const index = new SiteIndex(sites, cfg.grid_deg);
  for (const s of [...sites].sort((a, b) => (a.id < b.id ? -1 : 1))) {
    const band = s.climate.charAt(0).toUpperCase() + s.climate.slice(1);
    const pool = words[band];
    if (!Array.isArray(pool) || pool.length === 0) throw new Error(`no pond words for climate ${s.climate}`);
    const taken = new Set(index.around(s.lat, s.lng, 300).filter(x => x.s.word && x.s.type === s.type).map(x => x.s.word));
    const start = hash32(seed, s.id, 'word') % pool.length;
    s.word = pool[start];
    for (let i = 0; i < pool.length; i++) { const w = pool[(start + i) % pool.length]; if (!taken.has(w)) { s.word = w; break; } }
  }
}

export const fullName = (cfg: WildConfig, s: Pick<Site, 'word' | 'type'>) => `${s.word} ${cfg.type_words[s.type]}`;
