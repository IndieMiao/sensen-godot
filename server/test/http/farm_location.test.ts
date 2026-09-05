import { describe, expect, it } from 'vitest';
import { isFarmLocation, withinPlacementBounds } from '../../src/http/farm_location.js';

describe('farm placement validation', () => {
  it.each([null, [], {}, { lat: 31.2 }, { lat: '31.2', lng: 121.4 },
    { lat: 31.2, lng: NaN }, { lat: Infinity, lng: 121.4 }, { lat: 86, lng: 0 },
    { lat: 31.2, lng: 181 }, { lat: 31.2, lng: 121.4, label: 'unexpected' }])
  ('rejects malformed coordinates: %j', value => expect(isFarmLocation(value)).toBe(false));

  it('accepts coordinates in either hemisphere and protects the footprint at city edges', () => {
    expect(isFarmLocation({ lat: 34.0522, lng: -118.2437 })).toBe(true);
    const bounds: [number, number, number, number] = [30.67, 120.86, 31.9, 122.2];
    expect(withinPlacementBounds({ lat: 31.23, lng: 121.47 }, bounds)).toBe(true);
    expect(withinPlacementBounds({ lat: 34.05, lng: -118.24 }, bounds)).toBe(false);
    expect(withinPlacementBounds({ lat: 30.6701, lng: 121.47 }, bounds)).toBe(false);
    expect(withinPlacementBounds({ lat: 31.23, lng: 121.47 })).toBe(false);
  });
});
