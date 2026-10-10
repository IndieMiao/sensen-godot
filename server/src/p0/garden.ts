/**
 * P1 step 1 garden (q(59), SGODOT-239; plan §5.7): the plot grid shared with the client (content.garden), the 10 plots
 * Homestead Lv3 adds, and facilities on plots. A sprinkler stands on one empty plot and waters the ring of 8 around it
 * on the grid (diagonals included, fewer at the edge): a covered plot grows as it is sown, and its ripening time is cut
 * by 15% — with Compost's 20% capped at 35% together — locked when it starts growing. Built in one step with `place`
 * (q(22): no stock of built-but-unplaced facilities), moved for free with `move_facility`, never removed.
 * A greenhouse (q(118) ②, Farming Lv8) is a glass roof over a 4×4 block of plots, its anchor the block's first plot
 * (lowest col and row): the 16 are greenhouse plots — watered as they are sown, ripening −25% (with Compost at most
 * −45%), a regional crop at its home time; no tree, no sprinkler inside; moved only while nothing grows under it.
 */
import { createHash } from 'node:crypto';
import type { Crop, P0Content, WorkbenchRecipe } from './content.js';
import type { Refusal } from './fishing.js';
import { coinsNeeded, stepAt } from './homestead.js';
import { homeClimate } from './travel.js';
import type { P0Event } from './progress.js';
import { skillLevel } from './rules.js';
import type { Facility, P0State, Plot } from './state.js';
import { add, room } from './bag.js';
import { missing, putInStorage, takeStorageFirst } from './storage.js';

/** [col, row] of a plot on the garden grid, or null for an id the grid does not have. */
export function plotCell(c: P0Content, id: number): [number, number] | null {
  const at = c.garden.plots[id];
  return Number.isInteger(id) && at ? at : null;
}

/** The plots a facility on `plot` covers: ring8 = the neighbours on the grid that are plots, of the first `count`
 * (the homestead's plots now: an edge sprinkler at Homestead Lv2 covers none of 30–39 before they exist). */
export function coverOf(c: P0Content, kind: string, plot: number, count = c.garden.plots.length): number[] {
  const at = plotCell(c, plot), def = c.facilities.kinds[kind];
  if (!at || !def) return [];
  const out: number[] = [];
  if (def.cover === 'block') {   // the w × h plots from the anchor, of the homestead's plots
    const [w, h] = def.size ?? [4, 4];
    c.garden.plots.forEach(([x, y], id) => {
      if (id < count && x >= at[0] && x < at[0] + w && y >= at[1] && y < at[1] + h) out.push(id);
    });
    return out;
  }
  if (def.cover !== 'ring8') return [];
  c.garden.plots.forEach(([x, y], id) => {
    if (id < count && id !== plot && Math.abs(x - at[0]) <= 1 && Math.abs(y - at[1]) <= 1) out.push(id);
  });
  return out;
}

const isBlock = (c: P0Content, kind: string) => c.facilities.kinds[kind]?.cover === 'block';

const coverNow = (c: P0Content, s: P0State, f: Facility) => coverOf(c, f.kind, f.plot, s.plots.length);

/** Plot ids watered by a sprinkler now (the Coverage Overlay's). */
export function coveredPlots(c: P0Content, s: P0State): Set<number> {
  const out = new Set<number>();
  for (const f of s.facilities ?? []) if (f.kind === 'sprinkler') for (const id of coverNow(c, s, f)) out.add(id);
  return out;
}

/** Plot ids under a greenhouse's glass (q(118) ②). */
export function greenhousePlots(c: P0Content, s: P0State): Set<number> {
  const out = new Set<number>();
  for (const f of s.facilities ?? []) if (isBlock(c, f.kind)) for (const id of coverNow(c, s, f)) out.add(id);
  return out;
}

