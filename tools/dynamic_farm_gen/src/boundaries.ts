/** Traces cell masks into rectilinear polygons (grid corner coordinates), like the r4 `boundaries`. */
import { insideRings, signedArea, type Point } from './geo.js';

export interface BoundaryPolygon { outer: Point[]; holes: Point[][] }

/**
 * Interior is kept on the right of every directed edge, so outer rings run clockwise and holes
 * counter-clockwise (y up). Diagonal pinches turn right, which keeps corner-touching parts apart.
 */
export function trace(mask: Uint8Array, w: number, h: number): BoundaryPolygon[] {
  const filled = (x: number, y: number) => x >= 0 && y >= 0 && x < w && y < h && mask[y * w + x] === 1;
  const key = (x: number, y: number) => y * (w + 1) + x;
  const out = new Map<number, Point[]>();
  const add = (a: Point, b: Point) => {
    const k = key(a[0], a[1]);
    if (!out.has(k)) out.set(k, []);
    out.get(k)!.push(b);
  };
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    if (!filled(x, y)) continue;
    if (!filled(x, y - 1)) add([x + 1, y], [x, y]);
    if (!filled(x, y + 1)) add([x, y + 1], [x + 1, y + 1]);
    if (!filled(x - 1, y)) add([x, y], [x, y + 1]);
    if (!filled(x + 1, y)) add([x + 1, y + 1], [x + 1, y]);
  }
  const rings: Point[][] = [];
  const starts = [...out.keys()].sort((a, b) => a - b);
  for (const startKey of starts) {
    while ((out.get(startKey) ?? []).length > 0) {
      const sx = startKey % (w + 1);
      const sy = (startKey - sx) / (w + 1);
      const ring: Point[] = [[sx, sy]];
      let prev: Point = [sx, sy];
      let cur = out.get(startKey)!.shift()!;
      while (!(cur[0] === sx && cur[1] === sy)) {
        ring.push(cur);
        const options = out.get(key(cur[0], cur[1]))!;
        const din = [cur[0] - prev[0], cur[1] - prev[1]];
        // Right turn of (dx, dy) in a y-up frame is (dy, -dx).
        const rank = (n: Point) => {
          const d = [n[0] - cur[0], n[1] - cur[1]];
          if (d[0] === din[1] && d[1] === -din[0]) return 0;
          if (d[0] === din[0] && d[1] === din[1]) return 1;
          return 2;
        };
        options.sort((a, b) => rank(a) - rank(b));
        prev = cur;
        cur = options.shift()!;
      }
      rings.push(simplify(ring));
    }
  }
  const outers = rings.filter(r => signedArea(r) < 0).map(r => ({ outer: r, holes: [] as Point[][] }));
  const holes = rings.filter(r => signedArea(r) > 0);
  for (const hole of holes) {
    // The cell to the right of the hole's first edge is filled and lies in the owning part.
    const [a, b] = [hole[0], hole[1]];
    const d = [Math.sign(b[0] - a[0]), Math.sign(b[1] - a[1])];
    const probe: Point = [a[0] + d[0] * 0.5 + d[1] * 0.5, a[1] + d[1] * 0.5 - d[0] * 0.5];
    let owner: { outer: Point[]; holes: Point[][] } | null = null;
    for (const o of outers) {
      if (!insideRings([o.outer], probe[0], probe[1])) continue;
      if (!owner || Math.abs(signedArea(o.outer)) < Math.abs(signedArea(owner.outer))) owner = o;
    }
    if (!owner) throw new Error('hole without an outer ring');
    owner.holes.push(hole);
  }
  const first = (r: Point[]) => r[0][0] * 1e6 + r[0][1];
  for (const o of outers) o.holes.sort((a, b) => first(a) - first(b));
  outers.sort((a, b) => first(a.outer) - first(b.outer));
  return outers.map(o => ({ outer: close(o.outer), holes: o.holes.map(close) }));
}

/** Drops collinear vertices and starts at the smallest (x, then y) corner. */
function simplify(ring: Point[]): Point[] {
  const n = ring.length;
  const corners: Point[] = [];
  for (let i = 0; i < n; i++) {
    const a = ring[(i + n - 1) % n];
    const b = ring[i];
    const c = ring[(i + 1) % n];
    if ((b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]) !== 0) corners.push(b);
  }
  let start = 0;
  for (let i = 1; i < corners.length; i++) {
    const [x, y] = corners[i];
    const [bx, by] = corners[start];
    if (x < bx || (x === bx && y < by)) start = i;
  }
  return [...corners.slice(start), ...corners.slice(0, start)];
}

function close(ring: Point[]): Point[] {
  return [...ring, ring[0]];
}
