/** Cooking and eating (plan §7.2–7.6, §7.17): pots cost no energy; quality comes from heat taps judged on the server. */
import { dishId, dishParts, fishById, ingredient, itemKind, recipeById, type CookTier, type P0Content, type Recipe } from './content.js';
import { add, room } from './bag.js';
import { fireSpeed, giveClue, goldWidth, hasConvenience, noteMishap, triedBefore, trialRefundsLeft } from './cookbook.js';
import { isSeasoning } from './gathering.js';
import { cabinetCap, dishesFit, eatFrom, haveDish, haveIngredient, ingredientStock, rackOn, routeDish, takeIngredient } from './kitchen_storage.js';
import { grantItems } from './parcels.js';
import { firstXp, gainEnergy, gainXp, grantOnce, type P0Event } from './progress.js';
import { draw, foodCap, scaledXp, skillLevel, xpPercent } from './rules.js';
import { putInStorage } from './storage.js';
import type { Heat, P0State, Pot } from './state.js';
import type { Refusal } from './fishing.js';

const TAG = /^([WFOS])(\d)$/;

export function cookSlots(c: P0Content, s: P0State): number {
  const level = skillLevel(c, s, 'cooking');
  let slots = 1;
  for (const [at, n] of c.cooking.slots) if (level >= at) slots = n;
  return slots;
}

/** One token of a recipe: a specific id or a family × rarity tag such as W1 ("Any Common fish"). */
export function tokenInfo(c: P0Content, token: string): { family: string; rarity: number } | null {
  const tag = TAG.exec(token);
  if (tag) return { family: tag[1], rarity: Number(tag[2]) };
  return ingredient(c, token);
}

/** §7.4.1: highest ingredient rarity × number of families. */
export function deriveRarity(c: P0Content, parts: { family: string; rarity: number }[]): number {
  const top = Math.max(...parts.map(p => p.rarity));
  const families = new Set(parts.map(p => p.family)).size;
  return c.cooking.derive[top - 1][Math.min(families, 3) - 1];
}

export function recipeRarity(c: P0Content, recipe: Recipe): number {
  return deriveRarity(c, recipe.in.map(t => tokenInfo(c, t)!));
}

export function tokenMatches(c: P0Content, token: string, id: string): boolean {
  const tag = TAG.exec(token);
  if (!tag) return token === id;
  const ing = ingredient(c, id);
  return !!ing && ing.family === tag[1] && ing.rarity === Number(tag[2]);
}

function fits(c: P0Content, recipe: Recipe, items: string[]): boolean {
  if (recipe.in.length !== items.length) return false;
  const used = new Array(items.length).fill(false);
  const place = (i: number): boolean => {
    if (i === recipe.in.length) return true;
    for (let j = 0; j < items.length; j++) {
      if (used[j] || !tokenMatches(c, recipe.in[i], items[j])) continue;
      used[j] = true;
      if (place(i + 1)) return true;
      used[j] = false;
    }
    return false;
  };
  return place(0);
}

/** Specific-ingredient pages win over tag pages; among tag pages the fewest wildcards win (§7.2.3). */
export function matchRecipe(c: P0Content, items: string[]): Recipe | null {
  const wild = (r: Recipe) => r.in.filter(t => TAG.test(t)).length;
  return c.cooking.recipes.filter(r => fits(c, r, items)).sort((a, b) => wild(a) - wild(b))[0] ?? null;
}

/**
 * Concrete items for a known page: tag slots take the cheapest matching items the stove can reach, preferring a set
 * that would make this same page if laid out freely (q(67): Grilled Fish takes a carp before a crucian, which alone
 * is Grilled Crucian's). Without such a set, the cheapest set that fits still cooks this page (startPot cooks the
 * chosen page); null when nothing fits.
 */
