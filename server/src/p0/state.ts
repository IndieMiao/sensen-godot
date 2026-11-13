/** P0 player state (one homestead per player; no compatibility with the old farm state). */
import type { Family, P0Content, Skill } from './content.js';
import { maxEnergy } from './rules.js';
import { addPlots, clearNewBeds } from './garden.js';
import { clusterById, clusterOf, clusterOfCityName, fallbackOf, freshTravel, openCity, wildFrozen, writtenCluster, type TravelState } from './travel.js';
import { recallAwayTraps } from './fish_trap.js';
import { placeOf } from './world.js';
import { checkGuideTable, freshGuide, legacyGuide, type GuideState } from './guide.js';

export type PlotState = 'wild' | 'tilled' | 'sown' | 'growing';
export interface Plot {
  id: number; state: PlotState;
  crop?: string; xp_pct?: number; ready_at?: number;
  fert?: boolean;                 // compost this round (§5.5): −20% of the ripening time, once, gone at harvest; on a tree, Orchard Feed
  picks?: number;                 // a tree (P1, q(118)): times picked; 0 while it ripens the first time
  boost?: number;                 // the priest's farm buff when this was sown (its share of the ripening time, 0.5), gone at harvest
}
/** A facility standing on a plot (P1, SGODOT-239): a sprinkler waters the ring of 8 around it. Never removed (q(22)). */
export interface Facility { id: number; kind: string; plot: number; under?: 'wild' | 'tilled'; cell?: [number, number] }   // under: the plot as it was, back when it moves; cell: a yard facility's cell (plot −1)
/** One bag slot. A resident's gift meal is its own stack (gift), never merged with bought or cooked ones (§3.4.5). */
export interface BagStack { id: string; qty: number; gift?: { from: string; day: string } }

/** A passive reward that did not fit the bag (§10.4.8, q(45)): kept 24 h from when it enters the Inbox. */
export interface Parcel extends BagStack { key: string; source: string; created_at: number; expires_at: number }
/** What became of a parcel: claimed, expired (sellable items paid out as coins) or, for a gift, returned to its sender. */
export interface ParcelUpdate extends BagStack {
  key: string; source: string; at: number; status: 'claimed' | 'expired' | 'returned'; coins: number; read: boolean;
}
export interface P0Inbox {
  granted: string[];                          // reward sources already granted, one key each
  parcels: Parcel[];                          // at most 8 (§10.4.8)
  waiting: Omit<Parcel, 'expires_at'>[];      // queued while 8 parcels wait; their 24 h starts on admission (q(45))
  updates: ParcelUpdate[];                    // the last 100 claims and expiries
}
export const emptyInbox = (): P0Inbox => ({ granted: [], parcels: [], waiting: [], updates: [] });

/** A line in the water: the fish is drawn when it is cast (§6.1.2), the client only sees its rarity. */
export interface Cast {
  fish: string; site: string; at: number; bite_ms: number; bait: string | null;
  place?: string;                       // the catalog pond it was cast at (q(36)); site is that pond's template
  xp_pct: number;                       // level difference locked at the bite (§6.7.1)
  breaks: 'level' | 'rod' | null;       // gate failure decided up front, shown after the reel starts
  pin?: string;                         // a teaching pin this cast used (handed back if the line comes in before the bite)
  twin?: true;                          // the priest's fish buff was on when this was cast: it lands fish_qty of the fish
}
/** One heat ring (§7.2.4). q(288) (SGODOT-419): `from` is where the needle sets off on screen (degrees clockwise from 12,
 * shown only), `drift` how fast the ring turns against the needle (°/s); both absent on the teaching pot and older pots. */
