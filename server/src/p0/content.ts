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
export interface Rod { id: string; name: string; reach: number; level: number; price: number; hook_bonus_ms: number; band_bonus: number }
export interface FishSite { name: string; city: string; template: string; weights: number[]; fish: string[] }

export interface CookTier {
  energy: number; ms: number; heats: number[]; gold: number; spin_ms: number;
  first_xp: number; xp: number; level: number; bonus: number[];
}
export interface Recipe { id: string; name: string; in: string[]; known?: boolean; style?: string }

export type ShopId = 'homestead' | 'tackle' | 'market' | 'tea' | 'post';
export const SHOPS: readonly ShopId[] = ['homestead', 'tackle', 'market', 'tea', 'post'];
export type QuotaId = 'fish_tackle' | 'dish' | 'material' | 'request_bonus' | 'sys_requests';
export type BoardId = 'stall' | 'market';

/** What a request asks for: a kind, optionally narrowed to one id, one rarity, the same item or N distinct items. */
export interface Need { kind: 'crop' | 'fish' | 'dish' | 'material' | 'sow'; id?: string; rarity?: number; same?: boolean; distinct?: number }
export interface RequestTemplate { title: string; need: Need; skill: Skill; gate: [Skill, number][]; bonus: number; enabled?: boolean }
export interface ResidentRequest { id: string; title: string; text: string; stage: string; need: Need; qty: number; coins: number }
/** §13.2 gathering spot (SGODOT-231): the first yield is the spot's material (Farm Storage, +1 with gloves). */
export interface GatherSpot { name: string; yield: [string, number][]; homestead: number }
/** §13.3.3 one mine floor: weighted extra drop per rock, null = nothing extra. */
export interface MineFloorDef { floor: number; drops: [string | null, number][] }
/** §13.4 workbench recipe: out goes to the bag, Gear (equipped) or the owned list (passive tools). */
export interface WorkbenchRecipe {
  id: string; tab: string; out: string; qty: number; to: 'bag' | 'gear' | 'owned';
  cost: [string, number][]; gate?: [Skill, number];
}

export interface ResidentDef {
  name: string; role: string; portrait: string; likes: string; gift_meal: string; one_per_day: boolean;
  lines: Record<string, string>; requests: ResidentRequest[];
}

export interface P0Content {
  version: string;
  energy: { max_base: number; regen_ms: number; bonus_zone: number; rest_amount: number; rest_away_h: number };
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
    catch_xp: number[]; first_xp: number[]; first_cast_xp: number; first_landed_xp: number; first_city_xp: number;
    rods: Rod[];
    sites: Record<string, FishSite>;
    baits: Record<string, { shift: number[]; wait: number }>;
  };
  goods: Record<string, { name: string; price: number; skill: Skill; gate: number; daily: number; grow_mult?: number }>;
  blessing: { days: number; regen_mult: number; food_bonus: number };
  tackle: { keeper: { role: string; name: string }; buy: string[] };
  tools: {
    farming: string; fishing: string; mining: string; combat: string; names: Record<string, string>;
    row_hoe: { id: string; price: number; skill: Skill; gate: number; sow: number };
  };
  materials: Record<string, { name: string; price: number | null; ingr?: [Family, number] }>;   // ingr: seasonings (§7.3.1)
  wallet_floor: number;                       // §8.1.1 / q(32): every coin spend except seeds keeps this much
  homestead: {
    max_level: number;
    warming_cabinet: number;                  // portions once unlocked (Lv3; 12 from Lv8 is P1, §7.7)
    per_level: { energy: number; meals: number };
    board_slots: [number, number][];          // [from Homestead level, Stall Board slots]
    levels: { level: number; coins: number; skills: number; materials: [string, number][]; unlocks: string[] }[];
  };
  bag_upgrades: { id: string; name: string; homestead: number; price: number; materials: [string, number][]; capacity: number }[];
  drinks: { energy: number; prices: number[]; daily: number; items: Record<string, { name: string; shop: ShopId }> };
  specialty: Record<string, { name: string; price: number; shop: ShopId; to: 'storage' }>;
  shops: Record<ShopId, { sells: string; buys: Record<string, { rate: number; quota: QuotaId | null }> }>;
  market: { buy: string[]; specialty: string[] };
  quotas: Record<QuotaId, { cap: number; scope: string }>;
  affinity: {
    stages: [string, number][]; first_chat: number; request: number; gift_meal_stage: string;
    gift: { loved_fine: number; liked: number; any: number; perfect: number; cap: number; mystery: number; chef_touch: { cooking: number; bonus: number; cap: number } };
    mystery_line: string;
  };
  residents: Record<string, ResidentDef>;
  /** P0 has no nickname or city choice yet: what the Profile page shows (SGODOT-225). */
  profile: { name: string; city: string; climate: string; farm_name: string };
  /** §9.6 / §9.13.2 request boards: the Stall Board (slot 1 starts with the tutorial) and the Market Board. */
  requests: {
    slots: number; refill_h: number; tutorial: { id: string; title: string; item: string; qty: number; coins: number; where: string };
    done_refill_h: number; drop_refill_h: number; expire_h: number; track_max: number;
    qty: [number, number, number][];          // [from skill level, min, max]
    quality_bonus: number[];                  // dish requests: Plain / Good / Perfect
    floor_rate: number;                       // floor price = ⌊sell price × rate⌋
    boards: Record<BoardId, { title: string; slots?: number; templates: string[] }>;
    templates: Record<string, RequestTemplate>;
  };
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
  /** Consumables made at the workbench, with no shop row (Torch). */
  supplies: Record<string, { name: string }>;
  /** §13.2 (SGODOT-231): spot regrow, anti-script tempo between taps, the gloves and their bonus. */
  gather: { regen_h: number; tempo_ms: number; gloves: string; gloves_bonus: number; spots: Record<string, GatherSpot> };
  /** §13.3 floors 1–2 (SGODOT-231, LOCK-21). picks: Stone per rock by pickaxe. */
  mine: {
    runs_per_day: number; floor_energy: number; rock_energy: number; rocks: number; restart_floor: number; tempo_ms: number;
    floors: MineFloorDef[]; picks: Record<string, { stone: number }>;
  };
  /** §13.4 P0 workbench: Tools / Supplies (SGODOT-231). */
  workbench: { tabs: string[]; recipes: WorkbenchRecipe[] };
}