export function ingredientsFor(c: P0Content, s: P0State, recipe: Recipe): string[] | null {
  const left = ingredientStock(c, s);
  const priceOf = (id: string) => fishById(c, id)?.price ?? c.crops.find(cr => cr.id === id)?.price ?? 0;
  // Specific tokens first so a tag never eats the item a named slot needs.
  const order = [...recipe.in].sort((a, b) => Number(TAG.test(a)) - Number(TAG.test(b)));
  const out: string[] = [];
  let fallback: string[] | null = null;
  let tries = 0;
  const pick = (i: number): string[] | null => {
    if (i === order.length) {
      if (!fallback) fallback = [...out];
      return matchRecipe(c, out)?.id === recipe.id ? [...out] : null;
    }
    const options = [...left.entries()].filter(([id, n]) => n > 0 && tokenMatches(c, order[i], id)).sort((a, b) => priceOf(a[0]) - priceOf(b[0]));
    for (const [id, n] of options) {
      if (++tries > 200) break;   // pages have at most three slots; this only bounds a pathological stock
      left.set(id, n - 1); out.push(id);
      const found = pick(i + 1);
      out.pop(); left.set(id, n);
      if (found) return found;
    }
    return null;
  };
  return pick(0) ?? fallback;
}

export function startPot(c: P0Content, s: P0State, cmd: { items?: unknown; recipe?: unknown }, now: number, events: P0Event[]): Refusal | null {
  // Queue ×2 (Cooking Lv5): with a pot on and none waiting, the new pot waits behind it; plates left on the stove block both.
  const queueing = !!s.stove && !s.stove.left && !s.queue && hasConvenience(c, s, 'queue_two');
  if (s.stove && !queueing) {
    return { code: 'stove_busy', detail: { ready_in: Math.max(0, s.stove.started_at + s.stove.ms - now), queued: !!s.queue, left: !!s.stove.left } };
  }
  let items: string[];
  // A page the player chose (Cookbook Cook, Cook Again) cooks that page; only free slots go through matchRecipe (q(67)).
  let chosen: Recipe | null = null;
  if (cmd.recipe !== undefined) {
    const recipe = recipeById(c, String(cmd.recipe));
    if (!recipe || !s.cookbook.includes(recipe.id)) return { code: 'unknown_recipe' };
    const picked = ingredientsFor(c, s, recipe);
    // Never falls back to another page: what was picked must fit the chosen one.
    if (!picked || !fits(c, recipe, picked)) return { code: 'missing_ingredients', detail: { recipe: recipe.id } };
    items = picked;
    chosen = recipe;
  } else {
    if (!Array.isArray(cmd.items)) return { code: 'bad_items' };
    items = cmd.items.map(String);
  }
  const slots = cookSlots(c, s);
  if (items.length < 1 || items.length > slots) return { code: 'bad_slots', detail: { slots } };
  const parts: { family: string; rarity: number }[] = [];
  for (const id of items) {
    const ing = ingredient(c, id);
    if (!ing) return { code: itemKind(id) === 'fish' && fishById(c, id) ? 'not_for_cooking' : 'not_cookable', detail: { item: id } };
    parts.push(ing);
  }
  for (const id of new Set(items)) {
    const need = items.filter(x => x === id).length;
    const have = haveIngredient(c, s, id);
    if (have < need) return { code: 'not_enough', detail: { item: id, need, have } };
  }
  if (parts.every(p => p.family === 'S')) return { code: 'needs_main' };
  for (const id of new Set(items)) {
    const need = items.filter(x => x === id).length;
    takeIngredient(c, s, id, need, events);
  }
  const recipe = chosen ?? matchRecipe(c, items);
  const rarity = deriveRarity(c, parts);
  const tier: CookTier = c.cooking.tiers[String(rarity)];
  const teach = s.fires === 0;
  // The first fire is the wide teaching ring; later pots get Steady Hand I / Mastered widths and Quick Fire timing.
  const width = teach ? c.cooking.first_fire.gold : goldWidth(c, s, recipe?.id ?? null, tier.gold);
  const spin = teach ? c.cooking.first_fire.spin_ms : tier.spin_ms;
  const speed = fireSpeed(c, s), ms = Math.round(tier.ms * speed);
  const heats: Heat[] = tier.heats.map(at => ({ at: Math.round(at * speed), spin, width, gold: round3(0.1 + draw(s) * (0.85 - width)) }));
  s.fires += 1;
  const pot: Pot = {
    dish: recipe?.id ?? c.cooking.mystery.id, rarity, started_at: now, ms, heats,
    xp_pct: xpPercent(c, skillLevel(c, s, 'cooking'), tier.level), mystery: !recipe, items, id: s.fires,
  };
  if (queueing) s.queue = pot; else s.stove = pot;
  // tried is on every pot: true only for a combination already in Kitchen Mishaps, which the player has seen fail.
  events.push({ kind: 'pot', id: pot.id, dish: recipe && s.cookbook.includes(recipe.id) ? recipe.id : null, rarity, ms,
    tried: triedBefore(s, items), ...(queueing ? { queued: true } : {}) });
  return null;
}

