/**
 * P1 perennials on the 40-plot farm (q(118) ①, §5.2.4, SGODOT-240): a tree takes one plot (apple, citrus and grape
 * alike), planted through the sow command from its sapling — an empty plot, tilled or wild, one at a time (the Row Hoe
 * does not plant trees), 6 Energy — and stands there, growing at once (no Water step; sprinklers, Compost and the
 * greenhouse do nothing for it). Ripe, it is picked for 2 Energy and grows again for regrow_h; Orchard Feed halves the
 * next regrowth. The first pick also counts the planting's XP (locked when paid) and the first-harvest bonus. How many
 * stand is the orchard: homestead.perennial_slots, 1 + Homestead level up to 8. Chopping happens in Decorate (FARM-4).
 */
import type { Crop, P0Content } from './content.js';
import { cropById } from './content.js';
import { add, count, room, take } from './bag.js';
import type { Refusal } from './fishing.js';
import { energyDetail, firstXp, gainXp, spendEnergy, type P0Event } from './progress.js';
import { scaledXp, skillLevel, xpPercent } from './rules.js';
import type { P0State, Plot } from './state.js';

const H = 3_600_000;

export const treeOf = (c: P0Content, plot: Plot): Crop | undefined => {
  const crop = plot.crop ? cropById(c, plot.crop) : undefined;
  return crop?.perennial ? crop : undefined;
};

/** Trees the Homestead level allows: base + per_level × level, at most max (§5.2.4 q(118): 1 + level, 8 from Lv7). */
export function orchardCap(c: P0Content, s: P0State, level = s.homestead.level): number {
  const p = c.homestead.perennial_slots;
  return p ? Math.min(p.max, p.base + p.per_level * level) : 0;
}

export const orchardUsed = (c: P0Content, s: P0State): number => s.plots.filter(p => treeOf(c, p)).length;

/** The next Homestead level that adds a tree, or null once the orchard no longer grows. */
function orchardNext(c: P0Content, s: P0State): number | null {
  const next = s.homestead.level + 1;
  return next <= c.homestead.max_level && orchardCap(c, s, next) > orchardCap(c, s) ? next : null;
}

export function orchardView(c: P0Content, s: P0State) {
  return { used: orchardUsed(c, s), cap: orchardCap(c, s), homestead_next: orchardNext(c, s) };
}

/** sow {plot, seed: a sapling}: one empty plot (tilled or wild), 6 Energy, room in the orchard. */
export function plantTree(c: P0Content, s: P0State, ids: unknown[], crop: Crop, now: number, events: P0Event[]): Refusal | null {
  if (ids.length !== 1) return { code: 'bad_plot', detail: { most: 1 } };   // one tree at a time (q(118))
  const plot = s.plots.find(p => p.id === ids[0])!;
  if (plot.state !== 'tilled' && plot.state !== 'wild') return { code: 'wrong_state', detail: { plot: plot.id, state: plot.state } };
  if (count(s.bag, crop.seed) < 1) return { code: 'no_seed', detail: { seed: crop.seed, need: 1, have: 0 } };
  const used = orchardUsed(c, s), cap = orchardCap(c, s);
  if (used >= cap) return { code: 'orchard_full', detail: { used, cap, homestead_next: orchardNext(c, s) } };
  if (s.energy.value < crop.energy) return { code: 'need_energy', detail: energyDetail(c, s, now, crop.energy) };
  spendEnergy(c, s, now, crop.energy, events, 'sow');
  take(s.bag, crop.seed, 1);
  events.push({ kind: 'item', id: crop.seed, delta: -1 });
  plot.state = 'growing';
  plot.crop = crop.id;
  plot.xp_pct = xpPercent(c, skillLevel(c, s, 'farming'), crop.level);   // §5.2.4: the planting's XP, locked as paid
  plot.ready_at = now + crop.grow_h * H;
  plot.picks = 0;
  delete plot.fert;
  events.push({ kind: 'tree', action: 'planted', plot: plot.id, crop: crop.id, used: used + 1, cap });
  return null;
}

/** harvest on a ripe tree: 2 Energy, the fruit, XP (the first pick adds the planting's), then it grows again. */
export function pickTree(c: P0Content, s: P0State, plot: Plot, crop: Crop, now: number, events: P0Event[]): Refusal | null {
  const per = crop.perennial!;
  if (room(c, s, crop.id) < crop.yield) return { code: 'bag_full', detail: { need: crop.yield } };
  if (s.energy.value < per.harvest_energy) return { code: 'need_energy', detail: energyDetail(c, s, now, per.harvest_energy) };
  spendEnergy(c, s, now, per.harvest_energy, events, 'pick');
  add(c, s, crop.id, crop.yield);
  events.push({ kind: 'item', id: crop.id, delta: crop.yield });
  if (!plot.picks) gainXp(c, s, now, 'farming', scaledXp(s, crop.xp, plot.xp_pct ?? 100), plot.xp_pct ?? 100, events);
  const pct = xpPercent(c, skillLevel(c, s, 'farming'), crop.level);   // each pick's 2 XP: the level now
  gainXp(c, s, now, 'farming', scaledXp(s, per.harvest_xp, pct), pct, events);
  const first = `harvest:${crop.id}`;
  if (!s.firsts.includes(first)) {
    s.firsts.push(first);
    firstXp(c, s, now, 'farming', first, crop.first_xp, events);
  }
  plot.picks = (plot.picks ?? 0) + 1;
  plot.ready_at = now + per.regrow_h * H;
  delete plot.fert;
  return null;
}

/** fertilize a regrowing tree with Orchard Feed: this regrowth −50%, once, not while it ripens the first time. */
export function feedTree(c: P0Content, s: P0State, plot: Plot, crop: Crop, item: string, now: number, events: P0Event[]): Refusal | null {
  const feed = c.goods[item];
  if (!feed?.regrow_mult) return { code: 'trees_take_orchard_feed', detail: { item: 'fert_orchard' } };
  if (!plot.picks) return { code: 'first_ripening' };
  if ((plot.ready_at ?? 0) <= now) return { code: 'wrong_state', detail: { state: 'ready' } };
  if (plot.fert) return { code: 'fertilized' };
  if (count(s.bag, item) < 1) return { code: 'no_item', detail: { item } };
  take(s.bag, item, 1);
  events.push({ kind: 'item', id: item, delta: -1 });
  plot.fert = true;
  plot.ready_at = Math.max(now, plot.ready_at! - Math.round(crop.perennial!.regrow_h * H * (1 - feed.regrow_mult)));
  return null;
}

/** chop {plot}: the tree is gone and the plot is tilled ground again (FARM-4, from Decorate). */
export function chopTree(c: P0Content, s: P0State, cmd: { plot?: unknown; space?: string }, events: P0Event[]): Refusal | null {
  if (cmd.space !== undefined && cmd.space !== 'home') return { code: 'not_home' };
  const plot = s.plots.find(p => p.id === Number(cmd.plot));
  const crop = plot && treeOf(c, plot);
  if (!plot || !crop) return { code: 'not_a_tree' };
  plot.state = 'tilled';
  delete plot.crop; delete plot.xp_pct; delete plot.ready_at; delete plot.fert; delete plot.picks;
  events.push({ kind: 'tree', action: 'chopped', plot: plot.id, crop: crop.id, used: orchardUsed(c, s), cap: orchardCap(c, s) });
  return null;
}
