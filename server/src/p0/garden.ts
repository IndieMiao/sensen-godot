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
import { coinsNeeded, levelCap, stepAt, type LevelCap } from './homestead.js';
import { homeClimate } from './travel.js';
import type { P0Event } from './progress.js';
import { skillLevel, untilRollover } from './rules.js';
import type { Facility, P0State, Plot } from './state.js';
import { add, count, room, take } from './bag.js';
import { cellsOf, decorOf, yardBlock, yardWalk, type YardFeatures } from './decor.js';
import { cropById, quickCrop, fastCrop } from './content.js';
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
const isYard = (c: P0Content, kind: string) => c.facilities.kinds[kind]?.cover === 'yard';
/** A yard facility's cell from a command's x, y (the yard grid: P0Garden's cells, decor.yard). */
function yardCell(cmd: { x?: unknown; y?: unknown }): [number, number] | null {
  const x = Number(cmd.x), y = Number(cmd.y);
  return Number.isInteger(x) && Number.isInteger(y) ? [x, y] : null;
}

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
  if (at === undefined || skillLevel(c, s, 'farming') < at || crop.regional || crop.perennial || crop.quick) return;   // q(217): not a teaching seed
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
  // the priest's farm buff when it was sown (buffs.ts): after the cap, a layer of its own
  return Math.round(grow_h * 3_600_000 * (1 - Math.min(cut, c.facilities.grow_cut_cap)) * (plot.boost ?? 1));
}

/** Ripening time in ms for `crop` starting to grow now on `plot`: a teaching seed's fixed time (q(217): no sprinkler,
 * greenhouse or Compost cut), else growMs at this farm's hours. */
export function ripenMs(c: P0Content, s: P0State, plot: Plot, crop: Crop): number {
  return crop.quick ? crop.quick.ms : growMs(c, s, plot, cropGrowH(c, s, crop, plot));
}

/** SGODOT-355 b1 (v4 2.5): the Plots an annual may stand on at this Homestead level (homestead.plots: Lv1 8, +2 a level
 * to Lv15's 36, Lv16 39, Lv17 41). Trees and sprinklers never count against it (`Plots 41/41`, 不知火舞 on the grid). */
export function fieldCap(c: P0Content, s: P0State): number {
  return stepAt(c.homestead.plots, s.homestead.level, c.start.tilled_plots + c.start.wild_plots);
}

/** Annuals on the field now (sown, growing or ripe; a tree is not one). */
export function fieldsUsed(c: P0Content, s: P0State): number {
  return s.plots.filter(p => p.crop && p.state !== 'tilled' && p.state !== 'wild' && !cropById(c, p.crop)?.perennial).length;
}

/** Beds open on the garden grid (content.garden.plots, in the order they open): the Plots, plus one for each tree and
 * each sprinkler standing — placing one on an empty bed opens the next, so the Plots stay what the level gives (不知火舞
 * on the grid, 11-02). A bed once open stays open; at most the grid's 63. */
export function plotCount(c: P0Content, s: P0State): number {
  const trees = s.plots.filter(p => p.crop && cropById(c, p.crop)?.perennial).length;
  const stands = (s.facilities ?? []).filter(f => f.plot >= 0 && c.facilities.kinds[f.kind]?.cover !== 'block').length;
  const grid = c.garden?.plots.length ?? fieldCap(c, s);
  return Math.min(Math.max(fieldCap(c, s) + trees + stands, s.plots.length), grid);
}

/** A plot's cell on the yard grid Decorate uses: content garden.origin + pitch × its [col, row] (P0Garden.PLOT_ORIGIN, beds
 * two cells apart; Homestead Lv7's front beds are row −1, q(172)). */
export function plotYardCell(c: P0Content, id: number): [number, number] | null {
  const at = plotCell(c, id);
  if (!at) return null;
  const [ox, oy] = c.garden.origin ?? [4, 3], k = c.garden.pitch ?? 2;
  return [ox + k * at[0], oy + k * at[1]];
}

/** The yard cells of the beds the homestead has now, `x,y`: Decorate keeps off them (q(172): Homestead Lv7's beds 40–47
 * stand outside the field's rect). */
export function bedCells(c: P0Content, s: P0State): Set<string> {
  const out = new Set<string>();
  for (let id = 0; id < plotCount(c, s); id++) { const at = plotYardCell(c, id); if (at) out.add(`${at[0]},${at[1]}`); }
  return out;
}

/** What stood where beds were just added (Homestead Lv7's 40–47, q(172)) makes way: a piece goes back to Farm Storage,
 * said as a piece stored (`Wooden Bench · back in Farm Storage`, q(120)); a yard facility (the Compost Bin), which has
 * no storage, moves beside the workbench (`Compost Bin · moved beside the Workbench`, q(172) ③ 甲). */
