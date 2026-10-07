/** Cooking and eating (plan §7.2–7.6, §7.17): pots cost no energy; quality comes from heat taps judged on the server. */
import { dishId, dishParts, fishById, ingredient, itemKind, recipeById, type CookTier, type P0Content, type Recipe } from './content.js';
import { cabinetCap, dishesFit, eatFrom, haveDish, haveIngredient, ingredientStock, routeDish, takeIngredient } from './kitchen_storage.js';
import { gainEnergy, gainXp, grantOnce, type P0Event } from './progress.js';
import { draw, foodCap, scaledXp, skillLevel, xpPercent } from './rules.js';
import type { Heat, P0State } from './state.js';
import type { Refusal } from './fishing.js';

const TAG = /^([WFOS])(\d)$/;

export function cookSlots(c: P0Content, s: P0State): number {
  const level = skillLevel(c, s, 'cooking');
  let slots = 1;
  for (const [at, n] of c.cooking.slots) if (level >= at) slots = n;
  return slots;
}

/** One token of a recipe: a specific id or a family × rarity tag such as W1 ("Any Common fish"). */
function tokenInfo(c: P0Content, token: string): { family: string; rarity: number } | null {
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

function tokenMatches(c: P0Content, token: string, id: string): boolean {
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

/** Concrete items for a known page: tag slots take the cheapest matching item the stove can reach. */
export function ingredientsFor(c: P0Content, s: P0State, recipe: Recipe): string[] | null {
  const left = ingredientStock(c, s);
  const out: string[] = [];
  const priceOf = (id: string) => fishById(c, id)?.price ?? c.crops.find(cr => cr.id === id)?.price ?? 0;
  // Specific tokens first so a tag never eats the item a named slot needs.
  const order = [...recipe.in].sort((a, b) => Number(TAG.test(a)) - Number(TAG.test(b)));
  for (const token of order) {
    const options = [...left.entries()].filter(([id, n]) => n > 0 && tokenMatches(c, token, id)).sort((a, b) => priceOf(a[0]) - priceOf(b[0]));
    if (!options.length) return null;
    out.push(options[0][0]);
    left.set(options[0][0], options[0][1] - 1);
  }
  return out;
}

export function startPot(c: P0Content, s: P0State, cmd: { items?: unknown; recipe?: unknown }, now: number, events: P0Event[]): Refusal | null {
  if (s.stove) return { code: 'stove_busy', detail: { ready_in: Math.max(0, s.stove.started_at + s.stove.ms - now) } };
  let items: string[];
  if (cmd.recipe !== undefined) {
    const recipe = recipeById(c, String(cmd.recipe));
    if (!recipe || !s.cookbook.includes(recipe.id)) return { code: 'unknown_recipe' };
    const picked = ingredientsFor(c, s, recipe);
    if (!picked) return { code: 'missing_ingredients', detail: { recipe: recipe.id } };
    items = picked;
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
  const recipe = matchRecipe(c, items);
  const rarity = deriveRarity(c, parts);
  const tier: CookTier = c.cooking.tiers[String(rarity)];
  const teach = s.fires === 0;
  const width = teach ? c.cooking.first_fire.gold : tier.gold;
  const spin = teach ? c.cooking.first_fire.spin_ms : tier.spin_ms;
  const heats: Heat[] = tier.heats.map(at => ({ at, spin, width, gold: round3(0.1 + draw(s) * (0.85 - width)) }));
  s.fires += 1;
  s.stove = {
    dish: recipe?.id ?? c.cooking.mystery.id, rarity, started_at: now, ms: tier.ms, heats,
    xp_pct: xpPercent(c, skillLevel(c, s, 'cooking'), tier.level), mystery: !recipe,
  };
  events.push({ kind: 'pot', dish: recipe && s.cookbook.includes(recipe.id) ? recipe.id : null, rarity, ms: tier.ms });
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

/** Collect a ready pot. The portions go the Keep way (Warming Cabinet → bag). With eat: true (COOK-4 Eat) the
 * main portion is eaten from the pot instead, so a full cabinet and bag never block eating (§7.2.6). */
export function collectPot(c: P0Content, s: P0State, cmd: { taps?: unknown; eat?: unknown }, now: number, events: P0Event[], max: number): Refusal | null {
  const pot = s.stove;
  if (!pot) return { code: 'stove_empty' };
  const left = pot.started_at + pot.ms - now;
  if (left > 0) return { code: 'not_ready', detail: { ready_in: left } };
  const taps = Array.isArray(cmd.taps) ? cmd.taps.slice(0, 20).map(Number).filter(Number.isFinite) : [];
  const hits = pot.mystery ? 0 : heatHits(c, pot.heats, taps);
  const quality = Math.min(hits, 2);
  const main = dishId(pot.dish, quality);
  const extra = quality === 2 ? 1 : 0; // Perfect: a second, Plain portion (§7.2.5)
  const eat = cmd.eat === true;
  if (eat && s.energy.value >= max) return { code: 'energy_full' };
  const portions: [string, number][] = [];
  if (!eat) portions.push([main, 1]);
  if (extra) portions.push([pot.dish, 1]);
  if (!dishesFit(c, s, portions)) return { code: 'bag_full', detail: { cabinet: cabinetCap(c, s) > 0 } };   // the dish stays on the stove
  s.stove = null;
  for (const [id, n] of portions) routeDish(c, s, id, n, events);
  const firstKey = `cook:${pot.dish}`;
  const first = !s.firsts.includes(firstKey);
  if (first) s.firsts.push(firstKey);
  events.push({ kind: 'dish', dish: pot.dish, quality, qty: 1 + extra, first, mystery: pot.mystery, hits });
  if (eat) eatMeal(c, s, main, now, events);
  if (pot.mystery) return null;
  if (!s.cookbook.includes(pot.dish)) s.cookbook.push(pot.dish);
  if (first) {
    grantOnce(c, s, now, `first_dish_${pot.rarity}`, c.rewards.first_dish[pot.rarity - 1] ?? 0, events);
    const cooked = s.firsts.filter(f => f.startsWith('cook:') && f !== `cook:${c.cooking.mystery.id}`).length;
    for (const [n, energy] of c.rewards.cookbook) if (cooked >= n) grantOnce(c, s, now, `cookbook_${n}`, energy, events);
  }
  const tier = c.cooking.tiers[String(pot.rarity)];
  const before = s.day.cooked[pot.dish] ?? 0;
  s.day.cooked[pot.dish] = before + 1;
  if (first) {
    events.push({ kind: 'first', what: firstKey, xp: tier.first_xp });
    gainXp(c, s, now, 'cooking', tier.first_xp, 100, events);
  }
  // §7.6.2: level difference, then same-page decay (2nd half rounded up, 3rd+ none), then quality, rounded down.
  // The first pot of a page earns this as well as the first-cook bonus (§14.2.2: Good Grilled Crucian 10 + 4 × 1.25).
  const scaled = scaledXp(s, tier.xp, pot.xp_pct);
  const decayed = before === 0 ? scaled : before === 1 ? Math.ceil(scaled / 2) : 0;
  gainXp(c, s, now, 'cooking', Math.floor(decayed * c.cooking.quality_xp[quality]), pot.xp_pct, events);
  return null;
}

/** Nominal energy of one portion today: rarity + quality bonus, same page halves then zeroes (§7.17.1). */
export function mealValue(c: P0Content, s: P0State, id: string): number {
  const { base, quality } = dishParts(id);
  if (base === c.cooking.mystery.id) return c.cooking.mystery.energy;
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
