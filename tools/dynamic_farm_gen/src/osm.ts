/**
 * OpenStreetMap buildings from an OSM PBF extract (C-113). OSM data is © OpenStreetMap
 * contributors under the ODbL 1.0: a dataset built from it must say so and stay under the ODbL
 * (README). The public Overpass servers were at capacity and too slow from our network for a whole
 * city, so the source is one versioned extract file whose bytes and hash the snapshot keeps.
 *
 * `osmBuildings` reads the extract (PBF: OSMHeader + OSMData blocks, raw or zlib blobs) and returns
 * the buildings inside a bbox as GeoJSON features the snapshot reader and the audit already
 * understand. Closed `building=*` ways become polygons; `type=multipolygon` building relations are
 * assembled from their member ways. `area_id` is the way id, or the negated relation id (the two id
 * spaces overlap). Coordinates are OSM's own 7-decimal values.
 */
import { inflateSync } from 'node:zlib';
import { PbfReader } from 'pbf';
import type { Polygon } from './geo.js';

type Pt = [number, number];

/** `building` values that mean "no building here" (explicit no, lifecycle values). */
const NOT_BUILDINGS = new Set(['no', 'demolished', 'razed', 'destroyed', 'proposed']);
export const isBuilding = (value: string | undefined) => value !== undefined && !NOT_BUILDINGS.has(value);

const same = (a: Pt, b: Pt) => a[0] === b[0] && a[1] === b[1];
const closed = (r: Pt[]) => r.length >= 4 && same(r[0], r[r.length - 1]);

/** Joins way segments end to end into closed rings; segments that never close are dropped. */
export function joinRings(segments: Pt[][]): Pt[][] {
  const open = segments.filter(s => s.length >= 2).map(s => [...s]);
  const rings: Pt[][] = [];
  while (open.length > 0) {
    let current = open.shift()!;
    for (let grown = true; !closed(current) && grown;) {
      grown = false;
      for (let i = 0; i < open.length; i++) {
        const s = open[i];
        const end = current[current.length - 1];
        if (same(end, s[0])) current = current.concat(s.slice(1));
        else if (same(end, s[s.length - 1])) current = current.concat([...s].reverse().slice(1));
        else continue;
        open.splice(i, 1);
        grown = true;
        break;
      }
    }
    if (closed(current)) rings.push(current);
  }
  return rings;
}

function inside(r: Pt[], [x, y]: Pt): boolean {
  let hit = false;
  for (let i = 0, j = r.length - 1; i < r.length; j = i++) {
    if ((r[i][1] > y) !== (r[j][1] > y) && x < ((r[j][0] - r[i][0]) * (y - r[i][1])) / (r[j][1] - r[i][1]) + r[i][0]) hit = !hit;
  }
  return hit;
}

/** Outer rings (any role but `inner`) with each inner ring in the first outer that holds it. */
export function multipolygon(outer: Pt[][], inner: Pt[][]): Polygon[] {
  const polys: Polygon[] = joinRings(outer).map(o => [o]);
  for (const ring of joinRings(inner)) polys.find(p => inside(p[0], ring[0]))?.push(ring);
  return polys;
}

export interface OsmFeature {
  type: 'Feature';
  properties: { area_id: number; osm_type: 'way' | 'relation'; osm_id: number; building: string };
  geometry: { type: 'Polygon' | 'MultiPolygon'; coordinates: Polygon | Polygon[] };
}

export interface OsmHeader { writing_program: string | null; source: string | null; replication_timestamp: string | null }

interface Way { id: number; refs: number[]; tags: Map<string, string> }
interface Relation { id: number; tags: Map<string, string>; members: { type: number; ref: number; role: string }[] }

/** Blocks of a PBF file: [type, decompressed bytes]. */
function* blocks(file: Uint8Array): Generator<[string, Uint8Array]> {
  const view = new DataView(file.buffer, file.byteOffset, file.byteLength);
  for (let pos = 0; pos < file.length;) {
    const headerLength = view.getUint32(pos);
    pos += 4;
    const header = new PbfReader(file.subarray(pos, pos + headerLength)).readFields((tag, h: { type: string; size: number }, p) => {
      if (tag === 1) h.type = p.readString();
      else if (tag === 3) h.size = p.readVarint();
    }, { type: '', size: 0 });
    pos += headerLength;
    const blob = new PbfReader(file.subarray(pos, pos + header.size)).readFields((tag, b: { raw?: Uint8Array; zlib?: Uint8Array; other?: number }, p) => {
      if (tag === 1) b.raw = p.readBytes();
      else if (tag === 3) b.zlib = p.readBytes();
      else if (tag === 4 || tag === 5 || tag === 6 || tag === 7) b.other = tag;
    }, {});
    pos += header.size;
    if (blob.other) throw new Error(`OSM PBF: blob compression ${blob.other} is not supported (only raw and zlib)`);
    yield [header.type, blob.raw ?? inflateSync(blob.zlib ?? new Uint8Array())];
  }
}