export function clearNewBeds(c: P0Content, s: P0State, added: number[], events: P0Event[], yard: YardFeatures = {}): void {
  const cells = new Set(added.map(id => plotYardCell(c, id)).filter(at => at).map(at => `${at![0]},${at![1]}`));
  if (cells.size === 0) return;
  if (s.decor) s.decor.placed = s.decor.placed.filter(p => {
    if (!cellsOf(c, p.id, p.x, p.y, p.rot).some(([x, y]) => cells.has(`${x},${y}`))) return true;
    putInStorage(s, p.id, 1);
    events.push({ kind: 'decor', action: 'stored', uid: p.uid, item: p.id, x: p.x, y: p.y, rot: p.rot, reason: 'plots' });
    return false;
  });
  for (const f of s.facilities ?? []) {
    if (!f.cell || !cells.has(`${f.cell[0]},${f.cell[1]}`)) continue;
    const def = c.facilities.kinds[f.kind];
    const to = nearestYardCell(c, s, def?.start ?? [17, 16], def?.start_span ?? 0, f.id, yard);
    if (!to) continue;   // no free yard cell at all: it stays (never on a real farm)
    f.cell = to;
    events.push({ kind: 'facility', action: 'moved', facility: f.id, facility_kind: f.kind, plot: -1, covered: 0, started: [],
      x: to[0], y: to[1], reason: 'plots' });
  }
}

/** The legal yard cell nearest `from` for a yard facility, as the client's first preview picks it (P0FarmFacilities.
 * nearest_yard_cell): `span` cells either side count as `from` (the workbench's three), beside it first, then in front,
 * behind last. null when none is legal. */
export function nearestYardCell(c: P0Content, s: P0State, from: [number, number], span: number, facility?: number,
    yard: YardFeatures = {}): [number, number] | null {
  if (!decorOf(c)) return null;
  const walk = yardWalk(c, s, yard);
  let best: [number, number] | null = null, bestD = Infinity;
  for (let y = walk[1]; y < walk[1] + walk[3]; y++) for (let x = walk[0]; x < walk[0] + walk[2]; x++) {
    const dx = Math.max(0, Math.abs(x - from[0]) - span), dy = y - from[1];
    const d = dx * dx + dy * dy + (dy !== 0 ? 0.25 : 0) + (dy > 0 ? 0.5 : 0);
    if (d >= bestD || yardBlock(c, s, [[x, y]], { x, y }, { facility }, yard)) continue;
    bestD = d;
    best = [x, y];
  }
  return best;
}

/** Open the beds plotCount says and the save does not have yet, tilled (v4: a new bed comes ready to sow); the ids added
 * (an upgrade, a tree or a sprinkler on an empty bed). Existing plots never move. */
export function addPlots(c: P0Content, s: P0State): number[] {
  const added: number[] = [];
  for (let id = 0; id < plotCount(c, s); id++) {
    if (!s.plots.some(p => p.id === id)) { s.plots.push({ id, state: 'tilled' }); added.push(id); }
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
  return levelCap((c.homestead as Record<string, unknown>)[`${kind}_max`] as LevelCap | undefined, level ?? s.homestead.level);
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
    const quick = (quickCrop(c, p.crop) ?? fastCrop(c, p.crop))?.quick;   // q(217)/q(245): fixed time, no cut
    p.ready_at = now + (quick ? quick.ms : growMs(c, s, p, grow(p.crop, p)));
    started.push(p.id);
  }
  return started;
}

/** Build a facility in place (q(22)): on a plot, over a block of plots (greenhouse), or on a yard cell (x, y: the
 * Compost Bin, q(118) ③ — the decor yard's rules, never on the field). */
export function place(c: P0Content, s: P0State, cmd: { recipe?: unknown; plot?: unknown; x?: unknown; y?: unknown; space?: string }, now: number,
    events: P0Event[], grow: (id: string, plot: Plot) => number, yard: YardFeatures = {}): Refusal | null {
  if (cmd.space !== undefined && cmd.space !== 'home') return { code: 'not_home' };
  const r = c.workbench.recipes.find(x => x.id === String(cmd.recipe ?? '') && x.to === 'field');
  if (!r || !r.facility || !c.facilities.kinds[r.facility]) return { code: 'bad_recipe' };
  const cell = isYard(c, r.facility) ? yardCell(cmd) : null;
  if (isYard(c, r.facility) && !cell) return { code: 'bad_spot' };
  const block = placeBlock(c, s, r)
    ?? (cell ? yardBlock(c, s, [cell], { x: cell[0], y: cell[1] }, {}, yard) : spotBlock(c, s, cmd.plot, undefined, r.facility));
  if (block) return block;
  for (const [item, qty] of r.cost) { takeStorageFirst(s, item, qty); events.push({ kind: 'item', id: item, delta: -qty }); }
  if (r.coins) { s.coins -= r.coins; events.push({ kind: 'coins', delta: -r.coins }); }
  s.facilities ??= [];
  s.facility_count = (s.facility_count ?? 0) + 1;
  const plot = cell ? -1 : Number(cmd.plot);
  const f: Facility = { id: s.facility_count, kind: r.facility, plot,
    ...(cell ? { cell } : isBlock(c, r.facility) ? {} : { under: underOf(s, plot) }) };
  s.facilities.push(f);
  tillUnder(c, s, f);
  const started = waterCovered(c, s, now, grow);
  events.push({ kind: 'facility', action: 'placed', facility: f.id, facility_kind: f.kind, plot,
    covered: coverNow(c, s, f).length, started, ...(cell ? { x: cell[0], y: cell[1] } : {}) });
  return null;
}

