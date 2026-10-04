/** P0 player state (one homestead per player; no compatibility with the old farm state). */
import type { P0Content, Skill } from './content.js';

export type PlotState = 'wild' | 'tilled' | 'sown' | 'growing';
export interface Plot {
  id: number; state: PlotState;
  crop?: string; xp_pct?: number; ready_at?: number;
}
export interface BagStack { id: string; qty: number }

/** A line in the water: the fish is drawn when it is cast (§6.1.2), the client only sees its rarity. */
export interface Cast {
  fish: string; site: string; at: number; bite_ms: number; bait: string | null;
  xp_pct: number;                       // level difference locked at the bite (§6.7.1)
  breaks: 'level' | 'rod' | null;       // gate failure decided up front, shown after the reel starts
}
export interface Heat { at: number; spin: number; gold: number; width: number }
/** One pot on the stove (§7.2.3–7.2.4): ingredients are already gone, quality is judged at collect. */
export interface Pot {
  dish: string; rarity: number; started_at: number; ms: number; heats: Heat[];
  xp_pct: number; mystery: boolean;
}

export interface P0Day {
  key: string; rest: number;
  fails: number;                        // fishing failures (catch protection, §6.1.3)
  meals: number;                        // nominal energy eaten (§7.17.1)
  eaten: Record<string, number>;        // per recipe page
  cooked: Record<string, number>;       // per recipe page (same-page XP decay)
  bought: Record<string, number>;       // daily-stock goods
}

export interface P0State {
  v: 2;
  player: string;
  created_at: number;
  clock_ms: number;              // dev-only clock offset (time skip)
  energy: { value: number; tick_ms: number };
  coins: number;
  skills: Record<Skill, number>; // cumulative XP
  plots: Plot[];
  bag: BagStack[];               // one entry per slot; capacity from content
  firsts: string[];              // e.g. harvest:crop_radish, catch:fish_crucian, cook:dish_grilled_crucian
  rewards: string[];             // one-time rewards already granted
  day: P0Day;
  fishing: { casts: number; bites: number; caught: Record<string, number>; seen: string[] };
  cast: Cast | null;
  stove: Pot | null;
  cookbook: string[];            // known recipe pages
  fires: number;                 // pots ever started (first fire is the tutorial ring)
  rng: number;
  seq: number;
}

export const emptyDay = (key = ''): P0Day => ({ key, rest: 0, fails: 0, meals: 0, eaten: {}, cooked: {}, bought: {} });

export function freshState(c: P0Content, player: string, now: number, seed = hashSeed(player)): P0State {
  const plots: Plot[] = [];
  for (let i = 0; i < c.start.tilled_plots; i++) plots.push({ id: i, state: 'tilled' });
  for (let i = 0; i < c.start.wild_plots; i++) plots.push({ id: c.start.tilled_plots + i, state: 'wild' });
  return {
    v: 2, player, created_at: now, clock_ms: 0,
    energy: { value: c.energy.max_base, tick_ms: now },
    coins: c.start.coins,
    skills: { farming: 0, fishing: 0, cooking: 0 },
    plots,
    bag: c.start.bag.map(([id, qty]) => ({ id, qty })),
    firsts: [], rewards: [],
    day: emptyDay(),
    fishing: { casts: 0, bites: 0, caught: {}, seen: [] },
    cast: null, stove: null,
    cookbook: c.cooking.recipes.filter(r => r.known).map(r => r.id),
    fires: 0,
    rng: seed, seq: 0,
  };
}

/** Bring a stored M1 state (v1) up to the current shape; the prototype keeps playtest saves alive. */
export function upgradeState(c: P0Content, raw: P0State): P0State {
  const s = raw as P0State & { v: number };
  if (s.v === 2) return s;
  s.day = { ...emptyDay(s.day?.key ?? ''), ...s.day };
  s.fishing ??= { casts: 0, bites: 0, caught: {}, seen: [] };
  s.cast ??= null;
  s.stove ??= null;
  s.cookbook ??= c.cooking.recipes.filter(r => r.known).map(r => r.id);
  s.fires ??= 0;
  if (s.cast && !s.cast.site) s.cast.site = 'pond';
  s.v = 2;
  return s;
}

function hashSeed(text: string): number {
  let h = 2166136261;
  for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 16777619);
  return h | 0;
}
