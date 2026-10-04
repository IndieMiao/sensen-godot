/** P0 milestone-1 content (assets/p0/p0_content.json), shared with the Godot client. */
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export type Skill = 'farming' | 'fishing' | 'cooking';
export const SKILLS: readonly Skill[] = ['farming', 'fishing', 'cooking'];

export interface Crop {
  id: string; name: string; seed: string; seed_name: string;
  tier: number; energy: number; level: number; gate: number;
  seed_price: number; grow_h: number; yield: number; price: number; xp: number; first_xp: number;
}

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
}

export const DEFAULT_P0_CONTENT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../assets/p0/p0_content.json');

export function loadP0Content(file = DEFAULT_P0_CONTENT): P0Content {
  return JSON.parse(readFileSync(file, 'utf8')) as P0Content;
}

export function cropById(c: P0Content, id: string): Crop | undefined { return c.crops.find(crop => crop.id === id); }
export function cropBySeed(c: P0Content, seed: string): Crop | undefined { return c.crops.find(crop => crop.seed === seed); }

/** Bag kind from the id prefix: seed_*, crop_*, fish_*, dish_*, anything else is a material. */
export function itemKind(id: string): string {
  const head = id.split('_')[0];
  return ['seed', 'crop', 'fish', 'dish'].includes(head) ? head : 'material';
}
