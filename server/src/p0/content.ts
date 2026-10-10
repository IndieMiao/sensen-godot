/** P0 content (assets/p0/p0_content.json), shared with the Godot client. */
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { CityClusters } from './clusters.js';
import { cityPlaces } from './world.js';

export type Skill = 'farming' | 'fishing' | 'cooking';
export const SKILLS: readonly Skill[] = ['farming', 'fishing', 'cooking'];

/** Ingredient family (§7.3.1): Water, Field, Orchard, Seasoning. */
export type Family = 'W' | 'F' | 'O' | 'S';

export interface Crop {
  id: string; name: string; seed: string; seed_name: string;
  tier: number; energy: number; level: number; gate: number;
  seed_price: number; grow_h: number; yield: number; price: number; xp: number; first_xp: number;
  ingr: [Family, number];
  /** P1 (content/farm_crops.json, §5.2.3): where the seed is sold; a regional crop's climate zone (`Temperate`, as
   * profile.climate), its open-field time away from that zone, and how many of its seeds one player may buy a day. */
  sold_at?: 'stall' | 'market'; regional?: boolean; zone?: string; off_zone_grow_h?: number; seed_daily?: number;
}

export interface Fish {
  id: string; name: string; rarity: number; level: number; price: number; cook?: boolean; where: string[];
  // P1 (§6.2.1, SGODOT-283): a time multiplier per window or a window it only bites in, weather multipliers, and the
  // regional fish's climates (fishing_world.ts reads them)
  time?: Partial<Record<'dawn_dusk' | 'night', number>> | 'night_only' | 'dawn_dusk_only';
  weather?: Partial<Record<'sun' | 'rain' | 'wind', number>>;
  regional?: boolean; zones?: string[];
}
/** loss_mult: the minigame's out-of-band loss (Carbon Rod 0.9, §6.5.2); bite_spread_ms: the bite wait's random span
 * (Carbon Rod 1800 instead of fishing.bite_spread_ms). */
export interface Rod { id: string; name: string; reach: number; level: number; price: number; hook_bonus_ms: number; band_bonus: number; loss_mult?: number; bite_spread_ms?: number }
/** A fishing template (Pond / River / Coast). Its fish come from the fish table by habitat (fishing_world.ts poolAt),
 * not from a list here (SGODOT-283). */
export interface FishSite { name: string; template: string; weights: number[] }
/** A pond on the map (assets/p0/p0_ponds.json id): its fishing template follows the point, not its shape (q(36)). */
export interface FishPlace { name: string; site: string; city: string; cluster?: string; beginner?: boolean; at?: [number, number] }   // at: the pond list's point; cluster: SGODOT-280
/** An outpost on the P0 map (assets/p0/p0_outposts.json, SGODOT-227): its role and the residents who live there. */
export interface OutpostDef { id: string; role: string; residents: string[]; cluster?: string }

export interface CookTier {
  energy: number; ms: number; heats: number[]; gold: number; spin_ms: number;
  first_xp: number; xp: number; level: number; bonus: number[];
}
/** How a page can be learned, for the Hidden page's corner (§7.5.1): start = known from the start, gift = a level-up
 * recipe card, experiment, card = a stall recipe card, market = a Market card, taught = a resident, buy = bought. */
export type Learn = 'start' | 'gift' | 'experiment' | 'card' | 'market' | 'taught' | 'buy';
/** Cooking conveniences in P0 (§4.6.3, q(38)). */
export type Convenience = 'cook_again' | 'clue_double' | 'hearty_mishap' | 'steady_hand_1' | 'queue_two' | 'quick_fire'
  // P1 (SGODOT-282, §4.6.3 Lv7–10)
  | 'steady_hand_2' | 'fast_mastery' | 'cook_all' | 'provisions_plus' | 'chefs_touch' | 'title_chef' | 'lucky_double';
