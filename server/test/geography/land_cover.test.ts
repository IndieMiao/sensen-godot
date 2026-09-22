import { describe, expect, it, vi } from 'vitest';
import { writeArrayBuffer } from 'geotiff';
import { createLandCoverProvider, worldCoverTile } from '../../src/geography/land_cover.js';
import { pointInRing } from '../../src/domain/plot.js';

const CENTER = { lat: 34.09875, lng: -118.26627 }, RES = 1 / 12000;
function fixture(fill: number | ((x: number, y: number) => number), size = 16, origin = [CENTER.lng - size / 2 * RES, CENTER.lat + size / 2 * RES], keys = {}) {
  return new Uint8Array(writeArrayBuffer(Array.from({ length: size * size }, (_, n) => typeof fill === 'number' ? fill : fill(n % size, Math.floor(n / size))), {
    width: size, height: size, BitsPerSample: [8], SamplesPerPixel: 1,
    ModelPixelScale: [RES, RES, 0], ModelTiepoint: [0, 0, 0, origin[0], origin[1], 0],
    GTModelTypeGeoKey: 2, GeographicTypeGeoKey: 4326, GTRasterTypeGeoKey: 1, ...keys,
  }));
}
function ranged(bytes: Uint8Array, headers: HeadersInit | undefined, etag = '"fixture-v1"') {
  const match = /^bytes=(\d+)-(\d+)$/.exec(new Headers(headers).get('range') ?? '');
  expect(match).not.toBeNull(); const start = Number(match![1]), end = Math.min(Number(match![2]), bytes.length - 1);
  expect(start).toBeLessThan(bytes.length);
  return new Response(bytes.slice(start, end + 1), { status: 206, headers: {
    'content-range': `bytes ${start}-${end}/${bytes.length}`, etag,
  } });
}
const server = (bytes: Uint8Array) => vi.fn<typeof fetch>(async (_url, options) => ranged(bytes, options?.headers));

