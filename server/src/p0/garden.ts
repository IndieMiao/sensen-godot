/**
 * P1 step 1 garden (q(59), SGODOT-239; plan §5.7): the plot grid shared with the client (content.garden), the 10 plots
 * Homestead Lv3 adds, and facilities on plots. A sprinkler stands on one empty plot and waters the ring of 8 around it
 * on the grid (diagonals included, fewer at the edge): a covered plot grows as it is sown, and its ripening time is cut
 * by 15% — with Compost's 20% capped at 35% together — locked when it starts growing. Built in one step with `place`
 * (q(22): no stock of built-but-unplaced facilities), moved for free with `move_facility`, never removed.
 */
import type { P0Content, WorkbenchRecipe } from './content.js';
import type { Refusal } from './fishing.js';
import type { P0Event } from './progress.js';
import { skillLevel } from './rules.js';
import type { Facility, P0State, Plot } from './state.js';
import { missing, takeStorageFirst } from './storage.js';

/** [col, row] of a plot on the garden grid, or null for an id the grid does not have. */
export function plotCell(c: P0Content, id: number): [number, number] | null {
  const at = c.garden.plots[id];
  return Number.isInteger(id) && at ? at : null;
}

/** The plots a facility on `plot` covers: ring8 = the neighbours on the grid that are plots, of the first `count`
 * (the homestead's plots now: an edge sprinkler at Homestead Lv2 covers none of 30–39 before they exist). */
export function coverOf(c: P0Content, kind: string, plot: number, count = c.garden.plots.length): number[] {
  const at = plotCell(c, plot);
  if (!at || c.facilities.kinds[kind]?.cover !== 'ring8') return [];
  const out: number[] = [];
  c.garden.plots.forEach(([x, y], id) => {
    if (id < count && id !== plot && Math.abs(x - at[0]) <= 1 && Math.abs(y - at[1]) <= 1) out.push(id);
  });
  return out;
}

const coverNow = (c: P0Content, s: P0State, f: Facility) => coverOf(c, f.kind, f.plot, s.plots.length);

/** Plot ids watered by a sprinkler now. */
export function coveredPlots(c: P0Content, s: P0State): Set<number> {
  const out = new Set<number>();
  for (const f of s.facilities ?? []) if (f.kind === 'sprinkler') for (const id of coverNow(c, s, f)) out.add(id);
  return out;
}

export function facilityAt(s: P0State, plot: number): Facility | undefined {
  return (s.facilities ?? []).find(f => f.plot === plot);
}

/** Ripening time in ms for a crop that starts growing now on `plot` (§5.7 / §5.5: covered −15%, Compost −20%, ≤ −35%). */
export function growMs(c: P0Content, s: P0State, plot: Plot, grow_h: number): number {
  let cut = 0;
  if (coveredPlots(c, s).has(plot.id)) cut += c.facilities.kinds.sprinkler.grow_cut;
  if (plot.fert) cut += 1 - (c.goods.fert_compost.grow_mult ?? 1);
  return Math.round(grow_h * 3_600_000 * (1 - Math.min(cut, c.facilities.grow_cut_cap)));
}

/** Plots the current Homestead level has: P0's 30, 40 from Homestead Lv3 (q(59) §1.1). */
export function plotCount(c: P0Content, s: P0State): number {
  const extra = c.garden?.extra;
  return extra && s.homestead.level >= extra.homestead ? extra.from + extra.count : c.start.tilled_plots + c.start.wild_plots;
}

/** Add the plots the Homestead level brings and does not have yet, as wild; the ids added (an upgrade, or a save
 * already past the level when this version arrives, q(59) §1.1). Existing plots never move. */
export function addPlots(c: P0Content, s: P0State): number[] {
  const added: number[] = [];
  for (let id = 0; id < plotCount(c, s); id++) {
    if (!s.plots.some(p => p.id === id)) { s.plots.push({ id, state: 'wild' }); added.push(id); }
  }
  s.plots.sort((a, b) => a.id - b.id);
  return added;
}

export function facilityCap(c: P0Content, s: P0State, kind: string): number {
  const f = c.facilities.kinds[kind];
  return f ? f.cap_base + f.cap_per_homestead * s.homestead.level : 0;
}

/** Why a field recipe can't be placed at all right now, in button order: level gate, cap, materials. */
export function placeBlock(c: P0Content, s: P0State, r: WorkbenchRecipe): Refusal | null {
  const kind = r.facility ?? '';
  if (r.gate) {
    const [skill, level] = r.gate;
    if (skillLevel(c, s, skill) < level)
      return { code: 'skill_level_required', detail: { skill, level, xp_to_go: Math.max(0, c.skills[skill][level - 1] - s.skills[skill]) } };
  }
  const cap = facilityCap(c, s, kind), used = (s.facilities ?? []).filter(f => f.kind === kind).length;
  if (used >= cap) {
    const higher = c.homestead.max_level > s.homestead.level;
    return { code: 'facility_cap', detail: { cap, used, homestead_next: higher ? s.homestead.level + 1 : null } };
  }
  const gap = missing(s, r.cost);
  if (gap) return { code: 'missing_materials', detail: gap };
  return null;
}