/** A P0 Cookbook page that can be cooked (§7.14.0); n = its page number in the 48-page Cookbook. */
export interface Recipe {
  n?: number; id: string; name: string; in: string[]; known?: boolean; style?: string; learn?: Learn[];
  // P1 (SGODOT-282, Li Bai's 48 pages): rarity as the plan's table (used when an ingredient is not in this build);
  // families = each slot's family for the silhouette; cookable: false = buy-only (#9 Travel Biscuits).
  rarity?: number; families?: string[]; cookable?: boolean; buy?: { at: string; price: number; daily: number };
  card_price?: number; card_zone?: string; card_zones?: string[];   // recipe cards (§7.16.1): Market climate / Stall home climates
  teach?: string[]; buff?: string; regional?: boolean;              // residents who teach it (§7.16.3); Legendary Buff (P3)
  no_gift?: boolean; no_request?: boolean; no_buyback?: boolean;
}
/** A page outside P0 (§7.14.1–7.14.4): only its silhouette shows, slots = the family of each slot. */
export interface SilhouettePage { n: number; id: string; name: string; rarity: number; slots: string[]; style: string; learn: Learn[] }

export type ShopId = 'homestead' | 'tackle' | 'market' | 'tea' | 'post';
export const SHOPS: readonly ShopId[] = ['homestead', 'tackle', 'market', 'tea', 'post'];
export type QuotaId = 'fish_tackle' | 'dish' | 'material' | 'request_bonus' | 'sys_requests';
export type BoardId = 'stall' | 'market';

/**
 * What a request asks for: a kind, optionally narrowed to one id, one rarity, a dish style or styles (§9.6.3 P1: `Soup`
 * for Granny Wu, Grilled or Dessert for Packed Lunches), a crop family (`O` for the Orchard Basket), the same item or N
 * distinct items.
 */
export interface Need {
  kind: 'crop' | 'fish' | 'dish' | 'material' | 'sow' | 'visit'; id?: string; rarity?: number; style?: string | string[];
  family?: Family; same?: boolean; distinct?: number;
  /** §9.6.3 regional templates: the home climate's regional items (zone), the home city's 2 regional fish (city), or
   * regional items of another climate (other_zone). One such item is drawn; max_rarity caps it (Local Flavor: Fine). */
  regional?: 'zone' | 'city' | 'other_zone'; max_rarity?: number;
  /** §9.6.3 explore templates (kind visit): check in at another outpost of the home city than the board's own (Stamp Run). */
  visit?: { role?: string; where: 'same_city' };
}
/**
 * A system request template (§9.6.3). climate narrows it to the home climate (regional templates, `Temperate`);
 * type is the card's family (output by default; regional / explore / together wait for travel, so they ship disabled).
 */
export interface RequestTemplate {
  title: string; need: Need; skill: Skill; gate: [Skill | 'homestead', number][]; bonus: number; enabled?: boolean;
  climate?: string[]; type?: 'output' | 'regional' | 'explore' | 'together'; text?: string;
  /** Quantity × scale, rounded up (李白's Wholesale Order and Fish Market Crate: 1.5). */
  scale?: number;
}
/** A personal request's one-time reward beyond coins and +5 (§9.6.1, Trusted story requests): an item, a recipe page Tasted, a title. */
export interface ResidentReward { item?: [string, number]; recipe?: string; title?: string }
export interface ResidentRequest {
  id: string; title: string; text: string; stage: string; need: Need; qty: number; coins: number;
  /** The request card's need line when the rule alone would mislead (q(46): the only P0 Rare fish is the Pond koi). */
  need_line?: string;
  reward?: ResidentReward;
}
/** §13.2 gathering spot (SGODOT-231): the first yield is the spot's material (Farm Storage, +1 with gloves). */
export interface GatherSpot { name: string; yield: [string, number][]; homestead: number }
/** §13.3.3 one mine floor: weighted extra drop per rock (null = nothing extra), its rock count (default mine.rocks; floor 5
 * has none) and its monsters by id (§13.3.4, SGODOT-275). */
