/**
 * The Cookbook (plan §7.5, SGODOT-232 S5): page states, clues from failed pots, Kitchen Mishaps, the "You might have
 * what it takes" hint, and the P0 Cooking conveniences (Lv1–6, q(38); Lv7–10 come with P1).
 */
import { cropById, fishById, ingredient, type Convenience, type P0Content, type Recipe } from './content.js';
import { cookSlots, cookable, ingredientsFor, recipeRarity, tokenInfo, tokenMatches } from './cooking.js';
import { chefSignGold } from './homestead.js';
import { ingredientStock } from './kitchen_storage.js';
import { blessed, skillLevel, xpPercent } from './rules.js';
import type { P0Event } from './progress.js';
import { isDecor } from './decor.js';
import { putInStorage } from './storage.js';
import type { P0State } from './state.js';

export type PageState = 'hidden' | 'clued' | 'tasted' | 'discovered' | 'mastered';

export function hasConvenience(c: P0Content, s: P0State, id: Convenience): boolean {
  const at = c.cooking.conveniences[id];
  return at !== undefined && skillLevel(c, s, 'cooking') >= at;
}

/** Pages cooked at least once (Discovered or Mastered); the Mystery Dish is not a page. */
export function discoveredCount(c: P0Content, s: P0State): number {
  return s.firsts.filter(f => f.startsWith('cook:') && f !== `cook:${c.cooking.mystery.id}`).length;
}

export function masteredCount(c: P0Content, s: P0State): number {
  return c.cooking.recipes.filter(r => pageState(c, s, r.id) === 'mastered').length;
}

/** Cookbook milestones reached and not yet paid (§7.6.1): each once, its coins now; titles and the cabinet stay. */
export function noteMilestones(c: P0Content, s: P0State, events: P0Event[]): void {
  const discovered = discoveredCount(c, s), mastered = masteredCount(c, s);
  for (const m of c.cooking.milestones ?? []) {
    const key = `milestone:${m.id}`;
    if (s.firsts.includes(key)) continue;
    if (!((m.discovered !== undefined && discovered >= m.discovered) || (m.mastered !== undefined && mastered >= m.mastered))) continue;
    s.firsts.push(key);
    if (m.coins) { s.coins += m.coins; events.push({ kind: 'coins', delta: m.coins }); }
    if (m.decor && isDecor(c, m.decor)) putInStorage(s, m.decor, 1);   // the yard piece it gives goes to Farm Storage (q(29), Decorate)
    events.push({ kind: 'milestone', id: m.id, title: m.title, coins: m.coins ?? 0, cabinet: m.cabinet ?? 0, decor: m.decor ?? null });
  }
}

/** Warming Cabinet portions the milestones add (Head Chef +4). */
export function milestoneCabinet(c: P0Content, s: P0State): number {
  return (c.cooking.milestones ?? []).filter(m => s.firsts.includes(`milestone:${m.id}`)).reduce((n, m) => n + (m.cabinet ?? 0), 0);
}

/** Pots a page needs to be Mastered: 10, or 7 with Fast Mastery (Cooking Lv7, §4.6.3). */
export function masteredAt(c: P0Content, s: P0State): number {
  return hasConvenience(c, s, 'fast_mastery') ? (c.cooking.mastered.fast ?? c.cooking.mastered.cooked) : c.cooking.mastered.cooked;
}

export function conveniences(c: P0Content, s: P0State): Convenience[] {
  return (Object.keys(c.cooking.conveniences) as Convenience[]).filter(id => hasConvenience(c, s, id));
}

/** §7.5.1: Discovered once cooked (Mastered at 10 pots); Tasted when known but never cooked; Clued with a clue. */
export function pageState(c: P0Content, s: P0State, id: string): PageState {
  if (s.firsts.includes(`cook:${id}`)) return (s.book.cooked[id] ?? 0) >= masteredAt(c, s) ? 'mastered' : 'discovered';
  if (s.cookbook.includes(id)) return 'tasted';
  return (s.book.clues[id] ?? []).length > 0 ? 'clued' : 'hidden';
}

/** The same ingredients in any order are one Kitchen Mishaps entry. */
export const comboKey = (items: string[]) => [...items].sort().join('+');

