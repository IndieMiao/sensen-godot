/** What the client receives: the settled state plus everything it would otherwise have to re-derive. */
import { cropBySeed, dishId, fishById, ingredient, itemKind, itemName, QUALITIES, SKILLS, type P0Content } from './content.js';
import { count, freeSlots } from './bag.js';
import { cookSlots, ingredientsFor, mealValue, recipeRarity } from './cooking.js';
import { sellPrice, stallOffer } from './reducer.js';
import { dayKey, maxEnergy, nextTickIn, settleEnergy, skillLevel, untilRollover } from './rules.js';
import { emptyDay, type P0State } from './state.js';

export function viewOf(c: P0Content, input: P0State, now: number) {
  const s = structuredClone(input);
  settleEnergy(c, s, now);
  if (s.day.key !== dayKey(c, now)) s.day = emptyDay(dayKey(c, now));
  const skills = Object.fromEntries(SKILLS.map(skill => {
    const level = skillLevel(c, s, skill), th = c.skills[skill];
    return [skill, { level, xp: s.skills[skill], floor: th[level - 1], next: level < th.length ? th[level] : null }];
  }));
  const fishingLevel = skillLevel(c, s, 'fishing');
  const f = c.fishing;
  return {
    now, content_version: c.version, seq: s.seq,
    energy: { value: s.energy.value, max: maxEnergy(c, s), next_in: nextTickIn(c, s, now), regen_ms: c.energy.regen_ms },
    coins: s.coins,
    skills,
    plots: s.plots.map(p => ({
      id: p.id, state: p.state === 'growing' && (p.ready_at ?? Infinity) <= now ? 'ready' : p.state,
      crop: p.crop ?? null, ready_in: p.state === 'growing' && p.ready_at ? Math.max(0, p.ready_at - now) : null,
      xp_pct: p.xp_pct ?? null,
    })),
    bag: { capacity: c.bag.capacity, slots: s.bag, free: freeSlots(c, s.bag) },
    rest: { used: s.day.rest, limit: 1, resets_in: untilRollover(c, now), amount: c.energy.rest_amount },
    stall: {
      keeper: c.stall.keeper,
      buy: c.stall.buy.map(id => {
        const offer = stallOffer(c, id);
        const level = skillLevel(c, s, offer.skill);
        return { id, name: itemName(c, id), price: offer.price, energy: cropBySeed(c, id)?.energy ?? 0, gate: offer.gate, skill: offer.skill,
          unlocked: level >= offer.gate, xp_to_go: Math.max(0, c.skills[offer.skill][offer.gate - 1] - s.skills[offer.skill]),
          left: offer.daily ? Math.max(0, offer.daily - (s.day.bought[id] ?? 0)) : null };
      }),
    },
    fishing: {
      pond: f.pond.name, rod: f.rod.name, cast_energy: f.cast_energy,
      cast: s.cast ? { rarity: fishById(c, s.cast.fish)!.rarity, bite_in: Math.max(0, s.cast.at + s.cast.bite_ms - now),
        hook_ms: f.hook_window_ms, breaks: s.cast.breaks, bait: s.cast.bait } : null,
      protection_left: fishingLevel <= f.protect_max_level ? Math.max(0, f.protect_fails - s.day.fails) : null,
      caught: s.fishing.caught, seen: s.fishing.seen,
      dex: c.fish.map(fish => ({ id: fish.id, rarity: fish.rarity, level: fish.level, caught: s.fishing.caught[fish.id] ?? 0 })),
      baits: Object.keys(f.baits).map(id => ({ id, have: count(s.bag, id) })),
    },
    cooking: {
      slots: cookSlots(c, s),
      stove: s.stove ? {
        dish: s.cookbook.includes(s.stove.dish) && !s.stove.mystery ? s.stove.dish : null, rarity: s.stove.rarity,
        ms: s.stove.ms, elapsed: Math.max(0, now - s.stove.started_at), ready_in: Math.max(0, s.stove.started_at + s.stove.ms - now),
        heats: s.stove.heats,
      } : null,
      first_fire: s.fires === 0,
      cookbook: c.cooking.recipes.map(r => {
        const known = s.cookbook.includes(r.id);
        const rarity = recipeRarity(c, r);
        return { id: r.id, name: known ? r.name : null, rarity, in: known ? r.in : r.in.map(() => '?'),
          known, cooked: s.firsts.includes(`cook:${r.id}`), slots: r.in.length,
          can_cook: known && r.in.length <= cookSlots(c, s) && ingredientsFor(c, s, r) !== null,
          today: s.day.cooked[r.id] ?? 0 };
      }),
      tiers: Object.fromEntries(Object.entries(c.cooking.tiers).map(([k, t]) => [k, { energy: t.energy, ms: t.ms, bonus: t.bonus }])),
    },
    meals: { used: s.day.meals, cap: c.cooking.food_cap, resets_in: untilRollover(c, now), eaten: s.day.eaten },
    items: Object.fromEntries(bagIds(c, s).map(id => [id, itemInfo(c, s, id)])),
    rarity_names: c.rarity_names,
    prices: Object.fromEntries(c.crops.map(crop => [crop.id, crop.price])),
    names: Object.fromEntries([...c.crops.flatMap(crop => [[crop.id, crop.name], [crop.seed, crop.seed_name]]),
      ...c.fish.map(fish => [fish.id, fish.name]), ...c.cooking.recipes.map(r => [r.id, r.name]),
      ...Object.entries(c.goods).map(([id, g]) => [id, g.name]), [c.cooking.mystery.id, c.cooking.mystery.name]]),
    crops: c.crops.map(crop => ({ id: crop.id, seed: crop.seed, energy: crop.energy, grow_h: crop.grow_h, level: crop.level })),
    firsts: s.firsts,
  };
}

/** Every id the client may show this turn: bag contents plus all dishes and ingredients by name. */
function bagIds(c: P0Content, s: P0State): string[] {
  const ids = new Set(s.bag.map(b => b.id));
  for (const crop of c.crops) ids.add(crop.id);
  for (const fish of c.fish) ids.add(fish.id);
  return [...ids];
}

function itemInfo(c: P0Content, s: P0State, id: string) {
  const kind = itemKind(id);
  const ing = ingredient(c, id);
  const info: Record<string, unknown> = { name: itemName(c, id), kind, sell: sellPrice(c, id), cook: !!ing };
  if (ing) { info.family = ing.family; info.rarity = ing.rarity; }
  if (kind === 'fish') info.rarity = fishById(c, id)?.rarity ?? 1;
  if (kind === 'dish') {
    const [base, q] = id.split('@');
    const quality = Math.max(0, QUALITIES.indexOf((q ?? 'plain') as typeof QUALITIES[number]));
    const recipe = c.cooking.recipes.find(r => r.id === base);
    info.base = base; info.quality = quality;
    info.rarity = recipe ? recipeRarity(c, recipe) : 0;
    info.meal = mealValue(c, s, dishId(base, quality));
    info.full = recipe ? c.cooking.tiers[String(info.rarity)].energy + (c.cooking.tiers[String(info.rarity)].bonus[quality] ?? 0) : c.cooking.mystery.energy;
  }
  return info;
}