export interface Heat { at: number; spin: number; gold: number; width: number; from?: number; drift?: number }
/** One pot on the stove (§7.2.3–7.2.4): ingredients are already gone, quality is judged at collect. */
export interface Pot {
  dish: string; rarity: number; started_at: number; ms: number; heats: Heat[];
  xp_pct: number; mystery: boolean;
  items?: string[];                     // what went in (a failed pot's refund and its Kitchen Mishaps entry, §7.5.2)
  taps?: number[];                      // heat taps sent while it cooked (heat command), judged with collect's own
  left?: string[];   // collected (judged, XP paid) but no place to keep: these portions wait on the stove (§7.2.6)
  id?: number;       // which pot this is (s.fires when it was put on), so heat / collect name the pot they mean (Queue ×2)
  no_room?: boolean; // done but found no place to keep it: the waiting pot fires when it is taken, not when it was done
  double?: boolean;  // Big Pot Double (Homestead Lv6): ingredients ×2, two portions, one round of heat
}

/** One stove and the pot waiting behind it (Queue ×2). Stove 1 is s.stove / s.queue; stoves 2–3 (Homestead Lv4 / Lv8,
 * SGODOT-282) are s.burners[0..1]. Each stove cooks, queues and keeps its own pot. */
export interface Burner { stove: Pot | null; queue: Pot | null }

/** The Cookbook beyond the known pages (§7.5, SGODOT-232 S5). */
export interface CookbookBook {
  cooked: Record<string, number>;       // pots cooked per page, ever (Mastered at 10, §7.5.1)
  best: Record<string, number>;         // best quality per page (0 Plain, 1 Good, 2 Perfect)
  first_at: Record<string, number>;     // when the page was first cooked (Discovered)
  clues: Record<string, number[]>;      // Hidden pages: slot indexes shown as their ingredient (Clued)
  mishaps: { items: string[]; n: number; at: number }[];   // Kitchen Mishaps: each failed combination once, with a count
}
export const emptyBook = (): CookbookBook => ({ cooked: {}, best: {}, first_at: {}, clues: {}, mishaps: [] });

/** A request on the stall board: open → accepted (tracked) → done. Requests never pay skill XP (§6.7.1). */
export interface Request { id: string; title: string; item: string; qty: number; coins: number; where: string; status: 'open' | 'accepted' | 'done' }

/** A drawn system request (§9.6): items are fixed when drawn; coins are paid from what is handed in. */
export interface BoardRequest {
  id: string; template: string; items: string[]; rarity?: number; style?: string | string[]; family?: Family; kind: 'crop' | 'fish' | 'dish' | 'material' | 'visit';
  visit?: { place: string; done: boolean };   // explore (Stamp Run): the outpost to check in at, and whether the player has
  where?: 'not_home';   // Far Pond (q(128)): fish the home city's ponds don't have (boards.ts farFish)
  qty: number; bonus: number; drawn_at: number; status: 'open' | 'accepted';
  accepted_at?: number;   // when the player tracked it (q(143): Today keeps the latest tracked one); absent on older saves
}
/** A board slot: a request, or empty until refill_at. */
export interface BoardSlot { req: BoardRequest | null; refill_at: number }

/** Per resident (§9.4.4): affinity points and where their request line is. */
export interface ResidentState {
  affinity: number;
  chat_day: string;              // player day of the last first chat (+2 once a day)
  gift_day: string;              // player day of the last gift received (once a day)
  next: number;                  // index of the next request in the resident's list
  req: { id: string; at: number; progress: number } | null;   // accepted request; progress counts sow / harvest requests
  intro_done?: string[];         // q(218): teaching requests handed in (ResidentDef.intro_requests ids); absent = none
  done_day: string;              // player day the last request was completed (one a day)
  done_at?: number;              // when the last request was completed (P1: the next one opens next_request_h later)
  lesson_at?: number;            // when they last taught a page (§7.5.3: one a week from Familiar)
  kindred_at?: number;           // q(171): when their postcard and title were given (first reached Kindred)
}

export interface Homestead {
  level: number; plaque: { level: number; at: number }[];
  looks?: Record<string, 'a' | 'b'>;   // LOOK-PICK (SGODOT-282): a stage's look once changed; absent = a (q(24): closing = a)
}

/** v7 mines retain per-site records and a separate home-day session; no legacy runs. */
export type MineState = MineB1State;

