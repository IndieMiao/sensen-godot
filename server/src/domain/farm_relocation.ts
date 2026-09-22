import type { Content } from './content.js';
import type { FarmState } from './state.js';
import { footprintCells } from './handlers/decorations.js';
import { isPlaceable, isTillable, parseCell, type PlotLayout } from './plot.js';
import type { FarmTerrain } from '../geography/farm_terrain.js';
import type { FarmLocation } from '../http/farm_location.js';
import type { FarmRow } from '../http/dto.js';
import type { CommandEnvelope } from './commands.js';

export const RELOCATION_PREVIEW_TTL = 30 * 60_000;
export interface RelocationDraft {
  generation_version?: import('../geography/farm_terrain.js').FarmGenerationVersion;
  preview_id: string;
  base_version: number;
  expires_at: number;
  region_id: string;
  location: FarmLocation;
  farm_terrain: FarmTerrain;
  moved_cells: number;
  moved_decorations: number;
}
export interface RelocationConfirm { preview_id: string; base_version: number; idempotency_key: string }
export type RelocationOutcome = { kind: 'applied' | 'replayed'; farm: FarmRow }
  | { kind: 'rejected'; code: string };
export const relocationEnvelope = (input: RelocationConfirm): Omit<CommandEnvelope, 'type'> & { type: string } => ({
  idempotency_key: input.idempotency_key, base_version: input.base_version,
  type: 'relocate_farm', payload: { preview_id: input.preview_id },
});
export function relocationAvailable(farm: FarmRow): boolean {
  return farm.relocation_available === true && !farm.relocation_used && !farm.farm_terrain;
}
const COORDINATE_COMMANDS = new Set(['till_cells', 'sow_cells', 'water_cells', 'harvest_cells', 'clear_plot', 'save_decorations']);
/** A new version cannot turn an edit queued on the old farm into an edit on the new coordinate space. */
export function relocationCommandMatches(farm: FarmRow, env: CommandEnvelope): boolean {
  if (!farm.relocation_used || !COORDINATE_COMMANDS.has(env.type)) return true;
  const checksum = farm.farm_terrain?.plot.checksum;
  return typeof checksum === 'string' && checksum.length > 0 && env.terrain_checksum === checksum;
}
export function relocationBlocked(farm: FarmRow, now: number, content: Content): boolean {
  const active = farm.state.fishing?.active;
  return Boolean(active && now <= (active.hooked_at ?? active.hook_until)
    + content.fishing.max_steps * content.fishing.step_ms + content.fishing.settle_grace_ms || (farm.state.mine?.floor ?? 0) > 0);
}
export function relocationConfirmError(farm: FarmRow, input: RelocationConfirm, now: number, content: Content): string | undefined {
  if (!relocationAvailable(farm)) return 'RELOCATION_UNAVAILABLE';
  if (relocationBlocked(farm, now, content)) return 'RELOCATION_BUSY';
  const draft = farm.relocation_draft;
  if (!draft || draft.preview_id !== input.preview_id || draft.expires_at <= now) return 'RELOCATION_EXPIRED';
  if (draft.base_version !== input.base_version || farm.version !== input.base_version || draft.region_id !== farm.region_id)
    return 'RELOCATION_CONFLICT';
}
export class RelocationError extends Error {
  constructor(public code: string) { super(code); }
}

