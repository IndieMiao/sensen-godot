/** P0 player state (one homestead per player; no compatibility with the old farm state). */
import type { Family, P0Content, Skill } from './content.js';
import { maxEnergy } from './rules.js';
import { addPlots } from './garden.js';
import { clusterOf, clusterOfCityName, freshTravel, homeCluster, type TravelState } from './travel.js';

export type PlotState = 'wild' | 'tilled' | 'sown' | 'growing';
export interface Plot {
  id: number; state: PlotState;
  crop?: string; xp_pct?: number; ready_at?: number;
  fert?: boolean;                 // compost this round (§5.5): −20% of the ripening time, once, gone at harvest
}
/** A facility standing on a plot (P1, SGODOT-239): a sprinkler waters the ring of 8 around it. Never removed (q(22)). */
export interface Facility { id: number; kind: string; plot: number; under?: 'wild' | 'tilled' }   // under: the plot as it was, back when it moves
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
}
export interface Heat { at: number; spin: number; gold: number; width: number }
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
  qty: number; bonus: number; drawn_at: number; status: 'open' | 'accepted';
}
/** A board slot: a request, or empty until refill_at. */
export interface BoardSlot { req: BoardRequest | null; refill_at: number }

/** Per resident (§9.4.4): affinity points and where their request line is. */
export interface ResidentState {
  affinity: number;
  chat_day: string;              // player day of the last first chat (+2 once a day)
  gift_day: string;              // player day of the last gift received (once a day)
  next: number;                  // index of the next request in the resident's list
  req: { id: string; at: number; progress: number } | null;   // accepted request; progress counts sow for sow requests
  done_day: string;              // player day the last request was completed (one a day)
  done_at?: number;              // when the last request was completed (P1: the next one opens next_request_h later)
  lesson_at?: number;            // when they last taught a page (§7.5.3: one a week from Familiar)
}

export interface Homestead { level: number; plaque: { level: number; at: number }[] }

/** One mine run (§13.3, SGODOT-231; floors 3–5 SGODOT-275): floors[i] is floor i + 1; drops derive from the run seed.
 * mobs: each monster's HP left on that floor (content order); hp: the player's HP in the mine; express: started by Floor 5 ·
 * Express (it counts as having cleared floor 2). Runs saved before SGODOT-275 lack the newer fields (see mine.ts). */
export interface MineRun {
  id: number; seed: number; day: string;    // day = the player day it started; 04:00 ends it
  floors: { paid: boolean; broken: number[]; lit: boolean; mobs?: number[] }[];
  hp?: number; express?: boolean; attack_at?: number; hurt_at?: number;
}
export interface MineState {
  run: MineRun | null;
  count: number;                            // runs ever started (run ids)
  ended: { reason: 'reset'; at: number } | null;   // an unfinished run the 04:00 rollover ended (shown once at the mine mouth)
  swing_at: number;                         // last rock, for the 0.9 s anti-script tempo
  express?: boolean;                        // the account has cleared floor 4 once: Floor 5 · Express (SGODOT-275)
  elite?: { day: string; kills: number };   // elite kills this player day: its quartz drops on the first only (§13.3.4)
  completed?: { run: number; at: number } | null;   // the last run its elite ended (Run complete, shown once)
}

/** Where the player's commands come from (q(41)): when they last left the homestead, for Rest's 2 h rule. */
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
  mine_runs: number;                    // mine runs started today (§13.3.1, ≤ 2)
  xp: Partial<Record<Skill, number>>;   // XP earned today per skill, for the anti-script cap (§4.3.4)
  mishaps: number;                      // failed pots today (the blessing's first 10 refund their ingredients, §7.5.2)
}

/** The save version this server writes. Older saves are brought up to it at load (upgradeState). */
export const SAVE_VERSION = 5;

export interface P0State {
  v: 5;
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
  req_done: string[];            // last completed request ids (a repeated deliver says request_done)
  presence: Presence;
  inbox: P0Inbox;                // passive rewards that did not fit the bag (§10.4.8)
  firsts: string[];              // e.g. harvest:crop_radish, catch:fish_crucian, cook:dish_grilled_crucian
  rewards: string[];             // one-time rewards already granted
  day: P0Day;
  fishing: { casts: number; bites: number; caught: Record<string, number>; seen: string[] };
  cast: Cast | null;
  stove: Pot | null;
  queue: Pot | null;             // Queue ×2 (Cooking Lv5): the pot waiting behind the one on the stove
  burners: Burner[];             // stoves 2 and 3 (Homestead Lv4 / Lv8); [] until a pot goes on one
  cabinet: { id: string; qty: number }[];   // Warming Cabinet portions (Homestead Lv3, §7.7); stacks by dish id
  cookbook: string[];            // known recipe pages (Tasted or Discovered)
  book: CookbookBook;
  requests: Request[];
  gear: { rods: string[]; rod: string; hoes: string[]; hoe: string; picks: string[]; pick: string };   // Tools & Gear: owned and equipped rod / hoe / pickaxe (no bag slots)
  gather: { ready_at: Record<string, number>; last_at: number };   // §13.2: when each spot can be gathered again; last tap (tempo)
  mine: MineState;
  storage_auto: { at: number; items: [string, number][] } | null;   // last auto-store on coming home (q(40)), floated once by the client
  decor?: { placed: import('./decor.js').PlacedDecor[]; count: number };   // P1 Decorate (SGODOT-284): the yard's pieces and the uid counter
  travel: TravelState;           // home / current city, visited cities, stamps, Day Pass (v5, SGODOT-275)
  seen?: string[];   // map markers' ◆ already looked at: item:<id> / talk:<resident> (SGODOT-232, q(48))
  facilities?: Facility[];       // P1 (SGODOT-239): facilities on plots
  facility_count?: number;       // facilities ever built (their ids)
  fires: number;                 // pots ever started (first fire is the tutorial ring)
  rng: number;
  seq: number;
}