/** First tap inside each ring's lifetime is judged; gold arc ± tolerance is a hit (§7.2.4). */
export function heatHits(c: P0Content, heats: Heat[], taps: number[]): number {
  let hits = 0;
  for (const h of heats) {
    const tap = taps.find(t => t >= h.at && t <= h.at + h.spin);
    if (tap === undefined) continue;
    const from = h.at + h.gold * h.spin - c.cooking.tolerance_ms;
    const to = h.at + (h.gold + h.width) * h.spin + c.cooking.tolerance_ms;
    if (tap >= from && tap <= to) hits += 1;
  }
  return hits;
}

/** Collect a ready pot: heat is judged and XP paid now, and the portions go the Keep way (Warming Cabinet → bag).
 * With eat: true (COOK-4 Eat) the main portion is eaten from the pot instead, so a full kitchen never blocks
 * eating (§7.2.6). Portions with no place stay on the stove as `left` (Bag full · dish left on the stove); the
 * stove can't start a pot until a later collect takes them (Li Bai, 226 comment 250e4ef1). Never to the Inbox. */
export function collectPot(c: P0Content, s: P0State, cmd: { taps?: unknown; eat?: unknown; pot?: unknown }, now: number, events: P0Event[], max: number): Refusal | null {
  const pot = s.stove;
  if (!pot) return { code: 'stove_empty' };
  if (!aimsAt(cmd, pot)) return { code: 'stale_pot', detail: { pot: pot.id ?? null } };
  const eat = cmd.eat === true;
  if (eat && s.energy.value >= max && !(pot.mystery && !pot.left && noDish(c, s, pot, now))) return { code: 'energy_full' };
  if (pot.left) {
    const refusal = collectLeft(c, s, pot, eat, now, events);
    if (!refusal) startQueued(c, s, now, events);
    return refusal;
  }
  const left = pot.started_at + pot.ms - now;
  if (left > 0) return { code: 'not_ready', detail: { ready_in: left } };
  // The waiting pot fires when this one was done, as settleStove would have done it, unless it had no place then.
  const onTime = !pot.no_room && potFits(c, s, pot, now);
  finishPot(c, s, pot, [...(pot.taps ?? []), ...readTaps(cmd.taps)], eat, now, events);
  startQueued(c, s, onTime ? pot.started_at + pot.ms : now, events);
  return null;
}

/** heat / collect name their pot (`pot`: the id from the pot event or view.cooking.stove.id); without one, the pot on the stove. */
export function aimsAt(cmd: { pot?: unknown }, pot: Pot): boolean {
  return cmd.pot === undefined || cmd.pot === null || cmd.pot === (pot.id ?? null);
}

const autoQuality = (c: P0Content, pot: Pot): number => Math.min(pot.mystery ? 0 : heatHits(c, pot.heats, pot.taps ?? []), 2);