/** Only coordinates may change. No grants, inventory upgrades, clock projection or maturity reset. */
export function relocateFarmState(state: FarmState, plot: PlotLayout, content: Content) {
  const next = structuredClone(state), occupied = new Set<string>(), blocked = new Set<string>();
  const blockingObjects: string[][] = [];
  const ids = Array.from({ length: plot.gx * plot.gy }, (_, n) => `${n % plot.gx},${Math.floor(n / plot.gx)}`);
  const adjacent = (id: string) => {
    const [x, y] = parseCell(id)!;
    return [[x - 1, y], [x + 1, y], [x, y - 1], [x, y + 1]]
      .filter(([i, j]) => i >= 0 && j >= 0 && i < plot.gx && j < plot.gy).map(([i, j]) => `${i},${j}`);
  };
  const spawn = plot.anchors.spawn.join(',');
  const flood = (obstacles: Set<string>) => {
    const seen = new Set<string>();
    if (obstacles.has(spawn)) return seen;
    const queue = [spawn]; seen.add(spawn);
    for (let n = 0; n < queue.length; n++) for (const id of adjacent(queue[n])) {
      const [x, y] = parseCell(id)!;
      if (plot.walk[y * plot.gx + x] && !obstacles.has(id) && !seen.has(id)) { seen.add(id); queue.push(id); }
    }
    return seen;
  };
  const reachable = flood(blocked);
  if (Object.keys(state.cells).length > [...reachable].filter(id => isTillable(plot, id)).length)
    throw new RelocationError('RELOCATION_NO_SPACE');
  const protectedCells = new Set(Object.values(plot.anchors).map(cell => cell.join(',')).filter(id => reachable.has(id)));
  // New layouts persist their facility approaches; old frozen layouts retain the original cells.
  const approaches = [plot.anchors.pond_shore ?? [12, 37], plot.anchors.mine_approach ?? (plot.anchors.mine ? [plot.anchors.mine[0], plot.anchors.mine[1] - 2] : [25, 34])];
  for (const cell of approaches) if (reachable.has(cell.join(','))) protectedCells.add(cell.join(','));
  type ObjectToPlace = { origin: string; size: [number, number]; crop: boolean; blocks: boolean; place: (id: string) => void };
  const objects: ObjectToPlace[] = [];
  let moved_cells = 0, moved_decorations = 0;
  next.cells = {};
  for (const id of Object.keys(state.cells).sort()) {
    const value = state.cells[id];
    if (!value || !parseCell(id)) throw new RelocationError('RELOCATION_NO_SPACE');
    const woody = Boolean(['sown', 'growing'].includes(value.state) && value.crop && content.crops.crops[value.crop]?.woody);
    objects.push({ origin: id, size: [1, 1], crop: true, blocks: woody,
      place: target => { next.cells[target] = structuredClone(value); moved_cells += Number(target !== id); } });
  }
  for (const prop of next.decorations ?? []) {
    const size = content.decorations.props[prop.prop_id]?.footprint;
    if (!size || !Array.isArray(prop.cell) || prop.cell.length !== 2 || !prop.cell.every(Number.isSafeInteger))
      throw new RelocationError('RELOCATION_NO_SPACE');
    const origin = prop.cell.join(',');
    // rotation_q remains unchanged; footprint dimensions follow the existing server/client placement contract.
    objects.push({ origin, size, crop: false, blocks: true,
      place: target => { prop.cell = parseCell(target)!; moved_decorations += Number(target !== origin); } });
  }
  const covered = (item: ObjectToPlace, id: string) => footprintCells(parseCell(id)!, item.size);
  const allowed = (item: ObjectToPlace, id: string) => {
    const cells = covered(item, id);
    if (!cells.every(cell => reachable.has(cell) && !occupied.has(cell)
      && (item.crop ? isTillable(plot, cell) : isPlaceable(plot, cell)))) return false;
    if (!item.blocks) return true;
    if (cells.some(cell => protectedCells.has(cell))) return false;
    const obstacles = new Set([...blocked, ...cells]), walk = flood(obstacles);
    // Blocking props/woody crops may not cut off any formerly reachable land or another crop.
    return walk.size === reachable.size - obstacles.size
      && [...blockingObjects, cells].every(group => group.some(cell => adjacent(cell).some(other => walk.has(other))));
  };
  const place = (item: ObjectToPlace, id: string) => {
    const cells = covered(item, id);
    for (const cell of cells) { occupied.add(cell); if (item.blocks) blocked.add(cell); }
    if (item.blocks) blockingObjects.push(cells);
    item.place(id);
  };
  const pending: ObjectToPlace[] = [];
  for (const item of objects) {
    if (parseCell(item.origin) && allowed(item, item.origin)) place(item, item.origin);
    else pending.push(item);
  }
  for (const item of pending) {
    const origin = parseCell(item.origin);
    if (!origin) throw new RelocationError('RELOCATION_NO_SPACE');
    const candidates = ids.map((id, n) => ({ id, n, distance: (n % plot.gx - origin[0]) ** 2 + (Math.floor(n / plot.gx) - origin[1]) ** 2 }))
      .sort((a, b) => a.distance - b.distance || a.n - b.n);
    const target = candidates.find(candidate => allowed(item, candidate.id));
    if (!target) throw new RelocationError('RELOCATION_NO_SPACE');
    place(item, target.id);
  }
  return { state: next, moved_cells, moved_decorations };
}