/** Move a facility to another empty plot for free; the old plot is tilled ground again. Crops already growing keep
 * their time (it was locked when they started); sown plots the new spot covers start growing. */
export function moveFacility(c: P0Content, s: P0State, cmd: { facility?: unknown; plot?: unknown; x?: unknown; y?: unknown; space?: string }, now: number,
    events: P0Event[], grow: (id: string, plot: Plot) => number, yard: YardFeatures = {}): Refusal | null {
  if (cmd.space !== undefined && cmd.space !== 'home') return { code: 'not_home' };
  const f = (s.facilities ?? []).find(x => x.id === Number(cmd.facility));
  if (!f) return { code: 'bad_facility' };
  if (f.cell) {   // a yard facility moves to another yard cell (the Compost Bin)
    const cell = yardCell(cmd);
    if (!cell) return { code: 'bad_spot' };
    if (cell[0] === f.cell[0] && cell[1] === f.cell[1]) return { code: 'same_plot' };
    const block = yardBlock(c, s, [cell], { x: cell[0], y: cell[1] }, { facility: f.id }, yard);
    if (block) return block;
    f.cell = cell;
    events.push({ kind: 'facility', action: 'moved', facility: f.id, facility_kind: f.kind, plot: -1, x: cell[0], y: cell[1], covered: 0, started: [] });
    return null;
  }
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
  return (s.facilities ?? []).map(f => ({ id: f.id, kind: f.kind, plot: f.plot, covers: coverNow(c, s, f), ...(f.cell ? { cell: f.cell } : {}) }));
}

/** The Compost Bin (q(118) ③, §5.7): any crop in the bag — regional ones and fruit too — becomes Compost 1:1 at once,
 * up to the bin's daily (5) a player day; at home, with a bin standing. The crops leave before the Compost goes in, so
 * a stack turned whole makes its own room. */
export function compost(c: P0Content, s: P0State, cmd: { item?: unknown; qty?: unknown; space?: string }, now: number,
    events: P0Event[]): Refusal | null {
  if (cmd.space !== undefined && cmd.space !== 'home') return { code: 'not_home' };
  const bin = (s.facilities ?? []).find(f => c.facilities.kinds[f.kind]?.daily);
  if (!bin) return { code: 'no_compost_bin' };
  const cap = c.facilities.kinds[bin.kind].daily!;
  const item = String(cmd.item ?? ''), qty = Number(cmd.qty ?? 1);
  if (!cropById(c, item)) return { code: 'not_a_crop', detail: { item } };
  if (!Number.isInteger(qty) || qty < 1) return { code: 'bad_qty' };
  const used = s.day.compost ?? 0;
  if (used + qty > cap) return { code: 'limit_reached', detail: { used, cap, resets_in: untilRollover(c, s, now) } };
  const have = count(s.bag, item, 'skip');
  if (have < qty) return { code: 'not_enough', detail: { item, have, need: qty } };
  const out = 'fert_compost';
  const trial = { bag: structuredClone(s.bag), bag_cap: s.bag_cap, skills: s.skills };
  take(trial.bag, item, qty, 'skip');
  if (room(c, trial, out) < qty) return { code: 'bag_full', detail: { need: qty } };
  take(s.bag, item, qty, 'skip');
  add(c, s, out, qty);
  s.day.compost = used + qty;
  events.push({ kind: 'item', id: item, delta: -qty }, { kind: 'item', id: out, delta: qty },
    { kind: 'compost', item, qty, used: used + qty, cap });
  return null;
}

/** The view's Compost Bin quota (its drawer's `Compost today 2/5` / `resets in 9h 12m`); null without a bin. */
export function compostView(c: P0Content, s: P0State, now: number) {
  const bin = (s.facilities ?? []).find(f => c.facilities.kinds[f.kind]?.daily);
  if (!bin) return null;
  const cap = c.facilities.kinds[bin.kind].daily!, used = s.day.compost ?? 0;
  return { cap, used, left: Math.max(0, cap - used), resets_in: untilRollover(c, s, now) };
}

export function fieldRecipeView(c: P0Content, s: P0State, r: WorkbenchRecipe) {
  const kind = r.facility ?? '';
  return { facility: kind, cap: facilityCap(c, s, kind), used: (s.facilities ?? []).filter(f => f.kind === kind).length,
    ...capNext(c, s, kind), ...(r.coins ? { coins: r.coins, coins_need: coinsNeeded(c, r.coins), coins_have: s.coins } : {}) };
}
