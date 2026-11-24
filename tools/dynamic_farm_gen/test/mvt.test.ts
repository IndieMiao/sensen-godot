import { classifyRings, VectorTile } from '@mapbox/vector-tile';
import { PbfReader } from 'pbf';
import { describe, expect, it } from 'vitest';
import { douglasPeucker, slimPolygons } from '../src/buildings.js';
import { checkMapGeometry } from '../src/validate.js';
import type { Point, Polygon } from '../src/geo.js';
import { clipRing, DEFAULT_MAP_PARAMS, encodeTiles, mercator, resolveMapParams, ringArea2, tilePath } from '../src/mvt.js';

const decode = (bytes: Uint8Array) => new VectorTile(new PbfReader(bytes));
const p = resolveMapParams();

/** A lon/lat square of `size` degrees at (lon, lat), counter-clockwise, optionally with a centred hole. */
function square(lon: number, lat: number, size: number, hole = 0): Polygon {
  const ring = (x: number, y: number, s: number): Point[] => [[x, y], [x + s, y], [x + s, y + s], [x, y + s], [x, y]];
  const poly = [ring(lon, lat, size)];
  if (hole) poly.push(ring(lon + (size - hole) / 2, lat + (size - hole) / 2, hole).reverse());
  return poly;
}

/** Tile x/y of a lon/lat at zoom z. */
const tileOf = (pt: Point, z: number) => mercator(pt).map(v => Math.floor(v * 2 ** z)) as [number, number];

describe('web mercator', () => {
  it('matches the textbook formula', () => {
    for (const [lon, lat] of [[-122.47, 37.73], [0, 0], [151.2, -33.9], [-180, 85.05]] as Point[]) {
      const [x, y] = mercator([lon, lat]);
      expect(x).toBeCloseTo((lon + 180) / 360, 14);
      expect(y).toBeCloseTo((1 - Math.log(Math.tan(Math.PI / 4 + (lat * Math.PI) / 360)) / Math.PI) / 2, 12);
    }
  });
});

describe('clipRing', () => {
  it('cuts a square straddling the box edge and keeps one fully inside', () => {
    const ring: Point[] = [[-5, 0], [5, 0], [5, 10], [-5, 10], [-5, 0]];
    const clipped = clipRing(ring, 0, 0, 100, 100);
    expect(clipped.map(([x, y]) => `${x},${y}`).sort()).toEqual(['0,0', '0,10', '5,0', '5,10']);
    expect(clipRing(ring, -100, -100, 100, 100)).toHaveLength(4);
    expect(clipRing(ring, 50, 50, 100, 100)).toHaveLength(0);
  });
});

