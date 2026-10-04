/** P0 command reducer: one command → new state + events, or a typed refusal. Never mutates the input. */
import { cropById, cropBySeed, itemKind, type P0Content, type Skill } from './content.js';
import { dayKey, maxEnergy, nextTickIn, scaledXp, settleEnergy, skillLevel, xpPercent } from './rules.js';
import type { BagStack, P0State } from './state.js';

export type P0Command =
  | { type: 'till'; plot: number }
  | { type: 'sow'; plot: number; seed: string }
  | { type: 'water'; plot: number }
  | { type: 'harvest'; plot: number }
  | { type: 'buy'; item: string; qty: number }
  | { type: 'sell'; item: string; qty: number }
  | { type: 'rest' };

export type P0Event =
  | { kind: 'energy'; delta: number; reason: string }
  | { kind: 'xp'; skill: Skill; amount: number; percent: number }
  | { kind: 'item'; id: string; delta: number }
  | { kind: 'coins'; delta: number }
  | { kind: 'first'; what: string; xp: number }
  | { kind: 'level'; skill: Skill; level: number; energy: number; gifts: [string, number][] };

export type P0Result =
  | { ok: true; state: P0State; events: P0Event[] }
  | { ok: false; code: string; detail?: Record<string, unknown> };

const fail = (code: string, detail?: Record<string, unknown>): P0Result => ({ ok: false, code, detail });

export function applyP0(c: P0Content, input: P0State, cmd: P0Command, now: number): P0Result {
  const s = structuredClone(input);
  const events: P0Event[] = [];
  settleEnergy(c, s, now);
  rollDay(c, s, now);
  const plotOf = (id: unknown) => (Number.isInteger(id) ? s.plots.find(p => p.id === id) : undefined);

  switch (cmd.type) {
    case 'till': {
      const plot = plotOf(cmd.plot);
      if (!plot) return fail('bad_plot');
      if (plot.state !== 'wild') return fail('wrong_state', { state: plot.state });
      plot.state = 'tilled';
      break;
    }
    case 'sow': {
      const plot = plotOf(cmd.plot);
      if (!plot) return fail('bad_plot');
      if (plot.state !== 'tilled') return fail('wrong_state', { state: plot.state });
      const crop = cropBySeed(c, String(cmd.seed));
      if (!crop) return fail('bad_item');
      if (count(s.bag, crop.seed) < 1) return fail('no_seed', { seed: crop.seed });
      if (s.energy.value < crop.energy) return fail('need_energy', energyDetail(c, s, now, crop.energy));
      spendEnergy(c, s, now, crop.energy, events, 'sow');
      take(s.bag, crop.seed, 1);
      events.push({ kind: 'item', id: crop.seed, delta: -1 });
      plot.state = 'sown';
      plot.crop = crop.id;
      // §4.2.1: the level difference is locked at the moment the player pays.
      plot.xp_pct = xpPercent(c, skillLevel(c, s, 'farming'), crop.level);
      delete plot.ready_at;
      break;
    }
    case 'water': {
      const plot = plotOf(cmd.plot);
      if (!plot) return fail('bad_plot');
      if (plot.state !== 'sown' || !plot.crop) return fail('wrong_state', { state: plot.state });
      const crop = cropById(c, plot.crop)!;
      plot.state = 'growing';
      plot.ready_at = now + crop.grow_h * 3_600_000;
      break;
    }
    case 'harvest': {
      const plot = plotOf(cmd.plot);
      if (!plot) return fail('bad_plot');
      if (plot.state !== 'growing' || !plot.crop || (plot.ready_at ?? Infinity) > now)
        return fail('not_ready', { ready_in: plot.ready_at ? plot.ready_at - now : null });
      const crop = cropById(c, plot.crop)!;
      if (room(c, s.bag, crop.id) < crop.yield) return fail('bag_full', { need: crop.yield });
      add(c, s.bag, crop.id, crop.yield);
      events.push({ kind: 'item', id: crop.id, delta: crop.yield });
      gainXp(c, s, now, 'farming', scaledXp(s, crop.xp, plot.xp_pct ?? 100), plot.xp_pct ?? 100, events);
      const first = `harvest:${crop.id}`;
      if (!s.firsts.includes(first)) {
        s.firsts.push(first);
        events.push({ kind: 'first', what: first, xp: crop.first_xp });
        gainXp(c, s, now, 'farming', crop.first_xp, 100, events);
      }
      plot.state = 'tilled';
      delete plot.crop; delete plot.xp_pct; delete plot.ready_at;
      break;
    }
    case 'buy': {
      const qty = Number(cmd.qty);
      if (!Number.isInteger(qty) || qty < 1 || qty > 99) return fail('bad_qty');
      if (!c.stall.buy.includes(cmd.item)) return fail('bad_item');
      const crop = cropBySeed(c, cmd.item)!;
      const level = skillLevel(c, s, 'farming');
      if (level < crop.gate) return fail('locked', { skill: 'farming', level: crop.gate, xp_to_go: c.skills.farming[crop.gate - 1] - s.skills.farming });
      const cost = crop.seed_price * qty;
      if (s.coins < cost) return fail('no_coins', { need: cost - s.coins });
      if (room(c, s.bag, cmd.item) < qty) return fail('bag_full', { room: room(c, s.bag, cmd.item) });
      s.coins -= cost;
      add(c, s.bag, cmd.item, qty);
      events.push({ kind: 'coins', delta: -cost }, { kind: 'item', id: cmd.item, delta: qty });
      break;
    }
    case 'sell': {
      const qty = Number(cmd.qty);
      if (!Number.isInteger(qty) || qty < 1) return fail('bad_qty');
      const crop = cropById(c, cmd.item);
      if (!crop || itemKind(cmd.item) !== 'crop') return fail('not_sellable'); // §9.13.1: produce full price, no quota
      if (count(s.bag, cmd.item) < qty) return fail('not_enough', { have: count(s.bag, cmd.item) });
      take(s.bag, cmd.item, qty);
      s.coins += crop.price * qty;
      events.push({ kind: 'item', id: cmd.item, delta: -qty }, { kind: 'coins', delta: crop.price * qty });
      break;
    }
    case 'rest': {
      if (s.day.rest >= 1) return fail('rest_used');
      const max = maxEnergy(c, s);
      if (s.energy.value >= max) return fail('energy_full');
      const gain = Math.min(c.energy.rest_amount, max - s.energy.value);
      s.energy.value += gain;
      s.day.rest += 1;
      if (s.energy.value >= max) s.energy.tick_ms = now;
      events.push({ kind: 'energy', delta: gain, reason: 'rest' });
      break;
    }
    default:
      return fail('unknown_command');
  }
  s.seq += 1;
  return { ok: true, state: s, events };
}