export const emptyDay = (key = ''): P0Day => ({
  key, rest: 0, fails: 0, meals: 0, eaten: {}, cooked: {}, bought: {}, drinks: 0, quota: {}, bonus: 0, sys_done: 0, gift_meal: null, mine_runs: 0, xp: {}, mishaps: 0,
});

export function freshState(c: P0Content, player: string, now: number, seed = hashSeed(player)): P0State {
  const plots: Plot[] = [];
  for (let i = 0; i < c.start.tilled_plots; i++) plots.push({ id: i, state: 'tilled' });
  for (let i = 0; i < c.start.wild_plots; i++) plots.push({ id: c.start.tilled_plots + i, state: 'wild' });
  return {
    v: 5, player, created_at: now, clock_ms: 0,
    energy: { value: c.energy.max_base, tick_ms: now },
    coins: c.start.coins,
    skills: { farming: 0, fishing: 0, cooking: 0 },
    plots,
    bag: c.start.bag.map(([id, qty]) => ({ id, qty })),
    bag_cap: c.bag.capacity, storage: {}, locked: [], owned: [], inbox: emptyInbox(),
    homestead: { level: 1, plaque: [] },
    residents: {},
    boards: { stall: [{ req: tutorialRequest(c, now), refill_at: 0 }], market: [] }, req_done: [],
    presence: { left_at: null, last_at: 0, space: null, place: null },
    firsts: [], rewards: [],
    day: emptyDay(),
    fishing: { casts: 0, bites: 0, caught: {}, seen: [] },
    cast: null, stove: null, queue: null, burners: [], cabinet: [],
    cookbook: c.cooking.recipes.filter(r => r.known).map(r => r.id), book: emptyBook(),
    requests: [{ ...c.requests.tutorial, status: 'open' }],
    gear: { rods: [c.tools.fishing], rod: c.tools.fishing, hoes: [c.tools.farming], hoe: c.tools.farming, picks: [c.tools.mining], pick: c.tools.mining },
    gather: { ready_at: {}, last_at: 0 },
    mine: freshMine(),
    storage_auto: null,
    travel: freshTravel(c),
    seen: [],
    facilities: [], facility_count: 0,
    fires: 0,
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
  s.gear ??= { rods: [c.tools.fishing], rod: c.tools.fishing, hoes: [c.tools.farming], hoe: c.tools.farming, picks: [c.tools.mining], pick: c.tools.mining };
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
  // Until players choose a home (P2 second version), everyone's home is the content's city: a moved home moves saves
  // home too (as SGODOT-270 did), and the frozen fallback list is made again for it (§11.2.3 "换城后重算一次").
  if (s.travel.home !== homeCluster(c)) {
    const fresh = freshTravel(c);
    s.travel.home = fresh.home; s.travel.here = fresh.home; s.travel.fallback = fresh.fallback;
  }
  if (!s.travel.fallback.near10.length) {   // made before the cluster table was there: fill it once it is (§11.2.3)
    const f = freshTravel(c).fallback;
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
  // SGODOT-270: the home city moved (Shanghai → San Francisco). A pond that is no longer one of the home city's (gone
  // from the map, or left in another city, as notePlace judges) is let go when the save loads: the place is forgotten,
  // and a cast still out there comes in as a line in before the bite would — the Energy back, no fish, no XP, an unused
  // teaching pin returned. Old casts without a place are left alone.
  // v5: "the home city's" becomes "a city the player holds a pass for" (home, or a Day Pass bought before).
  const home = (id: string) => { const k = c.fishing.places[id] ? clusterOf(c, id) : null; return !!k && (k === s.travel.home || !!s.travel.passes[k]); };
  if (s.presence.place && !home(s.presence.place)) s.presence.place = null;
  const cast = s.cast;
  if (cast?.place && !home(cast.place)) {
    if (cast.pin) s.firsts = s.firsts.filter(f => f !== cast.pin);
    const cap = maxEnergy(c, s) + c.energy.bonus_zone;
    s.energy.value = Math.max(s.energy.value, Math.min(cap, s.energy.value + c.fishing.cast_energy));
    s.cast = null;
  }
  s.inbox ??= emptyInbox();   // SGODOT-232: filled for v3 and v4 saves alike, without a version of its own
  s.seen ??= [];   // SGODOT-232 map markers, the same way
  // P1 (SGODOT-239, q(59) §1.1): facilities, and the 10 plots a save already at Homestead Lv3 has from this version on
  // (30–39, wild; 0–29 never move). No version of their own, like the inbox: a fill beside v5's travel block.
  s.facilities ??= [];
  s.facility_count ??= s.facilities.reduce((m, f) => Math.max(m, f.id), 0);
  addPlots(c, s);
  // SGODOT-275: floors 3–5. A run saved with floors 1–2 gets the deeper floors unpaid (their monsters are met at full HP
  // by mine.floorMobs); its HP starts full (mine.runHp). No version of its own: the fields are additive.
  const run = s.mine?.run;
  if (run) while (run.floors.length < c.mine.floors.length) run.floors.push({ paid: false, broken: [], lit: false });
  s.day = { ...emptyDay(s.day?.key ?? ''), ...s.day };
  s.v = SAVE_VERSION;
  return s;
}

const freshMine = (): MineState => ({ run: null, count: 0, ended: null, swing_at: 0 });

function hashSeed(text: string): number {
  let h = 2166136261;
  for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 16777619);
  return h | 0;
}
