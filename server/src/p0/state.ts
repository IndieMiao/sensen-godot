/** P0 player state (one homestead per player; no compatibility with the old farm state). */
import type { P0Content, Skill } from './content.js';

export type PlotState = 'wild' | 'tilled' | 'sown' | 'growing';
export interface Plot {
  id: number; state: PlotState;
  crop?: string; xp_pct?: number; ready_at?: number;
}
export interface BagStack { id: string; qty: number }

export interface P0State {
  v: 1;
  player: string;
  created_at: number;
  clock_ms: number;              // dev-only clock offset (time skip)
  energy: { value: number; tick_ms: number };
  coins: number;
  skills: Record<Skill, number>; // cumulative XP
  plots: Plot[];
  bag: BagStack[];               // one entry per slot; capacity from content
  firsts: string[];              // e.g. harvest:crop_radish
  rewards: string[];             // one-time rewards already granted
  day: { key: string; rest: number };
  rng: number;
  seq: number;
}

export function freshState(c: P0Content, player: string, now: number, seed = hashSeed(player)): P0State {
  const plots: Plot[] = [];
  for (let i = 0; i < c.start.tilled_plots; i++) plots.push({ id: i, state: 'tilled' });
  for (let i = 0; i < c.start.wild_plots; i++) plots.push({ id: c.start.tilled_plots + i, state: 'wild' });
  return {
    v: 1, player, created_at: now, clock_ms: 0,
    energy: { value: c.energy.max_base, tick_ms: now },
    coins: c.start.coins,
    skills: { farming: 0, fishing: 0, cooking: 0 },
    plots,
    bag: c.start.bag.map(([id, qty]) => ({ id, qty })),
    firsts: [], rewards: [],
    day: { key: '', rest: 0 },
    rng: seed, seq: 0,
  };
}

function hashSeed(text: string): number {
  let h = 2166136261;
  for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 16777619);
  return h | 0;
}
