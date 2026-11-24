import { describe, expect, it } from 'vitest';
import { httpFailure, SOURCES } from '../src/sources.js';

describe('source fetch failures (C-75)', () => {
  it('does not retry a Socrata 403 and names the regional block and the way out', () => {
    const f = httpFailure(403, 'https://data.sf.gov/resource/ynuv-fyni.geojson', true);
    expect(f.retry).toBe(false);
    expect(f.message).toMatch(/^HTTP 403 for https:\/\/data\.sf\.gov\//);
    expect(f.message).toContain('not a missing app token');
    expect(f.message).toContain('sfgis-*');
    expect(f.message).toContain('NODE_USE_ENV_PROXY=1');
  });

  it('retries only transient statuses and keeps other messages plain', () => {
    expect(httpFailure(403, 'https://x/', false)).toEqual({ message: 'HTTP 403 for https://x/', retry: false });
    expect(httpFailure(404, 'https://x/', true).retry).toBe(false);
    for (const s of [408, 429, 500, 503]) expect(httpFailure(s, 'https://x/', true).retry).toBe(true);
  });

  it('points the DataSF sources at the current data.sf.gov domain', () => {
    expect(SOURCES['datasf-parcels'].url).toBe('https://data.sf.gov/resource/acdm-wktn.geojson');
    expect(SOURCES['datasf-buildings'].url).toBe('https://data.sf.gov/resource/ynuv-fyni.geojson');
  });
});
