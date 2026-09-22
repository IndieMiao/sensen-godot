/**
 * 农场地面属性（SGODOT-128 自由格子种田）。
 *
 * 这是农场空间的**唯一权威**：哪些格能开垦、能放道具、能站人。与 `assets/blueprints/`
 * 的地理蓝图无关——那边继续负责街道折线、地图叠加、选城页与它自己的 checksum。
 *
 * 数据是矩形区域列表而不是 mask 字符串：64×64×4 张 mask ≈ 16KB 的 0/1 串人手不可编辑、
 * diff 不可读，而农场地形本来就是块状的。光栅化规则必须与 `modules/farm/farm_plot.gd`
 * 逐字一致，两端各算一份 checksum 对账。
 */
import { createHash } from 'node:crypto';

export const PLOT_KINDS = ['soil', 'path', 'lawn', 'water', 'building', 'rock'] as const;
export type PlotKind = (typeof PLOT_KINDS)[number];

/** kind → 三个属性位。故意写死在代码里：JSON 只声明地形，不声明规则。 */
export const KIND_TRAITS: Record<PlotKind, { till: boolean; place: boolean; walk: boolean }> = {
  soil:     { till: true,  place: true,  walk: true },
  path:     { till: false, place: true,  walk: true },
  lawn:     { till: false, place: true,  walk: true },
  water:    { till: false, place: false, walk: false },
  building: { till: false, place: false, walk: false },
  rock:     { till: false, place: false, walk: false },
};

export interface PlotRegion {
  id?: string; kind: PlotKind;
  rect?: [number, number, number, number];
  ellipse?: [number, number, number, number];
  path?: [number, number][];
  width?: number;
  polygon?: [number, number][];
  holes?: [number, number][][];
}

/** Shared with FarmPlot.path_points and the ground-texture baker. Cell-centred coordinates. */
export function pathPoints(points: [number, number][]): [number, number][] {
  const out: [number, number][] = [];
  for (let i = 0; i < points.length - 1; i++) {
    const p0 = points[Math.max(0, i - 1)], p1 = points[i], p2 = points[i + 1], p3 = points[Math.min(points.length - 1, i + 2)];
    for (let step = 0; step < 8; step++) {
      const t = step / 8;
      out.push([0, 1].map(axis => .5 * (2 * p1[axis] + (-p0[axis] + p2[axis]) * t
        + (2 * p0[axis] - 5 * p1[axis] + 4 * p2[axis] - p3[axis]) * t * t
        + (-p0[axis] + 3 * p1[axis] - 3 * p2[axis] + p3[axis]) * t * t * t)) as [number, number]);
    }
  }
  if (points.length) out.push(points.at(-1)!);
  return out;
}

/** Polygon boundary belongs to the outer ring, but not to a hole. Shared with Godot. */
export function pointInRing(p: [number, number], ring: [number, number][]): boolean {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const a = ring[j], b = ring[i], dx = b[0] - a[0], dy = b[1] - a[1];
    const t = Math.max(0, Math.min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / Math.max(dx * dx + dy * dy, 1e-30)));
    if ((p[0] - a[0] - t * dx) ** 2 + (p[1] - a[1] - t * dy) ** 2 <= 1e-14) return true;
    if ((a[1] > p[1]) !== (b[1] > p[1]) && p[0] < (b[0] - a[0]) * (p[1] - a[1]) / (b[1] - a[1]) + a[0]) inside = !inside;
  }
  return inside;
}

export function regionContains(region: PlotRegion, i: number, j: number, curve = region.path ? pathPoints(region.path) : []): boolean {
  if (region.polygon) return pointInRing([i, j], region.polygon) && !(region.holes ?? []).some(hole => pointInRing([i, j], hole));
  if (region.rect) {
    const [x, y, w, h] = region.rect;
    return i >= x && i < x + w && j >= y && j < y + h;
  }
  if (region.ellipse) {
    const [x, y, rx, ry] = region.ellipse;
    if (!(rx > 0 && ry > 0)) throw new Error('Invalid plot ellipse');
    return ((i - x) / rx) ** 2 + ((j - y) / ry) ** 2 <= 1.00001;
  }
  if (region.path) {
    if (!(region.width! > 0) || curve.length < 2) throw new Error('Invalid plot path');
    const radius = region.width! / 2;
    for (let n = 1; n < curve.length; n++) {
      const a = curve[n - 1], b = curve[n], dx = b[0] - a[0], dy = b[1] - a[1];
      const t = Math.max(0, Math.min(1, ((i - a[0]) * dx + (j - a[1]) * dy) / Math.max(dx * dx + dy * dy, 1e-12)));
      if ((i - a[0] - t * dx) ** 2 + (j - a[1] - t * dy) ** 2 <= radius * radius + 1e-5) return true;
    }
    return false;
  }
  throw new Error('Missing plot region shape');
}

