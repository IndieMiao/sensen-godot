import { createHash } from 'node:crypto';
import type { Command } from './commands.js';
import type { Ctx } from './reducer.js';
import type { FarmState } from './state.js';
import { addBagItem, ensureBag, projectBagAggregates } from './bag.js';
import { err, ok, type Result } from './errors.js';

export interface FishingTier { name: string; bar_size: number; fish_speed: number; turn_steps: number; gain: number; loss: number }
export interface FishingSite { name: string; space: 'farm' | 'street'; stand: [number, number];
  center?: [number, number]; radii?: [number, number]; path?: [number, number][]; width?: number; fish_weights: number[] }
export interface FishingContent { version: 1; step_ms: number; max_steps: number; bite_min_ms: number; bite_spread_ms: number;
  hook_window_ms: number; settle_grace_ms: number; stand_radius: number; shore_range: number; max_cast: number; anchor_tolerance: number; bar_acceleration: number; bar_max_speed: number;
  initial_progress: number; tiers: Record<string, FishingTier>; fish: Record<string, { name: string; tier: number; price: number }>;
  sites: Record<string, FishingSite> }
/** Supplied by the realtime gateway under the farm command lock; never accepted from JSON. */
export interface FishingPresence { space: string; home: string; nonce: string; x: number; z: number; room?: string;
  /** Authoritative pond geometry of the joined host farm, including for visitors. */
  farm_site?: FishingSite;
  validSequence?: (sequence: number) => boolean; walkable?: (point: FishingPoint) => boolean }
export type FishingPresenceReader = () => FishingPresence | null;
export interface FishingCast { site: string; fish_id: string; seed: number; bite_at: number; hook_until: number;
  hooked_at?: number; nonce: string; rod_instance?: string; origin?: FishingPoint; target?: FishingPoint; home?: string; room?: string; cast_at?: number }
export interface FishingState { version: 1; sequence: number; active: FishingCast | null;
  last?: { sequence: number; outcome: 'caught' | 'escaped' | 'cancelled'; fish_id?: string; overflow?: boolean } }
export interface FishingSimulation { step: number; bar: number; velocity: number; fish: number; target: number; rng: number;
  progress: number; outcome: 'playing' | 'caught' | 'escaped' }

export function initialFishingSimulation(seed: number, c: FishingContent): FishingSimulation {
  return { step: 0, bar: .5, velocity: 0, fish: .5, target: .5, rng: seed, progress: c.initial_progress, outcome: 'playing' };
}
const clamp = (v: number, low: number, high: number) => Math.min(high, Math.max(low, v));
/** Fixed 50 ms input samples. The client runs the same simulation for immediate feedback. */
export function stepFishing(s: FishingSimulation, held: boolean, tier: FishingTier, c: FishingContent): void {
  if (s.outcome !== 'playing') return;
  const dt = c.step_ms / 1000;
  if (s.step % tier.turn_steps === 0) {
    s.rng = (Math.imul(s.rng, 1664525) + 1013904223) >>> 0;
    s.target = .1 + (s.rng / 4294967296) * .8;
  }
  s.fish += clamp(s.target - s.fish, -tier.fish_speed * dt, tier.fish_speed * dt);
  s.velocity = clamp(s.velocity + (held ? 1 : -1) * c.bar_acceleration * dt, -c.bar_max_speed, c.bar_max_speed);
  s.bar = clamp(s.bar + s.velocity * dt, tier.bar_size / 2, 1 - tier.bar_size / 2);
  if (s.bar === tier.bar_size / 2 || s.bar === 1 - tier.bar_size / 2) s.velocity = 0;
  s.progress = clamp(s.progress + (Math.abs(s.fish - s.bar) <= tier.bar_size / 2 ? tier.gain : -tier.loss) * dt, 0, 1);
  s.step++;
  if (s.progress >= 1) s.outcome = 'caught';
  else if (s.progress <= 0 || s.step >= c.max_steps) s.outcome = 'escaped';
}

