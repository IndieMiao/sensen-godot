import { mainHandStats } from '../domain/character.js';
import { createHash } from 'node:crypto';
import { addBagItem, ensureBag, projectBagAggregates } from '../domain/bag.js';
import { characterStats, ensureCharacter, grantStarterWeapon, spendCharacterBuff } from '../domain/character.js';
import type { Content } from '../domain/content.js';
import type { FarmRow } from '../http/dto.js';
import { initialMineState } from '../domain/mining.js';

export const CAPACITY = 300;
export const STEP = 0.05;
export { ACTIONS } from '../p0/online/actions.js';   // P0 owns the list (SGODOT-304)
export type Point = [number, number];
export interface Navigation { cell: number; rows: string[]; spawn: Point }
export interface Effect {
  player: string;
  damage?: number;
  raw_damage?: number;
  loot?: Record<string, number>;
  elevator?: boolean;
  starter?: boolean;
  mining?: boolean;
}
export interface Monster {
  id: string; kind: string; x: number; z: number; hp: number;
  phase: string; timer: number; direction: Point; contributors: string[];
}
export interface Floor {
  rocks: { id: string; position: Point; broken: boolean }[];
  monsters: Monster[];
  cleared: boolean;
}
export interface Expedition { run: number; floors: Record<string, Floor>; elevator: boolean; owner?: string; party?: string; retired?: boolean }
export interface Checkpoint { revision: number; commit: string; mine: Expedition; rescued?: string[] }
export interface CommitResult { checkpoint: Checkpoint; farms: FarmRow[] }
export interface RealtimePersistence {
  realtimeLoad(key: string): Promise<Checkpoint | null>;
  realtimeCommit(key: string, expected: number, commit: string, mine: Expedition, effects: Effect[]): Promise<CommitResult>;
  realtimeDirectory(player: string, action?: DirectoryAction, value?: string): Promise<DirectoryEntry>;
  realtimeHomes(players: string[]): Promise<PartyHome[]>;
}
export type DirectoryAction = 'get' | 'create' | 'join' | 'leave' | 'kick' | 'leader' | 'disband' | 'bind' | 'farm_access';
export interface Party { id: string; code: string; leader: string; members: string[] }
export interface DirectoryEntry { instance: string; party: Party | null; farm_access: boolean }
export interface DirectoryPlayer { instance: string; party: string; farm_access?: string }
export type PartyHome = Pick<FarmRow, 'id' | 'owner_id' | 'region_id' | 'layout_patch_id' | 'blueprint_revision' | 'visit_access'> & { party_farm_access: string };

export function applyEffects(farm: FarmRow, effects: Effect[], content: Content, rescued: string[] = []): FarmRow {
  const next = structuredClone(farm);
  ensureBag(next.state, content);
  ensureCharacter(next.state, content);
  for (const effect of effects) {
    if (effect.player !== farm.owner_id) continue;
    if (effect.starter) grantStarterWeapon(next.state, content);
    const damage = effect.raw_damage ? Math.max(1, effect.raw_damage - characterStats(next.state, content).defense) : effect.damage ?? 0;
    if (damage) {
      if (damage >= next.state.character!.hp! && !rescued.includes(farm.owner_id)) rescued.push(farm.owner_id);
      next.state.character!.hp = Math.max(1, next.state.character!.hp! - damage);
    }
    if (effect.elevator) (next.state.mine ??= initialMineState()).elevator_unlocked = true;
    const loot = { ...effect.loot };
    const miningBonus = effect.mining ? characterStats(next.state, content).mining_bonus : 0;
    if (effect.mining && loot.stone) loot.stone += miningBonus;
    for (const [item_id, quantity] of Object.entries(loot))
      addBagItem(next.state.bag!, { item_id, quantity, ...(item_id.startsWith('seed_') ? { seed_lot: 'bound' as const } : {}) }, content, true);
    if (Object.keys(effect.loot ?? {}).length) next.state.bag!.sequence++;
    if (effect.mining && miningBonus > 0) spendCharacterBuff(next.state, 'mining_bonus', content);
  }
  projectBagAggregates(next.state, content);
  next.version++;
  return next;
}

export function profile(farm: FarmRow, content: Content) {
  const state = structuredClone(farm.state);
  ensureBag(state, content);
  ensureCharacter(state, content);
  const stats = characterStats(state, content);
  const weapon = state.bag?.equipped.main_hand?.item_id ?? '';
  const spec = mainHandStats(state, content);
  return { hp: state.character!.hp!, max_hp: stats.max_hp, speed: stats.move_speed,
    defense: stats.defense, mining_bonus: stats.mining_bonus, ore_power: spec.ore_power, weapon,
    damage: Number(spec.damage ?? 0), attack_speed: Number(spec.speed ?? 1),
    reach: Number(spec.range ?? 0), knockback: Number(spec.knockback ?? 0),
    version: farm.version };
}

