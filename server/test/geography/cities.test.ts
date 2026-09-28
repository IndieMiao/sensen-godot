import { describe, expect, it } from 'vitest';
import path from 'node:path';
import { CityCatalog, cityView, distanceKm } from '../../src/geography/cities.js';
import { DEFAULT_CONTENT_DIR } from '../../src/domain/content.js';

const catalog = CityCatalog.fromRegionsFile(path.join(DEFAULT_CONTENT_DIR, 'regions.json'));

describe('CityCatalog', () => {
  it('keeps curated ids for Shanghai and Los Angeles and aliases their GeoNames entries', () => {
    expect(catalog.resolve({ lat: 31.2304, lng: 121.4737 })?.id).toBe('shanghai');
    expect(catalog.resolve({ lat: 34.0522, lng: -118.2437 })?.id).toBe('los_angeles');
    expect(catalog.get('gn-1796236')?.id).toBe('shanghai');
    expect(catalog.get('shanghai')?.timezone).toBe('Asia/Shanghai');
    expect(catalog.get('los_angeles')?.curated).toBe(true);
  });

  it.each([
    [35.6812, 139.7671, 'Tokyo', 'Asia/Tokyo'],
    [51.5074, -0.1278, 'London', 'Europe/London'],
    [1.3521, 103.8198, 'Singapore', 'Asia/Singapore'],
    [-33.8688, 151.2093, 'Sydney', 'Australia/Sydney'],
    [43.6532, -79.3832, 'Toronto', 'America/Toronto'],
    [40.6782, -73.9442, 'New York City', 'America/New_York'],
    [39.9042, 116.4074, 'Beijing', 'Asia/Shanghai'],
  ])('resolves %f,%f to %s', (lat, lng, name, tz) => {
    const city = catalog.resolve({ lat, lng });
    expect(city?.name).toBe(name);
    expect(city?.timezone).toBe(tz);
    expect(city?.id).toMatch(/^gn-\d+$/);
  });

  it('keeps a distinct large neighbour city separate', () => {
    expect(catalog.resolve({ lat: 35.4437, lng: 139.638 })?.name).toBe('Yokohama');
  });

  it('returns null far out at sea', () => {
    expect(catalog.resolve({ lat: 0, lng: -140 })).toBeNull();
  });

  it('keeps a chosen city near its border and falls back to resolving outside the tolerance', () => {
    const tokyo = catalog.resolve({ lat: 35.6812, lng: 139.7671 })!;
    const near = { lat: 35.6812 + 0.3, lng: 139.7671 };
    expect(distanceKm(near, { lat: tokyo.center[0], lng: tokyo.center[1] })).toBeLessThan(tokyo.radius_km * 1.25);
    expect(catalog.forPlacement(near, tokyo.id)?.id).toBe(tokyo.id);
    expect(catalog.forPlacement({ lat: 34.6937, lng: 135.5023 }, tokyo.id)?.name).toBe('Osaka');
  });

  it('bounds curated placement strictly by placement_bounds', () => {
    expect(catalog.forPlacement({ lat: 31.23, lng: 121.47 }, 'shanghai')?.id).toBe('shanghai');
    expect(catalog.forPlacement({ lat: 35.68, lng: 139.77 }, 'shanghai')?.name).toBe('Tokyo');
  });

  it('searches by name prefix, curated and bigger cities first', () => {
    const names = catalog.search('tok').map(c => c.name);
    expect(names[0]).toBe('Tokyo');
    expect(catalog.search('shang')[0].id).toBe('shanghai');
    expect(catalog.search('x')).toEqual([]);
  });

  it('gives every city a map bounding box', () => {
    const view = cityView(catalog.resolve({ lat: 35.68, lng: 139.77 })!, 3);
    expect(view.placement_bounds[0]).toBeLessThan(35.68);
    expect(view.placement_bounds[3]).toBeGreaterThan(139.77);
    expect(view.farm_count).toBe(3);
    expect(cityView(catalog.get('shanghai')!).placement_bounds).toEqual([30.67, 120.86, 31.9, 122.2]);
  });
});