/** Plot ids that need no Water step: a sprinkler's ring or a greenhouse's block. */
export function wateredPlots(c: P0Content, s: P0State): Set<number> {
  return new Set([...coveredPlots(c, s), ...greenhousePlots(c, s)]);
}

/** The facility standing on a plot (a sprinkler); a greenhouse stands over its plots, which stay fields. */
export function facilityAt(c: P0Content, s: P0State, plot: number): Facility | undefined {
  return (s.facilities ?? []).find(f => f.plot === plot && !isBlock(c, f.kind));
}

/** A crop's hours on this farm: a regional crop away from its climate zone takes off_zone_grow_h in the open field
 * (×1.5, §5.2.3 "not native"), its home time under a greenhouse (q(118) ②). The farm is always at home. */
export function cropGrowH(c: P0Content, s: P0State, crop: Crop, plot?: Plot): number {
  if (plot && greenhousePlots(c, s).has(plot.id)) return crop.grow_h;
  return crop.regional && crop.zone !== homeClimate(c, s) && crop.off_zone_grow_h ? crop.off_zone_grow_h : crop.grow_h;
}

/** Seed Saver (Farming Lv10, §4.6.1): a harvest of a general annual — not a regional crop, not a perennial — gives back
 * 1 seed of its kind with farming.seed_saver_chance (5%). The roll is sha256(player:plot:ready_at), never the save's rng,
 * so it shifts no fishing or cooking roll; the seed goes to the bag, or to Farm Storage when the bag has no room. */
export function seedSaver(c: P0Content, s: P0State, crop: Crop, plot: Plot, events: P0Event[]): void {
  const at = c.farming?.conveniences?.seed_saver, chance = c.farming?.seed_saver_chance ?? 0;
  if (at === undefined || skillLevel(c, s, 'farming') < at || crop.regional || (crop as { perennial?: unknown }).perennial) return;
  const roll = createHash('sha256').update(`${s.player}:seed_saver:${plot.id}:${plot.ready_at}`).digest().readUInt32BE(0) / 0x1_0000_0000;
  if (roll >= chance) return;
  if (room(c, s, crop.seed) >= 1) add(c, s, crop.seed, 1);
  else putInStorage(s, crop.seed, 1);
  events.push({ kind: 'item', id: crop.seed, delta: 1 });
  events.push({ kind: 'seed_saved', id: crop.seed, plot: plot.id });
}

/** Ripening time in ms for a crop that starts growing now on `plot` (§5.7 / §5.5: a greenhouse −25% or a sprinkler −15%,
 * Compost −20%, together at most grow_cut_cap −45%). */
export function growMs(c: P0Content, s: P0State, plot: Plot, grow_h: number): number {
  let cut = 0;
  const gh = c.facilities.kinds.greenhouse;
  if (gh && greenhousePlots(c, s).has(plot.id)) cut += gh.grow_cut;
  else if (coveredPlots(c, s).has(plot.id)) cut += c.facilities.kinds.sprinkler.grow_cut;
  if (plot.fert) cut += 1 - (c.goods.fert_compost.grow_mult ?? 1);
  return Math.round(grow_h * 3_600_000 * (1 - Math.min(cut, c.facilities.grow_cut_cap)));
}