export interface PlotLayoutSource {
  revision: number;
  name: string;
  grid: [number, number];
  cell_mm: number;
  default_kind: PlotKind;
  anchors: Record<string, [number, number]>;
  regions: PlotRegion[];
  checksum?: string;
}

export interface PlotContent {
  format: 1;
  default_layout: string;
  layouts: Record<string, PlotLayoutSource>;
}

/** 光栅化后的布局。mask 用 Uint8Array 而不是 Set<string>：4096 个字符串 key 约 300KB。 */
export interface PlotLayout {
  id: string;
  revision: number;
  name: string;
  gx: number;
  gy: number;
  cellMm: number;
  anchors: Record<string, [number, number]>;
  kinds: Uint8Array;
  till: Uint8Array;
  place: Uint8Array;
  walk: Uint8Array;
  checksum: string;
}

const index = (p: { gx: number }, i: number, j: number): number => j * p.gx + i;

/** `"i,j"` → 格坐标；非法格式返回 null。 */
export function parseCell(id: string): [number, number] | null {
  const m = /^(\d+),(\d+)$/.exec(id);
  return m ? [Number(m[1]), Number(m[2])] : null;
}

function inBounds(p: PlotLayout, i: number, j: number): boolean {
  return i >= 0 && j >= 0 && i < p.gx && j < p.gy;
}

function bit(p: PlotLayout, mask: Uint8Array, id: string): boolean {
  const c = parseCell(id);
  if (!c || !inBounds(p, c[0], c[1])) return false;
  return mask[index(p, c[0], c[1])] === 1;
}

/** 这格能不能开垦。未开垦格不进状态，所以这是「玩家能在哪下锄」的唯一判据。 */
export const isTillable = (p: PlotLayout, id: string): boolean => bit(p, p.till, id);
/** 这格能不能放道具。与「有没有作物占着」是两回事，后者查 state.cells。 */
export const isPlaceable = (p: PlotLayout, id: string): boolean => bit(p, p.place, id);
/** 静态通行性。木本作物与道具的动态阻挡是客户端概念，服务端不寻路。 */
export const isWalkable = (p: PlotLayout, id: string): boolean => bit(p, p.walk, id);

export function rasterize(id: string, src: PlotLayoutSource): PlotLayout {
  const [gx, gy] = src.grid;
  const size = gx * gy;
  const p: PlotLayout = {
    id, revision: src.revision, name: src.name, gx, gy, cellMm: src.cell_mm,
    anchors: src.anchors, kinds: new Uint8Array(size), till: new Uint8Array(size),
    place: new Uint8Array(size), walk: new Uint8Array(size), checksum: '',
  };
  const base = PLOT_KINDS.indexOf(src.default_kind);
  p.kinds.fill(base < 0 ? 0 : base);
  for (const region of src.regions) {
    const k = PLOT_KINDS.indexOf(region.kind);
    if (k < 0) continue;
    const curve = region.path ? pathPoints(region.path) : [];
    for (let j = 0; j < gy; j++)
      for (let i = 0; i < gx; i++)
        if (regionContains(region, i, j, curve)) p.kinds[index(p, i, j)] = k;
  }
  for (let n = 0; n < size; n++) {
    const traits = KIND_TRAITS[PLOT_KINDS[p.kinds[n]]];
    p.till[n] = traits.till ? 1 : 0;
    p.place[n] = traits.place ? 1 : 0;
    p.walk[n] = traits.walk ? 1 : 0;
  }
  p.checksum = plotChecksum(p);
  return p;
}

const maskText = (m: Uint8Array): string => Array.from(m, v => (v ? '1' : '0')).join('');

/**
 * 与 `modules/farm/farm_plot.gd` 的 `canonical()` 逐字节一致。改这里必须同步改那边，
 * 两端的 golden 测试会立刻变红。
 */
export function canonical(p: PlotLayout): string {
  return [
    p.id, '1', String(p.revision), `${p.gx},${p.gy}`, String(p.cellMm),
    maskText(p.walk), maskText(p.till), maskText(p.place),
  ].join('|') + (p.id.startsWith('geo_') ? '|kinds:' + Array.from(p.kinds).join('') + '|anchors:'
    + Object.keys(p.anchors).sort().map(key => key + ':' + p.anchors[key].join(',')).join(';') : '');
}

export const plotChecksum = (p: PlotLayout): string =>
  createHash('sha256').update(canonical(p), 'utf8').digest('hex');

/** 光栅化结果按 (布局 id + checksum) 缓存：每条命令重算 4096 格没有意义。 */
const cache = new Map<string, PlotLayout>();

export function loadPlot(content: PlotContent, layoutId?: string): PlotLayout {
  const id = layoutId ?? content.default_layout;
  const src = content.layouts[id];
  if (!src) throw new Error(`unknown plot layout ${id}`);
  const key = `${id}@${src.revision}`;
  const hit = cache.get(key);
  if (hit) return hit;
  const built = rasterize(id, src);
  cache.set(key, built);
  return built;
}