export function triedBefore(s: P0State, items: string[]): boolean {
  const key = comboKey(items);
  return s.book.mishaps.some(m => comboKey(m.items) === key);
}

/** Record a failed pot (§7.5.2); true when the combination is new (a new one earns a clue). */
export function noteMishap(s: P0State, items: string[], now: number): boolean {
  const m = s.book.mishaps.find(x => comboKey(x.items) === comboKey(items));
  if (m) { m.n += 1; return false; }
  s.book.mishaps.push({ items: [...items].sort(), n: 1, at: now });
  return true;
}

/** Can the player get an ingredient for this token now (seed gate, fish level and pond; materials always)? */
function obtainable(c: P0Content, s: P0State, token: string): boolean {
  const ok = (id: string): boolean => {
    const crop = cropById(c, id);
    if (crop) return skillLevel(c, s, 'farming') >= crop.gate;
    const fish = fishById(c, id);
    if (fish) return fish.cook !== false && skillLevel(c, s, 'fishing') >= fish.level && fish.where.some(w => w !== 'coast');
    return !!c.materials[id]?.ingr;
  };
  const ids = [...c.crops.map(x => x.id), ...c.fish.map(f => f.id), ...Object.keys(c.materials)];
  return ids.some(id => tokenMatches(c, token, id) && ok(id));
}

/**
 * A new failed combination turns over slots on one Hidden page (§7.5.2): 1 slot, 2 from Cooking Lv3 (Double Clue).
 * The page uses one of these ingredients and can be made with what the player can get, else it is the
 * lowest-rarity Hidden page; slots that match these ingredients turn first. Only P0 pages hold clues (the 34
 * silhouettes have no P0 ingredients). Null once every page is known.
 */
export function giveClue(c: P0Content, s: P0State, items: string[]): { page: string; slots: number[] } | null {
  const shown = (r: Recipe) => s.book.clues[r.id] ?? [];
  const open = (r: Recipe) => r.in.map((_, i) => i).filter(i => !shown(r).includes(i));
  const hidden = c.cooking.recipes.filter(r => ['hidden', 'clued'].includes(pageState(c, s, r.id)) && open(r).length > 0);
  const uses = (r: Recipe) => r.in.some(t => items.some(id => tokenMatches(c, t, id)));
  const usable = hidden.filter(r => uses(r) && r.in.every(t => obtainable(c, s, t)));
  const page = (usable.length ? usable : hidden).sort((a, b) => recipeRarity(c, a) - recipeRarity(c, b) || (a.n ?? 0) - (b.n ?? 0))[0];
  if (!page) return null;
  const matches = (i: number) => items.some(id => tokenMatches(c, page.in[i], id));
  const slots = open(page).sort((a, b) => Number(matches(b)) - Number(matches(a)) || a - b)
    .slice(0, hasConvenience(c, s, 'clue_double') ? 2 : 1);
  s.book.clues[page.id] = [...shown(page), ...slots].sort((a, b) => a - b);
  return { page: page.id, slots };
}

/** "You might have what it takes" (§7.5.1): every slot's family can be filled from what the stove reaches. */
export function mightHave(c: P0Content, r: Recipe, stock: Map<string, number>): boolean {
  const left = new Map<string, number>();
  for (const [id, n] of stock) {
    const ing = ingredient(c, id);
    if (ing && n > 0) left.set(ing.family, (left.get(ing.family) ?? 0) + n);
  }
  for (const t of r.in) {
    const family = tokenInfo(c, t)?.family;
    if (!family || (left.get(family) ?? 0) < 1) return false;
    left.set(family, left.get(family)! - 1);
  }
  return true;
}

/** Gold arc share of a new pot: the tier's, + Steady Hand I (Cooking Lv5), + a Mastered page, at most gold_cap. */
export function goldWidth(c: P0Content, s: P0State, page: string | null, base: number): number {
  let width = base;
  if (hasConvenience(c, s, 'steady_hand_1')) width += c.cooking.steady_hand_gold;
  if (hasConvenience(c, s, 'steady_hand_2')) width += c.cooking.steady_hand_gold;   // Lv7: another +5, same cap
  if (page && pageState(c, s, page) === 'mastered') width += c.cooking.mastered.gold;
  // Chef's Sign (Homestead Lv10, §7.7): +5 points on every dish, on top of the cap the skills reach.
  return Math.min(c.cooking.gold_cap + chefSignGold(c, s), Math.round((width + chefSignGold(c, s)) * 1000) / 1000);
}