describe('encodeTiles', () => {
  const z = 18;
  // About 30 m across, so the square crosses the z18 tile boundary at lon -122.4705… .
  const boundaryLon = (Math.floor(mercator([-122.4705, 37.73])[0] * 2 ** z) / 2 ** z) * 360 - 180;
  const feature = {
    id: 'p-1',
    properties: { block_id: 'p-1', name: '1 TEST WAY', farm_path: 'farms/p-1.json', core_cell_count: 800, center_lon: -122.4705, neg: -3, small: true },
    polygons: [square(boundaryLon - 0.0002, 37.73, 0.0004, 0.0001)],
  };
  const tiles = encodeTiles([feature], p);

  it('writes the parcel into every tile it touches at every zoom, in one layer "parcels"', () => {
    for (let zoom = p.tile_minzoom; zoom <= p.tile_maxzoom; zoom++) {
      const [x, y] = tileOf([boundaryLon + 0.0001, 37.7302], zoom);
      expect(tiles.has(tilePath(zoom, x, y)), `z${zoom}`).toBe(true);
    }
    const [x, y] = tileOf([boundaryLon + 0.0001, 37.7302], z);
    expect(tiles.has(tilePath(z, x - 1, y))).toBe(true); // west half of the square
    for (const bytes of tiles.values()) {
      const tile = decode(bytes);
      expect(Object.keys(tile.layers)).toEqual(['parcels']);
      expect(tile.layers.parcels.version).toBe(2);
      expect(tile.layers.parcels.extent).toBe(4096);
    }
  });

  it('round-trips every property type through an independent decoder', () => {
    const tile = decode(tiles.values().next().value!);
    expect(tile.layers.parcels.feature(0).properties).toEqual(feature.properties);
  });

  it('keeps the outer ring clockwise in tile space, the hole counter-clockwise, and the shape in place', () => {
    const [x, y] = tileOf([boundaryLon + 0.0001, 37.7302], z);
    const f = decode(tiles.get(tilePath(z, x, y))!).layers.parcels.feature(0);
    const rings = f.loadGeometry();
    expect(rings).toHaveLength(2); // the hole straddles the boundary too
    const polygons = classifyRings(rings);
    expect(polygons).toHaveLength(1);
    expect(polygons[0]).toHaveLength(2);
    expect(ringArea2(rings[0].map(pt => [pt.x, pt.y]))).toBeGreaterThan(0);
    expect(ringArea2(rings[1].map(pt => [pt.x, pt.y]))).toBeLessThan(0);
    const geo = f.toGeoJSON(x, y, z).geometry;
    if (geo.type !== 'Polygon') throw new Error(geo.type);
    const lons = geo.coordinates[0].map(c => c[0]);
    const lats = geo.coordinates[0].map(c => c[1]);
    const unit = 360 / 2 ** z / 4096;
    // East half: from the tile edge minus the buffer to the square's east side.
    expect(Math.max(...lons)).toBeCloseTo(boundaryLon + 0.0002, 6);
    expect(Math.abs(Math.min(...lons) - (boundaryLon - (p.tile_buffer * unit)))).toBeLessThan(1.5 * unit);
    expect(Math.min(...lats)).toBeCloseTo(37.73, 6);
    expect(Math.max(...lats)).toBeCloseTo(37.7304, 6);
  });

  it('is deterministic and drops nothing that is larger than a tile unit', () => {
    const again = encodeTiles([feature], p);
    expect([...again.keys()]).toEqual([...tiles.keys()]);
    for (const [k, v] of again) expect(Buffer.from(v).equals(Buffer.from(tiles.get(k)!))).toBe(true);
    // A 2 cm sliver vanishes at z15 (one unit ≈ 0.3 m) but is kept as soon as it spans units.
    const sliver = { ...feature, id: 'p-2', properties: { block_id: 'p-2' }, polygons: [square(-122.47, 37.73, 0.0000002)] };
    const out = encodeTiles([sliver], p);
    expect([...out.keys()].some(k => k.startsWith('tiles/15/'))).toBe(false);
  });

  it('rejects map parameters the client cannot read', () => {
    expect(() => resolveMapParams({ tile_maxzoom: 23 })).toThrow();
    expect(() => resolveMapParams({ tile_minzoom: 19 })).toThrow();
    expect(() => resolveMapParams({ building_decimals: 4 })).toThrow();
    expect(() => resolveMapParams({ unknown: 1 } as never)).toThrow(/unknown/);
    expect(resolveMapParams({ tile_buffer: 64 })).toEqual({ ...DEFAULT_MAP_PARAMS, tile_buffer: 64 });
  });
});

describe('building map layer', () => {
  it('drops collinear vertices within the tolerance and keeps corners', () => {
    const pts: Point[] = [[0, 0], [5, 0.05], [10, 0], [10, 10], [0, 10], [0, 0]];
    expect(douglasPeucker(pts, 0.1)).toEqual([true, false, true, true, true, true]);
    expect(douglasPeucker(pts, 0.01)).toEqual([true, true, true, true, true, true]);
  });

  it('rounds to 6 decimals, simplifies, and never loses a tiny footprint', () => {
    const lon = -122.4701234567;
    const lat = 37.7301234567;
    const d = 0.0001; // ≈ 9–11 m
    const house: Polygon = [[[lon, lat], [lon + d / 2, lat + 1e-8], [lon + d, lat], [lon + d, lat + d], [lon, lat + d], [lon, lat]]];
    const [slim] = slimPolygons([house], p);
    expect(slim[0]).toHaveLength(5); // the 1 mm bump is gone
    for (const [x, y] of slim[0]) {
      expect(Math.round(x * 1e6) / 1e6).toBe(x);
      expect(Math.round(y * 1e6) / 1e6).toBe(y);
    }
    const tiny: Polygon = [[[lon, lat], [lon + 2e-7, lat], [lon + 2e-7, lat + 2e-7], [lon, lat]]];
    expect(slimPolygons([tiny], p)[0][0].length).toBeGreaterThanOrEqual(4);
  });

  it('drops a part with no area left at 7 decimals instead of writing a ring the map rejects (C-43 V-167)', () => {
    // p-0274020's second part in the hosted r5: a there-and-back sliver, 3 positions after rounding.
    const sliver: Polygon = [[[-122.41151981, 37.79044731], [-122.41151669, 37.79043029], [-122.41151979, 37.79044729], [-122.41151981, 37.79044731]]];
    const lon = -122.4701234567;
    const lat = 37.7301234567;
    const house: Polygon = [[[lon, lat], [lon + 1e-4, lat], [lon + 1e-4, lat + 1e-4], [lon, lat + 1e-4], [lon, lat]]];
    const slim = slimPolygons([house, sliver], p);
    expect(slim).toHaveLength(1);
    expect(slim[0][0]).toHaveLength(5);
    expect(slimPolygons([sliver], p)).toEqual([]);
    for (const poly of slimPolygons([house, sliver, [house[0], sliver[0]]], p)) {
      expect(checkMapGeometry({ type: 'Polygon', coordinates: poly })).toBeNull();
    }
  });
});