function readHeader(bytes: Uint8Array): OsmHeader {
  return new PbfReader(bytes).readFields((tag, h: OsmHeader, p) => {
    if (tag === 16) h.writing_program = p.readString();
    else if (tag === 17) h.source = p.readString();
    else if (tag === 32) h.replication_timestamp = new Date(p.readVarint(true) * 1000).toISOString();
  }, { writing_program: null, source: null, replication_timestamp: null });
}

interface Block { strings: string[]; granularity: number; lat0: number; lon0: number; groups: Uint8Array[] }

function readBlock(bytes: Uint8Array): Block {
  return new PbfReader(bytes).readFields((tag, b: Block, p) => {
    if (tag === 1) {
      const strings = p.readBytes();
      new PbfReader(strings).readFields((t, list: string[], q) => { if (t === 1) list.push(q.readString()); }, b.strings);
    } else if (tag === 2) b.groups.push(p.readBytes());
    else if (tag === 17) b.granularity = p.readVarint();
    else if (tag === 19) b.lat0 = p.readVarint(true);
    else if (tag === 20) b.lon0 = p.readVarint(true);
  }, { strings: [], granularity: 100, lat0: 0, lon0: 0, groups: [] });
}

const tagsOf = (keys: number[], vals: number[], strings: string[]) => new Map(keys.map((k, i) => [strings[k], strings[vals[i]]]));
const delta = (values: number[]) => { for (let i = 1; i < values.length; i++) values[i] += values[i - 1]; return values; };

/** Node coordinates in 1e-7 degrees, kept sorted by id for binary search (PBF files are id-sorted). */
class NodeStore {
  ids = new Float64Array(1 << 20);
  lon = new Int32Array(1 << 20);
  lat = new Int32Array(1 << 20);
  n = 0;
  sorted = true;
  add(id: number, lon: number, lat: number) {
    if (this.n === this.ids.length) {
      const grow = <T extends Float64Array | Int32Array>(a: T): T => { const b = new (a.constructor as new (n: number) => T)(a.length * 2); b.set(a); return b; };
      this.ids = grow(this.ids); this.lon = grow(this.lon); this.lat = grow(this.lat);
    }
    if (this.n > 0 && id <= this.ids[this.n - 1]) this.sorted = false;
    this.ids[this.n] = id; this.lon[this.n] = lon; this.lat[this.n] = lat; this.n++;
  }
  get(id: number): Pt | null {
    let lo = 0;
    let hi = this.n - 1;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      const v = this.ids[mid];
      if (v === id) return [this.lon[mid] / 1e7, this.lat[mid] / 1e7];
      if (v < id) lo = mid + 1; else hi = mid - 1;
    }
    return null;
  }
}

/**
 * Buildings of an OSM PBF extract whose bounds meet `bbox` ([minLon, minLat, maxLon, maxLat]),
 * ways first (by id), then relations (by id). Two passes: relations name the member ways to keep.
 */