/**
 * A failed pot whose ingredients all come back (Newcomer Blessing, the first trial_refunds a day) makes no Mystery
 * Dish (李白 2026-10-08, PR #22 review): otherwise those pots are free Energy. COOK-4 says
 * `No dish this time · ingredients back (9 left today)`; from the 11th, and after the Blessing, the Mystery Dish comes out.
 */
function noDish(c: P0Content, s: P0State, pot: Pot, now: number): boolean {
  return pot.mystery && (trialRefundsLeft(c, s, now) ?? 0) > 0;
}

/** Whether the pot, kept automatically, finds a place (a pot that makes no dish always does). */
function potFits(c: P0Content, s: P0State, pot: Pot, now: number): boolean {
  return noDish(c, s, pot, now) || dishesFit(c, s, [[dishId(pot.dish, autoQuality(c, pot)), 1]]);
}

const readTaps = (taps: unknown): number[] => (Array.isArray(taps) ? taps.slice(0, 20).map(Number).filter(Number.isFinite) : []);

/**
 * Heat taps sent as they happen (SGODOT-232 S5): the first tap per ring is kept on the pot, so a pot that is kept
 * automatically (Queue ×2) is judged on what the player really did. collect may still send taps itself.
 */
export function recordHeat(s: P0State, cmd: { taps?: unknown; pot?: unknown }): Refusal | null {
  const pot = s.stove;
  if (!pot || pot.left) return { code: 'stove_empty' };
  if (!aimsAt(cmd, pot)) return { code: 'stale_pot', detail: { pot: pot.id ?? null } };
  const taps = readTaps(cmd.taps).filter(t => t >= 0 && t <= pot.ms);
  pot.taps = [...(pot.taps ?? []), ...taps].slice(0, 20);
  return null;
}

/**
 * Queue ×2 (§4.6.3 Lv5; 李白 2026-10-08): once the pot on the stove is done, it goes the Keep way (Warming Cabinet,
 * then bag) on its own, judged on the heat taps it has, and the waiting pot fires at that moment (never before it was
 * queued). With no room for it, it stays on the stove (no_room) and the waiting pot fires when a later command finds
 * room or the player takes it. The view runs this too, so it shows what the next command will find. The reducer runs
 * it before every command (except heat / collect aimed at the pot on the stove, which bring its taps) and again after.
 */
export function settleStove(c: P0Content, s: P0State, now: number, events: P0Event[]): void {
  const pot = s.stove, next = s.queue;
  if (!pot || !next || pot.left) return;
  const readyAt = pot.started_at + pot.ms;
  if (now < readyAt) return;
  if (!potFits(c, s, pot, now)) { pot.no_room = true; return; }
  const late = !!pot.no_room;
  finishPot(c, s, pot, pot.taps ?? [], false, now, events, true);
  startQueued(c, s, late ? now : readyAt, events);
}

/** The waiting pot fires once the stove is clear (no pot, no plates left on it), never before it was queued. */
function startQueued(c: P0Content, s: P0State, at: number, events: P0Event[]): void {
  if (s.stove || !s.queue) return;
  const from = Math.max(at, s.queue.started_at);
  s.stove = { ...s.queue, started_at: from };
  s.queue = null;
  events.push({ kind: 'queue', id: s.stove.id, dish: s.cookbook.includes(s.stove.dish) && !s.stove.mystery ? s.stove.dish : null, started_at: from, ms: s.stove.ms });
}

/** Judge a done pot and pay it out: portions the Keep way (or eaten), Cookbook, first-time rewards and XP.
 * auto: kept on its own (Queue ×2), so the client shows the Keep toast instead of the COOK-4 card. */
