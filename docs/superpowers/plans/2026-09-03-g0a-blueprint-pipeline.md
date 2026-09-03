# G0-A 街区蓝图离线管线 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 从 OSM 道路数据离线生成上海、洛杉矶各 3 个街区蓝图（外加 1 个合成安全蓝图），产出 Godot 可直接加载的 `farm_blueprint.json`、地图高亮用 `map_overlay.geojson`、预览 PNG、公平校验报告和 `regions.json`。

**Architecture:** Node.js + TypeScript 包 `tools/geo_blueprint/`（2026-09-03 拍板：服务端与工具统一 Node）。管线为 抓取（带缓存）→ 本地横轴墨卡托投影 → 道路与窗口边界 polygonize → 选 3-7 个主区块 → 等比缩放到 64 m 游玩区 → 栅格化四张 mask → 摆锚点与田畦 → 校验 → 写文件。所有几何运算收口在一个 `geos.ts` 封装里（`geos-wasm`，即 GEOS 本体），其余模块只操作 GeoJSON 与纯数据。合成安全蓝图走同一条 `buildFromLines`，只是跳过抓取。vitest 用一个手写的「井字路网」fixture 覆盖每一步。

**Tech Stack:** Node 22 LTS、pnpm、TypeScript（NodeNext）、`geos-wasm` 3.1（已在本机 spike 验证：unary union + polygonize + buffer + prepared contains + simplify 全可用）、`proj4`（tmerc）、`pngjs`、`undici`（让 `fetch` 走 `https_proxy`）、vitest、tsx。

## Global Constraints

- 数据源只用 OSM（Overpass 一次性抓取），缓存入库；不抽取 Mapbox Streets 数据（PRD §11.4）。
- 游玩区归一化 64×64 m，地面网格 1 m，田格 1 格 = 1 m（G0 灰盒口径；2 m 田格的视觉放大在 Godot 侧做），田畦 = 横向连续 3 格，初始 3 畦 9 格 + 预留第 4 畦 3 格。
- 步道宽 3 m（游戏单位，不随缩放），走速 2.5 m/s，单格动作 2.0 s；出生点到最远田格 ≤ 12 s；三蓝图间时间差 < 10%。
- 蓝图 revision 不可变：输出目录 `assets/blueprints/<layout_patch_id>/r<revision>/`。
- 坐标约定：蓝图局部坐标 x 向东、y 向北、单位米、原点在游玩区西南角；mask 行索引 = y，列索引 = x；Godot 世界系 x = x，z = −y。GeoJSON 坐标顺序 `[lng, lat]`；蓝图 `overlay_wgs84` 与 `source.center` 用 `[lat, lng]`。
- checksum = sha256(canonical 字符串)，canonical 定义见 Task 7，Godot 侧（G0-B Task 1）必须逐字一致。
- 抓取时走本机代理：`https_proxy=http://127.0.0.1:7890`（Node 的 `fetch` 默认不读该变量，`osm.ts` 用 undici 的 `EnvHttpProxyAgent` 接上）。
- TS 源码内相对导入带 `.js` 后缀（NodeNext 约定），tsx 与 vitest 都能解析。
- `geos-wasm` 的几何指针只在 `src/geos.ts` 内出现，其他文件不得直接 import `geos-wasm`。

## File Structure

```
tools/geo_blueprint/
  package.json / pnpm-lock.yaml / tsconfig.json / vitest.config.ts
  candidates.json                 两城、六候选、时区、street_zoom、pitch（管线唯一输入）
  src/config.ts                   常量、路径、候选加载
  src/types.ts                    Blueprint / Masks / Anchors / Report 类型
  src/geos.ts                     geos-wasm 封装（GeoJSON 进出）
  src/osm.ts                      Overpass 查询、缓存、解析 Way
  src/topology.ts                 投影、裁剪、polygonize
  src/normalize.ts                选块、缩放、简化、邻接
  src/masks.ts                    栅格化
  src/anchors.ts                  BFS、锚点、田畦、校验
  src/writer.ts                   canonical/checksum、json/geojson/png、regions.json
  src/pipeline.ts                 buildFromLines / buildCandidate / syntheticSafe
  src/cli.ts                      CLI
  cache/<layout_patch_id>.json    Overpass 原始响应（入库）
  test/fixtures/grid_overpass.json
  test/*.test.ts
assets/blueprints/<id>/r1/{farm_blueprint.json, map_overlay.geojson, preview.png, report.json}
assets/farm/data/regions.json
```

---

### Task 1: 包骨架、候选配置、geos 封装冒烟

**Files:**
- Create: `tools/geo_blueprint/package.json`、`tsconfig.json`、`vitest.config.ts`
- Create: `tools/geo_blueprint/candidates.json`
- Create: `tools/geo_blueprint/src/config.ts`、`src/types.ts`、`src/geos.ts`
- Create: `tools/geo_blueprint/test/config.test.ts`、`test/geos.test.ts`
- Modify: `.gitignore`（追加两行）

**Interfaces:**
- Produces: `config` 常量 `PLAY_AREA_M=64, GRID=64, CELL_M=1, PATH_WIDTH_M=3, WALK_SPEED=2.5, ACTION_S=2, MAX_FAR_BED_S=12, MIN_BLOCKS=3, MAX_BLOCKS=7, BED_CELLS=3, INITIAL_BEDS=3`；路径 `PKG_DIR, REPO_ROOT, CANDIDATES_FILE, CACHE_DIR, BLUEPRINTS_DIR, REGIONS_OUT`；`loadRegions(file?) -> Region[]`、`loadCandidates(file?) -> Candidate[]`、`candidate(id) -> Candidate`；`Candidate {regionId, layoutPatchId, name, lat, lng, radiusM}`。
- Produces: `geos.initGeos(): Promise<void>`（用前必须调一次），`unaryUnion(geoms) -> Geometry`、`polygonize(noded) -> Polygon[]`、`buffer(g, dist)`、`simplify(g, tol)`、`intersection(a, b)`、`intersects(a, b) -> boolean`、`area(g)`、`length(g)`、`isEmpty(g)`、`preparedContains(g) -> {contains(pt), dispose()}`。
- Produces: `types.ts` 里 `Cell=[number,number]`、`Masks`、`Bed`、`Anchors`、`Report`、`Blueprint`。

- [ ] **Step 1: 写 package.json / tsconfig / vitest 配置 / .gitignore**

`tools/geo_blueprint/package.json`：
```json
{
  "name": "geo-blueprint",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "vitest run",
    "typecheck": "tsc --noEmit",
    "cli": "tsx src/cli.ts"
  },
  "dependencies": {
    "geos-wasm": "^3.1.1",
    "pngjs": "^7.0.0",
    "proj4": "^2.15.0",
    "undici": "^7.0.0"
  },
  "devDependencies": {
    "@types/geojson": "^7946.0.16",
    "@types/node": "^22.0.0",
    "@types/pngjs": "^6.0.5",
    "@types/proj4": "^2.5.6",
    "tsx": "^4.19.0",
    "typescript": "^5.6.0",
    "vitest": "^2.1.0"
  }
}
```

`tools/geo_blueprint/tsconfig.json`：
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "resolveJsonModule": true,
    "types": ["node"],
    "noEmit": true
  },
  "include": ["src", "test"]
}
```

`tools/geo_blueprint/vitest.config.ts`：
```ts
import { defineConfig } from 'vitest/config';
export default defineConfig({ test: { include: ['test/**/*.test.ts'], testTimeout: 30000 } });
```

`.gitignore` 追加：
```
tools/geo_blueprint/node_modules/
tools/geo_blueprint/.tmp/
```

- [ ] **Step 2: 写候选配置**

`tools/geo_blueprint/candidates.json`（初始中心点，Task 9/10 目视后可换）：
```json
{
  "format": 1,
  "regions": [
    {"id": "shanghai", "name": "上海", "timezone": "Asia/Shanghai",
     "center": [31.2304, 121.4737], "street_zoom": 16.0, "pitch": 45.0,
     "candidates": [
       {"layout_patch_id": "sh_a", "name": "衡山路", "lat": 31.2076, "lng": 121.4432, "radius_m": 200},
       {"layout_patch_id": "sh_b", "name": "老城厢", "lat": 31.2265, "lng": 121.4915, "radius_m": 200},
       {"layout_patch_id": "sh_c", "name": "愚园路", "lat": 31.2240, "lng": 121.4450, "radius_m": 200}
     ]},
    {"id": "los_angeles", "name": "Los Angeles", "timezone": "America/Los_Angeles",
     "center": [34.0522, -118.2437], "street_zoom": 16.0, "pitch": 45.0,
     "candidates": [
       {"layout_patch_id": "la_a", "name": "Historic Core", "lat": 34.0455, "lng": -118.2495, "radius_m": 200},
       {"layout_patch_id": "la_b", "name": "Venice Canals", "lat": 33.9822, "lng": -118.4665, "radius_m": 200},
       {"layout_patch_id": "la_c", "name": "Silver Lake", "lat": 34.0870, "lng": -118.2745, "radius_m": 200}
     ]}
  ]
}
```

- [ ] **Step 3: 写失败测试**

`tools/geo_blueprint/test/config.test.ts`：
```ts
import { describe, it, expect } from 'vitest';
import * as config from '../src/config.js';

describe('config', () => {
  it('loads six candidates across two regions', () => {
    const c = config.loadCandidates();
    expect(c).toHaveLength(6);
    expect(new Set(c.map(x => x.regionId))).toEqual(new Set(['shanghai', 'los_angeles']));
    expect(c.every(x => x.radiusM > 0)).toBe(true);
  });
  it('constants', () => {
    expect(config.PLAY_AREA_M).toBe(64); expect(config.GRID).toBe(64);
    expect(config.PATH_WIDTH_M).toBe(3); expect(config.WALK_SPEED).toBe(2.5);
  });
});
```

`tools/geo_blueprint/test/geos.test.ts`：
```ts
import { describe, it, expect, beforeAll } from 'vitest';
import type { LineString } from 'geojson';
import * as geos from '../src/geos.js';

const line = (c: number[][]): LineString => ({ type: 'LineString', coordinates: c });