/** 355 E/F/G v0.4: active mine fields in development v7. */
export interface MineB1Record { deepest: number; guards: number[]; first_at: number }
export interface MineB1Ground { id: number; item: string; qty: number; from: number }
export interface MineB1FloorState {
  paid: boolean; broken: number[]; lit: boolean; mobs: number[]; guard_hit_at?: number;
  ground: MineB1Ground[]; ground_seq: number;
}
export interface MineB1Day {
  key: string;
  at: { mine: string; floor: number } | null;
  hp: number;
  floors: Record<string, MineB1FloorState>;
  picked: [string, number][];
  attack_at?: number; hurt_at?: number; drink_at?: number; swing_at?: number;
  /** q(291): out of the mine (left it, knocked out), `hp` refills from this time on (mine.ts mineHp); none inside. */
  hp_at?: number;
}
export type MineB1Notice = { kind: 'reset'; at: number; floor: number }
  | { kind: 'ko'; at: number; floor: number; lost: [string, number][] };
export interface MineB1State {
  records: Record<string, MineB1Record>; day: MineB1Day | null; notice: MineB1Notice | null;
}
export interface MineB1PlayerFields {
  mine: MineB1State;
  kills: Record<string, number>;
  guard_firsts: Record<string, { at: number; mine: string; floor: number; home: string }>;
}
export interface MineB1WeaponState { weapons: string[]; weapon: string }
/** Reserved for content with once_a_day, keyed by monster kind. Batch 1 has no such drops and leaves it empty. */
export interface MineB1DailyFields { once: Record<string, number> }

export function freshMineB1Fields(): MineB1PlayerFields {
  return { mine: { records: {}, day: null, notice: null }, kills: {}, guard_firsts: {} };
}

export function freshMineB1DailyFields(): MineB1DailyFields {
  return { once: {} };
}

/** Start with the weapon selected by content; owned weapons never take a bag slot. */
export function freshMineB1Weapons(weapon: string): MineB1WeaponState {
  return { weapons: [weapon], weapon };
}

/** Where the player's commands come from (q(41)). left_at was Rest's 2 h away (q(269) retired it): old saves keep it, unread. */
/** place: the catalog pond the player is at, only while in a pond space (cast reads its template from it, q(36)). */
export interface Presence { left_at: number | null; last_at: number; space: string | null; place?: string | null;
  entered?: string | null;   // the pond / outpost entered with a valid pass (v5): commands there are not re-checked
}

export interface P0Day {
  key: string; rest: number;
  fails: number;                        // fishing failures (catch protection, §6.1.3)
  meals: number;                        // nominal energy eaten (§7.17.1)
  eaten: Record<string, number>;        // per recipe page
  cooked: Record<string, number>;       // per recipe page (same-page XP decay)
  bought: Record<string, number>;       // daily-stock goods
  drinks: number;                       // hot tea + coffee, shared (§3.4.4)
  quota: Record<string, number>;        // coins paid today per buyback quota (§9.13.1)
  bonus: number;                        // request completion bonus paid today (§9.13.2)
  sys_done: number;                     // system requests completed today (§9.6.4)
  gift_meal: string | null;             // resident who gave today's gift meal (§3.4.5)
  once: Record<string, number>;          // reserved once_a_day counts; unused by batch 1 content
  cards?: string[];                     // today's recipe cards on the Homestead Stall shelf, drawn once a day (§7.16.1, SGODOT-282)
  xp: Partial<Record<Skill, number>>;   // XP earned today per skill, for the anti-script cap (§4.3.4)
  mishaps: number;                      // failed pots today (the blessing's first 10 refund their ingredients, §7.5.2)
  compost?: number;                     // crops turned into Compost at the Compost Bin today (q(118) ③, ≤ 5)
  bj_net?: number;                      // SGODOT-351: the card room's net coins today, hands begun today only — the observation log's, no economy's
  buffs?: number;                       // the priest's buffs taken today, both kinds (buffs.ts; limited from content.buffs.limit_from)
}

/** The save version this server writes. v7 is SGODOT-355's first batch: the save is cleared at that release (plan v4
 * conclusion 20, q row B), so a save older than v7 is not brought up — the store takes it as no save at all (store.ts).
 * upgradeState still fills a v7 save's optional fields. */