export type FishingPoint = [number, number];
const length = (a: FishingPoint, b: FishingPoint) => Math.hypot(a[0] - b[0], a[1] - b[1]);
const point = (v: unknown): v is FishingPoint => Array.isArray(v) && v.length === 2 && v.every(n => typeof n === 'number' && Number.isFinite(n));
function nearestSegment(p: FishingPoint, a: FishingPoint, b: FishingPoint): FishingPoint {
  const dx = b[0] - a[0], dz = b[1] - a[1];
  const t = clamp(((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / Math.max(1e-9, dx * dx + dz * dz), 0, 1);
  return [a[0] + dx * t, a[1] + dz * t];
}
export function waterContains(site: FishingSite, p: FishingPoint): boolean {
  if (site.center && site.radii) return ((p[0] - site.center[0]) / site.radii[0]) ** 2 + ((p[1] - site.center[1]) / site.radii[1]) ** 2 <= 1;
  return site.path!.slice(1).some((b, i) => length(p, nearestSegment(p, site.path![i], b)) <= site.width! / 2);
}
/** Exact closest point for an outside ellipse; capsules use segment projection. */
export function nearestWater(site: FishingSite, p: FishingPoint): FishingPoint {
  if (waterContains(site, p)) return [...p];
  if (site.center && site.radii) {
    const q = [p[0] - site.center[0], p[1] - site.center[1]], a = site.radii;
    let lo = 0, hi = Math.max(...a) * Math.hypot(...q);
    for (let i = 0; i < 40; i++) {
      const t = (lo + hi) / 2;
      if (q.reduce((sum, v, j) => sum + (a[j] * v / (t + a[j] ** 2)) ** 2, 0) > 1) lo = t; else hi = t;
    }
    return [0, 1].map(i => site.center![i] + a[i] ** 2 * q[i] / (hi + a[i] ** 2)) as FishingPoint;
  }
  let nearest: FishingPoint = site.path![0];
  for (let i = 1; i < site.path!.length; i++) {
    const candidate = nearestSegment(p, site.path![i - 1], site.path![i]);
    if (length(candidate, p) < length(nearest, p)) nearest = candidate;
  }
  const d = length(nearest, p), r = site.width! / 2;
  return [nearest[0] + (p[0] - nearest[0]) * r / d, nearest[1] + (p[1] - nearest[1]) * r / d];
}
export function defaultFishingTarget(site: FishingSite, p: FishingPoint): FishingPoint {
  const edge = nearestWater(site, p), d = length(edge, p);
  const inset = Math.min(.55, site.width ? site.width / 2 : .55);
  return d > .001 ? [edge[0] + (edge[0] - p[0]) * inset / d, edge[1] + (edge[1] - p[1]) * inset / d] : edge;
}
export function validFishingCast(site: FishingSite, origin: FishingPoint, target: unknown, c: FishingContent,
  walkable: (p: FishingPoint) => boolean = () => true): target is FishingPoint {
  if (!point(target) || !point(origin) || waterContains(site, origin) || !walkable(origin)
    || length(origin, nearestWater(site, origin)) > c.shore_range || !waterContains(site, target)
    || length(origin, target) > c.max_cast || length(origin, target) < .45) return false;
  let wet = false;
  const steps = Math.ceil(length(origin, target) / .1);
  for (let i = 1; i <= steps; i++) {
    const p: FishingPoint = [origin[0] + (target[0] - origin[0]) * i / steps, origin[1] + (target[1] - origin[1]) * i / steps];
    if (waterContains(site, p)) wet = true;
    // Navigation conservatively blocks shore cells overlapping water. Allow that rim only.
    else if (wet || (!walkable(p) && length(p, nearestWater(site, p)) > .55)) return false;
  }
  return true;
}
function atSite(ctx: Ctx, site: FishingSite, active?: FishingCast, sequence = 0): boolean {
  const p = ctx.fishingPresence;
  if (!p || p.space !== site.space) return false;
  if (active && (p.nonce !== active.nonce || (active.home !== undefined && p.home !== active.home)
    || (active.room !== undefined && p.room !== active.room) || p.validSequence?.(sequence) === false)) return false;
  const origin: FishingPoint = [p.x, p.z];
  if (active?.origin && length(origin, active.origin) > ctx.content.fishing.anchor_tolerance) return false;
  return validFishingCast(site, origin, active?.target ?? defaultFishingTarget(site, origin), ctx.content.fishing, p.walkable);
}

function siteFor(ctx: Ctx, id: string): FishingSite | undefined {
  if (!Object.hasOwn(ctx.content.fishing.sites, id)) return undefined;
  return id === 'farm_pond' && ctx.fishingPresence?.space === 'farm' && ctx.fishingPresence.farm_site
    ? ctx.fishingPresence.farm_site : ctx.content.fishing.sites[id];
}

export function applyFishing(state: FarmState, cmd: Command, ctx: Ctx): Result<FarmState> | null {
  if (!['cast_fishing', 'hook_fishing', 'finish_fishing', 'cancel_fishing', 'sell_fish'].includes(cmd.type)) return null;
  const c = ctx.content.fishing;
  const next = structuredClone(state);
  ensureBag(next, ctx.content);
  if (cmd.type === 'sell_fish') {
    if (!Number.isSafeInteger(cmd.sequence) || cmd.sequence !== next.bag!.sequence) return err('BAG_CHANGED');
    const stack = [...next.bag!.slots, ...next.bag!.overflow].find(s => s.id === cmd.stack_id);
    const fish = stack && Object.hasOwn(c.fish, stack.item_id) ? c.fish[stack!.item_id] : undefined;
    if (!fish || !stack || !Number.isSafeInteger(cmd.quantity) || cmd.quantity <= 0 || cmd.quantity > stack.quantity)
      return err('INVALID_BAG_ACTION');
    const coins = fish.price * cmd.quantity;
    stack.quantity -= cmd.quantity;
    next.bag!.slots = next.bag!.slots.filter(s => s.quantity > 0);
    next.bag!.overflow = next.bag!.overflow.filter(s => s.quantity > 0);
    next.bag!.sequence++;
    next.wallet += coins;
    projectBagAggregates(next, ctx.content);
    return ok(next, [{ type: 'fish_sold', item_id: stack.item_id, quantity: cmd.quantity, coins }]);
  }
  if (!('sequence' in cmd) || !Number.isSafeInteger(cmd.sequence) || cmd.sequence !== (state.fishing?.sequence ?? 0))
    return err('FISHING_CHANGED');
  const fishing = next.fishing ??= { version: 1, sequence: 0, active: null };
  const now = ctx.realNow ?? ctx.now;
  const rod = next.bag!.equipped.fishing_rod;
  if (cmd.type !== 'cancel_fishing' && (!rod || ctx.content.character.equipment[rod.item_id]?.slot !== 'fishing_rod')) return err('FISHING_ROD_REQUIRED');
  if (cmd.type === 'cast_fishing') {
    const site = typeof cmd.site_id === 'string' ? siteFor(ctx, cmd.site_id) : undefined;
    if (!site || !atSite(ctx, site)) return err('FISHING_LOCATION');
    const presence = ctx.fishingPresence!, origin: FishingPoint = [presence.x, presence.z];
    const target = cmd.target === undefined ? defaultFishingTarget(site, origin) : cmd.target;
    if (!validFishingCast(site, origin, target, c, presence.walkable)) return err('FISHING_LOCATION');
    if (fishing.active && now <= (fishing.active.hooked_at ?? fishing.active.hook_until) + c.max_steps * c.step_ms + c.settle_grace_ms)
      return err('FISHING_ACTIVE');
    const digest = createHash('sha256').update(`${ctx.farmId}:${now}:${fishing.sequence}`).digest();
    let roll = digest.readUInt32BE(0) / 4294967296 * site.fish_weights.reduce((a, b) => a + b, 0);
    let tier = 1;
    for (let i = 0; i < site.fish_weights.length; i++) {
      tier = i + 1;
      roll -= site.fish_weights[i];
      if (roll < 0) break;
    }
    const candidates = Object.keys(c.fish).filter(id => c.fish[id].tier === tier);
    const bite = now + c.bite_min_ms + digest.readUInt32BE(4) % c.bite_spread_ms;
    fishing.sequence++;
    fishing.active = { site: cmd.site_id, fish_id: candidates[digest[12] % candidates.length],
      seed: digest.readUInt32BE(8), bite_at: bite, hook_until: bite + c.hook_window_ms, nonce: presence.nonce, rod_instance: rod!.instance_id, origin, target, home: presence.home, room: presence.room, cast_at: now };
    return ok(next, [{ type: 'fishing_cast', sequence: fishing.sequence }]);
  }
  const active = fishing.active;
  if (cmd.type === 'cancel_fishing') {
    if (active) {
      fishing.last = { sequence: fishing.sequence, outcome: 'cancelled' };
      fishing.active = null;
    }
    return ok(next);
  }
  if (!active) return err('FISHING_CHANGED');
  if (active.rod_instance && active.rod_instance !== rod?.instance_id) return err('FISHING_ROD_REQUIRED');
  const activeSite = siteFor(ctx, active.site);
  if (!activeSite || !atSite(ctx, activeSite, active, fishing.sequence)) return err('FISHING_LOCATION');
  if (cmd.type === 'hook_fishing') {
    if (active.hooked_at !== undefined) return err('FISHING_CHANGED');
    if (now < active.bite_at || now > active.hook_until) return err('FISHING_TIMING');
    active.hooked_at = now;
    return ok(next);
  }
  if (cmd.type === 'finish_fishing') {
    if (active.hooked_at === undefined || now > active.hooked_at + c.max_steps * c.step_ms + c.settle_grace_ms)
      return err('FISHING_TIMING');
    if (typeof cmd.inputs !== 'string' || !/^[01]+$/.test(cmd.inputs) || cmd.inputs.length > c.max_steps
      || cmd.inputs.length * c.step_ms > now - active.hooked_at + c.step_ms) return err('FISHING_INPUT');
    const simulation = initialFishingSimulation(active.seed, c);
    for (const input of cmd.inputs) {
      if (simulation.outcome !== 'playing') return err('FISHING_INPUT');
      stepFishing(simulation, input === '1', c.tiers[String(c.fish[active.fish_id].tier)], c);
    }
    if (simulation.outcome === 'playing') return err('FISHING_INPUT');
    if (simulation.outcome === 'caught') {
      const before = next.bag!.overflow.reduce((sum, s) => sum + s.quantity, 0);
      addBagItem(next.bag!, { item_id: active.fish_id, quantity: 1 }, ctx.content, true);
      next.bag!.sequence++;
      const overflow = next.bag!.overflow.reduce((sum, s) => sum + s.quantity, 0) > before;
      fishing.last = { sequence: fishing.sequence, outcome: 'caught', fish_id: active.fish_id, overflow };
    } else fishing.last = { sequence: fishing.sequence, outcome: 'escaped' };
    fishing.active = null;
    return ok(next, [{ type: 'fishing_result', ...fishing.last }]);
  }
  return err('NOT_AVAILABLE');
}