export function osmBuildings(file: Uint8Array, bbox: number[]): { header: OsmHeader; features: OsmFeature[] } {
  let header: OsmHeader = { writing_program: null, source: null, replication_timestamp: null };
  const relations: Relation[] = [];
  const memberWays = new Set<number>();
  for (const [type, bytes] of blocks(file)) {
    if (type === 'OSMHeader') { header = readHeader(bytes); continue; }
    if (type !== 'OSMData') continue;
    const block = readBlock(bytes);
    for (const group of block.groups) {
      new PbfReader(group).readFields((tag, _: null, p) => {
        if (tag !== 4) return;
        const r = p.readMessage((t, rel: { id: number; keys: number[]; vals: number[]; roles: number[]; ids: number[]; types: number[] }, q) => {
          if (t === 1) rel.id = q.readVarint(true);
          else if (t === 2) q.readPackedVarint(rel.keys);
          else if (t === 3) q.readPackedVarint(rel.vals);
          else if (t === 8) q.readPackedVarint(rel.roles, true);
          else if (t === 9) q.readPackedSVarint(rel.ids);
          else if (t === 10) q.readPackedVarint(rel.types);
        }, { id: 0, keys: [], vals: [], roles: [], ids: [], types: [] });
        const tags = tagsOf(r.keys, r.vals, block.strings);
        if (tags.get('type') !== 'multipolygon' || !isBuilding(tags.get('building'))) return;
        const ids = delta(r.ids);
        const members = ids.map((ref, i) => ({ type: r.types[i], ref, role: block.strings[r.roles[i]] ?? '' }));
        for (const m of members) if (m.type === 1) memberWays.add(m.ref);
        relations.push({ id: r.id, tags, members });
      }, null);
    }
  }

  const nodes = new NodeStore();
  const ways = new Map<number, Way>();
  for (const [type, bytes] of blocks(file)) {
    if (type !== 'OSMData') continue;
    const block = readBlock(bytes);
    // lon/lat in 1e-7 degrees (OSM's precision): offset and granularity are in nanodegrees.
    const lon7 = (v: number) => Math.round((block.lon0 + block.granularity * v) / 100);
    const lat7 = (v: number) => Math.round((block.lat0 + block.granularity * v) / 100);
    for (const group of block.groups) {
      new PbfReader(group).readFields((tag, _: null, p) => {
        if (tag === 2) {
          const dense = p.readMessage((t, d: { ids: number[]; lat: number[]; lon: number[] }, q) => {
            if (t === 1) q.readPackedSVarint(d.ids);
            else if (t === 8) q.readPackedSVarint(d.lat);
            else if (t === 9) q.readPackedSVarint(d.lon);
          }, { ids: [], lat: [], lon: [] });
          delta(dense.ids); delta(dense.lat); delta(dense.lon);
          for (let i = 0; i < dense.ids.length; i++) nodes.add(dense.ids[i], lon7(dense.lon[i]), lat7(dense.lat[i]));
        } else if (tag === 1) {
          const n = p.readMessage((t, nd: { id: number; lat: number; lon: number }, q) => {
            if (t === 1) nd.id = q.readSVarint();
            else if (t === 8) nd.lat = q.readSVarint();
            else if (t === 9) nd.lon = q.readSVarint();
          }, { id: 0, lat: 0, lon: 0 });
          nodes.add(n.id, lon7(n.lon), lat7(n.lat));
        } else if (tag === 3) {
          const w = p.readMessage((t, way: { id: number; keys: number[]; vals: number[]; refs: number[] }, q) => {
            if (t === 1) way.id = q.readVarint(true);
            else if (t === 2) q.readPackedVarint(way.keys);
            else if (t === 3) q.readPackedVarint(way.vals);
            else if (t === 8) q.readPackedSVarint(way.refs);
          }, { id: 0, keys: [], vals: [], refs: [] });
          const tags = tagsOf(w.keys, w.vals, block.strings);
          if (isBuilding(tags.get('building')) || memberWays.has(w.id)) ways.set(w.id, { id: w.id, refs: delta(w.refs), tags });
        }
      }, null);
    }
  }
  if (!nodes.sorted) throw new Error('OSM PBF: nodes are not sorted by id');

  const line = (refs: number[]): Pt[] | null => {
    const pts: Pt[] = [];
    for (const ref of refs) { const p = nodes.get(ref); if (!p) return null; pts.push(p); }
    return pts;
  };
  const [minLon, minLat, maxLon, maxLat] = bbox;
  const meets = (polys: Polygon[]) => {
    let x0 = Infinity; let y0 = Infinity; let x1 = -Infinity; let y1 = -Infinity;
    for (const poly of polys) for (const [x, y] of poly[0]) { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); }
    return x1 >= minLon && x0 <= maxLon && y1 >= minLat && y0 <= maxLat;
  };
  const features: OsmFeature[] = [];
  const emit = (osm_type: 'way' | 'relation', id: number, building: string, polys: Polygon[]) => {
    if (polys.length === 0 || !meets(polys)) return;
    features.push({
      type: 'Feature',
      properties: { area_id: osm_type === 'way' ? id : -id, osm_type, osm_id: id, building },
      geometry: polys.length === 1 ? { type: 'Polygon', coordinates: polys[0] } : { type: 'MultiPolygon', coordinates: polys },
    });
  };
  for (const id of [...ways.keys()].sort((a, b) => a - b)) {
    const way = ways.get(id)!;
    const building = way.tags.get('building');
    if (!isBuilding(building)) continue;
    const ring = line(way.refs);
    if (ring && closed(ring)) emit('way', id, building!, [[ring]]);
  }
  for (const rel of relations.sort((a, b) => a.id - b.id)) {
    const parts = (inner: boolean) => rel.members
      .filter(m => m.type === 1 && (m.role === 'inner') === inner)
      .map(m => (ways.has(m.ref) ? line(ways.get(m.ref)!.refs) : null))
      .filter((r): r is Pt[] => r !== null);
    emit('relation', rel.id, rel.tags.get('building')!, multipolygon(parts(false), parts(true)));
  }
  return { header, features };
}
