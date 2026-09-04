/** 把各步串起来。真实候选与合成蓝图共用 buildFromLines。 */
import { statSync, unlinkSync } from 'node:fs';
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

/** 只过滤一次：留下的 play 线与留下的原始（局部窗口坐标）线一一对应，overlay 与 bp.paths 共用同一份 kept 列表。 */
function linesToPlay(lines: LineString[], half: number): { play: LineString[]; kept: LineString[] } {
  const play: LineString[] = [];
  const kept: LineString[] = [];
  for (const l of lines) {
    const g = norm.simplify(norm.toPlay(l, half, config.PLAY_AREA_M), 1.0);
    if (g.type === 'LineString' && geos.length(g) > 2.0) { play.push(g); kept.push(l); }
  }
  return { play, kept };
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
  const { play: pathsPlay, kept: pathsLocal } = linesToPlay(lines, half);
  const m = masks.rasterize(pathsPlay, blocksPlay, config.GRID, config.CELL_M, config.PATH_WIDTH_M);
  const pcs = masks.pathCells(pathsPlay, config.GRID, config.CELL_M, config.PATH_WIDTH_M);
  const a = anchors.place(m, pcs, config.GRID);
  const { ids, neighbors } = norm.adjacency(blocksPlay, config.PATH_WIDTH_M);
  let overlay: FeatureCollection = { type: 'FeatureCollection', features: [] };
  let center: [number, number] = [0, 0];
  let paths: [number, number][][] = [], blocksLL: [number, number][][] = [];
  if (transformer) {
    const o = overlayOf(transformer, pathsLocal, blocksLocal);
    overlay = o.geojson; paths = o.paths; blocksLL = o.blocks;
    const [lng, lat] = transformer.inverse([0, 0]);
    center = [lat, lng];
  }
  // NOTE: bp.overlay_wgs84 below is a coordinate-swapped duplicate of map_overlay.geojson (~25%
  // of each blueprint file) and the only location data carried inside the blueprint itself.
  // Whether it should leave the blueprint entirely is pending a decision; until then, any
  // endpoint that serves a blueprint to a visitor must strip this field.
  const bp: Blueprint = {
    format: 1, layout_patch_id: meta.layout_patch_id, revision: meta.revision, region_id: meta.region_id, name: meta.name,
    checksum: '', source: meta.source,
    // 权威尺寸是整数毫米（r2 起）；浮点字段留作展示用派生值，不进 canonical。
    cell_mm: Math.round(config.CELL_M * 1000), play_area_mm: Math.round(config.PLAY_AREA_M * 1000),
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
  if (refetch) { try { unlinkSync(cache); } catch { /* no cache */ } }
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
  const report = bp.report ?? anchors.validate(bp);
  if (report.errors.length) throw new anchors.ValidationError(report.errors.join('; '));
  const outDir = path.join(outRoot, bp.layout_patch_id, `r${bp.revision}`);
  writer.writeOutputs({ ...bp, report }, overlay, outDir);
  return outDir;
}