export const DEFAULT_P0_CONTENT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../assets/p0/p0_content.json');

export function loadP0Content(file = DEFAULT_P0_CONTENT): P0Content {
  return JSON.parse(readFileSync(file, 'utf8')) as P0Content;
}

export function cropById(c: P0Content, id: string): Crop | undefined { return c.crops.find(crop => crop.id === id); }
export function cropBySeed(c: P0Content, seed: string): Crop | undefined { return c.crops.find(crop => crop.seed === seed); }
export function fishById(c: P0Content, id: string): Fish | undefined { return c.fish.find(f => f.id === id); }
export function rodById(c: P0Content, id: string): Rod | undefined { return c.fishing.rods.find(r => r.id === id); }
export function recipeById(c: P0Content, id: string): Recipe | undefined { return c.cooking.recipes.find(r => r.id === id); }

/** Bag kind from the id prefix: seed_*, crop_*, fish_*, dish_*, bait_*, fert_*, torch (stacks of 20, §13.1.2), anything else is a material. */
export function itemKind(id: string): string {
  const head = id.split('_')[0];
  return ['seed', 'crop', 'fish', 'dish', 'bait', 'rod', 'fert', 'torch'].includes(head) ? head : 'material';
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
  const ingr = c.materials[id]?.ingr;   // Wild Herb and Rock Salt are seasonings (q(40))
  if (ingr) return { family: ingr[0], rarity: ingr[1] };
  return null;
}

/** Display name for any bag id the P0 content knows. */
export function itemName(c: P0Content, id: string): string {
  const crop = cropById(c, id) ?? cropBySeed(c, id);
  if (crop) return crop.id === id ? crop.name : crop.seed_name;
  const fish = fishById(c, id);
  if (fish) return fish.name;
  if (c.goods[id]) return c.goods[id].name;
  const rod = rodById(c, id);
  if (rod) return rod.name;
  if (c.tools.names[id]) return c.tools.names[id];
  if (c.materials[id]) return c.materials[id].name;
  if (c.drinks.items[id]) return c.drinks.items[id].name;
  if (c.specialty[id]) return c.specialty[id].name;
  if (c.supplies[id]) return c.supplies[id].name;
  const upgrade = c.bag_upgrades.find(u => u.id === id);
  if (upgrade) return upgrade.name;
  if (itemKind(id) === 'dish') {
    const { base } = dishParts(id);
    if (base === c.cooking.mystery.id) return c.cooking.mystery.name;
    return recipeById(c, base)?.name ?? base;
  }
  return id;
}

/** Floor price used by buyback-with-rate and requests (§9.13.1–9.13.2): ⌊sell price × rate⌋; dishes and materials have their own. */
export function sellPriceOf(c: P0Content, id: string): number | null {
  const kind = itemKind(id);
  if (kind === 'crop') return cropById(c, id)?.price ?? null;
  if (kind === 'fish') return fishById(c, id)?.price ?? null;
  if (kind === 'dish') return dishBuyback(c, id);
  if (kind === 'material') return c.materials[id]?.price ?? null;
  return null;
}

/**
 * §7.13.1 / §9.13.1 (q(42)): ⌊Σ ingredient buyback × 0.8⌋, at least 1. An ingredient's buyback is what the
 * Homestead Stall pays: crops and fish at full price, materials at their price; a tag slot counts its cheapest match.
 */
export function dishBuyback(c: P0Content, id: string): number | null {
  const { base } = dishParts(id);
  if (base === c.cooking.mystery.id) return null;
  const recipe = recipeById(c, base);
  if (!recipe) return null;
  const priceOf = (x: string) => cropById(c, x)?.price ?? fishById(c, x)?.price ?? c.materials[x]?.price ?? 0;
  let sum = 0;
  for (const token of recipe.in) {
    const tag = /^([WFOS])(\d)$/.exec(token);
    if (!tag) { sum += priceOf(token); continue; }
    const fits = [...c.crops.filter(cr => cr.ingr[0] === tag[1] && cr.ingr[1] === Number(tag[2])).map(cr => cr.price),
      ...(tag[1] === 'W' ? c.fish.filter(f => f.cook !== false && f.rarity === Number(tag[2])).map(f => f.price) : [])];
    sum += fits.length ? Math.min(...fits) : 0;
  }
  return Math.max(1, Math.floor(sum * 0.8 + 1e-9));
}

/** Rarity of a dish id from its recipe (0 for unknown ids and the Mystery Dish). */
export function dishRarity(c: P0Content, id: string, derive: (r: Recipe) => number): number {
  const recipe = recipeById(c, dishParts(id).base);
  return recipe ? derive(recipe) : 0;
}
