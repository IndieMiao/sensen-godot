import { pointInRing } from '../domain/plot.js';
import { createHash } from 'node:crypto';
import { GeographyError, type Geography, type GeographyProvider, type GeoFeature, type GeoPoint } from './farm_terrain.js';
import type { FarmLocation } from '../http/farm_location.js';

interface OsmGeometry { lat: number; lon: number }
interface OsmMember { type: string; ref: number; role?: string; geometry?: OsmGeometry[] }
export interface OsmElement { type: string; id: number; tags?: Record<string, string>; geometry?: OsmGeometry[]; members?: OsmMember[] }
export interface OsmResult { elements: OsmElement[]; remark?: string }
const AREA_FILTERS = ['["landuse"]', '["natural"~"^(water|sand|desert|bare_rock|scree|shingle|glacier|wood|scrub|grassland|heath|wetland|beach)$"]', '["water"]', '["waterway"="riverbank"]', '["leisure"~"^(park|garden|golf_course|pitch)$"]'];

export function geographyQuery(location: FarmLocation, extentM: number): string {
  const latRadius = extentM / 2 / 111320, lngRadius = latRadius / Math.cos(location.lat * Math.PI / 180);
  const bounds = [location.lat - latRadius, location.lng - lngRadius, location.lat + latRadius, location.lng + lngRadius].map(n => n.toFixed(7)).join(',');
  // Bbox queries alone miss enclosing polygons whose vertices all fall outside the selected window.
  const probes: string[] = [];
  for (const y of [-1, 0, 1]) for (const x of [-1, 0, 1]) probes.push(`is_in(${(location.lat + y * latRadius).toFixed(7)},${(location.lng + x * lngRadius).toFixed(7)})->.a${probes.length};`);
  const enclosed = AREA_FILTERS.flatMap(filter => [`way(pivot.enclosing)${filter};`, `rel(pivot.enclosing)${filter};`]);
  return `[out:json][timeout:25][maxsize:16777216];${probes.join('')}(${probes.map((_, i) => `.a${i};`).join('')})->.enclosing;(`
    + AREA_FILTERS.map(filter => `nwr${filter}(${bounds});`).join('')
    + `way["highway"~"^(primary|secondary|tertiary|residential|unclassified|living_street|pedestrian|footway|path|track|service)$"](${bounds});`
    + `way["natural"="coastline"](${bounds});` + enclosed.join('') + ');out geom;';
}
const same = (a: GeoPoint, b: GeoPoint) => Math.abs(a[0] - b[0]) <= 1e-10 && Math.abs(a[1] - b[1]) <= 1e-10;
const coords = (geometry?: OsmGeometry[]): GeoPoint[] => (geometry ?? []).map(p => [p.lon, p.lat]);
function closedRings(parts: GeoPoint[][]): GeoPoint[][] {
  const remaining = parts.filter(p => p.length >= 2).map(p => [...p]), rings: GeoPoint[][] = [];
  while (remaining.length) {
    let ring = remaining.shift()!;
    while (!same(ring[0], ring.at(-1)!)) {
      const index = remaining.findIndex(p => same(ring.at(-1)!, p[0]) || same(ring.at(-1)!, p.at(-1)!));
      if (index < 0) throw new GeographyError('GEOGRAPHY_UNAVAILABLE');
      let next = remaining.splice(index, 1)[0];
      if (!same(ring.at(-1)!, next[0])) next = next.reverse();
      ring = [...ring, ...next.slice(1)];
    }
    if (ring.length < 4) throw new GeographyError('GEOGRAPHY_UNAVAILABLE');
    rings.push(ring);
  }
  return rings;
}
function classify(tags: Record<string, string>): Pick<GeoFeature, 'kind' | 'surface'> | null {
  if (tags.natural === 'water' || tags.water || tags.waterway === 'riverbank' || tags.landuse === 'reservoir' || tags.landuse === 'basin' || tags.natural === 'wetland') return { kind: 'water' };
  if (['sand', 'desert', 'beach'].includes(tags.natural)) return { kind: 'desert' };
  if (['bare_rock', 'scree', 'shingle', 'glacier'].includes(tags.natural) || ['quarry', 'landfill'].includes(tags.landuse)) return { kind: 'rock' };
  if (['wood', 'scrub', 'grassland', 'heath'].includes(tags.natural) || ['forest', 'meadow', 'grass', 'recreation_ground', 'village_green', 'orchard', 'vineyard'].includes(tags.landuse)
    || ['park', 'garden', 'golf_course', 'pitch'].includes(tags.leisure)) return { kind: 'land', surface: 'lawn' };
  if (['residential', 'commercial', 'retail', 'industrial', 'farmland', 'farmyard', 'allotments', 'brownfield', 'greenfield', 'construction'].includes(tags.landuse)) return { kind: 'land', surface: 'soil' };
  if (tags.highway) return { kind: 'road' };
  return null;
}