export interface MineFloorDef { floor: number; drops: [string | null, number][]; rocks?: number; mobs?: string[] }
/** §13.3.4 a mine monster: loot as [item, qty, weight]; once_a_day = an item it gives a player at most once a player day. */
export interface MineMonster { name: string; hp: number; damage: number; loot: [string, number, number][]; once_a_day?: string }
/** §13.4 workbench recipe: out goes to the bag, Gear (equipped) or the owned list (passive tools). */
export interface WorkbenchRecipe {
  id: string; tab: string; out: string; qty: number; to: 'bag' | 'gear' | 'owned' | 'field';
  cost: [string, number][]; gate?: [Skill, number];
  facility?: string;   // to: field (P1, SGODOT-239): the facility it builds in place (place command), never crafted
}
/** P1 step 1 (q(59) §1.4): a facility on one plot; a sprinkler waters the ring of 8 around it and cuts ripening. */
export interface FacilityDef { name: string; cover: 'ring8'; grow_cut: number }

export interface ResidentDef {
  name: string; role: string; portrait: string; likes: string; gift_meal: string; one_per_day: boolean;
  lines: Record<string, string>; requests: ResidentRequest[];
  /** §7.5.3 / §7.16.3: the pages this resident teaches from Familiar, one a week; empty = none of their style yet. */
  teaches?: string[];
}