describe('bounded ESA WorldCover supplemental coverage', () => {
  it('reads native classes and leaves nodata holes unclassified while preserving water/bare cover', async () => {
    const fetcher = server(fixture(x => [50, 80, 60, 0][x % 4])), provider = createLandCoverProvider({ fetcher });
    const result = await provider(CENTER, 30);
    expect(result.source).toMatchObject({ provider: 'esa_worldcover', year: 2021, resolution_m: 10, license: 'CC BY 4.0', tiles: ['N33W120'] });
    expect(result.source.classes['0']).toBeGreaterThan(0); expect(result.source.classes['50']).toBeGreaterThan(0);
    expect(new Set(result.features.map(f => f.kind))).toEqual(new Set(['land', 'water', 'desert']));
    expect(result.features.every(f => f.layer === 'supplement')).toBe(true);
    const nodata: [number, number] = [CENTER.lng - .5 * RES, CENTER.lat - .5 * RES];
    expect(result.features.some(f => pointInRing(nodata, f.polygon!))).toBe(false);
    expect(fetcher).toHaveBeenCalledTimes(1);
    expect(String(fetcher.mock.calls[0][0])).toBe('https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/ESA_WorldCover_10m_2021_v200_N33W120_Map.tif');
  });

  it('does not invent land for an all-water tile and refuses all-nodata or unknown classes', async () => {
    const water = await createLandCoverProvider({ fetcher: server(fixture(80)) })(CENTER, 30);
    expect(water.features.length).toBeGreaterThan(0); expect(water.features.every(f => f.kind === 'water')).toBe(true);
    await expect(createLandCoverProvider({ fetcher: server(fixture(0)) })(CENTER, 30)).rejects.toThrow('GEOGRAPHY_INCOMPLETE');
    await expect(createLandCoverProvider({ fetcher: server(fixture(255)) })(CENTER, 30)).rejects.toThrow('GEOGRAPHY_INCOMPLETE');
  });

  it('retains conservative wetland, mangrove, bare ground and ice classifications', async () => {
    for (const [label, kind] of [[60, 'desert'], [70, 'rock'], [90, 'water'], [95, 'water']] as const) {
      const result = await createLandCoverProvider({ fetcher: server(fixture(label)) })(CENTER, 30);
      expect(result.features.every(feature => feature.kind === kind)).toBe(true);
    }
  });

  it('refuses full-file fallbacks and malformed or truncated Range responses', async () => {
    const bytes = fixture(50);
    for (const response of [
      () => new Response(bytes, { status: 200 }),
      () => new Response(bytes, { status: 206, headers: { 'content-range': `bytes 1-${bytes.length}/${bytes.length + 1}`, etag: '"fixture"' } }),
      () => new Response(bytes.slice(1), { status: 206, headers: { 'content-range': `bytes 0-${bytes.length - 1}/${bytes.length}`, etag: '"fixture"' } }),
      () => new Response(bytes, { status: 206, headers: { etag: '"fixture"' } }),
    ]) await expect(createLandCoverProvider({ fetcher: async () => response() })(CENTER, 30)).rejects.toThrow('GEOGRAPHY_UNAVAILABLE');
  });

  it('enforces request and byte budgets before fetching another block', async () => {
    for (const limits of [{ maxRequests: 1 }, { maxBytes: 32768 }]) {
      const fetcher = server(fixture(50, 250));
      await expect(createLandCoverProvider({ fetcher, ...limits })(CENTER, 30)).rejects.toThrow('GEOGRAPHY_UNAVAILABLE');
      expect(fetcher).toHaveBeenCalledTimes(1);
    }
    const fetcher = server(fixture(50));
    await expect(createLandCoverProvider({ fetcher, maxBytes: 100 })(CENTER, 30)).rejects.toThrow('GEOGRAPHY_UNAVAILABLE');
    expect(fetcher).not.toHaveBeenCalled();
  });

  it('rejects mixed object versions, unsupported CRS and unsupported pixel resolution', async () => {
    const bytes = fixture(50, 250);
    const fetcher = vi.fn<typeof fetch>(async (_url, options) => ranged(bytes, options?.headers, new Headers(options?.headers).get('range')?.startsWith('bytes=0-') ? '"v1"' : '"v2"'));
    await expect(createLandCoverProvider({ fetcher })(CENTER, 30)).rejects.toThrow('GEOGRAPHY_UNAVAILABLE');
    await expect(createLandCoverProvider({ fetcher: server(fixture(50, 16, undefined, { GeographicTypeGeoKey: 3857 })) })(CENTER, 30)).rejects.toThrow('GEOGRAPHY_INCOMPLETE');
    await expect(createLandCoverProvider({ fetcher: server(fixture(50, 16, undefined, { ModelPixelScale: [.001, .001, 0] })) })(CENTER, 30)).rejects.toThrow('GEOGRAPHY_INCOMPLETE');
  });

  it('returns independent cached results, keys exact selections, and bounds expiry/entry retention', async () => {
    let now = Date.now(); const fetcher = server(fixture(50)), diagnostics: unknown[] = [];
    const provider = createLandCoverProvider({ fetcher, now: () => now, cacheTtlMs: 100, maxCacheEntries: 1, onDiagnostic: d => diagnostics.push(d) });
    const original = await provider(CENTER, 30), checksum = original.source.source_checksum;
    original.features[0].kind = 'water'; original.source.classes['50'] = -1;
    const repeat = await provider(CENTER, 30); expect(repeat.source.source_checksum).toBe(checksum); expect(repeat.features[0].kind).toBe('land'); expect(repeat.source.classes['50']).toBeGreaterThan(0);
    expect(fetcher).toHaveBeenCalledTimes(1); expect(diagnostics).toHaveLength(1);
    const nearby = await provider({ ...CENTER, lng: CENTER.lng + .00001 }, 30); expect(nearby.source.source_checksum).not.toBe(checksum);
    await provider(CENTER, 30); expect(diagnostics).toHaveLength(3); expect(fetcher).toHaveBeenCalledTimes(1);
    now += 101; await provider(CENTER, 30); expect(fetcher).toHaveBeenCalledTimes(2);
  });

  it('deduplicates concurrent identical selections and does not cache an unavailable response', async () => {
    const bytes = fixture(50); let calls = 0;
    const fetcher: typeof fetch = async (_url, options) => { calls++; if (calls === 1) return new Response('', { status: 503 }); return ranged(bytes, options?.headers); };
    const provider = createLandCoverProvider({ fetcher });
    await expect(provider(CENTER, 30)).rejects.toThrow('GEOGRAPHY_UNAVAILABLE');
    const [a, b] = await Promise.all([provider(CENTER, 30), provider(CENTER, 30)]);
    expect(calls).toBe(2); expect(a).toEqual(b); expect(a).not.toBe(b); expect(a.features).not.toBe(b.features);
  });

  it('does not retain byte blocks larger than the configured raw cache budget', async () => {
    const fetcher = server(fixture(50));
    const provider = createLandCoverProvider({ fetcher, maxCacheEntries: 0, maxCacheBytes: 64 });
    await provider(CENTER, 30); await provider(CENTER, 30);
    expect(fetcher).toHaveBeenCalledTimes(2);
  });

  it('times out even when an injected transport ignores AbortSignal', async () => {
    const fetcher = vi.fn<typeof fetch>(() => new Promise(() => {}));
    await expect(createLandCoverProvider({ fetcher, timeoutMs: 20 })(CENTER, 30)).rejects.toThrow('GEOGRAPHY_UNAVAILABLE');
    expect(fetcher).toHaveBeenCalledTimes(1);
  });

  it('reads the four intersected geographic tiles without wrapping negative coordinates incorrectly', async () => {
    const center = { lat: 33, lng: 120 }, urls: string[] = [];
    const fetcher: typeof fetch = async (url, options) => {
      const tile = /_(N\d\d[EW]\d\d\d)_Map\.tif/.exec(String(url))![1]; urls.push(tile);
      const west = tile.endsWith('E117'), north = tile.startsWith('N33');
      const bytes = fixture(west ? 80 : 50, 16, [west ? 120 - 16 * RES : 120, north ? 33 + 16 * RES : 33]);
      return ranged(bytes, options?.headers, '"' + tile + '"');
    };
    const result = await createLandCoverProvider({ fetcher })(center, 30);
    expect(result.source.tiles.sort()).toEqual(['N30E117', 'N30E120', 'N33E117', 'N33E120']);
    expect(new Set(urls).size).toBe(4); expect(result.features.some(f => f.kind === 'water')).toBe(true); expect(result.features.some(f => f.kind === 'land')).toBe(true);
    expect(worldCoverTile(-.01, -.01)).toBe('S03W003'); expect(worldCoverTile(0, 0)).toBe('N00E000');
  });
});
