import { createHash } from 'node:crypto';
import { GeoTIFF } from 'geotiff';
import { GeographyError, type GeoFeature, type LandCoverProvider, type LandCoverSupplement } from './farm_terrain.js';
import { isFarmLocation, type FarmLocation } from '../http/farm_location.js';

const BASE_URL = 'https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/';
const BLOCK_BYTES = 32768;
const RESOLUTION_DEGREES = 1 / 12000;
const CLASSIFICATION: Record<number, Pick<GeoFeature, 'kind' | 'surface'>> = {
  10: { kind: 'land', surface: 'lawn' }, 20: { kind: 'land', surface: 'lawn' },
  30: { kind: 'land', surface: 'lawn' }, 40: { kind: 'land', surface: 'soil' },
  50: { kind: 'land', surface: 'soil' }, 60: { kind: 'desert' }, 70: { kind: 'rock' },
  80: { kind: 'water' }, 90: { kind: 'water' }, 95: { kind: 'water' }, 100: { kind: 'land', surface: 'lawn' },
};
const unavailable = () => new GeographyError('GEOGRAPHY_UNAVAILABLE');
const incomplete = () => new GeographyError('GEOGRAPHY_INCOMPLETE');
type Bounds = [west: number, south: number, east: number, north: number];
interface RangeBlock { bytes: Uint8Array; total: number; etag: string; expiresAt: number }
interface Budget { requests: number; bytes: number; reserved: number; cacheHits: number }
export interface LandCoverOptions {
  fetcher?: typeof fetch;
  timeoutMs?: number;
  maxBytes?: number;
  maxRequests?: number;
  cacheTtlMs?: number;
  maxCacheEntries?: number;
  maxCacheBytes?: number;
  now?: () => number;
  onDiagnostic?: (event: { range_requests: number; downloaded_bytes: number; cached_blocks: number; tiles: number }) => void;
}
export function worldCoverTile(latitude: number, longitude: number): string {
  const south = Math.floor(latitude / 3) * 3, west = Math.floor(longitude / 3) * 3;
  return `${south < 0 ? 'S' : 'N'}${String(Math.abs(south)).padStart(2, '0')}${west < 0 ? 'W' : 'E'}${String(Math.abs(west)).padStart(3, '0')}`;
}

interface PixelWindow {
  tile: string;
  window: [number, number, number, number];
  origin: number[];
  resolution: number[];
  width: number;
  height: number;
  values: Uint8Array;
  clip: Bounds;
}
/** Merge equal classified runs without smoothing, resampling, or filling nodata. */
function featuresForWindow(raster: PixelWindow): GeoFeature[] {
  const rectangles: { x0: number; x1: number; y0: number; y1: number; label: number }[] = [];
  let previous = new Map<string, typeof rectangles[number]>();
  for (let y = 0; y < raster.height; y++) {
    const next = new Map<string, typeof rectangles[number]>();
    for (let x = 0; x < raster.width;) {
      const label = raster.values[y * raster.width + x], start = x++;
      while (x < raster.width && raster.values[y * raster.width + x] === label) x++;
      if (label === 0) continue;
      if (!CLASSIFICATION[label]) throw incomplete();
      const key = `${start}:${x}:${label}`, prior = previous.get(key);
      if (prior) { prior.y1 = y + 1; next.set(key, prior); }
      else { const rect = { x0: start, x1: x, y0: y, y1: y + 1, label }; rectangles.push(rect); next.set(key, rect); }
    }
    previous = next;
  }
  return rectangles.map((rect, index) => {
    const west = Math.max(raster.clip[0], raster.origin[0] + (raster.window[0] + rect.x0) * raster.resolution[0]);
    const east = Math.min(raster.clip[2], raster.origin[0] + (raster.window[0] + rect.x1) * raster.resolution[0]);
    const north = Math.min(raster.clip[3], raster.origin[1] + (raster.window[1] + rect.y0) * raster.resolution[1]);
    const south = Math.max(raster.clip[1], raster.origin[1] + (raster.window[1] + rect.y1) * raster.resolution[1]);
    return { id: `esa_worldcover_2021_${raster.tile}_${raster.window[0]}_${raster.window[1]}_${index}`,
      layer: 'supplement' as const, ...CLASSIFICATION[rect.label],
      polygon: [[west, south], [east, south], [east, north], [west, north], [west, south]] as [number, number][] };
  }).filter(feature => feature.polygon[0][0] < feature.polygon[1][0] && feature.polygon[0][1] < feature.polygon[2][1]);
}