export function initialExpedition(content: Content, run = 0): Expedition {
  const floors: Record<string, Floor> = {};
  const positions: Point[] = [[2, -2.15], [4.5, -2.4], [7, -2], [2.5, -4.55], [4.8, -5.6], [7.35, -4.5]];
  for (let f = 1; f <= 5; f++) {
    const rocks = content.mining.rockless_floors.includes(f) ? [] :
      content.mining.rocks.map((rock, i) => ({ id: rock.id, position: positions[i], broken: false }));
    const floor: Floor = { rocks, monsters: [], cleared: false };
    const nav = mineNavigation(floor);
    floor.monsters = content.mining.combat.floors[String(f)].map((kind, i) => {
      const [x, z] = nearest(nav, [[4.75, -5], [2, -4.5], [7.5, -5.5]][i] as Point);
      return { id: `slime_${i + 1}`, kind, x, z, hp: content.mining.combat.monsters[kind].hp,
        phase: 'idle', timer: 0, direction: [0, 1], contributors: [] };
    });
    floors[String(f)] = floor;
  }
  return { run, floors, elevator: false };
}

export function mineNavigation(floor: Floor): Navigation {
  const rows: string[] = [];
  for (let y = 0; y < 18; y++) {
    let row = '';
    for (let x = 0; x < 20; x++) {
      const p: Point = [(x + .5) * .5, -(y + .5) * .5];
      row += x < 1 || x > 18 || y < 1 || y > 15 || distance(p, [1.25, -6.75]) < .85 ||
        floor.rocks.some(r => !r.broken && distance(p, r.position) < .65) ? '0' : '1';
    }
    rows.push(row);
  }
  return { cell: .5, rows, spawn: [4.75, -.75] };
}

export const distance = (a: Point, b: Point) => Math.hypot(a[0] - b[0], a[1] - b[1]);
export const walkable = (nav: Navigation, p: Point) =>
  nav.rows[Math.floor(-p[1] / nav.cell)]?.[Math.floor(p[0] / nav.cell)] === '1';
export function segment(nav: Navigation, a: Point, b: Point): boolean {
  if (!walkable(nav, a) || !walkable(nav, b)) return false;
  const cell = nav.cell;
  const minX = Math.max(0, Math.floor(Math.min(a[0], b[0]) / cell) - 1);
  const maxX = Math.min(nav.rows[0].length - 1, Math.floor(Math.max(a[0], b[0]) / cell) + 1);
  const minY = Math.max(0, Math.floor(Math.min(-a[1], -b[1]) / cell) - 1);
  const maxY = Math.min(nav.rows.length - 1, Math.floor(Math.max(-a[1], -b[1]) / cell) + 1);
  // BlueprintGrid uses closed cell AABBs. Sampling alone would miss a thin corner crossing.
  for (let y = minY; y <= maxY; y++) for (let x = minX; x <= maxX; x++) {
    if (nav.rows[y][x] === '1') continue;
    let enter = 0, exit = 1, intersects = true;
    const bounds: Point[] = [[x * cell, (x + 1) * cell], [-(y + 1) * cell, -y * cell]];
    for (let axis = 0; axis < 2; axis++) {
      const delta = b[axis] - a[axis], [low, high] = bounds[axis];
      if (Math.abs(delta) < 1e-12) { if (a[axis] < low || a[axis] > high) intersects = false; }
      else {
        const first = (low - a[axis]) / delta, second = (high - a[axis]) / delta;
        enter = Math.max(enter, Math.min(first, second)); exit = Math.min(exit, Math.max(first, second));
        if (enter > exit) intersects = false;
      }
      if (!intersects) break;
    }
    if (intersects) return false;
  }
  return true;
}
export function move(nav: Navigation, a: Point, b: Point, stride: number): Point {
  let p: Point = [...a];
  const length = distance(a, b);
  if (!length) return p;
  const travel = Math.min(length, stride);
  const steps = Math.max(1, Math.ceil(travel / (nav.cell * .2)));
  const dx = (b[0] - a[0]) / length * travel / steps, dz = (b[1] - a[1]) / length * travel / steps;
  for (let i = 0; i < steps; i++) {
    const next: Point = [p[0] + dx, p[1] + dz];
    if (segment(nav, p, next)) p = next;
    else {
      // Match PlayerMover's obstacle-edge sliding without crossing a blocked cell.
      const axes: Point[] = Math.abs(dx) >= Math.abs(dz) ? [[dx, 0], [0, dz]] : [[0, dz], [dx, 0]];
      for (const axis of axes) {
        const q: Point = [p[0] + axis[0], p[1] + axis[1]];
        if (segment(nav, p, q)) p = q;
      }
    }
  }
  return p;
}
export function nearest(nav: Navigation, p: Point): Point {
  let best = nav.spawn, d = Infinity;
  for (let z = 0; z < nav.rows.length; z++) for (let x = 0; x < nav.rows[z].length; x++) {
    const candidate: Point = [(x + .5) * nav.cell, -(z + .5) * nav.cell];
    if (walkable(nav, candidate) && distance(p, candidate) < d) { best = candidate; d = distance(p, candidate); }
  }
  return [...best];
}

export function lootRoll(key: string, drops: { item_id: string; quantity: number; weight: number }[]): Record<string, number> {
  let roll = createHash('sha256').update(key).digest().readUInt32BE(0) / 0x100000000 *
    drops.reduce((sum, d) => sum + d.weight, 0);
  for (const drop of drops) {
    if (roll < drop.weight) return drop.item_id ? { [drop.item_id]: drop.quantity } : {};
    roll -= drop.weight;
  }
  return {};
}
