/** P0 content (assets/p0/p0_content.json), shared with the Godot client. */
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export type Skill = 'farming' | 'fishing' | 'cooking';
export const SKILLS: readonly Skill[] = ['farming', 'fishing', 'cooking'];

/** Ingredient family (§7.3.1): Water, Field, Orchard, Seasoning. */
export type Family = 'W' | 'F' | 'O' | 'S';

export interface Crop {
  id: string; name: string; seed: string; seed_name: string;
  tier: number; energy: number; level: number; gate: number;
  seed_price: number; grow_h: number; yield: number; price: number; xp: number; first_xp: number;
  ingr: [Family, number];
}

export interface Fish { id: string; name: string; rarity: number; level: number; price: number; cook?: boolean; where: string[] }
export interface FishSite { name: string; template: string; weights: number[]; fish: string[] }

export interface CookTier {
  energy: number; ms: number; heats: number[]; gold: number; spin_ms: number;
  first_xp: number; xp: number; level: number; bonus: number[];
}
export interface Recipe { id: string; name: string; in: string[]; known?: boolean }

export interface P0Content {
  version: string;
  energy: { max_base: number; regen_ms: number; bonus_zone: number; rest_amount: number };
  day: { utc_offset_hours: number; rollover_hour: number };
  start: { coins: number; tilled_plots: number; wild_plots: number; bag: [string, number][] };
  bag: { capacity: number; stack: Record<string, number> };
  skills: Record<Skill, number[]>;
  level_up_energy: { first: number; later: number };
  level_gifts: Record<string, [string, number][]>;
  xp_multiplier: [number, number][];
  crops: Crop[];
  stall: { keeper: { role: string; name: string }; buy: string[] };
  rarity_names: string[];
  fish: Fish[];
  fishing: {
    cast_energy: number; refund_fail: number; protect_max_level: number; protect_fails: number;
    bite_min_ms: number; bite_spread_ms: number; hook_window_ms: number; stale_ms: number;
    catch_xp: number[]; first_xp: number[]; first_cast_xp: number; first_landed_xp: number;
    rod: { id: string; name: string; reach: number };
    sites: Record<string, FishSite>;
    baits: Record<string, { shift: number[]; wait: number }>;
  };
  goods: Record<string, { name: string; price: number; skill: Skill; gate: number; daily: number }>;
  blessing: { days: number; regen_mult: number; food_bonus: number };
  /** §9 stall board (P0: the one-time tutorial request in slot 1; slot 2 refills after refill_h). */
  requests: { slots: number; refill_h: number; tutorial: { id: string; title: string; item: string; qty: number; coins: number; where: string } };
  /** §3.4.8 one-time energy: by rarity (index = rarity − 1) and [count, energy] milestones; may pass max by ≤ max_over. */
  rewards: { first_fish: number[]; first_dish: number[]; cookbook: [number, number][]; fishdex: [number, number][]; max_over: number };
  cooking: {
    slots: [number, number][];
    tiers: Record<string, CookTier>;
    first_fire: { gold: number; spin_ms: number };
    tolerance_ms: number;
    quality_xp: number[];
    derive: number[][];
    mystery: { id: string; name: string; energy: number };
    food_cap: number;
    recipes: Recipe[];
  };
}

export const DEFAULT_P0_CONTENT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../assets/p0/p0_content.json');

export function loadP0Content(file = DEFAULT_P0_CONTENT): P0Content {
  return JSON.parse(readFileSync(file, 'utf8')) as P0Content;
}

export function cropById(c: P0Content, id: string): Crop | undefined { return c.crops.find(crop => crop.id === id); }
export function cropBySeed(c: P0Content, seed: string): Crop | undefined { return c.crops.find(crop => crop.seed === seed); }
export function fishById(c: P0Content, id: string): Fish | undefined { return c.fish.find(f => f.id === id); }
export function recipeById(c: P0Content, id: string): Recipe | undefined { return c.cooking.recipes.find(r => r.id === id); }

/** Bag kind from the id prefix: seed_*, crop_*, fish_*, dish_*, bait_*, anything else is a material. */
export function itemKind(id: string): string {
  const head = id.split('_')[0];
  return ['seed', 'crop', 'fish', 'dish', 'bait'].includes(head) ? head : 'material';
}

/** Dish stacks carry their quality in the id: dish_x (Plain), dish_x@good, dish_x@perfect (§7.2.5). */
export const QUALITIES = ['plain', 'good', 'perfect'] as const;
export function dishId(base: string, quality: number): string { return quality > 0 ? `${base}@${QUALITIES[quality]}` : base; }
export function dishParts(id: string): { base: string; quality: number } {
  const [base, q] = id.split('@');
  return { base, quality: Math.max(0, QUALITIES.indexOf((q ?? 'plain') as typeof QUALITIES[number])) };
}

/** Family and rarity of a cookable item, or null (seeds, bait, ornamental fish, dishes). */
export function ingredient(c: P0Content, id: string): { family: Family; rarity: number } | null {
  const crop = cropById(c, id);
  if (crop) return { family: crop.ingr[0], rarity: crop.ingr[1] };
  const fish = fishById(c, id);
  if (fish && fish.cook !== false) return { family: 'W', rarity: fish.rarity };
  return null;
}

/** Display name for any bag id the P0 content knows. */
export function itemName(c: P0Content, id: string): string {
  const crop = cropById(c, id) ?? cropBySeed(c, id);
  if (crop) return crop.id === id ? crop.name : crop.seed_name;
  const fish = fishById(c, id);
  if (fish) return fish.name;
  if (c.goods[id]) return c.goods[id].name;
  if (itemKind(id) === 'dish') {
    const { base } = dishParts(id);
    if (base === c.cooking.mystery.id) return c.cooking.mystery.name;
    return recipeById(c, base)?.name ?? base;
  }
  return id;
}