export function parseGeography(data: OsmResult, fetchedAt: string): Geography {
  if (!data || !Array.isArray(data.elements) || data.remark || data.elements.length > 20000) throw new GeographyError('GEOGRAPHY_UNAVAILABLE');
  const features: GeoFeature[] = [], seen = new Set<string>();
  // A tagged outer member may also be returned as a standalone way. Its relation owns
  // the holes; painting that way independently would refill every island.
  const ownedOuters = new Map<number, Set<GeoFeature['kind']>>();
  for (const element of data.elements) {
    const classified = element.type === 'relation' ? classify(element.tags ?? {}) : null;
    if (!classified) continue;
    for (const member of element.members ?? []) if (member.type === 'way' && (!member.role || member.role === 'outer')) {
      const kinds = ownedOuters.get(member.ref) ?? new Set<GeoFeature['kind']>();
      kinds.add(classified.kind); ownedOuters.set(member.ref, kinds);
    }
  }
  for (const element of data.elements) {
    const id = element.type + '/' + element.id;
    if (seen.has(id)) continue;
    seen.add(id);
    const classified = classify(element.tags ?? {});
    if (!classified) continue;
    if (element.type === 'way') {
      if (ownedOuters.get(element.id)?.has(classified.kind)) continue;
      const line = coords(element.geometry);
      if (line.some(p => !p.every(Number.isFinite))) throw new GeographyError('GEOGRAPHY_UNAVAILABLE');
      if (classified.kind === 'road') { if (line.length >= 2) features.push({ id, ...classified, line }); continue; }
      if (line.length < 4) throw new GeographyError('GEOGRAPHY_UNAVAILABLE');
      const rings = closedRings([line]);
      for (const polygon of rings) features.push({ id, ...classified, polygon });
    } else if (element.type === 'relation') {
      const members = element.members ?? [];
      const outer = closedRings(members.filter(m => m.type === 'way' && (!m.role || m.role === 'outer')).map(m => coords(m.geometry)));
      if (!outer.length) throw new GeographyError('GEOGRAPHY_UNAVAILABLE');
      const holes = closedRings(members.filter(m => m.type === 'way' && m.role === 'inner').map(m => coords(m.geometry)));
      const ownedHoles = outer.map(() => [] as GeoPoint[][]);
      for (const hole of holes) {
        const owners = outer.map((polygon, index) => pointInRing(hole[0], polygon) ? index : -1).filter(index => index >= 0);
        if (owners.length !== 1) throw new GeographyError('GEOGRAPHY_UNAVAILABLE');
        ownedHoles[owners[0]].push(hole);
      }
      // SVG even-odd fill and the authoritative point test must receive the same polygon.
      // A foreign hole is a filled island in SVG, so never attach one to another outer.
      outer.forEach((polygon, n) => features.push({ id: id + '/' + n, ...classified, polygon,
        ...(ownedHoles[n].length ? { holes: ownedHoles[n] } : {}) }));
    }
  }
  if (!features.length) throw new GeographyError('GEOGRAPHY_UNAVAILABLE');
  const source_checksum = createHash('sha256').update(JSON.stringify(features)).digest('hex');
  return { provider: 'osm', fetched_at: fetchedAt, features, attribution: '© OpenStreetMap contributors', license: 'ODbL 1.0', source_checksum };
}

export interface OsmDiagnostic {
  endpoint_index: number;
  reason: 'http' | 'timeout' | 'network' | 'empty_body' | 'response_too_large' | 'invalid_json' | 'invalid_data';
  http_status?: number;
}
export interface OsmProviderOptions {
  endpoint?: string;
  fetcher?: typeof fetch;
  /** Overall deadline across endpoints, including streamed body reads. */
  timeoutMs?: number;
  maxBytes?: number;
  cacheTtlMs?: number;
  maxCacheEntries?: number;
  /** Injectable cache clock; network deadlines always use the real/fake timer clock. */
  now?: () => number;
  /** Internal diagnostics contain no coordinates, query, endpoint URL or credentials. */
  onDiagnostic?: (event: OsmDiagnostic) => void;
}
class OsmFetchError extends Error {
  constructor(readonly reason: OsmDiagnostic['reason'], readonly http_status?: number) { super(reason); }
}