describe('geos wrapper', () => {
  beforeAll(geos.initGeos);
  it('unaryUnion + polygonize cuts a hash grid inside a window into 9 faces', () => {
    const H = 150;
    const noded = geos.unaryUnion([
      line([[-160, 100], [160, 100]]), line([[-160, -100], [160, -100]]),
      line([[-105, 160], [-105, -160]]), line([[105, 160], [105, -160]]),
      line([[-H, -H], [H, -H], [H, H], [-H, H], [-H, -H]]),
    ]);
    const polys = geos.polygonize(noded);
    expect(polys).toHaveLength(9);
    expect(Math.round(Math.max(...polys.map(geos.area)))).toBe(42000);
  });
  it('buffer + preparedContains', () => {
    const corridor = geos.buffer(line([[0, 32.5], [64, 32.5]]), 1.5);
    const pc = geos.preparedContains(corridor);
    expect(pc.contains([20.5, 32.5])).toBe(true);
    expect(pc.contains([20.5, 34.5])).toBe(false);
    pc.dispose();
  });
  it('intersection of disjoint shapes is empty; simplify keeps polygon', () => {
    const box = { type: 'Polygon' as const, coordinates: [[[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]]] };
    expect(geos.isEmpty(geos.intersection(line([[0, 32.5], [64, 32.5]]), box))).toBe(true);
    const s = geos.simplify(geos.buffer(box, -1), 1.5);
    expect(s.type).toBe('Polygon');
    expect(Math.round(geos.area(s))).toBe(64);
  });
});
```

- [ ] **Step 4: 安装依赖并跑测试确认失败**

```bash
cd tools/geo_blueprint
https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890 pnpm install
pnpm test
```
Expected: FAIL（`Cannot find module '../src/config.js'` 之类）。

- [ ] **Step 5: 写 types.ts、config.ts、geos.ts**

`tools/geo_blueprint/src/types.ts`：
```ts
export type Cell = [number, number]; // [x(i), y(j)]

export interface Masks {
  visual: string[];
  walkable: string[];
  buildable: string[];
  cultivable: string[];
}

export interface Bed { id: string; cells: Cell[] }

export interface Anchors {
  spawn: Cell; house: Cell; storage: Cell; well: Cell; exit: Cell;
  beds: Bed[];
  reserved_bed: Bed;
}

export interface Report { far_bed_s: number; tour_s: number; errors: string[] }

export interface Blueprint {
  format: 1;
  layout_patch_id: string;
  revision: number;
  region_id: string;
  name: string;
  checksum: string;
  source: Record<string, unknown>;
  play_area_m: number;
  cell_m: number;
  grid: [number, number];
  masks: Masks;
  paths: { id: string; points: Cell[]; width_m: number }[];
  blocks: { id: string; polygon: [number, number][]; neighbors: string[] }[];
  anchors: Anchors;
  overlay_wgs84: { center: [number, number]; paths: [number, number][][]; blocks: [number, number][][] };
  report?: Report;
}
```

`tools/geo_blueprint/src/config.ts`：
```ts
/** 管线常量与候选加载。路径以本文件位置推导，不依赖 cwd。 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

export const PKG_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const REPO_ROOT = path.resolve(PKG_DIR, '..', '..');
export const CANDIDATES_FILE = path.join(PKG_DIR, 'candidates.json');
export const CACHE_DIR = path.join(PKG_DIR, 'cache');
export const BLUEPRINTS_DIR = path.join(REPO_ROOT, 'assets', 'blueprints');
export const REGIONS_OUT = path.join(REPO_ROOT, 'assets', 'farm', 'data', 'regions.json');

export const PLAY_AREA_M = 64;
export const GRID = 64;
export const CELL_M = 1.0;
export const PATH_WIDTH_M = 3.0;
export const WALK_SPEED = 2.5;
export const ACTION_S = 2.0;
export const MAX_FAR_BED_S = 12.0;
export const MIN_BLOCKS = 3;
export const MAX_BLOCKS = 7;
export const BED_CELLS = 3;
export const INITIAL_BEDS = 3;

export interface RawCandidate { layout_patch_id: string; name: string; lat: number; lng: number; radius_m?: number }
export interface Region {
  id: string; name: string; timezone: string; center: [number, number];
  street_zoom: number; pitch: number; candidates: RawCandidate[];
}
export interface Candidate { regionId: string; layoutPatchId: string; name: string; lat: number; lng: number; radiusM: number }

export function loadRegions(file: string = CANDIDATES_FILE): Region[] {
  return JSON.parse(readFileSync(file, 'utf8')).regions as Region[];
}

export function loadCandidates(file: string = CANDIDATES_FILE): Candidate[] {
  return loadRegions(file).flatMap(r => r.candidates.map(c => ({
    regionId: r.id, layoutPatchId: c.layout_patch_id, name: c.name,
    lat: c.lat, lng: c.lng, radiusM: c.radius_m ?? 200,
  })));
}

export function candidate(layoutPatchId: string): Candidate {
  const c = loadCandidates().find(x => x.layoutPatchId === layoutPatchId);
  if (!c) throw new Error(`unknown candidate ${layoutPatchId}`);
  return c;
}
```

`tools/geo_blueprint/src/geos.ts`：
```ts
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
```

- [ ] **Step 6: 跑测试确认通过**

Run: `cd tools/geo_blueprint && pnpm test && pnpm typecheck`
Expected: 5 passed；typecheck 无错误（若 `GEOSPreparedGeom_destroy` 等在 d.ts 缺类型，用 `(g as any).GEOSPreparedGeom_destroy(prep)` 并加注释）。

- [ ] **Step 7: Commit**

```bash
git add .gitignore tools/geo_blueprint/package.json tools/geo_blueprint/pnpm-lock.yaml tools/geo_blueprint/tsconfig.json tools/geo_blueprint/vitest.config.ts tools/geo_blueprint/candidates.json tools/geo_blueprint/src tools/geo_blueprint/test
git commit -m "feat(blueprint): geo_blueprint Node 包骨架、双城六候选配置与 geos 封装"
```

---

### Task 2: Overpass 抓取（带缓存、走代理）与解析

**Files:**
- Create: `tools/geo_blueprint/src/osm.ts`
- Create: `tools/geo_blueprint/test/fixtures/grid_overpass.json`
- Create: `tools/geo_blueprint/test/osm.test.ts`

**Interfaces:**
- Produces: `Way {id, highway, coords: [lat,lng][]}`、`bbox(lat,lng,radiusM) -> [s,w,n,e]`、`buildQuery(lat,lng,radiusM) -> string`、`fetchOverpass(lat,lng,radiusM,cachePath) -> Promise<OverpassJson>`（有缓存不联网）、`parseWays(data) -> Way[]`、常量 `HIGHWAY_RE`。

- [ ] **Step 1: 写 fixture（井字路网，中心 31.2, 121.4，半径 150 m）**

`tools/geo_blueprint/test/fixtures/grid_overpass.json`：
```json
{"version": 0.6, "elements": [
 {"type":"node","id":1,"lat":31.20090,"lon":121.39820},{"type":"node","id":2,"lat":31.20090,"lon":121.40180},
 {"type":"node","id":3,"lat":31.19910,"lon":121.39820},{"type":"node","id":4,"lat":31.19910,"lon":121.40180},
 {"type":"node","id":5,"lat":31.20160,"lon":121.39895},{"type":"node","id":6,"lat":31.19840,"lon":121.39895},
 {"type":"node","id":7,"lat":31.20160,"lon":121.40105},{"type":"node","id":8,"lat":31.19840,"lon":121.40105},
 {"type":"way","id":101,"nodes":[1,2],"tags":{"highway":"residential","name":"North St"}},
 {"type":"way","id":102,"nodes":[3,4],"tags":{"highway":"residential","name":"South St"}},
 {"type":"way","id":103,"nodes":[5,6],"tags":{"highway":"tertiary","name":"West Ave"}},
 {"type":"way","id":104,"nodes":[7,8],"tags":{"highway":"tertiary","name":"East Ave"}},
 {"type":"way","id":105,"nodes":[1,3],"tags":{"highway":"footway"}}
]}
```
（105 是 footway，用来验证非白名单道路会被解析、由 Task 3 过滤。）

- [ ] **Step 2: 写失败测试**

`tools/geo_blueprint/test/osm.test.ts`：
```ts
import { describe, it, expect } from 'vitest';
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import * as osm from '../src/osm.js';

const FIX = path.join(__dirname, 'fixtures', 'grid_overpass.json');

describe('osm', () => {
  it('bbox is symmetric in lat and wider in lng', () => {
    const [s, w, n, e] = osm.bbox(31.2, 121.4, 200);
    expect(Math.abs((n - 31.2) - (31.2 - s))).toBeLessThan(1e-9);
    expect(e - w).toBeGreaterThan(n - s);
  });
  it('query mentions highway regex and out body', () => {
    const q = osm.buildQuery(31.2, 121.4, 200);
    expect(q).toContain('way["highway"~');
    expect(q).toContain('residential');
    expect(q).toContain('out body');
  });
  it('parses five ways from fixture', () => {
    const ways = osm.parseWays(JSON.parse(readFileSync(FIX, 'utf8')));
    expect(ways).toHaveLength(5);
    const w = ways.find(x => x.id === 101)!;
    expect(w.highway).toBe('residential');
    expect(w.coords[0]).toEqual([31.2009, 121.3982]);
  });
  it('fetchOverpass returns cache without network', async () => {
    const dir = mkdtempSync(path.join(os.tmpdir(), 'osm-'));
    const cache = path.join(dir, 'c.json');
    writeFileSync(cache, readFileSync(FIX));
    const data = await osm.fetchOverpass(31.2, 121.4, 150, cache);
    expect(data.elements).toHaveLength(13);
  });
});
```

- [ ] **Step 3: 跑测试确认失败**

Run: `cd tools/geo_blueprint && pnpm test test/osm.test.ts`
Expected: FAIL `Cannot find module '../src/osm.js'`

- [ ] **Step 4: 写 osm.ts**

```ts
/** Overpass 一次性抓取 + 本地缓存。缓存文件入库，之后构建不联网。 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { EnvHttpProxyAgent, setGlobalDispatcher } from 'undici';

export const OVERPASS_URL = 'https://overpass-api.de/api/interpreter';
export const HIGHWAY_RE =
  'primary|primary_link|secondary|secondary_link|tertiary|tertiary_link|residential|unclassified|living_street|pedestrian';
const M_PER_DEG_LAT = 111319.4908;

export interface OverpassElement {
  type: string; id: number; lat?: number; lon?: number; nodes?: number[]; tags?: Record<string, string>;
}
export interface OverpassJson { elements: OverpassElement[] }
export interface Way { id: number; highway: string; coords: [number, number][] } // [lat, lng]

export function bbox(lat: number, lng: number, radiusM: number): [number, number, number, number] {
  const dlat = radiusM / M_PER_DEG_LAT;
  const dlng = radiusM / (M_PER_DEG_LAT * Math.cos((lat * Math.PI) / 180));
  return [lat - dlat, lng - dlng, lat + dlat, lng + dlng];
}

export function buildQuery(lat: number, lng: number, radiusM: number): string {
  const [s, w, n, e] = bbox(lat, lng, radiusM);
  return `[out:json][timeout:60];way["highway"~"^(${HIGHWAY_RE})$"]` +
    `(${s.toFixed(6)},${w.toFixed(6)},${n.toFixed(6)},${e.toFixed(6)});(._;>;);out body;`;
}

let proxyInstalled = false;
function installEnvProxy(): void {
  if (proxyInstalled) return;
  proxyInstalled = true;
  if (process.env.https_proxy || process.env.HTTPS_PROXY) setGlobalDispatcher(new EnvHttpProxyAgent());
}

export async function fetchOverpass(lat: number, lng: number, radiusM: number, cachePath: string): Promise<OverpassJson> {
  if (existsSync(cachePath)) return JSON.parse(readFileSync(cachePath, 'utf8')) as OverpassJson;
  installEnvProxy();
  const res = await fetch(OVERPASS_URL, {
    method: 'POST',
    body: new URLSearchParams({ data: buildQuery(lat, lng, radiusM) }),
  });
  if (!res.ok) throw new Error(`overpass HTTP ${res.status}`);
  const data = (await res.json()) as OverpassJson;
  mkdirSync(path.dirname(cachePath), { recursive: true });
  writeFileSync(cachePath, JSON.stringify(data, null, 1));
  return data;
}

export function parseWays(data: OverpassJson): Way[] {
  const nodes = new Map<number, [number, number]>();
  for (const el of data.elements) if (el.type === 'node' && el.lat !== undefined && el.lon !== undefined) nodes.set(el.id, [el.lat, el.lon]);
  const ways: Way[] = [];
  for (const el of data.elements) {
    if (el.type !== 'way') continue;
    const coords = (el.nodes ?? []).map(n => nodes.get(n)).filter((c): c is [number, number] => !!c);
    if (coords.length >= 2) ways.push({ id: el.id, highway: el.tags?.highway ?? '', coords });
  }
  return ways;
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: `cd tools/geo_blueprint && pnpm test test/osm.test.ts`
Expected: 4 passed

- [ ] **Step 6: Commit**

```bash
git add tools/geo_blueprint
git commit -m "feat(blueprint): Overpass 抓取带缓存与 Way 解析"
```

---

### Task 3: 投影、裁剪、polygonize

**Files:**
- Create: `tools/geo_blueprint/src/topology.ts`
- Create: `tools/geo_blueprint/test/topology.test.ts`

**Interfaces:**
- Produces: `Transformer {forward([lng,lat]) -> [x,y]; inverse([x,y]) -> [lng,lat]}`、`makeTransformer(lat,lng)`、`projectWays(ways, lat, lng, allowedRe=HIGHWAY_RE) -> LineString[]`、`windowPolygon(half) -> Polygon`、`clipLines(lines, half) -> LineString[]`、`polygonizeBlocks(lines, half) -> Polygon[]`（含窗口边界闭合）。

- [ ] **Step 1: 写失败测试**

`tools/geo_blueprint/test/topology.test.ts`：
```ts
import { describe, it, expect, beforeAll } from 'vitest';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import * as osm from '../src/osm.js';
import * as topo from '../src/topology.js';
import * as geos from '../src/geos.js';

const FIX = path.join(__dirname, 'fixtures', 'grid_overpass.json');
const ways = () => osm.parseWays(JSON.parse(readFileSync(FIX, 'utf8')));

describe('topology', () => {
  beforeAll(geos.initGeos);
  it('projection: center is origin, east is +x (~95 m per 0.001°)', () => {
    const t = topo.makeTransformer(31.2, 121.4);
    const [x, y] = t.forward([121.4, 31.2]);
    expect(Math.abs(x)).toBeLessThan(1e-6); expect(Math.abs(y)).toBeLessThan(1e-6);
    const [x2] = t.forward([121.401, 31.2]);
    expect(x2).toBeGreaterThan(90); expect(x2).toBeLessThan(100);
    const [lng, lat] = t.inverse([95, 0]);
    expect(lng).toBeCloseTo(121.401, 5); expect(lat).toBeCloseTo(31.2, 6);
  });
  it('projectWays filters footway', () => {
    expect(topo.projectWays(ways(), 31.2, 121.4)).toHaveLength(4);
  });
  it('hash grid + window gives nine faces', () => {
    const lines = topo.clipLines(topo.projectWays(ways(), 31.2, 121.4), 150);
    const polys = topo.polygonizeBlocks(lines, 150);
    expect(polys).toHaveLength(9);
    const biggest = Math.max(...polys.map(geos.area));
    expect(biggest).toBeGreaterThan(190 * 190); expect(biggest).toBeLessThan(210 * 210);
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd tools/geo_blueprint && pnpm test test/topology.test.ts`
Expected: FAIL `Cannot find module '../src/topology.js'`

- [ ] **Step 3: 写 topology.ts**

```ts
/** 地理 → 本地米制（横轴墨卡托，中心为原点，x 东 y 北）、窗口裁剪、区块 polygonize。 */
import proj4 from 'proj4';
import type { LineString, Polygon, Position, Geometry } from 'geojson';
import { HIGHWAY_RE, type Way } from './osm.js';
import * as geos from './geos.js';