/** Plots the current Homestead level has (homestead.plots: Lv1 30, Lv3 40, q(59) §1.1), at most the garden grid's. */
export function plotCount(c: P0Content, s: P0State): number {
  const p0 = c.start.tilled_plots + c.start.wild_plots;
  return Math.min(stepAt(c.homestead.plots, s.homestead.level, p0), c.garden?.plots.length ?? p0);
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

/** How many of a facility may stand: by Homestead level, homestead.<kind>_max (sprinkler_max: Lv1 4 … Lv7 on 10), or
 * by Farming level, the kind's cap_by_farming (greenhouse: Lv8 1, Lv10 2). */
export function facilityCap(c: P0Content, s: P0State, kind: string, level?: number): number {
  const def = c.facilities.kinds[kind];
  if (!def) return 0;
  if (def.cap_by_farming) return stepAt(def.cap_by_farming, level ?? skillLevel(c, s, 'farming'), 0);
  const m = (c.homestead as Record<string, unknown>)[`${kind}_max`] as { base: number; per_level: number; max: number } | undefined;
  return m ? Math.min(m.max, m.base + m.per_level * (level ?? s.homestead.level)) : 0;
}

/** What lets one more stand next: {homestead_next} or {farming_next} (a level), null when the cap no longer grows. */
function capNext(c: P0Content, s: P0State, kind: string): { homestead_next: number | null } | { farming_next: number | null } {
  const def = c.facilities.kinds[kind];
  if (def?.cap_by_farming) {
    const now = skillLevel(c, s, 'farming'), cap = facilityCap(c, s, kind);
    const next = def.cap_by_farming.map(([lv]) => lv).find(lv => lv > now && facilityCap(c, s, kind, lv) > cap);
    return { farming_next: next ?? null };
  }
  const next = s.homestead.level + 1;
  return { homestead_next: next <= c.homestead.max_level && facilityCap(c, s, kind, next) > facilityCap(c, s, kind) ? next : null };
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
  if (used >= cap) return { code: 'facility_cap', detail: { cap, used, ...capNext(c, s, kind) } };
  const gap = missing(s, r.cost);
  if (gap) return { code: 'missing_materials', detail: gap };
  if (r.coins && s.coins < coinsNeeded(c, r.coins)) return { code: 'no_coins', detail: { need: coinsNeeded(c, r.coins) - s.coins } };
  return null;
}

/** Why a facility can't stand on `plot`: no such plot, or a crop / another facility there; a sprinkler never under a
 * greenhouse. A greenhouse needs its whole 4×4 block clear (`needs_clear_block`, the plots in the way). */
export function spotBlock(c: P0Content, s: P0State, plot: unknown, moving?: Facility, kind = moving?.kind ?? 'sprinkler'): Refusal | null {
  const id = Number(plot);
  const p = Number.isInteger(id) ? s.plots.find(x => x.id === id) : undefined;
  if (!p || !plotCell(c, id)) return { code: 'bad_plot' };
  if (isBlock(c, kind)) {
    const [w, h] = c.facilities.kinds[kind].size ?? [4, 4];
    const ids = coverOf(c, kind, id, s.plots.length);
    const others = new Set<number>();
    for (const f of s.facilities ?? []) if (f !== moving && isBlock(c, f.kind)) for (const g of coverNow(c, s, f)) others.add(g);
    const blocked = ids.filter(g => {
      const q = s.plots.find(x => x.id === g)!;
      return facilityAt(c, s, g) || others.has(g) || q.crop || q.state === 'sown' || q.state === 'growing';
    });
    if (ids.length < w * h || blocked.length) return { code: 'needs_clear_block', detail: { plots: blocked, size: [w, h] } };
    return null;
  }
  const other = facilityAt(c, s, id);
  if ((other && other !== moving) || p.crop || p.state === 'sown' || p.state === 'growing')
    return { code: 'plot_occupied', detail: { plot: id, facility: other?.kind ?? null, crop: p.crop ?? null } };
  if (greenhousePlots(c, s).has(id)) return { code: 'plot_occupied', detail: { plot: id, facility: 'greenhouse', crop: null } };
  return null;
}

/** A greenhouse goes down: the wild plots under it are tilled (q(118) ②: covered wild ground counts as tilled). */
function tillUnder(c: P0Content, s: P0State, f: Facility): void {
  if (!isBlock(c, f.kind)) return;
  for (const id of coverNow(c, s, f)) { const q = s.plots.find(x => x.id === id); if (q?.state === 'wild') q.state = 'tilled'; }
}

const underOf = (s: P0State, plot: number): 'wild' | 'tilled' => s.plots.find(p => p.id === plot)?.state === 'wild' ? 'wild' : 'tilled';

/** Sown, not yet watered plots a facility now covers start growing (§5.7: watered as the sprinkler goes down). */
function waterCovered(c: P0Content, s: P0State, now: number, grow: (id: string, plot: Plot) => number): number[] {
  const started: number[] = [];
  const cover = wateredPlots(c, s);
  for (const p of s.plots) {
    if (p.state !== 'sown' || !p.crop || !cover.has(p.id)) continue;
    p.state = 'growing';
    p.ready_at = now + growMs(c, s, p, grow(p.crop, p));
    started.push(p.id);
  }
  return started;
}

export function place(c: P0Content, s: P0State, cmd: { recipe?: unknown; plot?: unknown; space?: string }, now: number,
    events: P0Event[], grow: (id: string, plot: Plot) => number): Refusal | null {
  if (cmd.space !== undefined && cmd.space !== 'home') return { code: 'not_home' };
  const r = c.workbench.recipes.find(x => x.id === String(cmd.recipe ?? '') && x.to === 'field');
  if (!r || !r.facility || !c.facilities.kinds[r.facility]) return { code: 'bad_recipe' };
  const block = placeBlock(c, s, r) ?? spotBlock(c, s, cmd.plot, undefined, r.facility);
  if (block) return block;
  for (const [item, qty] of r.cost) { takeStorageFirst(s, item, qty); events.push({ kind: 'item', id: item, delta: -qty }); }
  if (r.coins) { s.coins -= r.coins; events.push({ kind: 'coins', delta: -r.coins }); }
  s.facilities ??= [];
  s.facility_count = (s.facility_count ?? 0) + 1;
  const plot = Number(cmd.plot);
  const f: Facility = { id: s.facility_count, kind: r.facility, plot, ...(isBlock(c, r.facility) ? {} : { under: underOf(s, plot) }) };
  s.facilities.push(f);
  tillUnder(c, s, f);
  const started = waterCovered(c, s, now, grow);
  events.push({ kind: 'facility', action: 'placed', facility: f.id, facility_kind: f.kind, plot,
    covered: coverNow(c, s, f).length, started });
  return null;
}

/** Move a facility to another empty plot for free; the old plot is tilled ground again. Crops already growing keep
 * their time (it was locked when they started); sown plots the new spot covers start growing. */
export function moveFacility(c: P0Content, s: P0State, cmd: { facility?: unknown; plot?: unknown; space?: string }, now: number,
    events: P0Event[], grow: (id: string, plot: Plot) => number): Refusal | null {
  if (cmd.space !== undefined && cmd.space !== 'home') return { code: 'not_home' };
  const f = (s.facilities ?? []).find(x => x.id === Number(cmd.facility));
  if (!f) return { code: 'bad_facility' };
  if (f.plot === Number(cmd.plot)) return { code: 'same_plot' };
  if (isBlock(c, f.kind)) {   // a greenhouse moves only while nothing grows under it (`Move · Harvest first`)
    const growing = coverNow(c, s, f).filter(id => { const q = s.plots.find(x => x.id === id)!; return q.crop || q.state === 'sown' || q.state === 'growing'; });
    if (growing.length) return { code: 'greenhouse_not_empty', detail: { plots: growing } };
  }
  const block = spotBlock(c, s, cmd.plot, f);
  if (block) return block;
  const from = f.plot;
  const old = s.plots.find(p => p.id === from);
  if (old && !isBlock(c, f.kind)) old.state = f.under ?? 'tilled';   // wild ground stays wild (亚瑟 on #207): moving never tills for free
  f.plot = Number(cmd.plot);
  if (isBlock(c, f.kind)) tillUnder(c, s, f);
  else f.under = underOf(s, f.plot);
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
    ...capNext(c, s, kind), ...(r.coins ? { coins: r.coins, coins_need: coinsNeeded(c, r.coins), coins_have: s.coins } : {}) };
}