/** ESA data supplements an already successful OSM response; the caller retains that authority. */
export function createLandCoverProvider(options: LandCoverOptions = {}): LandCoverProvider {
  const timeoutMs = options.timeoutMs ?? 9000, maxBytes = options.maxBytes ?? 4 * 1024 * 1024;
  const maxRequests = options.maxRequests ?? 32, ttl = options.cacheTtlMs ?? 5 * 60_000;
  const maxEntries = options.maxCacheEntries ?? 8, maxCacheBytes = options.maxCacheBytes ?? 8 * 1024 * 1024;
  if (![timeoutMs, maxBytes, maxRequests].every(n => Number.isSafeInteger(n) && n > 0)
    || ![ttl, maxEntries, maxCacheBytes].every(n => Number.isSafeInteger(n) && n >= 0)) throw new Error('Invalid land cover limits');
  const now = options.now ?? Date.now, fetcher = options.fetcher ?? fetch;
  const blocks = new Map<string, RangeBlock>(); let cachedBytes = 0;
  const results = new Map<string, { result: LandCoverSupplement; expiresAt: number }>();
  const inFlight = new Map<string, Promise<LandCoverSupplement>>();
  const removeBlock = (key: string) => { const prior = blocks.get(key); if (prior) { cachedBytes -= prior.bytes.byteLength; blocks.delete(key); } };
  const cachedBlock = (key: string): RangeBlock | undefined => {
    const found = blocks.get(key); if (!found) return;
    if (found.expiresAt <= now()) { removeBlock(key); return; }
    blocks.delete(key); blocks.set(key, found); return found;
  };
  const cacheBlock = (key: string, block: RangeBlock) => {
    if (!ttl || !maxCacheBytes || block.bytes.byteLength > maxCacheBytes) return;
    removeBlock(key); blocks.set(key, block); cachedBytes += block.bytes.byteLength;
    while (cachedBytes > maxCacheBytes) removeBlock(blocks.keys().next().value!);
  };

  async function loadWindow(tile: string, bounds: Bounds, signal: AbortSignal, budget: Budget): Promise<PixelWindow> {
    const url = `${BASE_URL}ESA_WorldCover_10m_2021_v200_${tile}_Map.tif`;
    const local = new Map<number, RangeBlock>(), pending = new Map<string, Promise<void>>();
    let fileSize: number | null = null, etag = '';
    const accept = (block: RangeBlock) => {
      if (fileSize !== null && fileSize !== block.total || etag && etag !== block.etag) {
        for (const key of blocks.keys()) if (key.startsWith(url + ':')) removeBlock(key);
        throw unavailable();
      }
      fileSize = block.total; etag = block.etag;
    };
    const fetchBlocks = async (first: number, last: number) => {
      if (signal.aborted) throw unavailable();
      const key = `${first}:${last}`;
      if (pending.has(key)) return pending.get(key)!;
      const request = (async () => {
        const start = first * BLOCK_BYTES, end = (last + 1) * BLOCK_BYTES - 1;
        if (++budget.requests > maxRequests || (budget.reserved += end - start + 1) > maxBytes) throw unavailable();
        const response = await fetcher(url, { headers: { Range: `bytes=${start}-${end}`, accept: 'application/octet-stream',
          'user-agent': 'JourneyFarm/1.0 (ESA WorldCover land coverage)' }, signal });
        const range = /^bytes (\d+)-(\d+)\/(\d+)$/.exec(response.headers.get('content-range') ?? '');
        const tag = response.headers.get('etag');
        if (signal.aborted || response.status !== 206 || !response.body || !range || !tag || tag.length > 128) {
          void response.body?.cancel().catch(() => {}); throw unavailable();
        }
        const [actualStart, actualEnd, total] = range.slice(1).map(Number), length = actualEnd - actualStart + 1;
        if (![actualStart, actualEnd, total].every(Number.isSafeInteger) || actualStart !== start || total <= 0 || total > 4 * 1024 ** 3
          || actualEnd !== Math.min(end, total - 1) || length <= 0 || length > end - start + 1) {
          void response.body.cancel().catch(() => {}); throw unavailable();
        }
        const reader = response.body.getReader(), chunks: Uint8Array[] = []; let received = 0;
        const cancel = () => { void reader.cancel().catch(() => {}); };
        signal.addEventListener('abort', cancel, { once: true });
        try {
          while (true) {
            const part = await reader.read(); if (part.done) break;
            received += part.value.byteLength; budget.bytes += part.value.byteLength;
            if (received > length || budget.bytes > maxBytes) throw unavailable();
            chunks.push(part.value);
          }
          if (signal.aborted || received !== length) throw unavailable();
        } catch (error) { void reader.cancel().catch(() => {}); throw error; }
        finally { signal.removeEventListener('abort', cancel); reader.releaseLock(); }
        const buffer = Buffer.concat(chunks), expiresAt = now() + ttl;
        for (let block = first; block <= last && block * BLOCK_BYTES < total; block++) {
          // Copy each bounded block so one tiny cache entry cannot retain a much larger response.
          const data: RangeBlock = { bytes: Uint8Array.from(buffer.subarray((block - first) * BLOCK_BYTES, (block - first + 1) * BLOCK_BYTES)), total, etag: tag, expiresAt };
          accept(data); local.set(block, data); cacheBlock(url + ':' + block, data);
        }
      })();
      pending.set(key, request);
      try { await request; } finally { pending.delete(key); }
    };
    const source = {
      get fileSize() { return fileSize; },
      fetch: async (slices: { offset: number; length: number }[]) => Promise.all(slices.map(async ({ offset, length }) => {
        if (signal.aborted || !Number.isSafeInteger(offset) || !Number.isSafeInteger(length) || offset < 0 || length <= 0
          || length > 1024 * 1024 || offset + length > 4 * 1024 ** 3) throw unavailable();
        const first = Math.floor(offset / BLOCK_BYTES), last = Math.floor((offset + length - 1) / BLOCK_BYTES);
        const missing: number[] = [];
        for (let block = first; block <= last; block++) {
          if (!local.has(block)) { const hit = cachedBlock(url + ':' + block); if (hit) { accept(hit); local.set(block, hit); budget.cacheHits++; } }
          if (!local.has(block) && (fileSize === null || block * BLOCK_BYTES < fileSize)) missing.push(block);
        }
        for (let index = 0; index < missing.length;) {
          const begin = missing[index++]; let end = begin;
          while (index < missing.length && missing[index] === end + 1) end = missing[index++];
          await fetchBlocks(begin, end);
        }
        if (signal.aborted || fileSize === null || offset >= fileSize) throw unavailable();
        const count = Math.min(length, fileSize - offset), result = new Uint8Array(count);
        for (let i = 0; i < count;) {
          const at = offset + i, block = local.get(Math.floor(at / BLOCK_BYTES)); if (!block) throw unavailable();
          const start = at % BLOCK_BYTES, take = Math.min(count - i, block.bytes.byteLength - start);
          if (take <= 0) throw unavailable(); result.set(block.bytes.subarray(start, start + take), i); i += take;
        }
        return result.buffer;
      })),
    };
    const tiff = await GeoTIFF.fromSource(source, { cache: false }, signal), image = await tiff.getImage();
    const origin = image.getOrigin(), resolution = image.getResolution(), keys = image.getGeoKeys();
    const width = image.getWidth(), height = image.getHeight();
    if (keys.GeographicTypeGeoKey !== 4326 || keys.GTRasterTypeGeoKey !== 1 || image.getSamplesPerPixel() !== 1 || image.getBitsPerSample() !== 8
      || !Number.isSafeInteger(width) || !Number.isSafeInteger(height) || width <= 0 || height <= 0 || width > 40000 || height > 40000
      || ![image.getTileWidth(), image.getTileHeight()].every(n => Number.isSafeInteger(n) && n > 0)
      || image.getTileWidth() * image.getTileHeight() > 1024 * 1024
      || !origin.slice(0, 2).every(Number.isFinite) || Math.abs(resolution[0] - RESOLUTION_DEGREES) > 1e-10
      || Math.abs(resolution[1] + RESOLUTION_DEGREES) > 1e-10 || image.fileDirectory.ModelTransformation) throw incomplete();
    const window: [number, number, number, number] = [Math.floor((bounds[0] - origin[0]) / resolution[0]), Math.floor((bounds[3] - origin[1]) / resolution[1]),
      Math.ceil((bounds[2] - origin[0]) / resolution[0]), Math.ceil((bounds[1] - origin[1]) / resolution[1])];
    // Rounding a tile boundary can miss by one ulp, but missing coverage is never filled.
    for (const index of [0, 1]) if (window[index] === -1 && Math.abs(bounds[index === 0 ? 0 : 3] - origin[index]) < 1e-10) window[index] = 0;
    if (window[2] === width + 1 && Math.abs(bounds[2] - (origin[0] + width * resolution[0])) < 1e-10) window[2] = width;
    if (window[3] === height + 1 && Math.abs(bounds[1] - (origin[1] + height * resolution[1])) < 1e-10) window[3] = height;
    const count = (window[2] - window[0]) * (window[3] - window[1]);
    if (window[0] < 0 || window[1] < 0 || window[2] > width || window[3] > height || window[2] <= window[0] || window[3] <= window[1]
      || count > 16384) throw incomplete();
    const values = await image.readRasters({ window, samples: [0], interleave: true, signal });
    if (signal.aborted || !(values instanceof Uint8Array) || values.length !== count) throw unavailable();
    return { tile, window, origin, resolution, width: window[2] - window[0], height: window[3] - window[1], values, clip: bounds };
  }

  async function load(location: FarmLocation, extentM: number): Promise<LandCoverSupplement> {
    const controller = new AbortController(), budget: Budget = { requests: 0, bytes: 0, reserved: 0, cacheHits: 0 };
    const latRadius = extentM / 2 / 111320, lngRadius = latRadius / Math.cos(location.lat * Math.PI / 180);
    const bounds: Bounds = [location.lng - lngRadius, location.lat - latRadius, location.lng + lngRadius, location.lat + latRadius];
    if (bounds[0] < -180 || bounds[2] >= 180 || bounds[1] < -85 || bounds[3] > 85) throw incomplete();
    const windows: { tile: string; bounds: Bounds }[] = [];
    for (let south = Math.floor(bounds[1] / 3) * 3; south < bounds[3]; south += 3)
      for (let west = Math.floor(bounds[0] / 3) * 3; west < bounds[2]; west += 3)
        windows.push({ tile: worldCoverTile(south + 1, west + 1), bounds: [Math.max(west, bounds[0]), Math.max(south, bounds[1]), Math.min(west + 3, bounds[2]), Math.min(south + 3, bounds[3])] });
    if (windows.length > 4) throw incomplete();
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      const execute = async () => {
        const rasters = await Promise.all(windows.map(window => loadWindow(window.tile, window.bounds, controller.signal, budget)));
        const features = rasters.flatMap(featuresForWindow), classes: Record<string, number> = {};
        if (controller.signal.aborted) throw unavailable();
        if (!features.length || features.length > 400) throw incomplete();
        for (const raster of rasters) for (const value of raster.values) classes[String(value)] = (classes[String(value)] ?? 0) + 1;
        const source_checksum = createHash('sha256').update(JSON.stringify(rasters.map(r => ({ tile: r.tile, window: r.window, clip: r.clip, pixels: Array.from(r.values) })))).digest('hex');
        return { features, source: { provider: 'esa_worldcover' as const, dataset: 'ESA WorldCover 10m 2021 v200', year: 2021,
          license: 'CC BY 4.0', attribution: 'ESA WorldCover 2021 v200 (Zanaga et al., 2022; DOI:10.5281/zenodo.7254221)',
          resolution_m: 10, tiles: windows.map(w => w.tile), classes, source_checksum } };
      };
      const expired = new Promise<never>((_resolve, reject) => { timer = setTimeout(() => { controller.abort(); reject(unavailable()); }, timeoutMs); });
      return await Promise.race([execute(), expired]);
    } catch (error) { controller.abort(); throw error instanceof GeographyError ? error : unavailable(); }
    finally {
      if (timer !== undefined) clearTimeout(timer);
      try { options.onDiagnostic?.({ range_requests: budget.requests, downloaded_bytes: budget.bytes, cached_blocks: budget.cacheHits, tiles: windows.length }); } catch { /* Diagnostic failures cannot change data authority. */ }
    }
  }
  return async (location, extentM) => {
    if (!isFarmLocation(location) || !Number.isFinite(extentM) || extentM <= 0 || extentM > 500) throw incomplete();
    const key = JSON.stringify([location.lat, location.lng, extentM]), cached = results.get(key);
    if (cached && cached.expiresAt > now()) { results.delete(key); results.set(key, cached); return structuredClone(cached.result); }
    results.delete(key);
    let pending = inFlight.get(key);
    if (!pending) {
      pending = load({ ...location }, extentM).then(result => {
        if (ttl && maxEntries) {
          results.set(key, { result: structuredClone(result), expiresAt: now() + ttl });
          while (results.size > maxEntries) results.delete(results.keys().next().value!);
        }
        return result;
      }).finally(() => inFlight.delete(key));
      inFlight.set(key, pending);
    }
    return structuredClone(await pending);
  };
}