function finishPot(c: P0Content, s: P0State, pot: Pot, taps: number[], eat: boolean, now: number, events: P0Event[], auto = false): void {
  const hits = pot.mystery ? 0 : heatHits(c, pot.heats, taps);
  const quality = Math.min(hits, 2);
  const main = dishId(pot.dish, quality);
  const extra = quality === 2 ? 1 : 0; // Perfect: a second, Plain portion (§7.2.5)
  const none = noDish(c, s, pot, now);
  const portions = none ? [] : extra ? [main, pot.dish] : [main];
  keepOrLeave(c, s, pot, eat ? portions.slice(1) : portions, events);
  const firstKey = `cook:${pot.dish}`;
  const first = !s.firsts.includes(firstKey);
  if (first) s.firsts.push(firstKey);
  events.push({ kind: 'dish', pot: pot.id, dish: pot.dish, quality, qty: portions.length, first, mystery: pot.mystery, hits,
    ...(none ? { none: true as const, trial_left: Math.max(0, (trialRefundsLeft(c, s, now) ?? 0) - 1) } : {}), ...(auto ? { auto: true as const } : {}) });
  if (eat && !none) eatMeal(c, s, main, now, events);
  if (pot.mystery) { failedPot(c, s, pot.items ?? [], pot.started_at, now, events); return; }
  if (!s.cookbook.includes(pot.dish)) s.cookbook.push(pot.dish);
  s.book.cooked[pot.dish] = (s.book.cooked[pot.dish] ?? 0) + 1;
  s.book.best[pot.dish] = Math.max(s.book.best[pot.dish] ?? 0, quality);
  if (first) s.book.first_at[pot.dish] = now;
  if (first) {
    grantOnce(c, s, now, `first_dish_${pot.rarity}`, c.rewards.first_dish[pot.rarity - 1] ?? 0, events);
    const cooked = s.firsts.filter(f => f.startsWith('cook:') && f !== `cook:${c.cooking.mystery.id}`).length;
    for (const [n, energy] of c.rewards.cookbook) if (cooked >= n) grantOnce(c, s, now, `cookbook_${n}`, energy, events);
  }
  const tier = c.cooking.tiers[String(pot.rarity)];
  const before = s.day.cooked[pot.dish] ?? 0;
  s.day.cooked[pot.dish] = before + 1;
  if (first) {
    firstXp(c, s, now, 'cooking', firstKey, tier.first_xp, events);
  }
  // §7.6.2: level difference, then same-page decay (2nd half rounded up, 3rd+ none), then quality, rounded down.
  // The first pot of a page earns this as well as the first-cook bonus (§14.2.2: Good Grilled Crucian 10 + 4 × 1.25).
  const scaled = scaledXp(s, tier.xp, pot.xp_pct);
  const decayed = before === 0 ? scaled : before === 1 ? Math.ceil(scaled / 2) : 0;
  gainXp(c, s, now, 'cooking', Math.floor(decayed * c.cooking.quality_xp[quality]), pot.xp_pct, events, before + 1);
}

/**
 * A Mystery Dish came out (§7.5.2): Kitchen Mishaps keeps each combination once; a new one turns over a clue. In the
 * Newcomer Blessing the first trial_refunds failures a day give every ingredient back; otherwise only Rare and
 * Legendary ones come back. No XP either way.
 */
function failedPot(c: P0Content, s: P0State, items: string[], potAt: number, now: number, events: P0Event[]): void {
  const trial = (trialRefundsLeft(c, s, now) ?? 0) > 0;
  s.day.mishaps += 1;
  const fresh = noteMishap(s, items, now);
  const clue = fresh ? giveClue(c, s, items) : null;
  const back: string[] = [];
  items.forEach((id, i) => {
    if (!trial && (ingredient(c, id)?.rarity ?? 1) < 3) return;
    giveBack(c, s, id, `refund:${potAt}:${i}`, now, events);
    back.push(id);
  });
  events.push({ kind: 'mishap', items: [...items].sort(), tried: !fresh, refund: back, trial_left: trialRefundsLeft(c, s, now),
    clue: clue ? { page: clue.page, slots: clue.slots } : null });
}

/** A refunded ingredient goes back where the stove took it: seasonings to storage with the rack, the rest to the bag;
 * with no room it waits in the Inbox rather than being lost. */