export function createOsmProvider(options: OsmProviderOptions = {}): GeographyProvider {
  const configuredEndpoint = options.endpoint ?? process.env.GEOGRAPHY_OVERPASS_URL;
  const endpoints = configuredEndpoint !== undefined ? [configuredEndpoint] : [
    'https://overpass-api.de/api/interpreter', 'https://overpass.kumi.systems/api/interpreter',
  ];
  const timeoutMs = options.timeoutMs ?? 30000, maxBytes = options.maxBytes ?? 8 * 1024 * 1024;
  const cacheTtlMs = options.cacheTtlMs ?? 5 * 60_000, maxCacheEntries = options.maxCacheEntries ?? 8;
  if (!Number.isFinite(timeoutMs) || timeoutMs <= 0 || !Number.isSafeInteger(maxBytes) || maxBytes <= 0
    || !Number.isFinite(cacheTtlMs) || cacheTtlMs < 0 || !Number.isSafeInteger(maxCacheEntries) || maxCacheEntries < 0)
    throw new Error('Invalid OSM provider limits');
  const now = options.now ?? Date.now;
  const cache = new Map<string, { expiresAt: number; geography: Geography }>();
  const inFlight = new Map<string, Promise<Geography>>();

  const read = async (endpoint: string, query: string, controller: AbortController): Promise<Geography> => {
    let response: Response;
    try {
      response = await (options.fetcher ?? fetch)(endpoint, { method: 'POST', signal: controller.signal,
        headers: { 'user-agent': 'JourneyFarm/1.0 (OSM geography)', accept: 'application/json', 'content-type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ data: query }) });
    } catch { throw new OsmFetchError(controller.signal.aborted ? 'timeout' : 'network'); }
    if (controller.signal.aborted) {
      void response.body?.cancel().catch(() => {});
      throw new OsmFetchError('timeout');
    }
    if (!response.ok) { controller.abort(); throw new OsmFetchError('http', response.status); }
    if (!response.body) throw new OsmFetchError('empty_body');
    const reader = response.body.getReader(), chunks: Uint8Array[] = []; let bytes = 0;
    const cancel = () => { void reader.cancel().catch(() => {}); };
    controller.signal.addEventListener('abort', cancel, { once: true });
    try {
      while (true) {
        const chunk = await reader.read(); if (chunk.done) break;
        bytes += chunk.value.byteLength;
        if (bytes > maxBytes) throw new OsmFetchError('response_too_large');
        chunks.push(chunk.value);
      }
    } catch (error) {
      controller.abort();
      // Release partially read streams on errors, including custom fetchers that ignore abort.
      void reader.cancel().catch(() => {});
      throw error instanceof OsmFetchError ? error : new OsmFetchError('network');
    } finally { controller.signal.removeEventListener('abort', cancel); reader.releaseLock(); }
    let parsed: OsmResult;
    try { parsed = JSON.parse(Buffer.concat(chunks).toString('utf8')) as OsmResult; }
    catch { throw new OsmFetchError('invalid_json'); }
    try { return parseGeography(parsed, new Date().toISOString()); }
    catch { throw new OsmFetchError('invalid_data'); }
  };

  const load = async (location: FarmLocation, extentM: number): Promise<Geography> => {
    const query = geographyQuery(location, extentM), deadline = Date.now() + timeoutMs;
    for (let index = 0; index < endpoints.length; index++) {
      const remaining = deadline - Date.now();
      if (remaining <= 0) break;
      // Reserve time for the default fallback. A configured endpoint receives the whole budget.
      const budget = Math.max(1, Math.floor(remaining / (endpoints.length - index)));
      const controller = new AbortController();
      let timer: ReturnType<typeof setTimeout> | undefined;
      try {
        const timedOut = new Promise<never>((_resolve, reject) => {
          timer = setTimeout(() => { controller.abort(); reject(new OsmFetchError('timeout')); }, budget);
        });
        const geography = await Promise.race([read(endpoints[index], query, controller), timedOut]);
        if (Date.now() > deadline) throw new OsmFetchError('timeout');
        return geography;
      } catch (error) {
        const failure = error instanceof OsmFetchError ? error : new OsmFetchError('network');
        try { options.onDiagnostic?.({ endpoint_index: index, reason: failure.reason,
          ...(failure.http_status !== undefined ? { http_status: failure.http_status } : {}) }); }
        catch { /* Observability must not prevent retry or change a successful geography response. */ }
      } finally { if (timer !== undefined) clearTimeout(timer); }
    }
    throw new GeographyError('GEOGRAPHY_UNAVAILABLE');
  };

  return async (location, extentM) => {
    // Exact full-precision selection identity; nearby points and different extents never alias.
    const key = JSON.stringify([location.lat, location.lng, extentM]), sampled = now();
    for (const [oldKey, value] of cache) if (value.expiresAt <= sampled) cache.delete(oldKey);
    const cached = cache.get(key);
    if (cached) { cache.delete(key); cache.set(key, cached); return structuredClone(cached.geography); }
    let pending = inFlight.get(key);
    if (!pending) {
      pending = load({ ...location }, extentM).then(geography => {
        if (cacheTtlMs > 0 && maxCacheEntries > 0) {
          cache.set(key, { expiresAt: now() + cacheTtlMs, geography });
          while (cache.size > maxCacheEntries) cache.delete(cache.keys().next().value!);
        }
        return geography;
      });
      inFlight.set(key, pending);
    }
    try { return structuredClone(await pending); }
    finally { if (inFlight.get(key) === pending) inFlight.delete(key); }
  };
}
