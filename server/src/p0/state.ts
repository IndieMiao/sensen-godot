/** P0 player state (one homestead per player; no compatibility with the old farm state). */
import type { P0Content, Skill } from './content.js';

export type PlotState = 'wild' | 'tilled' | 'sown' | 'growing';
export interface Plot {
  id: number; state: PlotState;
  crop?: string; xp_pct?: number; ready_at?: number;
}
/** One bag slot. A resident's gift meal is its own stack (gift), never merged with bought or cooked ones (§3.4.5). */
export interface BagStack { id: string; qty: number; gift?: { from: string; day: string } }

/** A line in the water: the fish is drawn when it is cast (§6.1.2), the client only sees its rarity. */
export interface Cast {
  fish: string; site: string; at: number; bite_ms: number; bait: string | null;
  xp_pct: number;                       // level difference locked at the bite (§6.7.1)
  breaks: 'level' | 'rod' | null;       // gate failure decided up front, shown after the reel starts
  pin?: string;                         // a teaching pin this cast used (handed back if the line comes in before the bite)
}
export interface Heat { at: number; spin: number; gold: number; width: number }
/** One pot on the stove (§7.2.3–7.2.4): ingredients are already gone, quality is judged at collect. */
export interface Pot {
  dish: string; rarity: number; started_at: number; ms: number; heats: Heat[];
  xp_pct: number; mystery: boolean;
}

/** A request on the stall board: open → accepted (tracked) → done. Requests never pay skill XP (§6.7.1). */
export interface Request { id: string; title: string; item: string; qty: number; coins: number; where: string; status: 'open' | 'accepted' | 'done' }

/** A drawn system request (§9.6): items are fixed when drawn; coins are paid from what is handed in. */
export interface BoardRequest {
  id: string; template: string; items: string[]; rarity?: number; kind: 'crop' | 'fish' | 'dish' | 'material';
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
}

export interface Homestead { level: number; plaque: { level: number; at: number }[] }

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
}

export interface P0State {
  v: 3;
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
  firsts: string[];              // e.g. harvest:crop_radish, catch:fish_crucian, cook:dish_grilled_crucian
  rewards: string[];             // one-time rewards already granted
  day: P0Day;
  fishing: { casts: number; bites: number; caught: Record<string, number>; seen: string[] };
  cast: Cast | null;
  stove: Pot | null;
  cookbook: string[];            // known recipe pages
  requests: Request[];
  gear: { rods: string[]; rod: string; hoes: string[]; hoe: string };   // Tools & Gear: owned and equipped rod / hoe (no bag slots)
  fires: number;                 // pots ever started (first fire is the tutorial ring)
  rng: number;
  seq: number;
}

export const emptyDay = (key = ''): P0Day => ({
  key, rest: 0, fails: 0, meals: 0, eaten: {}, cooked: {}, bought: {}, drinks: 0, quota: {}, bonus: 0, sys_done: 0, gift_meal: null,
});

export function freshState(c: P0Content, player: string, now: number, seed = hashSeed(player)): P0State {
  const plots: Plot[] = [];
  for (let i = 0; i < c.start.tilled_plots; i++) plots.push({ id: i, state: 'tilled' });
  for (let i = 0; i < c.start.wild_plots; i++) plots.push({ id: c.start.tilled_plots + i, state: 'wild' });
  return {
    v: 3, player, created_at: now, clock_ms: 0,
    energy: { value: c.energy.max_base, tick_ms: now },
    coins: c.start.coins,
    skills: { farming: 0, fishing: 0, cooking: 0 },
    plots,
    bag: c.start.bag.map(([id, qty]) => ({ id, qty })),
    bag_cap: c.bag.capacity, storage: {}, locked: [], owned: [],
    homestead: { level: 1, plaque: [] },
    residents: {},
    boards: { stall: [{ req: tutorialRequest(c, now), refill_at: 0 }], market: [] },
    firsts: [], rewards: [],
    day: emptyDay(),
    fishing: { casts: 0, bites: 0, caught: {}, seen: [] },
    cast: null, stove: null,
    cookbook: c.cooking.recipes.filter(r => r.known).map(r => r.id),
    requests: [{ ...c.requests.tutorial, status: 'open' }],
    gear: { rods: [c.tools.fishing], rod: c.tools.fishing, hoes: [c.tools.farming], hoe: c.tools.farming },
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
 * Bring a stored playtest save up to the current shape (v1 M1 → v2 M2 → v3 SGODOT-228). The prototype promises no
 * compatibility, but filling defaults keeps local saves playable: v3 adds Homestead Lv1, an empty farm storage and
 * the boards, moving the old tutorial request into Stall Board slot 1 with its status.
 */
export function upgradeState(c: P0Content, raw: P0State, now = Date.now()): P0State {
  const s = raw as P0State & { v: number };
  s.requests ??= [{ ...c.requests.tutorial, status: 'open' }];
  s.gear ??= { rods: [c.tools.fishing], rod: c.tools.fishing, hoes: [c.tools.farming], hoe: c.tools.farming };
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
    const first = tutorialRequest(c, now);
    s.boards ??= {
      stall: [old?.status === 'done' ? { req: null, refill_at: now } : { req: { ...first, status: old?.status === 'accepted' ? 'accepted' : 'open' }, refill_at: 0 }],
      market: [],
    };
  }
  s.day = { ...emptyDay(s.day?.key ?? ''), ...s.day };
  s.v = 3;
  return s;
}

function hashSeed(text: string): number {
  let h = 2166136261;
  for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 16777619);
  return h | 0;
}