export const SAVE_VERSION = 7;
/** The weapon a new save holds (v7, 355 G; 周瑜's contract v0.1: weapon ids are weapon_*, the G PR adds the item). */
export const START_WEAPON = 'weapon_wooden_sword';

export interface P0State {
  v: 7;
  player: string;
  created_at: number;
  clock_ms: number;              // dev-only clock offset (time skip)
  energy: { value: number; tick_ms: number };
  coins: number;
  skills: Record<Skill, number>; // cumulative XP
  plots: Plot[];
  bag: BagStack[];               // one entry per slot
  bag_cap: number;               // 25, 30 after Bag Upgrade I (§10.4.3)
  storage: Record<string, number>;   // farm storage: no slot limit, upgrades take from it first (§10.4.8)
  locked: string[];              // item ids locked against Sell All (F-07)
  owned: string[];               // one-time purchases: bag upgrades, specialty items
  homestead: Homestead;
  residents: Record<string, ResidentState>;
  boards: { stall: BoardSlot[]; market: BoardSlot[] };
  // q(270) (v6): one Market Board per city cluster, made the first time the player is in that city. `boards.market`
  // stays the home city's board, as v5 and older had it, and markets[home] is the same array, linked at load, on every
  // settle and on a home change. Outside `boards`: a server rolled back to v5 walks every value of `boards` as a board,
  // and reads the home board it knew. Walks: boards.boardsOf.
  markets: Record<string, BoardSlot[]>;
  // q(272): each city's local requests from its keepers (locals.ts), by city cluster; absent until the first away from
  // home, filled in place (no version of its own, as the inbox): a server without it keeps the field as it was.
  locals?: Record<string, LocalCity>;
  req_done: string[];            // last completed request ids (a repeated deliver says request_done)
  presence: Presence;
  inbox: P0Inbox;                // passive rewards that did not fit the bag (§10.4.8)
  firsts: string[];              // e.g. harvest:crop_radish, catch:fish_crucian, cook:dish_grilled_crucian
  rewards: string[];             // one-time rewards already granted
  day: P0Day;
  fishing: { casts: number; bites: number; caught: Record<string, number>; seen: string[];
    quick?: string };   // Quick Recast (Fishing Lv9, §4.6.2): the pond whose last rod catch landed; its next cast bites sooner
  traps?: import('./fish_trap.js').Trap[];   // P1 Fish Traps in the water (SGODOT-283); absent on older saves
  cast: Cast | null;
  stove: Pot | null;
  queue: Pot | null;             // Queue ×2 (Cooking Lv5): the pot waiting behind the one on the stove
  burners: Burner[];             // stoves 2 and 3 (Homestead Lv4 / Lv8); [] until a pot goes on one
  cabinet: { id: string; qty: number }[];   // Warming Cabinet portions (Homestead Lv3, §7.7); stacks by dish id
  cookbook: string[];            // known recipe pages (Tasted or Discovered)
  book: CookbookBook;
  requests: Request[];
  gear: { rods: string[]; rod: string; hoes: string[]; hoe: string; picks: string[]; pick: string;   // Tools & Gear: owned and equipped rod / hoe / pickaxe (no bag slots)
    weapons: string[]; weapon: string };   // v7 (355 G): the weapon slot, owned and held; a new save has the Wooden Sword
  kills: Record<string, number>;   // v7 (355 E/F, plan §3.6): monsters beaten, by kind (the second batch's bestiary reads it)
  guard_firsts: Record<string, { at: number; mine: string; floor: number; home: string }>;   // home is captured at the first kill, never inferred after a home change
  gather: { ready_at: Record<string, number>; last_at: number };   // §13.2: when each spot can be gathered again; last tap (tempo)
  mine: MineState;
  storage_auto: { at: number; items: [string, number][] } | null;   // last auto-store on coming home (q(40)), floated once by the client
  decor?: { placed: import('./decor.js').PlacedDecor[]; count: number };   // P1 Decorate (SGODOT-284): the yard's pieces and the uid counter
  travel: TravelState;           // home / current city, visited cities, stamps, Day Pass (v5, SGODOT-275)
  seen?: string[];   // map markers' ◆ already looked at: item:<id> / talk:<resident> (SGODOT-232, q(48))
  facilities?: Facility[];       // P1 (SGODOT-239): facilities on plots
  facility_count?: number;       // facilities ever built (their ids)
  fires: number;                 // pots ever started (first fire is the tutorial ring)
  guide?: GuideState;            // SGODOT-341 new-player guide: step and counts (guide.ts); older saves are legacy, no version of its own
  blackjack?: import('./blackjack.js').BjState;   // SGODOT-351 the card room: intro seen, hand count, the hand in play, a result not yet seen (no version of its own)
  buffs?: { farm?: number; fish?: number };   // the priest's buffs (buffs.ts): each one's end, real time; one gone by is dropped at the next take
  title?: string;                // q(180): the title worn, a stable id (titles.ts); absent until the player picks one, never filled in
  // SGODOT-488 accounts (q(312)–q(317); optional, an older server ignores them, no save version): the name the player
  // gave (absent when they skipped it), the terms and privacy versions they agreed to and when, and the age gate passed.
  profile?: { name?: string; name_set_at?: number; name_locked_until?: number };
  consent?: { terms: string; privacy: string; at: number };
  age_ok?: true;
  test?: true;                   // SGODOT-488 §2.5: a test account (Test options' Start new test account), left out of the counts
  login?: 'code';                // contract v1.4 §4: an account a test code signs into (a reviewer's, a tester's without Google)
  rng: number;
  seq: number;
}

