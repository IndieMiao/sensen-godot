/** geos-wasm 封装：外部只见 GeoJSON。所有指针在本文件内分配并释放。 */
import initGeosJs from 'geos-wasm';
import { geojsonToGeosGeom, geosGeomToGeojson } from 'geos-wasm/helpers';
import type { Geometry, Polygon, Position } from 'geojson';

type Geos = Awaited<ReturnType<typeof initGeosJs>>;
interface Mem { _malloc(n: number): number; _free(p: number): void; HEAP32: Int32Array; HEAPF64: Float64Array }

let geos: Geos | null = null;

export async function initGeos(): Promise<void> {
  if (!geos) geos = await initGeosJs();
}

function G(): Geos {
  if (!geos) throw new Error('geos not initialised: await initGeos() first');
  return geos;
}
const mem = (): Mem => G().Module as unknown as Mem;

function withGeom<T>(g: Geometry, fn: (ptr: number) => T): T {
  const ptr = geojsonToGeosGeom(g, G());
  try { return fn(ptr); } finally { G().GEOSGeom_destroy(ptr); }
}

function take(ptr: number): Geometry {
  const out = geosGeomToGeojson(ptr, G()) as Geometry;
  G().GEOSGeom_destroy(ptr);
  return out;
}

export function unaryUnion(geoms: Geometry[]): Geometry {
  return withGeom({ type: 'GeometryCollection', geometries: geoms }, p => take(G().GEOSUnaryUnion(p)));
}

/** 输入必须已 noding（先过 unaryUnion）。返回每个闭合面。 */
export function polygonize(noded: Geometry): Polygon[] {
  const g = G(); const m = mem();
  return withGeom(noded, p => {
    const arr = m._malloc(4);
    m.HEAP32[arr >> 2] = p;
    const coll = g.GEOSPolygonize(arr, 1);
    m._free(arr);
    const n = g.GEOSGetNumGeometries(coll);
    const out: Polygon[] = [];
    for (let i = 0; i < n; i++) out.push(geosGeomToGeojson(g.GEOSGetGeometryN(coll, i), g) as Polygon);
    g.GEOSGeom_destroy(coll);
    return out;
  });
}

export function buffer(geom: Geometry, dist: number): Geometry {
  return withGeom(geom, p => take(G().GEOSBuffer(p, dist, 8)));
}

export function simplify(geom: Geometry, tol: number): Geometry {
  return withGeom(geom, p => take(G().GEOSTopologyPreserveSimplify(p, tol)));
}

export function intersection(a: Geometry, b: Geometry): Geometry {
  return withGeom(a, pa => withGeom(b, pb => take(G().GEOSIntersection(pa, pb))));
}

export function intersects(a: Geometry, b: Geometry): boolean {
  return withGeom(a, pa => withGeom(b, pb => G().GEOSIntersects(pa, pb) === 1));
}

function readDouble(p: number, fn: (ptr: number, out: number) => number): number {
  const m = mem(); const out = m._malloc(8);
  fn(p, out);
  const v = m.HEAPF64[out >> 3];
  m._free(out);
  return v;
}

export function area(geom: Geometry): number {
  return withGeom(geom, p => readDouble(p, (a, o) => G().GEOSArea(a, o)));
}

export function length(geom: Geometry): number {
  return withGeom(geom, p => readDouble(p, (a, o) => G().GEOSLength(a, o)));
}

export function isEmpty(geom: Geometry): boolean {
  return withGeom(geom, p => G().GEOSisEmpty(p) === 1);
}

/** 点在面内判定器（prepared geometry，适合几千次查询）。用完必须 dispose()。 */
export function preparedContains(geom: Geometry): { contains(pt: Position): boolean; dispose(): void } {
  const g = G();
  const ptr = geojsonToGeosGeom(geom, g);
  const prep = g.GEOSPrepare(ptr);
  return {
    contains(pt) {
      const pp = geojsonToGeosGeom({ type: 'Point', coordinates: pt }, g);
      const r = g.GEOSPreparedContains(prep, pp) === 1;
      g.GEOSGeom_destroy(pp);
      return r;
    },
    dispose() { g.GEOSPreparedGeom_destroy(prep); g.GEOSGeom_destroy(ptr); },
  };
}
