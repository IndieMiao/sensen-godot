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