/** q(272): a city's local requests — `day` the player day they were drawn on (dayKey), each slot a request and the
 * keeper's outpost giving it. Tracked ones stay past their day; the untracked go at the next day's draw. */
export interface LocalCity { day: string; slots: { req: BoardRequest; place: string }[] }

export const emptyDay = (key = ''): P0Day => ({
  key, rest: 0, fails: 0, meals: 0, eaten: {}, cooked: {}, bought: {}, drinks: 0, quota: {}, bonus: 0, sys_done: 0, gift_meal: null, ...freshMineB1DailyFields(), xp: {}, mishaps: 0,
});

/** opts.pending: the client creating the save can offer the home pick (SGODOT-303, routes' x-p0-features);
 * opts.guide: it can show the new-player guide (SGODOT-341), so the save starts on the guide's first step. */
export function freshState(c: P0Content, player: string, now: number, seed = hashSeed(player), opts: { pending?: boolean; guide?: boolean } = {}): P0State {
  const guide = freshGuide(c, now, !!opts.guide);
  // 339 decides whether a guided save still gets Pond Catch (guide.pond_catch false: none); every other save does
  const pondCatch = guide.step === null || c.guide?.pond_catch !== false;
  const plots: Plot[] = [];
  for (let i = 0; i < c.start.tilled_plots; i++) plots.push({ id: i, state: 'tilled' });
  for (let i = 0; i < c.start.wild_plots; i++) plots.push({ id: c.start.tilled_plots + i, state: 'wild' });
  const travel = freshTravel(c, opts.pending);
  const market: BoardSlot[] = [];   // the home city's Market Board, `boards.market` and `markets[home]` one array (q(270))
  return {
    v: 7, player, created_at: now, clock_ms: 0,
    energy: { value: c.energy.max_base, tick_ms: now },
    coins: c.start.coins,
    skills: { farming: 0, fishing: 0, cooking: 0 },
    plots,
    // q(217): a guided save starts with the teaching seeds first (Quick Radish Seeds ×2, the bar's first slot); others as before
    bag: [...(guide.step !== null ? c.start.guide_bag ?? [] : []), ...c.start.bag].map(([id, qty]) => ({ id, qty })),
    bag_cap: c.bag.capacity, storage: {}, locked: [], owned: [], inbox: emptyInbox(),
    homestead: { level: 1, plaque: [] },
    residents: {},
    boards: { stall: pondCatch ? [{ req: tutorialRequest(c, now), refill_at: 0 }] : [], market }, markets: { [travel.home]: market },
    req_done: [],
    presence: { left_at: null, last_at: 0, space: null, place: null },
    firsts: [], rewards: [],
    day: emptyDay(),
    fishing: { casts: 0, bites: 0, caught: {}, seen: [] },
    cast: null, stove: null, queue: null, burners: [], cabinet: [],
    cookbook: c.cooking.recipes.filter(r => r.known).map(r => r.id), book: emptyBook(),
    requests: pondCatch ? [{ ...c.requests.tutorial, status: 'open' }] : [],
    gear: { rods: [c.tools.fishing], rod: c.tools.fishing, hoes: [c.tools.farming], hoe: c.tools.farming, picks: [c.tools.mining], pick: c.tools.mining,
      weapons: [START_WEAPON], weapon: START_WEAPON },
    kills: {}, guard_firsts: {},
    gather: { ready_at: {}, last_at: 0 },
    mine: freshMine(),
    storage_auto: null,
    travel,
    seen: [],
    facilities: [], facility_count: 0,
    fires: 0,
    guide,
    rng: seed, seq: 0,
  };
}