export interface P0Content {
  outposts?: OutpostDef[];   // loaded from p0_outposts.json beside the table (loadP0Content)
  version: string;
  energy: { max_base: number; regen_ms: number; bonus_zone: number; rest_amount: number; rest_away_h: number };
  day: { utc_offset_hours: number; rollover_hour: number };   // the offset is the fallback when profile.timezone is absent
  start: { coins: number; tilled_plots: number; wild_plots: number; bag: [string, number][] };
  bag: { capacity: number; stack: Record<string, number> };
  skills: Record<Skill, number[]>;
  level_up_energy: { first: number; later: number };
  level_gifts: Record<string, [string, number][]>;
  xp_multiplier: [number, number][];
  skill_daily_cap: number;                    // §4.3.4: XP per skill per player day, an anti-script limit only
  crops: Crop[];
  stall: { keeper: { role: string; name: string }; buy: string[] };
  rarity_names: string[];
  fish: Fish[];
  fishing: {
    cast_energy: number; refund_fail: number; protect_max_level: number; protect_fails: number;
    bite_min_ms: number; bite_spread_ms: number; hook_window_ms: number; stale_ms: number;
    catch_xp: number[]; first_xp: number[]; first_cast_xp: number; first_landed_xp: number; first_city_xp: number;
    rods: Rod[];
    sites: Record<string, FishSite>;      // templates: pond (Pond) / river (River) / coast (Coast, P1)
    places: Record<string, FishPlace>;
    baits: Record<string, { shift: number[]; wait: number; regional_mult?: number }>;   // regional_mult: Spinner Lure 2 (§6.4.2)
  };
  goods: Record<string, { name: string; price: number; skill: Skill; gate: number; daily: number; grow_mult?: number }>;
  blessing: { days: number; regen_mult: number; food_bonus: number };
  tackle: { keeper: { role: string; name: string }; buy: string[] };
  tools: {
    farming: string; fishing: string; mining: string; combat: string; names: Record<string, string>;
    row_hoe: { id: string; price: number; skill: Skill; gate: number; sow: number };
  };
  materials: Record<string, { name: string; price: number | null; floor?: number; ingr?: [Family, number] }>;   // ingr: seasonings (§7.3.1); floor: a request's price for one with no buyback (quartz, hardwood)
  wallet_floor: number;                       // §8.1.1 / q(32): every coin spend except seeds keeps this much
  homestead: {
    max_level: number;
    warming_cabinet: number;                  // portions once unlocked (Lv3, §7.7)
    // P1 (SGODOT-282, §7.7 / §8.3.2): kitchen facilities by Homestead level, each [from level, value] ascending.
    stoves?: [number, number][];              // stoves in the kitchen: Lv1 1, Lv4 2, Lv8 3 (absent = 1)
    warming_cabinet_by_level?: [number, number][];   // Warming Cabinet portions: Lv3 6, Lv8 12 (absent = warming_cabinet)
    chefs_sign_gold?: number;                 // Chef's Sign (Lv10): every dish's gold zone + this (0.05 = 5 points)
    plots?: [number, number][];               // plots the homestead has: Lv1 30, Lv3 40 (P1 q(59) §1.1; absent = P0's start)
    sprinkler_max?: { base: number; per_level: number; max: number };   // sprinklers that may stand: 3 + level, at most max
    // Barter (§8.4.5, SGODOT-282): at the Market Square keeper, `give` of this climate's regional crops or fish for 1
    // mineral; a mineral at most `level_share` of the next level's need by barter; at most `daily` a day.
    barter?: { give: number; minerals: string[]; level_share: number; daily: number; items: Record<string, string[]> };   // items: climate → ids
    per_level: { energy: number; meals: number };
    board_slots: [number, number][];          // [from Homestead level, Stall Board slots]
    levels: { level: number; coins: number; skills: number; materials: [string, number][]; unlocks: string[] }[];
  };
  bag_upgrades: { id: string; name: string; homestead: number; price: number; materials: [string, number][]; capacity: number; requires?: string }[];   // requires: the tier before (II after I)
  drinks: { energy: number; prices: number[]; daily: number; items: Record<string, { name: string; shop: ShopId }> };
  specialty: Record<string, { name: string; price: number; shop: ShopId; to: 'storage' }>;
  shops: Record<ShopId, { sells: string; buys: Record<string, { rate: number; quota: QuotaId | null }> }>;
  market: { buy: string[]; specialty: string[] };
  quotas: Record<QuotaId, { cap: number; scope: string }>;
  affinity: {
    stages: [string, number][]; first_chat: number; request: number; gift_meal_stage: string;
    /** §7.5.3 Taught: from this stage, every `every_days` days, one page the player has not got yet. */
    lesson?: { stage: string; every_days: number };
    /** §9.6.1: a resident's next request opens this long after the last one is done (24 h; P0's one_per_day = the player day). */
    next_request_h?: number;
    gift: { loved_fine: number; liked: number; any: number; perfect: number; cap: number; mystery: number; chef_touch: { cooking: number; bonus: number; cap: number } };
    mystery_line: string;
  };
  residents: Record<string, ResidentDef>;
  /** P0 has no nickname or city choice yet: what the Profile page shows (SGODOT-225). */
  profile: { name: string; city: string; climate: string; farm_name: string; farm_at?: [number, number]; timezone?: string };   // timezone: IANA, for the 04:00 rollover (SGODOT-270)
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
    mystery: { id: string; name: string; energy: number; hearty: number };   // hearty: from Cooking Lv3 (Hearty Mishap)
    food_cap: number;
    conveniences: Partial<Record<Convenience, number>>;   // the Cooking level each convenience comes at (q(38)); absent = not in this build
    gold_cap: number; steady_hand_gold: number;  // gold arc share: bonuses stop at gold_cap; Steady Hand I adds steady_hand_gold
    mastered: { cooked: number; gold: number; fast?: number };  // Mastered at `cooked` pots (`fast` with Fast Mastery, Lv7); its gold arc is wider (§7.5.1)
    lucky_double?: number;                        // Lucky Double (Lv10): chance of one more Plain portion (not Legendary, not with Double)
    cook_all_per_page?: number;                   // Cook All (Lv8): at most this many pots of one page (q(4))
    // Cookbook milestones past Home Cook (§7.6.1, SGODOT-282): titles at Discovered / Mastered counts, once each;
    // coins paid, cabinet = Warming Cabinet portions added, decor = the yard piece it gives (placed with Decorate).
    // Recipe cards (§7.16.1, SGODOT-282): a card makes a page Tasted. The Homestead Stall shows `stall_daily` cards a
    // day from `stall` (pages not yet in the Cookbook); Market sells `market` cards of its climate. Prices by rarity.
    cards?: { prices?: Record<string, number>; stall_daily: number };   // the pool and prices are on the recipes (card_price / card_zone / card_zones)
    milestones?: { id: string; title: string; discovered?: number; mastered?: number; coins?: number; cabinet?: number; decor?: string }[];
    quick_fire: number;                          // Quick Fire: cooking time and heat times × this (§4.6.3 Lv6)
    trial_refunds: number;                       // failed pots a day that refund their ingredients in the blessing (§7.5.2)
    recipes: Recipe[];
    pages: SilhouettePage[];   // the other 34 of the 48 pages, not cookable in P0 (q(39))
  };
  /** Consumables made at the workbench, with no shop row (Torch). */
  supplies: Record<string, { name: string }>;
  /** §13.2 (SGODOT-231): spot regrow, anti-script tempo between taps, the gloves and their bonus. */
  gather: { regen_h: number; tempo_ms: number; gloves: string; gloves_bonus: number; spots: Record<string, GatherSpot> };
  /** §13.3 floors 1–5 (SGODOT-231, LOCK-21; 3–5 SGODOT-275). picks: Stone per rock by pickaxe; combat: the mine's HP and the
   * Combat slot's weapons; express_unlock_floor: the floor whose first clear opens Floor 5 · Express for the account. */
  mine: {
    runs_per_day: number; floor_energy: number; rock_energy: number; rocks: number; restart_floor: number; tempo_ms: number;
    floors: MineFloorDef[]; picks: Record<string, { stone: number }>;
    monsters: Record<string, MineMonster>;
    combat: { hp: number; invulnerability_ms: number; weapons: Record<string, { attack: number; speed: number }> };
    express_unlock_floor: number;
  };
  /** §13.4 P0 workbench: Tools / Supplies (SGODOT-231), Facilities from P1. */
  workbench: { tabs: string[]; recipes: WorkbenchRecipe[] };
  /** P1 (SGODOT-239, content/farm_garden.json): plot id → [col, row] on the garden grid; how many of them the homestead has
   * is homestead.plots (the ids past P0's 30 come as wild). */
  garden: { plots: [number, number][] };
  /** P1 (SGODOT-239): facilities by kind; grow_cut_cap caps a facility's cut and Compost's together. */
  facilities: { grow_cut_cap: number; kinds: Record<string, FacilityDef> };
}

