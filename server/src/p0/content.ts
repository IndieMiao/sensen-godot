/** P0 content (assets/p0/p0_content.json), shared with the Godot client. */
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { CityClusters } from './clusters.js';
import { cityPlaces, worldOf } from './world.js';
import type { LevelCap } from './homestead.js';

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
  /** A tree (§5.2.4): grow_h is its first ripening; then regrow_h after each pick, picked for harvest_energy. */
  perennial?: { plant: string; plant_name: string; regrow_h: number; harvest_energy: number; harvest_xp: number; footprint: [number, number] };
  /** A teaching seed's plot crop (quickCrop): it ripens a fixed time after it starts growing and is harvested as `harvest`. */
  quick?: { ms: number; harvest: string };
  /** q(245): plot-only adapter for fast_crops[], never a cooking/request crop. */
  fast?: true;
}

/** A teaching seed (q(217), content/farm_quick_seeds.json): Quick Radish Seeds, sown for `energy`, ripe grow_s after it
 * starts growing, harvested as `harvest` (a crop of crops[]). Kept out of crops[]: what walks the crops never sees it. */
export interface QuickSeed { id: string; name: string; seed: string; seed_name: string; energy: number; grow_s: number; harvest: string }

/** q(245), §5.2.7: own harvest, fixed duration, outside crops[]. */
export interface FastCrop {
  id: string; name: string; seed: string; seed_name: string; farming: number; grow_s: number;
  seed_price: number; price: number; energy: number; xp: number; first_xp: number;
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
export interface OutpostDef { id: string; role: string; name?: string; residents: string[]; cluster?: string; lat?: number; lng?: number;   // name: SGODOT-341's Today line
  keeper?: { name: string; role: string } }   // the hand-written keeper (Finn · Tackle Keeper), who gives local requests (q(272))

/** A Homestead look stage (LOOK-PICK, SGODOT-282): picked at `level`, a (timber) or b (stone). */
export interface HomesteadLook { id: string; level: number; name: string; a: string; b: string }

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
  | 'steady_hand_2' | 'fast_mastery' | 'batch_cook' | 'provisions_plus' | 'chefs_touch' | 'title_chef' | 'lucky_double';
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
// q(251): the Tackle Shop's fish_tackle (80) and the Market's regional_market (60) are gone: those two take only crops and fish
export type QuotaId = 'dish' | 'material' | 'request_bonus' | 'sys_requests';
export type BoardId = 'stall' | 'market';

/**
 * What a request asks for: a kind, optionally narrowed to one id, one rarity, a dish style or styles (§9.6.3 P1: `Soup`
 * for Granny Wu, Grilled or Dessert for Packed Lunches), a crop family (`O` for the Orchard Basket), the same item or N
 * distinct items.
 */
export interface Need {
  kind: 'crop' | 'fish' | 'dish' | 'material' | 'sow' | 'harvest' | 'visit'; id?: string; rarity?: number; style?: string | string[];
  family?: Family; same?: boolean; distinct?: number;
  /** §9.6.3 regional templates: the home climate's regional items (zone), the home city's 2 regional fish (city), or
   * regional items of another climate (other_zone). One such item is drawn; max_rarity caps it (Local Flavor: Fine). */
  regional?: 'zone' | 'city' | 'other_zone'; max_rarity?: number;
  /** §9.6.3 explore templates (kind visit): check in at another outpost of the home city than the board's own (Stamp Run);
   * or, cross-city (q(128), SGODOT-284), at the first `role` outpost (a small city's Trading Post) of a city of one of
   * the `trip` tiers (Tea Trail 1–2, Postcard Trip 2–3), or of the nearest city in another climate zone (New Climate). */
  visit?: { role?: 'market' | 'tea'; where: 'same_city' | 'other_city' | 'other_zone'; trip?: [number, number] };
  /** Far Pond (q(128)): fish the home city's ponds don't have, wherever they were caught (boards.ts farFish). */
  where?: 'not_home';
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
  /** q(270) ②: drawn on the home city's Market Board only — a template that picks its city or its items by distance from
   * home (Far Pond, Tea Trail, Postcard Trip, New Climate; Visitor's Catch and Seeds from Afar, out of home's zone). */
  home_only?: boolean;
}
/** A personal request's one-time reward beyond coins and +5 (§9.6.1, Trusted story requests): an item, a recipe page Tasted, a title. */
export interface ResidentReward { item?: [string, number]; recipe?: string; title?: string }
export interface ResidentRequest {
  id: string; title: string; text: string; stage: string; need: Need; qty: number; coins: number;
  /** The request card's need line when the rule alone would mislead (q(46): the only P0 Rare fish is the Pond koi). */
  need_line?: string;
  reward?: ResidentReward;
  /** q(218): what the resident says on the open bar once it is handed in (the client fills `{pond}`, the home's beginner pond). */
  thanks?: string;
}
/** 355 E: per-type floor bands, special floors and the site facts supplied by C. */
export interface MineBand {
  from: number; to: number; mobs: [string, number, number][]; rocks: [number, number]; drops: [string | null, number][];
}
export interface MineFloorOverride { add?: [string, number, number][]; elite?: string; only?: string[]; guard?: string; hp_mult?: number }
export interface MineSite {
  id: string; type: string; name: string; near: string; open?: boolean;
  mine: { floors: number; main: string | null; main_from: number; side: string | number | null; open_to: number | null };
}
export interface MineWeapon { name: string; attack: number; speed: number; tier: number }
/** §13.3.4 a mine monster: loot as [item, qty, weight]; once_a_day = an item it gives a player at most once a player day. */
export interface MineMonster {
  name: string; hp: number; damage: number; loot?: [string | null, number, number][]; once_a_day?: string;
  elite?: boolean; guard?: boolean; tier?: number; stun_mult?: number; first?: [string, number][]; pack?: [string, number];
}
/** §13.4 workbench recipe: out goes to the bag, Gear (equipped) or the owned list (passive tools); 355 G: a weapon
 * into the weapon slot (contract-efg §9.3, the Iron Sword). */
export interface WorkbenchRecipe {
  id: string; tab: string; out: string; qty: number; to: 'bag' | 'gear' | 'owned' | 'field' | 'weapon';
  cost: [string, number][]; gate?: [Skill, number];
  homestead?: number;  // 355 G: the Homestead level it opens at (Iron Sword Lv8), as a shop offer's; `gate` stays a skill's
  facility?: string;   // to: field (P1, SGODOT-239): the facility it builds in place (place command), never crafted
  coins?: number;      // coins paid as it is placed or crafted, on top of the materials (greenhouse 300, §5.7; Iron Sword 150; the 40 floor kept)
}
/** P1 step 1 (q(59) §1.4): a facility on one plot; a sprinkler waters the ring of 8 around it and cuts ripening. */
export interface FacilityDef {
  name: string; cover: 'ring8' | 'block' | 'yard'; grow_cut: number;   // yard: on a yard cell, never a plot (Compost Bin)
  start?: [number, number]; start_span?: number;   // a yard facility's first cell: nearest this (the workbench, its 3 cells: span 1)
  daily?: number;                          // Compost Bin: crops a player day it turns into Compost (q(118) ③, 5)
  size?: [number, number];                 // block: the plots it roofs (greenhouse 4 × 4, q(118) ②)
  cap_by_farming?: [number, number][];     // how many may stand by Farming level (greenhouse: Lv8 1, Lv10 2)
}

export interface ResidentDef {
  name: string; role: string; portrait: string; likes: string; gift_meal: string; one_per_day: boolean;
  lines: Record<string, string>; requests: ResidentRequest[];
  /** q(218): teaching requests before `requests`, only for a guided save that has not started the line (residents.ts
   * introOn); kept out of `requests` so its indexes (ResidentState.next) never move. */
  intro_requests?: ResidentRequest[];
  /** §7.5.3 / §7.16.3: the pages this resident teaches from Familiar, one a week; empty = none of their style yet. */
  teaches?: string[];
}

/** An ops event at a place (§9.3.3, content/map_events.json): its pin wears the purple ★ while it is lit (markers.ts). */
export interface EventVenue {
  id: string;
  place: string;   // a pond or outpost id, as the map markers' places
  name: string;
  starts: string;   // ISO 8601, UTC
  ends: string;
}

export interface P0Content {
  outposts?: OutpostDef[];   // loaded from p0_outposts.json beside the table (loadP0Content)
  event_venues?: EventVenue[];   // §9.3.3, content/map_events.json: empty in the prototype (only the field is kept)
  version: string;
  energy: { max_base: number; regen_ms: number; bonus_zone: number; rest_amount: number };
  day: { utc_offset_hours: number; rollover_hour: number };   // the offset is the fallback when profile.timezone is absent
  start: { coins: number; tilled_plots: number; wild_plots: number; bag: [string, number][]; guide_bag?: [string, number][] };   // guide_bag: q(217), a guided save's first stacks
  bag: { capacity: number; stack: Record<string, number> };
  skills: Record<Skill, number[]>;
  level_up_energy: { first: number; later: number };
  level_gifts: Record<string, [string, number][]>;
  xp_multiplier: [number, number][];
  skill_daily_cap: number;                    // §4.3.4: XP per skill per player day, an anti-script limit only
  crops: Crop[];
  quick_seeds?: QuickSeed[];                  // q(217) teaching seeds (quickCrop), not crops
  fast_crops?: FastCrop[];                    // q(245), merged from farm_fast_crops.json, never crops[]
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
    creel?: { level: number; stack: number };   // P1 (content/fishing_p1.json): from this Fishing level a fish slot holds `stack` (§4.6.2 Lv10: 10 → 15)
    quick_recast?: { level: number; wait: number };   // P1 (content/fishing_p1.json): §4.6.2 Lv9 — after a landed fish, the next cast at that pond waits ×wait
  };
  goods: Record<string, { name: string; price: number; skill: Skill; gate: number; daily: number; grow_mult?: number;
    regrow_mult?: number; shop?: 'market' }>;   // P1: Orchard Feed halves a tree's regrowth; shop: sold at the Market
  blessing: { days: number; regen_mult: number; food_bonus: number };
  tackle: { keeper: { role: string; name: string }; buy: string[] };
  tools: {
    farming: string; fishing: string; mining: string; names: Record<string, string>;
    row_hoe: { id: string; price: number; skill: Skill; gate: number; sow: number };
  };
  materials: Record<string, { name: string; price: number | null; floor?: number; ingr?: [Family, number] }>;   // ingr: seasonings (§7.3.1); floor: a request's price for one with no buyback (quartz, hardwood)
  wallet_floor: number;                       // §8.1.1 / q(32): every coin spend except seeds keeps this much
  /** Travel line data (content/travel_p2.json, SGODOT-275): landmark stamps by cluster (plan §11.9.3 表 11-18) and the
   * display names of clusters whose seed city is not the one players look for (none at present: San Diego, once gn-3981609's, is a cluster of its own, SGODOT-280). */
  travel?: { landmarks?: Record<string, { landmark: string; stamp: string }>; cluster_names?: Record<string, string>; closed_countries?: string[];
    country_names?: Record<string, string>; city_only_countries?: string[]; city_only_clusters?: string[];   // q(210), q(211)
    fares?: { energy: number[]; coins: number[] } };   // q(256) §11.2.1: a first visit's Energy and coins by Trip 1–7 (index 0 = Trip 1)
  homestead: {
    max_level: number;
    warming_cabinet: number;                  // portions once unlocked (Lv3, §7.7)
    // P1 (SGODOT-282, §7.7 / §8.3.2): kitchen facilities by Homestead level, each [from level, value] ascending.
    stoves?: [number, number][];              // stoves in the kitchen: Lv1 1, Lv4 2, Lv8 3 (absent = 1)
    warming_cabinet_by_level?: [number, number][];   // Warming Cabinet portions: Lv3 6, Lv8 12 (absent = warming_cabinet)
    chefs_sign_gold?: number;                 // Chef's Sign (Lv10): every dish's gold zone + this (0.05 = 5 points)
    plots?: [number, number][];               // beds the homestead has by level: Lv1 8 … Lv17 41 (355 grid; absent = P0's start)
    perennial_slots?: LevelCap;   // trees that may stand: 1 + level, at most 8, 10 from Lv14 (v4q(1) ⑧)
    sprinkler_max?: LevelCap;     // sprinklers that may stand: 3 + level, at most 10, 12 from Lv14
    energy_steps: [number, number][];         // v4q(1) ⑦: the Energy pool and meal cap, [from level, + a level]: [[2, 10], [11, 5]]
    board_slots: [number, number][];          // [from Homestead level, Stall Board slots]
    // v4q(1): each skill's own gate (farming / fishing / cooking, absent = none), the travel gate from Lv16 (city stamps,
    // other climate bands), and the Energy a level gives back — a number, always (Lv2–15 50, Lv16 on 0)
    levels: { level: number; coins: number; skills: Partial<Record<'farming' | 'fishing' | 'cooking', number>>; travel?: { stamps: number; climates: number };
      materials: [string, number][]; unlocks: string[]; energy: number }[];
    /** Looks (content/homestead_looks.json, §8.3.1, q(112)): a stage per look level, its id the level's unlock id. */
    looks?: HomesteadLook[];
  };
  bag_upgrades: { id: string; name: string; homestead: number; price: number; materials: [string, number][]; capacity: number; requires?: string }[];   // requires: the tier before (II after I)
  drinks: { energy: number; prices: number[]; daily: number; items: Record<string, { name: string; shop: ShopId }> };
  specialty: Record<string, { name: string; price: number; shop: ShopId; to: 'storage'; cluster?: string }>;
  city_postcard?: { price: number };   // SGODOT-296: every M-tier-and-up city's postcard (cityPostcard)
  /** A counter's buy-back by item kind; regional: only the regional items of the counter's own climate (§9.13.1: the
   * Market Square takes its climate's regional crops and fish). The rate is the counter's at home; away from home it is
   * times sell_distance's (q(251)). */
  shops: Record<ShopId, { sells: string; buys: Record<string, { rate: number; quota: QuotaId | null; regional?: boolean }> }>;
  /** q(251): what a counter pays by how far it is from home — 1 at home (the home cluster), else by the Trip band of
   * the counter's city (tripOf: Trip 1–7, index trip − 1). Unit = max(1, ⌊full price × rate × this⌋). */
  sell_distance: { home: number; trip: number[] };
  market: { buy: string[]; specialty: string[] };
  // by_homestead (q(272) ⑩): [from Homestead level, cap] rows, the last one reached wins over cap (request_bonus)
  quotas: Record<QuotaId, { cap: number; scope: string; per_city?: boolean; by_homestead?: [number, number][] }>;   // per_city: one count per account × city cluster (§11.7.3)
  affinity: {
    stages: [string, number][]; first_chat: number; request: number; gift_meal_stage: string;
    /** §7.5.3 Taught: from this stage, every `every_days` days, one page the player has not got yet. */
    lesson?: { stage: string; every_days: number };
    /** §9.6.1: a resident's next request opens this long after the last one is done (24 h; P0's one_per_day = the player day). */
    next_request_h?: number;
    /** q(171): what first reaching Kindred gives, `{name}` the resident's — `Postcard from Pip` into the Passport (its text
     * their Kindred line) and the title `Pip's Best Friend`. */
    kindred?: { postcard: string; title: string };
    gift: { loved_fine: number; liked: number; any: number; perfect: number; cap: number; mystery: number; chef_touch: { cooking: number; bonus: number; cap: number };
      first: number };   // q(220): a resident's first dish from you
    mystery_line: string;
  };
  residents: Record<string, ResidentDef>;
  /** SGODOT-341: the new-player guide's step table (content/guide_steps.json; empty until 339's §14 v3). */
  guide?: import('./guide.js').GuideContent;
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
    /** q(272): local requests from the keepers of a city away from home (content/requests_local.json); none without it. */
    local?: { per_day: number; prune_days: number; roles: Record<string, string[]> };
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
    // q(288) (SGODOT-419): every ring differs. width_mul: each ring's width is the pot's × a draw in it, at most gold_cap;
    // drift: the ring turns against the needle, °/s; lead_ms: the gold starts no sooner than this after the needle sets
    // off; end: it ends by this share of the ring; pair_min_deg / pair_opposite_deg: two rings' gold centres at least
    // this far apart and not within this of opposite. Absent: rings as before (the teaching pot never has it).
    heat_vary?: { width_mul: [number, number]; drift: number; lead_ms: number; end: number; pair_min_deg: number; pair_opposite_deg: number };
    mastered: { cooked: number; gold: number; fast?: number };  // Mastered at `cooked` pots (`fast` with Fast Mastery, Lv7); its gold arc is wider (§7.5.1)
    lucky_double?: number;                        // Lucky Double (Lv10): chance of one more Plain portion (not Legendary, not with Double)
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
  /** The anti-script tempo between gathering taps (a city's points, v4q(4); the farm's spots left with v4q(4) ①). */
  gather: { tempo_ms: number };
  /** 355 E/F: all provisional economy and combat values live in the three non-overlapping mine fragments. */
  mine: {
    floor_energy: number; rock_energy: number; fee_per_day: boolean; picks: Record<string, { stone: number }>;
    monsters: Record<string, MineMonster>;
    /** q(291): ko_hp — HP a knock-out leaves; regen_full_ms — outside the mine, 0 to full in this long (whole points). */
    combat: { hp: number; invulnerability_ms: number; ko_keep_from: number; ko_lose: number; under_tier: number;
      ko_hp: number; regen_full_ms: number; weapons: Record<string, MineWeapon> };
    types: Record<string, { bands: MineBand[]; floors: Record<string, MineFloorOverride>;
      main_weight?: [number, number][]; gate?: { homestead: number } }>;
    dev_sites?: MineSite[];
    potions: Record<string, { name: string; price: number; stock: number; sold_at: string; gate: { homestead: number };
      heal: number | 'full'; floors: 'any' | number[]; cooldown_ms: number }>;
    /** tempo_burst (preview B, 奕星 11-05): how many swings or rocks may come ahead of their tempo (mine.ts tempoWait);
     * absent = none, each one its full interval after the last. */
    rules: { rock_tempo_ms: number; attack_tempo_factor: number; max_targets: number; guard_fast_factor: number; tempo_burst?: number };
    /** 355 G (contract-efg §9.2): Pip's First Dig, its own slot beside the request line; lines.pip_vein is Pip's one
     * line toward the iron vein (v4q(9) ②), `%s` the vein's name filled in by the client. Absent = not in this build. */
    first_dig?: { giver: string; floor: number; gate: { homestead: number }; reward: { weapon?: string; affinity?: number };
      lines?: Record<string, string> };
  };
  /** §13.4 P0 workbench: Tools / Supplies (SGODOT-231), Facilities from P1. */
  workbench: { tabs: string[]; recipes: WorkbenchRecipe[] };
  /** P1 (SGODOT-239, content/farm_garden.json): plot id → [col, row] on the garden grid; how many of them the homestead has
   * is homestead.plots (the ids past P0's 30 come as wild). */
  garden: { plots: [number, number][]; origin?: [number, number]; pitch?: number };   // origin / pitch: a plot's yard cell (q(172))
  /** P1 (content/farm_garden.json): the Farming level each convenience comes at (§4.6.1: seed_saver 10) and Seed
   * Saver's chance per harvest. Absent = not in this build. */
  farming?: { conveniences?: Partial<Record<string, number>>; seed_saver_chance?: number };
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
  if (c.mine.fee_per_day !== true) throw new Error('p0 content: mine.fee_per_day must be true for batch 1');
  const mainFrom = (worldOf(c) as { wild?: { mines?: { vein?: { main_from: number } } } } | undefined)?.wild?.mines?.vein?.main_from;
  if (!Number.isInteger(mainFrom) || c.mine.types.vein.main_weight?.[1]?.[0] !== mainFrom)
    throw new Error('p0 content: mine.types.vein.main_weight[1].from must equal world.wild.mines.vein.main_from');
  const dig = c.mine.first_dig;
  if (dig && (!c.residents[dig.giver] || (dig.reward.weapon !== undefined && !c.mine.combat.weapons[dig.reward.weapon])))
    throw new Error('p0 content: mine.first_dig names a resident or a weapon the table does not have');
  for (const r of c.workbench.recipes)
    if (r.to === 'weapon' && !c.mine.combat.weapons[r.out]) throw new Error(`p0 content: workbench ${r.id} makes ${r.out}, not a weapon of mine.combat`);
  checkHomestead(c);
  const outposts = path.join(dir, 'p0_outposts.json');
  if (existsSync(outposts)) {
    c.outposts = (JSON.parse(readFileSync(outposts, 'utf8')).outposts as { id: string; role: string; name?: string; residents?: string[]; cluster?: string; lat?: number; lng?: number; keeper?: { name?: string; role?: string } }[])
      .map(o => ({ id: o.id, role: o.role, ...(o.name ? { name: o.name } : {}), residents: o.residents ?? [], ...(o.cluster ? { cluster: o.cluster } : {}),
        ...(o.keeper?.name ? { keeper: { name: o.keeper.name, role: o.keeper.role ?? '' } } : {}),
        ...(typeof o.lat === 'number' && typeof o.lng === 'number' ? { lat: o.lat, lng: o.lng } : {}) }));   // lat/lng: SGODOT-303's 300 m
  }
  // v5 (SGODOT-278): the frozen city clusters beside the content (亚瑟's build_clusters.mjs), with the server's member table.
  const clusters = path.join(dir, 'city_clusters.json');
  // Not enumerable: a structuredClone of the content (tests) leaves it out instead of copying a class without methods.
  if (existsSync(clusters)) {
    const table = CityClusters.load(clusters);
    // q(189): a closed country's cities are not in the table the game reads (their generated places stay unchanged)
    const closed = new Set(c.travel?.closed_countries ?? []);
    for (const [id, cl] of table.byId) if (closed.has(cl.country_code)) table.byId.delete(id);
    // A cluster's display name (travel.cluster_names): the id stays frozen, only the name players read changes.
    for (const [id, name] of Object.entries(c.travel?.cluster_names ?? {})) { const cl = table.get(id); if (cl) cl.name = name; }
    Object.defineProperty(c, 'clusters', { value: table, enumerable: false, writable: true, configurable: true });
  }
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

/** v4q(1) ⑥ (复核 ③): every level's `energy` is a number — a missing one used to mean a full refill. Wrong content
 * stops the server here rather than refilling everyone. */
export function checkHomestead(c: P0Content): void {
  for (const l of c.homestead.levels) {
    if (typeof l.energy !== 'number') throw new Error(`homestead.levels Lv${l.level}: energy must be a number (0 for none), got ${JSON.stringify(l.energy)}`);
    if (typeof l.skills !== 'object' || l.skills === null) throw new Error(`homestead.levels Lv${l.level}: skills must be { farming?, fishing?, cooking? }`);
  }
  if (!Array.isArray(c.homestead.energy_steps)) throw new Error('homestead.energy_steps: [[from level, + a level], …] is required');
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

/** A teaching seed's plot crop as a Crop (q(217)): the harvest crop's yield, XP, first-harvest bonus, level and family,
 * with its own id, names and Energy; `quick` says when it ripens and what it gives. By its plot crop id or its seed. */
export function quickCrop(c: P0Content, id: string): Crop | undefined {
  const q = c.quick_seeds?.find(x => x.id === id || x.seed === id);
  const base = q && cropById(c, q.harvest);
  if (!q || !base) return undefined;
  return { ...base, id: q.id, name: q.name, seed: q.seed, seed_name: q.seed_name, energy: q.energy, seed_price: 0,
    grow_h: q.grow_s / 3600, sold_at: undefined, regional: undefined, perennial: undefined,
    quick: { ms: q.grow_s * 1000, harvest: base.id } };
}

/** By harvest id or seed. Only plot consumers use this adapter; ingredient()/cropById() cannot see it. */
export function fastCrop(c: P0Content, id: string): Crop | undefined {
  const f = c.fast_crops?.find(x => x.id === id || x.seed === id);
  if (!f) return undefined;
  return { ...f, tier: 1, level: f.farming, gate: f.farming, grow_h: f.grow_s / 3600, yield: 1,
    ingr: ['F', 1], sold_at: 'stall', fast: true, quick: { ms: f.grow_s * 1000, harvest: f.id } };
}

/** What grows on a plot, including both separately authored short-duration series. */
export function plotCrop(c: P0Content, id: string): Crop | undefined { return cropById(c, id) ?? quickCrop(c, id) ?? fastCrop(c, id); }
export function fishById(c: P0Content, id: string): Fish | undefined { return c.fish.find(f => f.id === id); }
export function rodById(c: P0Content, id: string): Rod | undefined { return c.fishing.rods.find(r => r.id === id); }
export function recipeById(c: P0Content, id: string): Recipe | undefined { return c.cooking.recipes.find(r => r.id === id); }

/** Bag kind from the id prefix: seed_*, crop_*, fish_*, dish_*, bait_*, fert_*, torch (stacks of 20, §13.1.2), anything else is a material. */
/**
 * SGODOT-296: a city's postcard id. A cluster with its own specialty entry (San Francisco, Shanghai: `cluster`) keeps
 * that old id, so an account that bought one owns it already; any other cluster's is postcard_<cluster id>, stable from
 * the id alone (never the world revision or a placing order).
 */
export function cityPostcardId(c: P0Content, cluster: string): string {
  const own = Object.entries(c.specialty).find(([, sp]) => sp.cluster === cluster);
  return own ? own[0] : `postcard_${cluster}`;
}

/** The cluster a derived postcard id (postcard_<cluster id>) is for, or null: not one, an unknown cluster, or a cluster
 * whose postcard has its own old id (no second San Francisco postcard). */
export function cityPostcardCluster(c: P0Content, id: string): { id: string; name: string } | null {
  if (!id.startsWith('postcard_gn-')) return null;
  const cluster = id.slice('postcard_'.length);
  const cl = (c as P0Content & { clusters?: { get(id: string): { id: string; name: string } | undefined } }).clusters?.get(cluster);
  if (!cl || cityPostcardId(c, cluster) !== id) return null;
  return { id: cl.id, name: cl.name };
}

export function itemKind(id: string): string {
  if (id.startsWith('weapon_')) return 'weapon';
  if (id.startsWith('potion_')) return 'potion';   // v4q(7) ⑥: its own bag.stack tier (10), never a material's
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
  const mineItem = c.mine.combat.weapons[id] ?? c.mine.potions[id];
  if (mineItem) return mineItem.name;
  const crop = cropById(c, id) ?? cropBySeed(c, id) ?? quickCrop(c, id) ?? fastCrop(c, id);
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
  const card = cityPostcardCluster(c, id);
  if (card) return `${card.name} Postcard`;
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