/** The first-session request in Stall Board slot 1 (§14.2): Pond Catch, 2 Pond Crucian. */
export function tutorialRequest(c: P0Content, now: number): BoardRequest {
  const t = c.requests.tutorial;
  return { id: t.id, template: 'req_sys_fish_common', items: [t.item], kind: 'fish', qty: t.qty, bonus: c.requests.templates.req_sys_fish_common.bonus,
    drawn_at: now, status: 'open' };
}

/**
 * Bring a stored playtest save up to the current shape (v1 M1 → v2 M2 → v3 SGODOT-228 → v4 SGODOT-231 → v5 SGODOT-275). The prototype promises no
 * compatibility, but filling defaults keeps local saves playable: v3 adds Homestead Lv1, an empty farm storage and
 * the boards, moving the old tutorial request into Stall Board slot 1 with its status.
 */
export function upgradeState(c: P0Content, raw: P0State, now = Date.now()): P0State {
  const s = raw as P0State & { v: number };
  s.requests ??= [{ ...c.requests.tutorial, status: 'open' }];
  s.gear ??= { rods: [c.tools.fishing], rod: c.tools.fishing, hoes: [c.tools.farming], hoe: c.tools.farming, picks: [c.tools.mining], pick: c.tools.mining,
    weapons: [START_WEAPON], weapon: START_WEAPON };
  s.gear.weapons ??= [START_WEAPON];   // v7's own fields, filled on any save that lacks them (a test's hand-made one)
  s.gear.weapon ??= START_WEAPON;
  s.kills ??= {};
  s.guard_firsts ??= {};
  if (s.v < 2) {
    s.fishing ??= { casts: 0, bites: 0, caught: {}, seen: [] };
    s.cast ??= null;
    s.stove ??= null;
    s.cookbook ??= c.cooking.recipes.filter(r => r.known).map(r => r.id);
    s.fires ??= 0;
    if (s.cast && !s.cast.site) s.cast.site = 'pond';
  }
  if (s.v < 3) {
    s.gear.hoes ??= [c.tools.farming];
    s.gear.hoe ??= c.tools.farming;
    s.bag_cap ??= c.bag.capacity;
    s.storage ??= {};
    s.locked ??= [];
    s.owned ??= [];
    s.homestead ??= { level: 1, plaque: [] };
    s.residents ??= {};
    const old = s.requests.find(r => r.id === c.requests.tutorial.id);
    s.req_done ??= old?.status === 'done' ? [old.id] : [];
    const first = tutorialRequest(c, s.created_at ?? now);   // keep the request's age: it dates from the account (PR #15 review)
    s.boards ??= {
      stall: [old?.status === 'done' ? { req: null, refill_at: now } : { req: { ...first, status: old?.status === 'accepted' ? 'accepted' : 'open' }, refill_at: 0 }],
      market: [],
    };
  }
  if (s.v < 4) {   // SGODOT-231: pickaxes, gathering spots, the mine run, the last auto-store
    s.gear.picks ??= [c.tools.mining];
    s.gear.pick ??= c.tools.mining;
    s.gather ??= { ready_at: {}, last_at: 0 };
    s.mine ??= freshMine();
    s.storage_auto ??= null;
  }
  if (s.v < 5) {   // SGODOT-275: cross-city travel. Everyone starts at home, nothing visited, no stamps, no pass
    s.travel ??= freshTravel(c);
    // The first-catch-in-a-city key moves from the city name to its cluster, so San Francisco's is not paid again.
    s.firsts = s.firsts.map(f => {
      if (!f.startsWith('fishing_city:') || f.startsWith('fishing_city:gn-')) return f;
      const id = clusterOfCityName(c, f.slice('fishing_city:'.length));
      return id ? `fishing_city:${id}` : f;
    });
    s.firsts = [...new Set(s.firsts)];
  }
  s.travel ??= freshTravel(c);   // a v5 save from a build without the block cannot exist, but never read one without it
  // A home the player picked stays (SGODOT-303, q(163)). A save that never picked one is the written city's (q(163) ③):
  // if the written city moved (as SGODOT-270 did), it moves home too and its frozen fallback list is made again (§11.2.3
  // "换城后重算一次"). A home the cluster table no longer knows goes back to the written city the same way.
  const t = s.travel;
  if (t.home !== writtenCluster(c) && (!t.home_chosen_at || !clusterById(c, t.home))) {
    const fresh = freshTravel(c);
    t.home = fresh.home; t.here = fresh.home; t.fallback = fresh.fallback;
    delete t.wild_near3; delete t.wild_priced; Object.assign(t, wildFrozen(c, t.home));   // v4q(3): frozen with the fallback
    delete t.farm_at; delete t.home_set; delete t.home_chosen_at;
  }
  // A server from before SGODOT-303 (a rollback to 0.2.5) moved a picked home back to the written city and kept the
  // pick's fields it did not know (蒙恬 on #371): the frozen home set says where the player chose, so home goes back
  // there, with its fallback list. A pick in a city the table no longer knows is dropped instead.
  const picked = t.home_set ? clusterOf(c, t.home_set.pond) : null;
  if (picked && picked !== t.home) {
    if (t.home_chosen_at && (picked === writtenCluster(c) || clusterById(c, picked))) {
      if (t.here === t.home) t.here = picked;
      t.home = picked;
      delete t.passes[picked];
      t.fallback = fallbackOf(c, picked);
      delete t.wild_near3; delete t.wild_priced; Object.assign(t, wildFrozen(c, picked));   // v4q(3): frozen with the fallback
    } else {
      delete t.farm_at; delete t.home_set; delete t.home_chosen_at;
    }
  }
  if (s.v < 6 && !s.markets) {   // q(270), SGODOT-378: the one Market Board becomes the home city's, with its requests and refill times
    s.markets = { [t.home]: s.boards.market ?? [] };
  } else if (s.v < 6) {
    // back from a v5 server (a rollback): `boards.market` is the board it played; the other cities' boards waited as they
    // were. One it read under another home (a home change meanwhile) holds requests that board took along: those go.
    const held = new Set((s.boards.market ?? []).map(slot => slot.req?.id).filter(Boolean));
    for (const [city, slots] of Object.entries(s.markets)) {
      if (city !== t.home) for (const slot of slots) if (slot.req && held.has(slot.req.id)) { slot.req = null; slot.refill_at = now; }
    }
  }
  s.markets ??= {};
  s.boards.market ??= s.markets[t.home] ?? [];   // the home board, one array under both names (P0State.markets)
  s.markets[t.home] = s.boards.market;
  if (t.day_hold && now >= t.day_hold.until) delete t.day_hold;   // q(173): the carried day is over
  // q(189) ③: a city the table no longer has (a closed country's): the player is home, its Day Pass goes, and an accepted
  // board request with a check-in there is dropped, free. Visits and stamps stay in the save (the view leaves them out).
  for (const id of Object.keys(t.passes)) if (!openCity(c, id)) delete t.passes[id];
  if (!openCity(c, t.here)) t.here = t.home;
  for (const slots of [s.boards.stall ?? [], ...Object.values(s.markets ?? {})]) {
    for (const slot of slots) {
      const at = slot.req?.visit?.place, city = at ? clusterOf(c, at) : null;
      if (city && !openCity(c, city)) { slot.req = null; slot.refill_at = now; }
    }
  }
  if (!s.travel.fallback.near10.length) {   // made before the cluster table was there: fill it once it is (§11.2.3)
    const f = fallbackOf(c, s.travel.home);
    if (f.near10.length) s.travel.fallback = f;
  }
  s.req_done ??= [];
  s.cabinet ??= [];
  s.queue ??= null;
  s.burners ??= [];   // SGODOT-282: older saves have stove 1 only
  if (!s.book) {   // SGODOT-232 S5: pages already cooked count once, with no date (no version of their own)
    s.book = emptyBook();
    for (const f of s.firsts) if (f.startsWith('cook:') && f !== `cook:${c.cooking.mystery.id}`) s.book.cooked[f.slice(5)] = 1;
  }
  s.presence ??= { left_at: null, last_at: 0, space: null };
  s.presence.place ??= null;
  letGoAway(c, s);
  s.inbox ??= emptyInbox();   // SGODOT-232: filled for v3 and v4 saves alike, without a version of its own
  s.seen ??= [];   // SGODOT-232 map markers, the same way
  s.guide ??= legacyGuide(now);   // SGODOT-341: a save from before the guide never gets it (all of them, test players too)
  checkGuideTable(c, s, now);   // its step gone from a changed table: the guide ends here
  // P1 (SGODOT-239, q(59) §1.1): facilities, and the 10 plots a save already at Homestead Lv3 has from this version on
  // (30–39, wild; 0–29 never move). No version of their own, like the inbox: a fill beside v5's travel block.
  s.facilities ??= [];
  s.facility_count ??= s.facilities.reduce((m, f) => Math.max(m, f.id), 0);
  clearNewBeds(c, s, addPlots(c, s), []);   // a save already at Lv7: pieces on the new beds back to storage (q(172))
  // Older versions are discarded by the v7 store; only fill missing fields of a v7 save here.
  s.mine ??= freshMine();
  s.day = { ...emptyDay(s.day?.key ?? ''), ...s.day };
  recallAwayTraps(c, s, now, []);   // q(177) ③: a trap left outside home (a home put back after a rollback, #393), once every field is filled
  s.v = SAVE_VERSION;
  return s;
}