export const DEFAULT_P0_CONTENT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../assets/p0/p0_content.json');

/**
 * The content table, plus the map data the map markers read (SGODOT-232, q(48)) from their own files beside it:
 * outpost ids, roles and residents from the outpost table (assets/p0/p0_outposts.json, SGODOT-227) and each pond's
 * point from P0's pond list (assets/p0/p0_ponds.json, SGODOT-270: the San Francisco points Journey's server serves,
 * the client registers the same file). Either file missing leaves that part out.
 */
export function loadP0Content(file = DEFAULT_P0_CONTENT): P0Content {
  const c = JSON.parse(readFileSync(file, 'utf8')) as P0Content;
  const dir = path.dirname(file);
  mergeContentDir(c as unknown as Record<string, unknown>, path.join(dir, 'content'));
  const outposts = path.join(dir, 'p0_outposts.json');
  if (existsSync(outposts)) {
    c.outposts = (JSON.parse(readFileSync(outposts, 'utf8')).outposts as { id: string; role: string; residents?: string[]; cluster?: string }[])
      .map(o => ({ id: o.id, role: o.role, residents: o.residents ?? [], ...(o.cluster ? { cluster: o.cluster } : {}) }));
  }
  // v5 (SGODOT-278): the frozen city clusters beside the content (亚瑟's build_clusters.mjs), with the server's member table.
  const clusters = path.join(dir, 'city_clusters.json');
  // Not enumerable: a structuredClone of the content (tests) leaves it out instead of copying a class without methods.
  if (existsSync(clusters)) Object.defineProperty(c, 'clusters', { value: CityClusters.load(clusters), enumerable: false, writable: true, configurable: true });
  // SGODOT-280: generated cities for travel.ts cityInfo (GET /v1/p0/city/:cluster). Not enumerable, like clusters.
  Object.defineProperty(c, 'cityPlaces', { value: (id: string) => cityPlaces(c, id), enumerable: false, writable: true, configurable: true });
  const ponds = path.join(dir, 'p0_ponds.json');
  if (existsSync(ponds)) {
    for (const l of JSON.parse(readFileSync(ponds, 'utf8')).locations as { id: string; lat: number; lng: number }[]) {
      const place = c.fishing.places[l.id];
      if (place) place.at = [l.lat, l.lng];
    }
  }
  return c;
}