/** Why a facility can't stand on `plot`: no such plot, or a crop / another facility there. */
export function spotBlock(c: P0Content, s: P0State, plot: unknown, moving?: Facility): Refusal | null {
  const id = Number(plot);
  const p = Number.isInteger(id) ? s.plots.find(x => x.id === id) : undefined;
  if (!p || !plotCell(c, id)) return { code: 'bad_plot' };
  const other = facilityAt(s, id);
  if ((other && other !== moving) || p.crop || p.state === 'sown' || p.state === 'growing')
    return { code: 'plot_occupied', detail: { plot: id, facility: other?.kind ?? null, crop: p.crop ?? null } };
  return null;
}

const underOf = (s: P0State, plot: number): 'wild' | 'tilled' => s.plots.find(p => p.id === plot)?.state === 'wild' ? 'wild' : 'tilled';

/** Sown, not yet watered plots a facility now covers start growing (§5.7: watered as the sprinkler goes down). */
function waterCovered(c: P0Content, s: P0State, now: number, grow: (id: string) => number): number[] {
  const started: number[] = [];
  const cover = coveredPlots(c, s);
  for (const p of s.plots) {
    if (p.state !== 'sown' || !p.crop || !cover.has(p.id)) continue;
    p.state = 'growing';
    p.ready_at = now + growMs(c, s, p, grow(p.crop));
    started.push(p.id);
  }
  return started;
}

export function place(c: P0Content, s: P0State, cmd: { recipe?: unknown; plot?: unknown; space?: string }, now: number,
    events: P0Event[], grow: (id: string) => number): Refusal | null {
  if (cmd.space !== undefined && cmd.space !== 'home') return { code: 'not_home' };
  const r = c.workbench.recipes.find(x => x.id === String(cmd.recipe ?? '') && x.to === 'field');
  if (!r || !r.facility || !c.facilities.kinds[r.facility]) return { code: 'bad_recipe' };
  const block = placeBlock(c, s, r) ?? spotBlock(c, s, cmd.plot);
  if (block) return block;
  for (const [item, qty] of r.cost) { takeStorageFirst(s, item, qty); events.push({ kind: 'item', id: item, delta: -qty }); }
  s.facilities ??= [];
  s.facility_count = (s.facility_count ?? 0) + 1;
  const plot = Number(cmd.plot);
  const f: Facility = { id: s.facility_count, kind: r.facility, plot, under: underOf(s, plot) };
  s.facilities.push(f);
  const started = waterCovered(c, s, now, grow);
  events.push({ kind: 'facility', action: 'placed', facility: f.id, facility_kind: f.kind, plot,
    covered: coverNow(c, s, f).length, started });
  return null;
}

/** Move a facility to another empty plot for free; the old plot is tilled ground again. Crops already growing keep
 * their time (it was locked when they started); sown plots the new spot covers start growing. */
export function moveFacility(c: P0Content, s: P0State, cmd: { facility?: unknown; plot?: unknown; space?: string }, now: number,
    events: P0Event[], grow: (id: string) => number): Refusal | null {
  if (cmd.space !== undefined && cmd.space !== 'home') return { code: 'not_home' };
  const f = (s.facilities ?? []).find(x => x.id === Number(cmd.facility));
  if (!f) return { code: 'bad_facility' };
  if (f.plot === Number(cmd.plot)) return { code: 'same_plot' };
  const block = spotBlock(c, s, cmd.plot, f);
  if (block) return block;
  const from = f.plot;
  const old = s.plots.find(p => p.id === from);
  if (old) old.state = f.under ?? 'tilled';   // wild ground stays wild (亚瑟 on #207): moving never tills for free
  f.plot = Number(cmd.plot);
  f.under = underOf(s, f.plot);
  const started = waterCovered(c, s, now, grow);
  events.push({ kind: 'facility', action: 'moved', facility: f.id, facility_kind: f.kind, plot: f.plot, from,
    covered: coverNow(c, s, f).length, started });
  return null;
}

/** The view's facts: each facility with what it covers; per field recipe the cap, how many stand and the first block. */
export function facilitiesView(c: P0Content, s: P0State) {
  return (s.facilities ?? []).map(f => ({ id: f.id, kind: f.kind, plot: f.plot, covers: coverNow(c, s, f) }));
}

export function fieldRecipeView(c: P0Content, s: P0State, r: WorkbenchRecipe) {
  const kind = r.facility ?? '';
  return { facility: kind, cap: facilityCap(c, s, kind), used: (s.facilities ?? []).filter(f => f.kind === kind).length,
    homestead_next: c.homestead.max_level > s.homestead.level ? s.homestead.level + 1 : null };
}
