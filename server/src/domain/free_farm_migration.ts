import { CROP_IDS } from './content.js';
import type { FarmState } from './state.js';
import { isPlaceable, isTillable, parseCell, type PlotLayout } from './plot.js';
import type { DecorationPlacement } from './state.js';

/** Preserve crop records, deadlines and ownership; move conflicting plots to the nearest free cells. */
export function upgradeFreeFarmState(state: FarmState, plot?: PlotLayout,
  footprints: Record<string, [number, number]> = {}): FarmState {
  const next = structuredClone(state);
  for (const [id, value] of Object.entries(next.cells)) {
    if (!value) continue;
    const cell = value as unknown as Record<string, unknown>;
    if (cell.state === 'wild' || cell.state === 'cleared') {
      if (cell.crop != null || cell.ready_at != null) throw new Error(`Unexpected planted legacy cell ${id}`);
      delete next.cells[id];
    } else if (['tilled', 'sown', 'growing'].includes(String(cell.state))) {
      if (!Object.hasOwn(cell, 'watered_at'))
        cell.watered_at = cell.care_done_at ?? null;
    } else throw new Error(`Unknown cell state at ${id}`);
  }
  for (const crop of CROP_IDS) {
    next.inventory.seeds[crop] ??= { bought: 0, bound: 0 };
    next.inventory.produce[crop] ??= 0;
  }
  if (plot) {
    const decorations: DecorationPlacement[] = (next.decorations ?? []).map(value => {
      const old = value as unknown as { prop_id: DecorationPlacement['prop_id']; cell?: [number, number]; offset_q?: [number, number]; anchor_id?: string; rotation_q?: number };
      if (!footprints[old.prop_id]) throw new Error(`Missing decoration footprint: ${old.prop_id}`);
      let cell = old.cell;
      if (!cell && old.anchor_id === 'courtyard' && old.offset_q?.length === 2 && old.offset_q.every(Number.isSafeInteger))
        cell = [32 + old.offset_q[0], 12 - old.offset_q[1]];
      if (!cell || cell.length !== 2 || !cell.every(Number.isSafeInteger)) throw new Error('Unknown saved decoration position');
      return { prop_id: old.prop_id, cell, ...(old.rotation_q ? { rotation_q: old.rotation_q } : {}) };
    });
    const covered = (prop: DecorationPlacement): string[] => {
      const [w, h] = footprints[prop.prop_id]; const out: string[] = [];
      for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) out.push(`${prop.cell[0] + i},${prop.cell[1] + j}`);
      return out;
    };
    const furniture = new Set(decorations.flatMap(covered));
    const occupied = new Set(Object.keys(next.cells));
    const blocked = [...occupied].filter(id => !isTillable(plot, id)).sort();
    for (const id of blocked) {
      const origin = parseCell(id);
      if (!origin) throw new Error(`Invalid saved cell ID ${id}`);
      let best = '', distance = Infinity;
      // Deterministic nearest free cell; ties favour the lower row, then lower column.
      for (let j = 0; j < plot.gy; j++) for (let i = 0; i < plot.gx; i++) {
        const candidate = `${i},${j}`;
        if (occupied.has(candidate) || furniture.has(candidate) || !isTillable(plot, candidate)) continue;
        const squared = (i - origin[0]) ** 2 + (j - origin[1]) ** 2;
        if (squared < distance) { best = candidate; distance = squared; }
      }
      if (!best) throw new Error('No free cultivable cell for save migration');
      next.cells[best] = next.cells[id];
      delete next.cells[id];
      occupied.delete(id); occupied.add(best);
    }
    const placed = new Set<string>();
    for (const prop of decorations) {
      const allowed = (candidate: DecorationPlacement) => covered(candidate)
        .every(id => isPlaceable(plot, id) && !occupied.has(id) && !placed.has(id));
      if (!allowed(prop)) {
        const origin = prop.cell; let best: [number, number] | undefined, distance = Infinity;
        for (let j = 0; j < plot.gy; j++) for (let i = 0; i < plot.gx; i++) {
          if (!allowed({ ...prop, cell: [i, j] })) continue;
          const squared = (i - origin[0]) ** 2 + (j - origin[1]) ** 2;
          if (squared < distance) { best = [i, j]; distance = squared; }
        }
        if (!best) throw new Error('No free position for saved decoration');
        prop.cell = best;
      }
      for (const id of covered(prop)) placed.add(id);
    }
    if (next.decorations !== undefined) next.decorations = decorations;
  }
  return next;
}