/**
 * SGODOT-270: the home city moved (Shanghai → San Francisco). A pond that is no longer one of the home city's (gone
 * from the map, or left in another city, as notePlace judges) is let go when the save loads: the place is forgotten,
 * and a cast still out there comes in as a line in before the bite would — the Energy back, no fish, no XP, an unused
 * teaching pin returned. Old casts without a place are left alone.
 * v5: "the home city's" becomes "a city the player holds a pass for" (home, or a Day Pass bought before).
 * SGODOT-303: changing home lets go the same way.
 */
export function letGoAway(c: P0Content, s: P0State): void {
  const home = (id: string) => { const k = placeOf(c, id) ? clusterOf(c, id) : null; return !!k && (k === s.travel.home || !!s.travel.passes[k]); };
  if (s.presence.place && !home(s.presence.place)) s.presence.place = null;
  const cast = s.cast;
  if (cast?.place && !home(cast.place)) {
    if (cast.pin) s.firsts = s.firsts.filter(f => f !== cast.pin);
    const cap = maxEnergy(c, s) + c.energy.bonus_zone;
    s.energy.value = Math.max(s.energy.value, Math.min(cap, s.energy.value + c.fishing.cast_energy));
    s.cast = null;
  }
}

const freshMine = (): MineState => freshMineB1Fields().mine;

function hashSeed(text: string): number {
  let h = 2166136261;
  for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 16777619);
  return h | 0;
}