export interface Transformer { forward(lnglat: Position): Position; inverse(xy: Position): Position }

export function makeTransformer(lat: number, lng: number): Transformer {
  const def = `+proj=tmerc +lat_0=${lat} +lon_0=${lng} +k=1 +x_0=0 +y_0=0 +ellps=WGS84 +units=m +no_defs`;
  const conv = proj4('EPSG:4326', def);
  return {
    forward: p => conv.forward([p[0], p[1]]) as Position,
    inverse: p => conv.inverse([p[0], p[1]]) as Position,
  };
}

export function projectWays(ways: Way[], lat: number, lng: number, allowedRe: string = HIGHWAY_RE): LineString[] {
  const t = makeTransformer(lat, lng);
  const re = new RegExp(`^(${allowedRe})$`);
  return ways.filter(w => re.test(w.highway)).map(w => ({
    type: 'LineString',
    coordinates: w.coords.map(([la, lg]) => t.forward([lg, la])),
  }));
}

export function windowPolygon(half: number): Polygon {
  return { type: 'Polygon', coordinates: [[[-half, -half], [half, -half], [half, half], [-half, half], [-half, -half]]] };
}

function collectLines(g: Geometry, out: LineString[]): void {
  if (g.type === 'LineString' && g.coordinates.length >= 2) out.push(g);
  else if (g.type === 'MultiLineString') for (const c of g.coordinates) if (c.length >= 2) out.push({ type: 'LineString', coordinates: c });
  else if (g.type === 'GeometryCollection') for (const sub of g.geometries) collectLines(sub, out);
}

export function clipLines(lines: LineString[], half: number): LineString[] {
  const win = windowPolygon(half);
  const out: LineString[] = [];
  for (const l of lines) collectLines(geos.intersection(l, win), out);
  return out;
}