function giveBack(c: P0Content, s: P0State, id: string, key: string, now: number, events: P0Event[]): void {
  if (rackOn(c, s) && isSeasoning(c, id)) { putInStorage(s, id, 1); return; }
  if (room(c, s, id) > 0) { add(c, s, id, 1); events.push({ kind: 'item', id, delta: 1 }); return; }
  grantItems(c, s, now, key, 'Kitchen refund', [[id, 1]], events);
}

/** Portions already judged and waiting on the stove: Eat takes the first, the rest go the Keep way again. */
function collectLeft(c: P0Content, s: P0State, pot: Pot, eat: boolean, now: number, events: P0Event[]): Refusal | null {
  const ids = [...pot.left!];
  if (!eat && !ids.some(id => dishesFit(c, s, [[id, 1]]))) return { code: 'bag_full', detail: { cabinet: cabinetCap(c, s) > 0, left: ids.length } };
  const eaten = eat ? ids.shift()! : null;
  keepOrLeave(c, s, pot, ids, events);
  if (eaten) eatMeal(c, s, eaten, now, events);
  return null;
}

/** Keep each portion that has a place; the others stay on the stove (a `plate` event says which). */
function keepOrLeave(c: P0Content, s: P0State, pot: Pot, ids: string[], events: P0Event[]): void {
  const left: string[] = [];
  for (const id of ids) {
    if (dishesFit(c, s, [[id, 1]])) routeDish(c, s, id, 1, events);
    else left.push(id);
  }
  s.stove = left.length ? { ...pot, left } : null;
  if (left.length) events.push({ kind: 'plate', ids: left, cabinet: cabinetCap(c, s) > 0 });
}

/** Nominal energy of one portion today: rarity + quality bonus, same page halves then zeroes (§7.17.1). */
export function mealValue(c: P0Content, s: P0State, id: string): number {
  const { base, quality } = dishParts(id);
  // Mystery Dish: never decays; Cooking Lv3 Hearty Mishap raises it (§7.5.2).
  if (base === c.cooking.mystery.id) return hasConvenience(c, s, 'hearty_mishap') ? c.cooking.mystery.hearty : c.cooking.mystery.energy;
  const recipe = recipeById(c, base);
  if (!recipe) return 0;
  const tier = c.cooking.tiers[String(recipeRarity(c, recipe))];
  const full = tier.energy + (tier.bonus[quality] ?? 0);
  const eaten = s.day.eaten[base] ?? 0;
  return eaten === 0 ? full : eaten === 1 ? Math.ceil(full / 2) : 0;
}

/** Eat one portion from the bag, or from the Warming Cabinet with from: "cabinet" (§7.7). */
export function eatDish(c: P0Content, s: P0State, cmd: { item?: unknown; from?: unknown }, now: number, events: P0Event[], max: number): Refusal | null {
  const id = String(cmd.item ?? '');
  const from = cmd.from === 'cabinet' ? 'cabinet' : 'bag';
  if (itemKind(id) !== 'dish') return { code: 'not_edible' };
  if (haveDish(c, s, id, from) < 1) return { code: 'not_enough', detail: { item: id, have: 0 } };
  if (s.energy.value >= max) return { code: 'energy_full' };
  eatFrom(c, s, id, from, events);
  eatMeal(c, s, id, now, events);
  return null;
}

/** One portion eaten (already removed from where it was): daily cap, same-dish decay, energy (§7.17.1). */
function eatMeal(c: P0Content, s: P0State, id: string, now: number, events: P0Event[]): void {
  const nominal = mealValue(c, s, id);
  const cap = foodCap(c, s, now);
  const counted = Math.max(0, Math.min(nominal, cap - s.day.meals));
  const { base } = dishParts(id);
  s.day.eaten[base] = (s.day.eaten[base] ?? 0) + 1;
  s.day.meals += counted;
  const gain = gainEnergy(c, s, now, counted, events, 'eat');
  events.push({ kind: 'meal', dish: id, nominal, counted, gain, meals: s.day.meals, cap });
}

const round3 = (x: number) => Math.round(x * 1000) / 1000;