/**
 * Content fragments (SGODOT-275, 亚瑟's cross-city plan §6): from P1 on each line adds its data in its own file,
 * assets/p0/content/<line>_<topic>.json, shaped like the main table (the same top-level keys). The files are merged
 * in name order into the main table, never over it: objects merge key by key, arrays of objects with an `id` append
 * by id; a key, an id or a scalar that is already there is an error naming the file and the path. So two lines can
 * never change the same entry, and a clash shows up in the tests rather than as one line's data silently winning.
 * Keys starting with `_` (a fragment's own `_note`) are skipped. The Godot client merges the same way (P0Logic).
 */
export const CONTENT_FRAGMENT = /^[a-z][a-z0-9]*(_[a-z0-9]+)*\.json$/;

export function mergeContentDir(base: Record<string, unknown>, dir: string): string[] {
  if (!existsSync(dir)) return [];
  const files = readdirSync(dir).filter(f => f.endsWith('.json')).sort();
  for (const f of files) {
    if (!CONTENT_FRAGMENT.test(f)) throw new Error(`p0 content: ${f}: name must be <line>_<topic>.json in lower case`);
    mergeContent(base, JSON.parse(readFileSync(path.join(dir, f), 'utf8')) as Record<string, unknown>, f);
  }
  return files;
}

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v);
const withId = (v: unknown): v is { id: string } => isObject(v) && typeof v.id === 'string';

export function mergeContent(base: Record<string, unknown>, add: Record<string, unknown>, file: string, at = ''): void {
  for (const [k, v] of Object.entries(add)) {
    if (at === '' && k.startsWith('_')) continue;
    const where = at === '' ? k : `${at}.${k}`;
    if (!(k in base)) { base[k] = v; continue; }
    const have = base[k];
    if (isObject(have) && isObject(v)) { mergeContent(have, v, file, where); continue; }
    if (Array.isArray(have) && Array.isArray(v) && have.every(withId) && v.every(withId)) {
      const ids = new Set(have.map(e => e.id));
      for (const e of v) {
        if (ids.has(e.id)) throw new Error(`p0 content: ${file}: ${where} already has id ${e.id}`);
        ids.add(e.id);
        have.push(e);
      }
      continue;
    }
    throw new Error(`p0 content: ${file}: ${where} is already set (fragments add, they never change an entry)`);
  }
}

export function cropById(c: P0Content, id: string): Crop | undefined { return c.crops.find(crop => crop.id === id); }
export function cropBySeed(c: P0Content, seed: string): Crop | undefined { return c.crops.find(crop => crop.seed === seed); }
export function fishById(c: P0Content, id: string): Fish | undefined { return c.fish.find(f => f.id === id); }
export function rodById(c: P0Content, id: string): Rod | undefined { return c.fishing.rods.find(r => r.id === id); }
export function recipeById(c: P0Content, id: string): Recipe | undefined { return c.cooking.recipes.find(r => r.id === id); }

/** Bag kind from the id prefix: seed_*, crop_*, fish_*, dish_*, bait_*, fert_*, torch (stacks of 20, §13.1.2), anything else is a material. */
export function itemKind(id: string): string {
  const head = id.split('_')[0];
  return ['seed', 'crop', 'fish', 'dish', 'bait', 'rod', 'fert', 'torch', 'trap'].includes(head) ? head : 'material';   // trap_fish: P1
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
  const decor = (c as { decor?: { items: Record<string, { name: string }> } }).decor?.items[id];   // Decorate (SGODOT-284)
  if (decor) return decor.name;
  if (c.supplies[id]) return c.supplies[id].name;
  if (id.startsWith('facility_') && c.facilities?.kinds[id.slice(9)]) return c.facilities.kinds[id.slice(9)].name;
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