export function energyDetail(c: P0Content, s: P0State, now: number, need: number) {
  return { need, have: s.energy.value, next_in: nextTickIn(c, s, now) };
}

function spendEnergy(c: P0Content, s: P0State, now: number, amount: number, events: P0Event[], reason: string): void {
  const wasFull = s.energy.value >= maxEnergy(c, s);
  s.energy.value -= amount;
  if (wasFull) s.energy.tick_ms = now;
  events.push({ kind: 'energy', delta: -amount, reason });
}

/** Add XP; every level crossed grants the one-time energy reward (may enter the bonus zone, §3.4.8) and gifts. */
function gainXp(c: P0Content, s: P0State, now: number, skill: Skill, amount: number, percent: number, events: P0Event[]): void {
  if (amount <= 0) { events.push({ kind: 'xp', skill, amount: 0, percent }); return; }
  const before = skillLevel(c, s, skill);
  s.skills[skill] += amount;
  events.push({ kind: 'xp', skill, amount, percent });
  const after = skillLevel(c, s, skill);
  for (let level = before + 1; level <= after; level++) {
    const firstEver = !s.rewards.includes('levelup_first');
    const energy = firstEver ? c.level_up_energy.first : c.level_up_energy.later;
    if (firstEver) s.rewards.push('levelup_first');
    const cap = maxEnergy(c, s) + c.energy.bonus_zone;
    const granted = Math.max(0, Math.min(energy, cap - s.energy.value));
    s.energy.value += granted;
    if (s.energy.value >= maxEnergy(c, s)) s.energy.tick_ms = now;
    const gifts = c.level_gifts[`${skill}:${level}`] ?? [];
    for (const [id, qty] of gifts) { const put = Math.min(qty, room(c, s.bag, id)); if (put > 0) add(c, s.bag, id, put); }
    events.push({ kind: 'level', skill, level, energy: granted, gifts });
  }
}

function rollDay(c: P0Content, s: P0State, now: number): void {
  const key = dayKey(c, now);
  if (s.day.key !== key) s.day = { key, rest: 0 };
}

// ---- bag (25 slots, stacking by kind) -------------------------------------------------------
export function count(bag: BagStack[], id: string): number { return bag.filter(b => b.id === id).reduce((n, b) => n + b.qty, 0); }
function stackLimit(c: P0Content, id: string): number { return c.bag.stack[itemKind(id)] ?? 99; }
export function room(c: P0Content, bag: BagStack[], id: string): number {
  const limit = stackLimit(c, id);
  const partial = bag.filter(b => b.id === id).reduce((n, b) => n + (limit - b.qty), 0);
  return partial + Math.max(0, c.bag.capacity - bag.length) * limit;
}
function add(c: P0Content, bag: BagStack[], id: string, qty: number): void {
  const limit = stackLimit(c, id);
  for (const b of bag) if (b.id === id && qty > 0) { const put = Math.min(qty, limit - b.qty); b.qty += put; qty -= put; }
  while (qty > 0 && bag.length < c.bag.capacity) { const put = Math.min(qty, limit); bag.push({ id, qty: put }); qty -= put; }
}
function take(bag: BagStack[], id: string, qty: number): void {
  // Take from the smallest stack first (§10.3.3 "从最少的堆扣起").
  const stacks = bag.filter(b => b.id === id).sort((a, b) => a.qty - b.qty);
  for (const b of stacks) { const put = Math.min(qty, b.qty); b.qty -= put; qty -= put; if (qty === 0) break; }
  for (let i = bag.length - 1; i >= 0; i--) if (bag[i].qty <= 0) bag.splice(i, 1);
}