/** Cooking time and heat times: × quick_fire from Cooking Lv6 (Quick Fire); the needle speed stays the same. */
export function fireSpeed(c: P0Content, s: P0State): number {
  return hasConvenience(c, s, 'quick_fire') ? c.cooking.quick_fire : 1;
}

/** Failed pots today that still refund their ingredients (Newcomer Blessing only, §7.5.2); null outside it. */
export function trialRefundsLeft(c: P0Content, s: P0State, now: number): number | null {
  return blessed(c, s, now) ? Math.max(0, c.cooking.trial_refunds - s.day.mishaps) : null;
}

/** The Cookbook as facts for the panel (SGODOT-226 reads it): all 48 pages in order, then mishaps and conveniences. */
export function cookbookView(c: P0Content, s: P0State, now: number) {
  const slots = cookSlots(c, s), stock = ingredientStock(c, s), level = skillLevel(c, s, 'cooking');
  const xpToLv4 = Math.max(0, c.skills.cooking[3] - s.skills.cooking);
  const lock = (n: number) => (n > slots ? { level: 4, xp_to_go: xpToLv4 } : null);
  const pages = [
    ...c.cooking.recipes.map(r => {
      const state = pageState(c, s, r.id), rarity = recipeRarity(c, r), known = s.cookbook.includes(r.id);
      // p0 = cookable in this build (every ingredient exists, not buy-only); the rest show as silhouettes with their
      // slot families (SGODOT-282: all 48 pages are recipes, P1 crops and fish arrive with their lines).
      const cooks = cookable(c, r);
      const clues = s.book.clues[r.id] ?? [];
      const open = state === 'tasted' || state === 'discovered' || state === 'mastered';
      return {
        n: r.n ?? 0, id: r.id, name: known ? r.name : null, rarity, slots: r.in.length,
        families: r.in.map((t, i) => tokenInfo(c, t)?.family ?? r.families?.[i] ?? '?'), style: r.style ?? '', learn: r.learn ?? [],
        state, known, in: r.in.map((t, i) => (open || clues.includes(i) ? t : '?')),
        cooked: s.firsts.includes(`cook:${r.id}`), cooked_total: s.book.cooked[r.id] ?? 0, best: s.book.best[r.id] ?? null,
        first_at: s.book.first_at[r.id] ?? null, mastered: state === 'mastered',
        can_cook: cooks && known && r.in.length <= slots && ingredientsFor(c, s, r) !== null,
        maybe: cooks && (state === 'hidden' || state === 'clued') && r.in.length <= slots && mightHave(c, r, stock),
        lock: lock(r.in.length), today: s.day.cooked[r.id] ?? 0,
        xp_pct: xpPercent(c, level, c.cooking.tiers[String(rarity)].level), p0: cooks,
        buff: rarity === 4 ? (r.buff ?? null) : null,   // Legendary: the Buff slot, empty until P3 ("Buff · coming later")
        buy: r.buy ?? null, regional: r.regional ?? false,
      };
    }),
    ...c.cooking.pages.map(p => ({
      n: p.n, id: p.id, name: null, rarity: p.rarity, slots: p.slots.length, families: p.slots, style: p.style, learn: p.learn,
      state: 'hidden' as PageState, known: false, in: p.slots.map(() => '?'), cooked: false, cooked_total: 0, best: null,
      first_at: null, mastered: false, can_cook: false, maybe: false, lock: lock(p.slots.length), today: 0, xp_pct: 100, p0: false,
      buff: null, buy: null, regional: false,
    })),
  ].sort((a, b) => a.n - b.n);
  return {
    pages,
    total: pages.length,
    discovered: pages.filter(p => p.cooked).length,
    mishaps: [...s.book.mishaps].sort((a, b) => b.at - a.at),
    conveniences: conveniences(c, s),
    third_slot: slots < 3 ? { level: 4, xp_to_go: xpToLv4 } : null,
    trial_refunds: trialRefundsLeft(c, s, now),
  };
}