/** 道路 + 窗口边界一起 noding，窗口内每个闭合面都成为候选区块。 */
export function polygonizeBlocks(lines: LineString[], half: number): Polygon[] {
  const ring: LineString = { type: 'LineString', coordinates: windowPolygon(half).coordinates[0] };
  const noded = geos.unaryUnion([...lines, ring]);
  return geos.polygonize(noded).filter(p => geos.area(p) > 1.0);
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd tools/geo_blueprint && pnpm test test/topology.test.ts`
Expected: 3 passed

- [ ] **Step 5: Commit**

```bash
git add tools/geo_blueprint
git commit -m "feat(blueprint): 本地投影、窗口裁剪与区块 polygonize"
```

---

### Task 4: 选块、归一化缩放、简化、邻接

**Files:**
- Create: `tools/geo_blueprint/src/normalize.ts`
- Create: `tools/geo_blueprint/test/normalize.test.ts`

**Interfaces:**
- Produces: `selectBlocks(polys, half, minFrac=0.02, maxBlocks=7) -> Polygon[]`（面积降序）、`mapCoords(geom, fn)`、`toPlay(geom, half, playM)`（窗口 [-half,half]² → [0,playM]²）、`simplify(geom, tol=1.5)`、`adjacency(blocks, gap) -> {ids, neighbors}`。

- [ ] **Step 1: 写失败测试**

`tools/geo_blueprint/test/normalize.test.ts`：
```ts
import { describe, it, expect, beforeAll } from 'vitest';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import type { Polygon, Point } from 'geojson';
import * as osm from '../src/osm.js';
import * as topo from '../src/topology.js';
import * as norm from '../src/normalize.js';
import * as geos from '../src/geos.js';

const FIX = path.join(__dirname, 'fixtures', 'grid_overpass.json');
function polys(): Polygon[] {
  const ways = osm.parseWays(JSON.parse(readFileSync(FIX, 'utf8')));
  return topo.polygonizeBlocks(topo.clipLines(topo.projectWays(ways, 31.2, 121.4), 150), 150);
}
const box = (x0: number, y0: number, x1: number, y1: number): Polygon =>
  ({ type: 'Polygon', coordinates: [[[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]]] });

describe('normalize', () => {
  beforeAll(geos.initGeos);
  it('selectBlocks caps at seven, sorted desc', () => {
    const kept = norm.selectBlocks(polys(), 150);
    expect(kept.length).toBeGreaterThanOrEqual(3); expect(kept.length).toBeLessThanOrEqual(7);
    const areas = kept.map(geos.area);
    expect(areas).toEqual([...areas].sort((a, b) => b - a));
  });
  it('selectBlocks drops slivers', () => {
    const kept = norm.selectBlocks([...polys(), box(0, 0, 2, 2)], 150);
    expect(kept.every(p => geos.area(p) > 0.02 * 300 * 300)).toBe(true);
  });
  it('toPlay maps window corners to [0,64]²', () => {
    const p: Point = { type: 'Point', coordinates: [-150, -150] };
    expect(norm.toPlay(p, 150, 64).coordinates).toEqual([0, 0]);
    const q: Point = { type: 'Point', coordinates: [150, 0] };
    expect(norm.toPlay(q, 150, 64).coordinates).toEqual([64, 32]);
  });
  it('adjacency: center block touches at least four neighbours', () => {
    const play = norm.selectBlocks(polys(), 150).map(p => norm.toPlay(p, 150, 64));
    const { ids, neighbors } = norm.adjacency(play, 3.0);
    expect(ids[0]).toBe('b0');
    expect(neighbors['b0'].length).toBeGreaterThanOrEqual(4);
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd tools/geo_blueprint && pnpm test test/normalize.test.ts`
Expected: FAIL `Cannot find module '../src/normalize.js'`

- [ ] **Step 3: 写 normalize.ts**

```ts
/** 区块筛选、窗口 → 游玩区缩放、简化、邻接。 */
import type { Geometry, Polygon, Position } from 'geojson';
import * as geos from './geos.js';

export function selectBlocks(polys: Polygon[], half: number, minFrac = 0.02, maxBlocks = 7): Polygon[] {
  const areaWin = (2 * half) ** 2;
  return polys
    .map(p => ({ p, a: geos.area(p) }))
    .filter(x => x.a >= minFrac * areaWin)
    .sort((x, y) => y.a - x.a)
    .slice(0, maxBlocks)
    .map(x => x.p);
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function mapNested(c: any, f: (p: Position) => Position): any {
  return typeof c[0] === 'number' ? f(c as Position) : (c as unknown[]).map(x => mapNested(x, f));
}

export function mapCoords<T extends Geometry>(g: T, f: (p: Position) => Position): T {
  if (g.type === 'GeometryCollection') return { ...g, geometries: g.geometries.map(x => mapCoords(x, f)) } as T;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return { ...g, coordinates: mapNested((g as any).coordinates, f) } as T;
}

export function toPlay<T extends Geometry>(g: T, half: number, playM: number): T {
  const s = playM / (2 * half);
  return mapCoords(g, ([x, y]) => [(x + half) * s, (y + half) * s]);
}

export function simplify<T extends Geometry>(g: T, tol = 1.5): T {
  return geos.simplify(g, tol) as T;
}

export function adjacency(blocks: Polygon[], gap: number): { ids: string[]; neighbors: Record<string, string[]> } {
  const ids = blocks.map((_, i) => `b${i}`);
  const neighbors: Record<string, string[]> = Object.fromEntries(ids.map(i => [i, [] as string[]]));
  for (let i = 0; i < blocks.length; i++) {
    const grown = geos.buffer(blocks[i], gap);
    for (let j = i + 1; j < blocks.length; j++) {
      if (geos.intersects(grown, blocks[j])) { neighbors[ids[i]].push(ids[j]); neighbors[ids[j]].push(ids[i]); }
    }
  }
  return { ids, neighbors };
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd tools/geo_blueprint && pnpm test test/normalize.test.ts`
Expected: 4 passed

- [ ] **Step 5: Commit**

```bash
git add tools/geo_blueprint
git commit -m "feat(blueprint): 区块筛选、归一化缩放与邻接"
```

---

### Task 5: 栅格化四张 mask

**Files:**
- Create: `tools/geo_blueprint/src/masks.ts`
- Create: `tools/geo_blueprint/test/masks.test.ts`

**Interfaces:**
- Produces: `cellKey(i,j,grid) -> number`（`j*grid+i`）、`pathCells(paths, grid, cellM, widthM) -> Set<number>`、`rasterize(paths, blocks, grid, cellM, widthM) -> Masks`（`cultivable` 先填全 0，由 Task 6 覆盖）、`count(mask: string[]) -> number`。

- [ ] **Step 1: 写失败测试**

`tools/geo_blueprint/test/masks.test.ts`：
```ts
import { describe, it, expect, beforeAll } from 'vitest';
import type { LineString, Polygon } from 'geojson';
import * as masks from '../src/masks.js';
import * as geos from '../src/geos.js';

const line = (c: number[][]): LineString => ({ type: 'LineString', coordinates: c });
const box = (x0: number, y0: number, x1: number, y1: number): Polygon =>
  ({ type: 'Polygon', coordinates: [[[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]]] });

describe('masks', () => {
  beforeAll(geos.initGeos);
  it('shapes; walkable includes path and block; buildable eroded', () => {
    const m = masks.rasterize([line([[0, 32], [64, 32]])], [box(4, 4, 28, 28)], 64, 1, 3);
    expect(Object.keys(m).sort()).toEqual(['buildable', 'cultivable', 'visual', 'walkable']);
    expect(m.walkable).toHaveLength(64); expect(m.walkable.every(r => r.length === 64)).toBe(true);
    expect(m.walkable[32][10]).toBe('1');   // 路上（y=32 行）
    expect(m.walkable[10][10]).toBe('1');   // 区块内
    expect(m.walkable[50][50]).toBe('0');   // 空地
    expect(m.buildable[10][10]).toBe('1'); expect(m.buildable[4][4]).toBe('0');
    expect(masks.count(m.cultivable)).toBe(0);
  });
  it('path corridor is three cells wide', () => {
    const pc = masks.pathCells([line([[0, 32.5], [64, 32.5]])], 64, 1, 3);
    const col = [...pc].filter(k => k % 64 === 20).map(k => Math.floor(k / 64)).sort((a, b) => a - b);
    expect(col).toEqual([31, 32, 33]);
  });
  it('count', () => { expect(masks.count(['0110', '0000'])).toBe(2); });
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd tools/geo_blueprint && pnpm test test/masks.test.ts`
Expected: FAIL `Cannot find module '../src/masks.js'`

- [ ] **Step 3: 写 masks.ts**

```ts
/** 几何 → 逻辑格。判定用格中心点；所有 mask 都是 grid 行 × grid 列的 '0'/'1' 字符串。 */
import type { LineString, Polygon } from 'geojson';
import type { Masks } from './types.js';
import * as geos from './geos.js';

export const cellKey = (i: number, j: number, grid: number): number => j * grid + i;

export function pathCells(paths: LineString[], grid: number, cellM: number, widthM: number): Set<number> {
  const out = new Set<number>();
  if (paths.length === 0) return out;
  const pc = geos.preparedContains(geos.unaryUnion(paths.map(p => geos.buffer(p, widthM / 2))));
  for (let j = 0; j < grid; j++) for (let i = 0; i < grid; i++)
    if (pc.contains([(i + 0.5) * cellM, (j + 0.5) * cellM])) out.add(cellKey(i, j, grid));
  pc.dispose();
  return out;
}

export function rasterize(paths: LineString[], blocks: Polygon[], grid: number, cellM: number, widthM: number): Masks {
  const pcs = pathCells(paths, grid, cellM, widthM);
  const blockArea = blocks.length ? geos.preparedContains(geos.unaryUnion(blocks)) : null;
  const eroded = blocks.map(b => geos.buffer(b, -1.0)).filter(g => !geos.isEmpty(g));
  const buildArea = eroded.length ? geos.preparedContains(geos.unaryUnion(eroded)) : null;
  const visual: string[] = [], walkable: string[] = [], buildable: string[] = [], cultivable: string[] = [];
  for (let j = 0; j < grid; j++) {
    let w = '', b = '';
    for (let i = 0; i < grid; i++) {
      const c: [number, number] = [(i + 0.5) * cellM, (j + 0.5) * cellM];
      const onPath = pcs.has(cellKey(i, j, grid));
      const inBlock = blockArea?.contains(c) ?? false;
      w += onPath || inBlock ? '1' : '0';
      b += !onPath && (buildArea?.contains(c) ?? false) ? '1' : '0';
    }
    visual.push('1'.repeat(grid)); walkable.push(w); buildable.push(b); cultivable.push('0'.repeat(grid));
  }
  blockArea?.dispose(); buildArea?.dispose();
  return { visual, walkable, buildable, cultivable };
}

export function count(mask: string[]): number {
  return mask.reduce((n, r) => n + (r.match(/1/g)?.length ?? 0), 0);
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd tools/geo_blueprint && pnpm test test/masks.test.ts`
Expected: 3 passed

- [ ] **Step 5: Commit**

```bash
git add tools/geo_blueprint
git commit -m "feat(blueprint): 四张逻辑 mask 栅格化"
```

---

### Task 6: 锚点、田畦配额、可达性与公平校验

**Files:**
- Create: `tools/geo_blueprint/src/anchors.ts`
- Create: `tools/geo_blueprint/test/anchors.test.ts`

**Interfaces:**
- Produces: `bfs(walkable: string[], start: Cell) -> Map<number, number>`（键 `cellKey`，4 邻接）、`place(masks, pathCellSet, grid) -> Anchors`（**就地覆盖 `masks.cultivable`**）、`validate(bp) -> Report`、`class ValidationError`。

- [ ] **Step 1: 写失败测试**

`tools/geo_blueprint/test/anchors.test.ts`：
```ts
import { describe, it, expect, beforeAll } from 'vitest';
import type { LineString, Polygon } from 'geojson';
import * as masks from '../src/masks.js';
import * as anchors from '../src/anchors.js';
import * as config from '../src/config.js';
import * as geos from '../src/geos.js';
import type { Blueprint } from '../src/types.js';

const line = (c: number[][]): LineString => ({ type: 'LineString', coordinates: c });
const box = (x0: number, y0: number, x1: number, y1: number): Polygon =>
  ({ type: 'Polygon', coordinates: [[[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]]] });

function scene() {
  const paths = [line([[0, 32.5], [64, 32.5]]), line([[32.5, 0], [32.5, 64]])];
  const blocks = [box(2, 2, 30, 30), box(35, 2, 62, 30), box(2, 35, 30, 62), box(35, 35, 62, 62)];
  const m = masks.rasterize(paths, blocks, 64, 1, 3);
  const pcs = masks.pathCells(paths, 64, 1, 3);
  return { m, pcs };
}
const bpOf = (m: Blueprint['masks'], a: Blueprint['anchors'], nblocks = 4): Blueprint => ({
  format: 1, layout_patch_id: 't', revision: 1, region_id: 'r', name: 't', checksum: '', source: {},
  play_area_m: 64, cell_m: 1, grid: [64, 64], masks: m, paths: [],
  blocks: Array.from({ length: nblocks }, (_, i) => ({ id: `b${i}`, polygon: [], neighbors: [] })),
  anchors: a, overlay_wgs84: { center: [0, 0], paths: [], blocks: [] },
});

describe('anchors', () => {
  beforeAll(geos.initGeos);
  it('bfs is four-neighbour', () => {
    const d = anchors.bfs(['111', '101', '111'], [0, 0]);
    expect(d.get(masks.cellKey(2, 2, 3))).toBe(4);
    expect(d.has(masks.cellKey(1, 1, 3))).toBe(false);
  });
  it('place gives nine cultivable cells and reachable anchors', () => {
    const { m, pcs } = scene();
    const a = anchors.place(m, pcs, 64);
    expect(masks.count(m.cultivable)).toBe(9);
    expect(a.beds).toHaveLength(3); expect(a.beds.every(b => b.cells.length === 3)).toBe(true);
    expect(a.reserved_bed.id).toBe('bed3');
    expect(pcs.has(masks.cellKey(a.spawn[0], a.spawn[1], 64))).toBe(true);
    const d = anchors.bfs(m.walkable, a.spawn);
    for (const k of ['house', 'storage', 'well', 'exit'] as const) expect(d.has(masks.cellKey(a[k][0], a[k][1], 64))).toBe(true);
    expect([0, 63].includes(a.exit[0]) || [0, 63].includes(a.exit[1])).toBe(true);
  });
  it('validate reports times without errors', () => {
    const { m, pcs } = scene();
    const a = anchors.place(m, pcs, 64);
    const r = anchors.validate(bpOf(m, a));
    expect(r.errors).toEqual([]);
    expect(r.far_bed_s).toBeGreaterThan(0); expect(r.far_bed_s).toBeLessThanOrEqual(config.MAX_FAR_BED_S);
    expect(r.tour_s).toBeGreaterThan(9 * config.ACTION_S);
  });
  it('validate flags unreachable house', () => {
    const { m, pcs } = scene();
    const a = anchors.place(m, pcs, 64);
    a.house = [63, 63];
    expect(anchors.validate(bpOf(m, a)).errors.some(e => e.includes('house'))).toBe(true);
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd tools/geo_blueprint && pnpm test test/anchors.test.ts`
Expected: FAIL `Cannot find module '../src/anchors.js'`

- [ ] **Step 3: 写 anchors.ts**

```ts
/** 锚点摆放与蓝图校验。距离用 4 邻接 BFS（与 Godot 侧 AStarGrid2D DIAGONAL_MODE_NEVER 一致）。 */
import * as config from './config.js';
import { cellKey } from './masks.js';
import type { Anchors, Bed, Blueprint, Cell, Masks, Report } from './types.js';

export class ValidationError extends Error {}

export function bfs(walkable: string[], start: Cell): Map<number, number> {
  const g = walkable.length;
  const dist = new Map<number, number>([[cellKey(start[0], start[1], g), 0]]);
  const q: Cell[] = [start];
  while (q.length) {
    const [x, y] = q.shift()!;
    const d = dist.get(cellKey(x, y, g))!;
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]] as const) {
      const nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= g || ny >= g) continue;
      const k = cellKey(nx, ny, g);
      if (walkable[ny][nx] === '1' && !dist.has(k)) { dist.set(k, d + 1); q.push([nx, ny]); }
    }
  }
  return dist;
}

const cellsOf = (mask: string[]): Cell[] => {
  const out: Cell[] = [];
  mask.forEach((row, j) => { for (let i = 0; i < row.length; i++) if (row[i] === '1') out.push([i, j]); });
  return out;
};
const fromKey = (k: number, g: number): Cell => [k % g, Math.floor(k / g)];
const sq = (a: Cell, b: Cell) => (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2;
const nearest = (cells: Cell[], target: Cell): Cell => cells.reduce((best, c) => (sq(c, target) < sq(best, target) ? c : best));
const farFrom = (c: Cell, used: Cell[], margin = 1) => used.every(u => Math.abs(c[0] - u[0]) > margin || Math.abs(c[1] - u[1]) > margin);

export function place(masks: Masks, pathCells: Set<number>, grid: number): Anchors {
  if (pathCells.size === 0) throw new ValidationError('no path cells');
  const pcs = [...pathCells].map(k => fromKey(k, grid));
  const center: Cell = [Math.floor(grid / 2), Math.floor(grid / 2)];
  const spawn = nearest(pcs, center);
  const dist = bfs(masks.walkable, spawn);
  const has = (c: Cell) => dist.has(cellKey(c[0], c[1], grid));
  const dOf = (c: Cell) => dist.get(cellKey(c[0], c[1], grid)) ?? Number.POSITIVE_INFINITY;
  const reachablePath = pcs.filter(has);
  const boundary = reachablePath.filter(c => c[0] === 0 || c[0] === grid - 1 || c[1] === 0 || c[1] === grid - 1);
  const pool = boundary.length ? boundary : reachablePath;
  const exit = pool.reduce((best, c) => (dOf(c) > dOf(best) ? c : best));
  const buildable = cellsOf(masks.buildable).filter(has);
  const bset = new Set(buildable.map(c => cellKey(c[0], c[1], grid)));
  const runs: Cell[][] = [];
  for (const [i, j] of buildable)
    if (bset.has(cellKey(i + 1, j, grid)) && bset.has(cellKey(i + 2, j, grid))) runs.push([[i, j], [i + 1, j], [i + 2, j]]);
  runs.sort((a, b) => dOf(a[0]) + dOf(a[2]) - (dOf(b[0]) + dOf(b[2])));
  const beds: Cell[][] = []; const used: Cell[] = [];
  for (const r of runs) {
    if (r.every(c => farFrom(c, used))) { beds.push(r); used.push(...r); }
    if (beds.length === config.INITIAL_BEDS + 1) break;
  }
  if (beds.length < config.INITIAL_BEDS + 1) throw new ValidationError(`only ${beds.length} bed sites, need ${config.INITIAL_BEDS + 1}`);
  const free = buildable.filter(c => farFrom(c, used, 2));
  if (free.length < 2) throw new ValidationError('no room for house/storage');
  const house = nearest(free, spawn);
  const storage = nearest(free.filter(c => c !== house), house);
  const wellPool = pcs.filter(c => Math.abs(c[0] - spawn[0]) + Math.abs(c[1] - spawn[1]) === 1);
  const well = wellPool[0] ?? spawn;
  const cult = masks.walkable.map(() => Array(grid).fill('0') as string[]);
  for (const r of beds.slice(0, config.INITIAL_BEDS)) for (const [i, j] of r) cult[j][i] = '1';
  masks.cultivable = cult.map(row => row.join(''));
  const bed = (id: string, cells: Cell[]): Bed => ({ id, cells: cells.map(c => [c[0], c[1]]) });
  return {
    spawn, house, storage, well, exit,
    beds: beds.slice(0, 3).map((r, k) => bed(`bed${k}`, r)),
    reserved_bed: bed('bed3', beds[3]),
  };
}

export function validate(bp: Blueprint): Report {
  const walk = bp.masks.walkable, g = walk.length, a = bp.anchors;
  const dist = bfs(walk, a.spawn);
  const key = (c: Cell) => cellKey(c[0], c[1], g);
  const errors: string[] = [];
  for (const name of ['house', 'storage', 'well', 'exit'] as const)
    if (!dist.has(key(a[name]))) errors.push(`${name} unreachable from spawn`);
  let far = 0; const firsts: Cell[] = [];
  for (const b of a.beds) {
    for (const c of b.cells) {
      if (!dist.has(key(c))) errors.push(`${b.id} cell ${c} unreachable`);
      far = Math.max(far, dist.get(key(c)) ?? 1e6);
    }
    firsts.push(b.cells[0]);
  }
  if (bp.blocks.length < config.MIN_BLOCKS || bp.blocks.length > config.MAX_BLOCKS)
    errors.push(`block count ${bp.blocks.length} outside ${config.MIN_BLOCKS}-${config.MAX_BLOCKS}`);
  const ncult = bp.masks.cultivable.reduce((n, r) => n + (r.match(/1/g)?.length ?? 0), 0);
  if (ncult !== config.INITIAL_BEDS * config.BED_CELLS) errors.push(`cultivable cells ${ncult} != 9`);
  let tour = 0; let cur: Cell = a.spawn;
  for (const nxt of [...firsts, a.spawn]) { tour += bfs(walk, cur).get(key(nxt)) ?? 1e6; cur = nxt; }
  const farS = (far * bp.cell_m) / config.WALK_SPEED;
  const tourS = (tour * bp.cell_m) / config.WALK_SPEED + config.INITIAL_BEDS * config.BED_CELLS * config.ACTION_S;
  if (farS > config.MAX_FAR_BED_S) errors.push(`farthest bed ${farS.toFixed(1)}s > ${config.MAX_FAR_BED_S}s`);
  return { far_bed_s: Math.round(farS * 100) / 100, tour_s: Math.round(tourS * 100) / 100, errors };
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd tools/geo_blueprint && pnpm test test/anchors.test.ts`
Expected: 4 passed

- [ ] **Step 5: Commit**

```bash
git add tools/geo_blueprint
git commit -m "feat(blueprint): 锚点、田畦配额、BFS 可达性与公平校验"
```

---

### Task 7: canonical/checksum、写文件、预览、regions.json

**Files:**
- Create: `tools/geo_blueprint/src/writer.ts`
- Create: `tools/geo_blueprint/test/writer.test.ts`

**Interfaces:**
- Produces: `canonical(bp) -> string`、`checksum(bp) -> string`（sha256 hex）、`renderPreview(bp, px=8) -> Buffer`（PNG）、`writeOutputs(bp, overlayGeojson, outDir)`（写 `farm_blueprint.json`、`map_overlay.geojson`、`preview.png`、有 `report` 时写 `report.json`）、`writeRegions(regions, blueprintsByRegion, file)`。
- canonical 定义（Godot 侧必须逐字一致）：`[layout_patch_id, String(revision), walkable.join(''), cultivable.join(''), buildable.join(''), visual.join(''), anchorsStr].join('|')`，其中 `anchorsStr = "spawn:x,y;house:x,y;storage:x,y;well:x,y;exit:x,y;beds:" + beds.map(b => b.cells.map(c => c.join(',')).join(',')).join('/')`。

- [ ] **Step 1: 写失败测试**

`tools/geo_blueprint/test/writer.test.ts`：
```ts
import { describe, it, expect } from 'vitest';
import { createHash } from 'node:crypto';
import { existsSync, mkdtempSync, readFileSync } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import * as writer from '../src/writer.js';
import type { Blueprint } from '../src/types.js';

const bp = (): Blueprint => ({
  format: 1, layout_patch_id: 't', revision: 1, region_id: 'r', name: 'T', checksum: '', source: {},
  play_area_m: 2, cell_m: 1, grid: [2, 2],
  masks: { visual: ['11', '11'], walkable: ['11', '10'], buildable: ['00', '01'], cultivable: ['00', '00'] },
  paths: [], blocks: [],
  anchors: { spawn: [0, 0], house: [1, 1], storage: [1, 1], well: [0, 0], exit: [1, 0],
    beds: [{ id: 'bed0', cells: [[1, 1], [1, 1], [1, 1]] }],
    reserved_bed: { id: 'bed3', cells: [[1, 1], [1, 1], [1, 1]] } },
  overlay_wgs84: { center: [0, 0], paths: [], blocks: [] },
});

describe('writer', () => {
  it('canonical exact string and sha256', () => {
    const c = writer.canonical(bp());
    expect(c).toBe('t|1|1110|0000|0001|1111|spawn:0,0;house:1,1;storage:1,1;well:0,0;exit:1,0;beds:1,1,1,1,1,1');
    expect(writer.checksum(bp())).toBe(createHash('sha256').update(c).digest('hex'));
  });
  it('writeOutputs roundtrip', () => {
    const dir = mkdtempSync(path.join(os.tmpdir(), 'bp-'));
    writer.writeOutputs(bp(), { type: 'FeatureCollection', features: [] }, dir);
    const loaded = JSON.parse(readFileSync(path.join(dir, 'farm_blueprint.json'), 'utf8'));
    expect(loaded.checksum).toBe(writer.checksum(bp()));
    expect(existsSync(path.join(dir, 'preview.png'))).toBe(true);
    expect(existsSync(path.join(dir, 'map_overlay.geojson'))).toBe(true);
  });
  it('writeRegions strips coordinates from candidates', () => {
    const dir = mkdtempSync(path.join(os.tmpdir(), 'rg-'));
    const file = path.join(dir, 'regions.json');
    writer.writeRegions(
      [{ id: 'shanghai', name: '上海', timezone: 'Asia/Shanghai', center: [31.2, 121.4], street_zoom: 16, pitch: 45, candidates: [] }],
      { shanghai: [{ layout_patch_id: 'sh_a', revision: 1, name: 'A' }] }, file);
    const data = JSON.parse(readFileSync(file, 'utf8'));
    expect(data.regions[0].candidates[0].layout_patch_id).toBe('sh_a');
    expect(data.regions[0].candidates[0].lat).toBeUndefined();
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd tools/geo_blueprint && pnpm test test/writer.test.ts`
Expected: FAIL `Cannot find module '../src/writer.js'`

- [ ] **Step 3: 写 writer.ts**

```ts
/** 输出：farm_blueprint.json / map_overlay.geojson / preview.png / report.json / regions.json。 */
import { createHash } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { PNG } from 'pngjs';
import type { Region } from './config.js';
import type { Blueprint } from './types.js';

type RGB = [number, number, number];
const COLORS: Record<string, RGB> = {
  ground: [222, 226, 214], path: [232, 214, 172], block: [160, 205, 160], buildable: [140, 190, 140],
  bed: [150, 105, 70], reserved: [200, 170, 140], spawn: [52, 211, 153], house: [60, 90, 200],
  storage: [120, 120, 120], well: [60, 160, 220], exit: [220, 80, 80],
};

export function canonical(bp: Blueprint): string {
  const m = bp.masks, a = bp.anchors;
  const beds = a.beds.map(b => b.cells.map(c => `${c[0]},${c[1]}`).join(',')).join('/');
  const anchors = `spawn:${a.spawn[0]},${a.spawn[1]};house:${a.house[0]},${a.house[1]};` +
    `storage:${a.storage[0]},${a.storage[1]};well:${a.well[0]},${a.well[1]};exit:${a.exit[0]},${a.exit[1]};beds:${beds}`;
  return [bp.layout_patch_id, String(bp.revision), m.walkable.join(''), m.cultivable.join(''),
    m.buildable.join(''), m.visual.join(''), anchors].join('|');
}

export function checksum(bp: Blueprint): string {
  return createHash('sha256').update(canonical(bp), 'utf8').digest('hex');
}

export function renderPreview(bp: Blueprint, px = 8): Buffer {
  const g = bp.grid[0];
  const png = new PNG({ width: g * px, height: g * px });
  const fill = (x0: number, y0: number, w: number, h: number, [r, gg, b]: RGB) => {
    for (let y = y0; y < y0 + h; y++) for (let x = x0; x < x0 + w; x++) {
      const o = (y * png.width + x) * 4; png.data[o] = r; png.data[o + 1] = gg; png.data[o + 2] = b; png.data[o + 3] = 255;
    }
  };
  fill(0, 0, png.width, png.height, COLORS.ground);
  const cell = (i: number, j: number, c: RGB) => fill(i * px, (g - 1 - j) * px, px, px, c); // 图像 y 向下，蓝图 y 向北 → 翻转
  const m = bp.masks;
  for (let j = 0; j < g; j++) for (let i = 0; i < g; i++) {
    if (m.walkable[j][i] === '1') cell(i, j, m.buildable[j][i] === '0' ? COLORS.path : COLORS.block);
    if (m.buildable[j][i] === '1') cell(i, j, COLORS.buildable);
    if (m.cultivable[j][i] === '1') cell(i, j, COLORS.bed);
  }
  for (const [i, j] of bp.anchors.reserved_bed.cells) cell(i, j, COLORS.reserved);
  for (const name of ['house', 'storage', 'well', 'exit', 'spawn'] as const) cell(bp.anchors[name][0], bp.anchors[name][1], COLORS[name]);
  return PNG.sync.write(png);
}

export function writeOutputs(bp: Blueprint, overlayGeojson: unknown, outDir: string): void {
  mkdirSync(outDir, { recursive: true });
  const { report, ...rest } = bp;
  const out: Blueprint = { ...rest, checksum: checksum(bp) };
  writeFileSync(path.join(outDir, 'farm_blueprint.json'), JSON.stringify(out, null, 1));
  writeFileSync(path.join(outDir, 'map_overlay.geojson'), JSON.stringify(overlayGeojson));
  writeFileSync(path.join(outDir, 'preview.png'), renderPreview(out));
  if (report) writeFileSync(path.join(outDir, 'report.json'), JSON.stringify(report, null, 1));
}

export interface ShippedCandidate { layout_patch_id: string; revision: number; name: string }

export function writeRegions(regions: Region[], byRegion: Record<string, ShippedCandidate[]>, file: string): void {
  const out = {
    format: 1,
    regions: regions.map(r => ({
      id: r.id, name: r.name, timezone: r.timezone, center: r.center, street_zoom: r.street_zoom, pitch: r.pitch,
      candidates: (byRegion[r.id] ?? []).map(c => ({ layout_patch_id: c.layout_patch_id, revision: c.revision, name: c.name })),
    })),
  };
  mkdirSync(path.dirname(file), { recursive: true });
  writeFileSync(file, JSON.stringify(out, null, 1));
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd tools/geo_blueprint && pnpm test test/writer.test.ts`
Expected: 3 passed

- [ ] **Step 5: Commit**

```bash
git add tools/geo_blueprint
git commit -m "feat(blueprint): canonical checksum、输出写入、预览图与 regions.json"
```

---

### Task 8: 管线装配、合成安全蓝图、CLI

**Files:**
- Create: `tools/geo_blueprint/src/pipeline.ts`
- Create: `tools/geo_blueprint/src/cli.ts`
- Create: `tools/geo_blueprint/test/pipeline.test.ts`

**Interfaces:**
- Produces: `buildFromLines(lines, half, meta, transformer?) -> {bp, overlay}`（`meta` 含 `layout_patch_id/revision/region_id/name/source`；无 transformer 时 overlay 为空 FeatureCollection、`overlay_wgs84.center=[0,0]`）、`buildCandidate(cand, revision=1, refetch=false) -> Promise<{bp, overlay}>`、`syntheticSafe(id='safe_grid') -> {bp, overlay}`、`buildAndWrite(bp, overlay, outRoot) -> outDir`（有 errors 抛 `ValidationError`）。
- CLI（`pnpm cli <cmd>`）：`build <id> [--refetch]` / `build-all [--refetch]` / `synthetic` / `validate-all` / `regions`。

- [ ] **Step 1: 写失败测试**

`tools/geo_blueprint/test/pipeline.test.ts`：
```ts
import { describe, it, expect, beforeAll } from 'vitest';
import { existsSync, mkdtempSync, readFileSync } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import * as osm from '../src/osm.js';
import * as topo from '../src/topology.js';
import * as pipeline from '../src/pipeline.js';
import * as writer from '../src/writer.js';
import * as geos from '../src/geos.js';

const FIX = path.join(__dirname, 'fixtures', 'grid_overpass.json');

describe('pipeline', () => {
  beforeAll(geos.initGeos);
  it('builds a valid, deterministic blueprint from the fixture', () => {
    const ways = osm.parseWays(JSON.parse(readFileSync(FIX, 'utf8')));
    const lines = topo.clipLines(topo.projectWays(ways, 31.2, 121.4), 150);
    const meta = { layout_patch_id: 'fix', revision: 1, region_id: 'shanghai', name: 'Fixture', source: {} };
    const t = topo.makeTransformer(31.2, 121.4);
    const { bp, overlay } = pipeline.buildFromLines(lines, 150, meta, t);
    const { bp: bp2 } = pipeline.buildFromLines(lines, 150, meta, t);
    expect(bp.report!.errors).toEqual([]);
    expect(writer.checksum(bp)).toBe(writer.checksum(bp2));
    expect(bp.blocks.length).toBeGreaterThanOrEqual(3); expect(bp.blocks.length).toBeLessThanOrEqual(7);
    expect(bp.grid).toEqual([64, 64]);
    expect(overlay.features).toHaveLength(bp.paths.length + bp.blocks.length);
    expect(bp.overlay_wgs84.center[0]).toBeCloseTo(31.2, 8);
    expect(bp.overlay_wgs84.center[1]).toBeCloseTo(121.4, 8);
  });
  it('synthetic safe blueprint is valid', () => {
    const { bp, overlay } = pipeline.syntheticSafe();
    expect(bp.layout_patch_id).toBe('safe_grid');
    expect(bp.report!.errors).toEqual([]);
    expect(overlay.features).toEqual([]);
  });
  it('buildAndWrite writes report', () => {
    const { bp, overlay } = pipeline.syntheticSafe();
    const out = pipeline.buildAndWrite(bp, overlay, mkdtempSync(path.join(os.tmpdir(), 'out-')));
    expect(existsSync(path.join(out, 'farm_blueprint.json'))).toBe(true);
    expect(existsSync(path.join(out, 'report.json'))).toBe(true);
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd tools/geo_blueprint && pnpm test test/pipeline.test.ts`
Expected: FAIL `Cannot find module '../src/pipeline.js'`

- [ ] **Step 3: 写 pipeline.ts**

```ts
/** 把各步串起来。真实候选与合成蓝图共用 buildFromLines。 */
import { statSync } from 'node:fs';
import path from 'node:path';
import type { Feature, FeatureCollection, LineString, Polygon } from 'geojson';
import * as config from './config.js';
import * as osm from './osm.js';
import * as topo from './topology.js';
import * as norm from './normalize.js';
import * as masks from './masks.js';
import * as anchors from './anchors.js';
import * as writer from './writer.js';
import * as geos from './geos.js';
import type { Blueprint } from './types.js';

export interface Meta { layout_patch_id: string; revision: number; region_id: string; name: string; source: Record<string, unknown> }
export interface Built { bp: Blueprint; overlay: FeatureCollection }

const round2 = (v: number) => Math.round(v * 100) / 100;

function linesToPlay(lines: LineString[], half: number): LineString[] {
  const out: LineString[] = [];
  for (const l of lines) {
    const g = norm.simplify(norm.toPlay(l, half, config.PLAY_AREA_M), 1.0);
    if (g.type === 'LineString' && geos.length(g) > 2.0) out.push(g);
  }
  return out;
}

function overlayOf(t: topo.Transformer, lines: LineString[], blocks: Polygon[]) {
  const features: Feature[] = [];
  const paths: [number, number][][] = [], blocksLL: [number, number][][] = [];
  for (const l of lines) {
    const ll = l.coordinates.map(c => t.inverse(c));                       // [lng,lat]
    features.push({ type: 'Feature', properties: { kind: 'path' }, geometry: { type: 'LineString', coordinates: ll } });
    paths.push(ll.map(([lg, la]) => [la, lg]));
  }
  for (const b of blocks) {
    const ll = b.coordinates[0].map(c => t.inverse(c));
    features.push({ type: 'Feature', properties: { kind: 'block' }, geometry: { type: 'Polygon', coordinates: [ll] } });
    blocksLL.push(ll.map(([lg, la]) => [la, lg]));
  }
  return { geojson: { type: 'FeatureCollection', features } as FeatureCollection, paths, blocks: blocksLL };
}

export function buildFromLines(rawLines: LineString[], half: number, meta: Meta, transformer?: topo.Transformer): Built {
  const lines = topo.clipLines(rawLines, half);
  const polys = topo.polygonizeBlocks(lines, half);
  const blocksLocal = norm.selectBlocks(polys, half);
  const blocksPlay = blocksLocal.map(b => norm.simplify(norm.toPlay(b, half, config.PLAY_AREA_M)));
  const pathsPlay = linesToPlay(lines, half);
  const m = masks.rasterize(pathsPlay, blocksPlay, config.GRID, config.CELL_M, config.PATH_WIDTH_M);
  const pcs = masks.pathCells(pathsPlay, config.GRID, config.CELL_M, config.PATH_WIDTH_M);
  const a = anchors.place(m, pcs, config.GRID);
  const { ids, neighbors } = norm.adjacency(blocksPlay, config.PATH_WIDTH_M);
  let overlay: FeatureCollection = { type: 'FeatureCollection', features: [] };
  let center: [number, number] = [0, 0];
  let paths: [number, number][][] = [], blocksLL: [number, number][][] = [];
  if (transformer) {
    const o = overlayOf(transformer, lines, blocksLocal);
    overlay = o.geojson; paths = o.paths; blocksLL = o.blocks;
    const [lng, lat] = transformer.inverse([0, 0]);
    center = [lat, lng];
  }
  const bp: Blueprint = {
    format: 1, layout_patch_id: meta.layout_patch_id, revision: meta.revision, region_id: meta.region_id, name: meta.name,
    checksum: '', source: meta.source,
    play_area_m: config.PLAY_AREA_M, cell_m: config.CELL_M, grid: [config.GRID, config.GRID],
    masks: m,
    paths: pathsPlay.map((l, i) => ({ id: `p${i}`, points: l.coordinates.map(([x, y]) => [round2(x), round2(y)] as [number, number]), width_m: config.PATH_WIDTH_M })),
    blocks: blocksPlay.map((b, i) => ({ id: ids[i], polygon: b.coordinates[0].map(([x, y]) => [round2(x), round2(y)] as [number, number]), neighbors: neighbors[ids[i]] })),
    anchors: a,
    overlay_wgs84: { center, paths, blocks: blocksLL },
  };
  bp.report = anchors.validate(bp);
  return { bp, overlay };
}

export async function buildCandidate(cand: config.Candidate, revision = 1, refetch = false): Promise<Built> {
  const cache = path.join(config.CACHE_DIR, `${cand.layoutPatchId}.json`);
  if (refetch) { try { (await import('node:fs')).unlinkSync(cache); } catch { /* no cache */ } }
  const data = await osm.fetchOverpass(cand.lat, cand.lng, cand.radiusM, cache);
  const lines = topo.projectWays(osm.parseWays(data), cand.lat, cand.lng);
  const t = topo.makeTransformer(cand.lat, cand.lng);
  const meta: Meta = {
    layout_patch_id: cand.layoutPatchId, revision, region_id: cand.regionId, name: cand.name,
    source: { provider: 'osm', license: 'ODbL 1.0', attribution: '© OpenStreetMap contributors',
      fetched_at: statSync(cache).mtime.toISOString(), center: [cand.lat, cand.lng], radius_m: cand.radiusM },
  };
  return buildFromLines(lines, cand.radiusM, meta, t);
}

export function syntheticSafe(layoutPatchId = 'safe_grid', revision = 1): Built {
  const half = 32;
  const line = (c: number[][]): LineString => ({ type: 'LineString', coordinates: c });
  const lines = [line([[-half, 0], [half, 0]]), line([[0, -half], [0, half]]),
    line([[-half, 20], [half, 20]]), line([[-20, -half], [-20, half]])];
  const meta: Meta = { layout_patch_id: layoutPatchId, revision, region_id: 'any', name: 'Safe Grid', source: { provider: 'synthetic' } };
  return buildFromLines(lines, half, meta);
}

export function buildAndWrite(bp: Blueprint, overlay: FeatureCollection, outRoot: string): string {
  if (bp.report && bp.report.errors.length) throw new anchors.ValidationError(bp.report.errors.join('; '));
  const outDir = path.join(outRoot, bp.layout_patch_id, `r${bp.revision}`);
  writer.writeOutputs(bp, overlay, outDir);
  return outDir;
}
```

- [ ] **Step 4: 写 cli.ts**

```ts
/** CLI：build <id> [--refetch] | build-all [--refetch] | synthetic | validate-all | regions */
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import * as config from './config.js';
import * as pipeline from './pipeline.js';
import * as writer from './writer.js';
import * as anchors from './anchors.js';
import * as geos from './geos.js';
import type { Blueprint } from './types.js';

function shippedBlueprints(): { file: string; bp: Blueprint }[] {
  if (!existsSync(config.BLUEPRINTS_DIR)) return [];
  const out: { file: string; bp: Blueprint }[] = [];
  for (const id of readdirSync(config.BLUEPRINTS_DIR)) {
    const dir = path.join(config.BLUEPRINTS_DIR, id);
    for (const rev of readdirSync(dir)) {
      const file = path.join(dir, rev, 'farm_blueprint.json');
      if (existsSync(file)) out.push({ file, bp: JSON.parse(readFileSync(file, 'utf8')) as Blueprint });
    }
  }
  return out;
}

function validateAll(): number {
  const reports: Record<string, ReturnType<typeof anchors.validate>> = {};
  for (const { file, bp } of shippedBlueprints()) {
    if (writer.checksum(bp) !== bp.checksum) { console.log(`CHECKSUM MISMATCH ${file}`); return 1; }
    const r = anchors.validate(bp);
    if (r.errors.length) { console.log(`INVALID ${file}: ${r.errors.join('; ')}`); return 1; }
    reports[bp.layout_patch_id] = r;
  }
  for (const key of ['far_bed_s', 'tour_s'] as const) {
    const vals = Object.entries(reports).filter(([id]) => !id.startsWith('safe')).map(([, r]) => r[key]);
    if (!vals.length) continue;
    const min = Math.min(...vals), max = Math.max(...vals);
    const spread = (max - min) / Math.max(min, 1e-9);
    console.log(`${key}: min=${min} max=${max} spread=${(spread * 100).toFixed(1)}%`);
    if (spread > 0.10) { console.log(`FAIRNESS FAIL on ${key}`); return 1; }
  }
  console.log(`OK ${Object.keys(reports).length} blueprints`);
  return 0;
}

async function main(argv: string[]): Promise<number> {
  await geos.initGeos();
  const cmd = argv[0] ?? 'help';
  const refetch = argv.includes('--refetch');
  if (cmd === 'build') {
    const { bp, overlay } = await pipeline.buildCandidate(config.candidate(argv[1]), 1, refetch);
    console.log(JSON.stringify(bp.report));
    console.log(pipeline.buildAndWrite(bp, overlay, config.BLUEPRINTS_DIR));
    return 0;
  }
  if (cmd === 'build-all') {
    for (const cand of config.loadCandidates()) {
      const { bp, overlay } = await pipeline.buildCandidate(cand, 1, refetch);
      console.log(cand.layoutPatchId, JSON.stringify(bp.report));
      pipeline.buildAndWrite(bp, overlay, config.BLUEPRINTS_DIR);
    }
    return 0;
  }
  if (cmd === 'synthetic') {
    const { bp, overlay } = pipeline.syntheticSafe();
    console.log(pipeline.buildAndWrite(bp, overlay, config.BLUEPRINTS_DIR));
    return 0;
  }
  if (cmd === 'validate-all') return validateAll();
  if (cmd === 'regions') {
    const byRegion: Record<string, writer.ShippedCandidate[]> = {};
    for (const cand of config.loadCandidates()) {
      if (existsSync(path.join(config.BLUEPRINTS_DIR, cand.layoutPatchId, 'r1', 'farm_blueprint.json')))
        (byRegion[cand.regionId] ??= []).push({ layout_patch_id: cand.layoutPatchId, revision: 1, name: cand.name });
    }
    writer.writeRegions(config.loadRegions(), byRegion, config.REGIONS_OUT);
    console.log(config.REGIONS_OUT);
    return 0;
  }
  console.log('usage: pnpm cli build <id> [--refetch] | build-all [--refetch] | synthetic | validate-all | regions');
  return 2;
}

main(process.argv.slice(2)).then(code => process.exit(code), err => { console.error(err); process.exit(1); });
```

- [ ] **Step 5: 跑全部测试与类型检查**

Run: `cd tools/geo_blueprint && pnpm test && pnpm typecheck`
Expected: 全部通过（约 24 条），typecheck 无错。

- [ ] **Step 6: 生成安全蓝图并入库**

```bash
cd tools/geo_blueprint && pnpm cli synthetic && cd ../..
ls assets/blueprints/safe_grid/r1/ && cat assets/blueprints/safe_grid/r1/report.json
```
Expected: 四个文件；`errors` 为空。`open assets/blueprints/safe_grid/r1/preview.png` 目视：米色十字路，四个绿区块，三条棕色田畦在出生点附近，一条浅棕预留畦。

- [ ] **Step 7: Commit**

```bash
git add tools/geo_blueprint assets/blueprints/safe_grid
git commit -m "feat(blueprint): 管线装配、CLI 与合成安全蓝图"
```

---

### Task 9: 上海三候选实跑与目视 QA

**Files:**
- Create: `tools/geo_blueprint/cache/sh_a.json`、`sh_b.json`、`sh_c.json`（抓取产物）
- Create: `assets/blueprints/sh_{a,b,c}/r1/*`
- Modify: `tools/geo_blueprint/candidates.json`（若换中心点）

- [ ] **Step 1: 抓取并构建**

```bash
cd tools/geo_blueprint
export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890
pnpm cli build sh_a
pnpm cli build sh_b
pnpm cli build sh_c
cd ../..
```
Expected: 每条先打印 `{"far_bed_s":...,"tour_s":...,"errors":[]}` 再打印输出目录。若抛 `ValidationError`（区块 <3、田畦位不够、最远田畦 >12 s、house 无处放），改 `candidates.json` 里该候选的 `lat/lng/radius_m`，加 `--refetch` 重跑。Overpass 偶发 429/504 就等一分钟重试。

- [ ] **Step 2: 目视三张 preview.png**

```bash
open assets/blueprints/sh_a/r1/preview.png assets/blueprints/sh_b/r1/preview.png assets/blueprints/sh_c/r1/preview.png
```
判据（PRD §4.6「去标签后能把农场匹配到街区轮廓」的前置）：三张图的主路走向和区块形状肉眼可区分；没有一张是「一大块 + 碎边」。不合格就换中心点重跑。

- [ ] **Step 3: 跨候选公平校验**

Run: `cd tools/geo_blueprint && pnpm cli validate-all && cd ../..`
Expected: `far_bed_s`、`tour_s` 两行 `spread` 均 ≤ 10%，最后一行 `OK 4 blueprints`。超过就调最差那个候选的中心点。

- [ ] **Step 4: Commit**

```bash
git add tools/geo_blueprint/cache tools/geo_blueprint/candidates.json assets/blueprints/sh_a assets/blueprints/sh_b assets/blueprints/sh_c
git commit -m "feat(blueprint): 上海三候选蓝图（OSM ODbL，r1）"
```

---

### Task 10: 洛杉矶三候选与 regions.json

**Files:**
- Create: `tools/geo_blueprint/cache/la_{a,b,c}.json`
- Create: `assets/blueprints/la_{a,b,c}/r1/*`
- Create: `assets/farm/data/regions.json`
- Create: `tools/geo_blueprint/test/shipped.test.ts`

- [ ] **Step 1: 抓取并构建洛杉矶三候选，目视，公平校验**

同 Task 9 的三步，把 `sh_*` 换成 `la_a la_b la_c`。`validate-all` 现在比较六个候选，spread 仍须 ≤ 10%。

- [ ] **Step 2: 生成 regions.json**

Run: `cd tools/geo_blueprint && pnpm cli regions && cd ../.. && cat assets/farm/data/regions.json`
Expected: 两个 region，各 3 个 candidate，candidate 只有 `layout_patch_id/revision/name`，没有经纬度。

- [ ] **Step 3: 写入库产物的守卫测试**

`tools/geo_blueprint/test/shipped.test.ts`：
```ts
import { describe, it, expect } from 'vitest';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import * as config from '../src/config.js';
import * as writer from '../src/writer.js';
import * as anchors from '../src/anchors.js';
import type { Blueprint } from '../src/types.js';

describe('shipped blueprints', () => {
  it('regions.json points to existing, valid, checksum-matching blueprints', () => {
    expect(existsSync(config.REGIONS_OUT)).toBe(true);
    const data = JSON.parse(readFileSync(config.REGIONS_OUT, 'utf8'));
    expect(new Set(data.regions.map((r: { id: string }) => r.id))).toEqual(new Set(['shanghai', 'los_angeles']));
    for (const r of data.regions) {
      expect(r.candidates).toHaveLength(3);
      for (const c of r.candidates) {
        const file = path.join(config.BLUEPRINTS_DIR, c.layout_patch_id, `r${c.revision}`, 'farm_blueprint.json');
        const bp = JSON.parse(readFileSync(file, 'utf8')) as Blueprint;
        expect(bp.checksum).toBe(writer.checksum(bp));
        expect(anchors.validate(bp).errors).toEqual([]);
        expect(c.lat).toBeUndefined();
      }
    }
  });
});
```

- [ ] **Step 4: 跑全部测试**

Run: `cd tools/geo_blueprint && pnpm test && cd ../..`
Expected: 全绿。

- [ ] **Step 5: Commit**

```bash
git add tools/geo_blueprint assets/blueprints/la_a assets/blueprints/la_b assets/blueprints/la_c assets/farm/data/regions.json
git commit -m "feat(blueprint): 洛杉矶三候选蓝图与 regions.json"
```

---

## Self-Review

- **Spec coverage**：PRD §4.2 继承与归一（Task 3/4/5）、四张 mask（5/6）、§4.4 公平门槛与淘汰（6 校验 + CLI validate-all）、§4.5 管线与不可变 revision（8 输出目录）、§4.6 访客不下发经纬度（regions.json 不含坐标；蓝图内 `overlay_wgs84` 只供地图高亮，G0-B 不把它塞进访客接口）、§11.4 许可记录（`source` 字段 + cache 入库）、双城（9/10）、安全蓝图（8）。
- **未覆盖，明确留到后续 Gate**：河流/绿地转水渠花圃（PRD §4.2 可选项）、`bake_blueprint.gd` 烘焙 .res（G0-B 用运行时生成，G4 再烘）。
- **Placeholder scan**：无 TBD；每步有代码与命令。
- **Type consistency**：`Masks` 四键、`Anchors` 键名、`Bed.cells` 形状、`cellKey` 约定（`j*grid+i`）、canonical 顺序在 Task 5/6/7/8 一致；`Transformer.forward/inverse` 输入输出都是 `[lng,lat]`/`[x,y]`，蓝图内 `overlay_wgs84`/`source.center` 统一 `[lat,lng]`；G0-B Task 1 逐字复刻 canonical。
- **已在本机验证的外部 API**（2026-09-03 spike，geos-wasm 3.1.1）：`geojsonToGeosGeom/geosGeomToGeojson`、`GEOSUnaryUnion`、`GEOSPolygonize`（指针数组经 `Module.HEAP32`）、`GEOSBuffer`、`GEOSPrepare/GEOSPreparedContains`、`GEOSTopologyPreserveSimplify`、`GEOSIntersection`、`GEOSArea`（经 `Module.HEAPF64` 读回）、proj4 tmerc 正反投影、pngjs 写图。`GEOSIntersects`、`GEOSLength`、`GEOSPreparedGeom_destroy` 是标准 GEOS C API，未单独跑过，Task 1 的测试会覆盖到前两者。
