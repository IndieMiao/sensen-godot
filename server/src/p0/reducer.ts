/** P0 command reducer: one command → new state + events, or a typed refusal. Never mutates the input. */
import { cropById, cropBySeed, fishById, itemKind, rodById, type P0Content } from './content.js';
import { add, count, room, take } from './bag.js';
import { collectPot, eatDish, startPot } from './cooking.js';
import { castLine, reelLine, type FishCommand } from './fishing.js';
import { upgradeHomestead } from './homestead.js';
import { energyDetail, gainXp, spendEnergy, type P0Event } from './progress.js';
import { dayKey, maxEnergy, scaledXp, settleEnergy, skillLevel, xpPercent } from './rules.js';
import { emptyDay, type P0State } from './state.js';

export type { P0Event } from './progress.js';

/** Every command may carry `expect_seq`: the state version the client saw. A mismatch is refused as
 * `stale_state` without applying, so a retry after a lost response can never apply twice (SGODOT-211). */
export type P0Command = P0CommandBody & { expect_seq?: number };

type P0CommandBody =
  | { type: 'till'; plot: number }
  | { type: 'sow'; plot: number; seed: string }
  | { type: 'water'; plot: number }
  | { type: 'harvest'; plot: number }
  | { type: 'buy'; item: string; qty: number; shop?: 'stall' | 'tackle' }
  | { type: 'equip'; item: string }
  | { type: 'sell'; item: string; qty: number }
  | { type: 'rest' }
  | FishCommand
  | { type: 'cook'; items?: string[]; recipe?: string }
  | { type: 'collect'; taps?: number[] }
  | { type: 'eat'; item: string }
  | { type: 'accept'; request: string }
  | { type: 'deliver'; request: string }
  | { type: 'homestead_upgrade' };

export type P0Result =
  | { ok: true; state: P0State; events: P0Event[] }
  | { ok: false; code: string; detail?: Record<string, unknown> };

const fail = (code: string, detail?: Record<string, unknown>): P0Result => ({ ok: false, code, detail });

export function applyP0(c: P0Content, input: P0State, cmd: P0Command, now: number): P0Result {
  if (cmd.expect_seq !== undefined && cmd.expect_seq !== input.seq) {
    return fail('stale_state', { seq: input.seq, expected: cmd.expect_seq });
  }
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
      if (room(c, s, crop.id) < crop.yield) return fail('bag_full', { need: crop.yield });
      add(c, s, crop.id, crop.yield);
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
      const list = cmd.shop === 'tackle' ? c.tackle.buy : c.stall.buy;
      if (!list.includes(cmd.item)) return fail('bad_item');
      const offer = stallOffer(c, cmd.item);
      const level = skillLevel(c, s, offer.skill);
      if (level < offer.gate) return fail('locked', { skill: offer.skill, level: offer.gate, xp_to_go: c.skills[offer.skill][offer.gate - 1] - s.skills[offer.skill] });
      if (offer.daily && (s.day.bought[cmd.item] ?? 0) + qty > offer.daily)
        return fail('sold_out', { left: Math.max(0, offer.daily - (s.day.bought[cmd.item] ?? 0)) });
      const cost = offer.price * qty;
      if (s.coins < cost) return fail('no_coins', { need: cost - s.coins });
      if (itemKind(cmd.item) === 'rod') {
        // Rods go to Tools & Gear, not the bag; a new rod is equipped right away (switch back any time).
        if (qty !== 1) return fail('bad_qty');
        if (s.gear.rods.includes(cmd.item)) return fail('owned');
        s.coins -= cost;
        s.gear.rods.push(cmd.item);
        s.gear.rod = cmd.item;
        events.push({ kind: 'coins', delta: -cost }, { kind: 'item', id: cmd.item, delta: 1 });
        break;
      }
      if (room(c, s, cmd.item) < qty) return fail('bag_full', { room: room(c, s, cmd.item) });
      s.coins -= cost;
      if (offer.daily) s.day.bought[cmd.item] = (s.day.bought[cmd.item] ?? 0) + qty;
      add(c, s, cmd.item, qty);
      events.push({ kind: 'coins', delta: -cost }, { kind: 'item', id: cmd.item, delta: qty });
      break;
    }
    case 'sell': {
      const qty = Number(cmd.qty);
      if (!Number.isInteger(qty) || qty < 1) return fail('bad_qty');
      const price = sellPrice(c, cmd.item); // §9.13.1 / §6.6.3: produce and fish full price at home, no quota
      if (price === null) return fail('not_sellable');
      if (count(s.bag, cmd.item) < qty) return fail('not_enough', { have: count(s.bag, cmd.item) });
      take(s.bag, cmd.item, qty);
      s.coins += price * qty;
      events.push({ kind: 'item', id: cmd.item, delta: -qty }, { kind: 'coins', delta: price * qty });
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
    case 'equip': {
      if (!rodById(c, String(cmd.item)) || !s.gear.rods.includes(String(cmd.item))) return fail('not_owned');
      s.gear.rod = String(cmd.item);
      break;
    }
    case 'accept': case 'deliver': {
      const req = s.requests.find(r => r.id === String(cmd.request));
      if (!req) return fail('bad_request');
      if (req.status === 'done') return fail('request_done');
      if (cmd.type === 'accept') {
        if (req.status === 'accepted') return fail('already_accepted');
        req.status = 'accepted';
        events.push({ kind: 'request', id: req.id, status: 'accepted', coins: 0 });
        break;
      }
      const have = count(s.bag, req.item);
      if (have < req.qty) return fail('not_enough', { item: req.item, need: req.qty, have });
      take(s.bag, req.item, req.qty);
      s.coins += req.coins;
      req.status = 'done';
      events.push({ kind: 'item', id: req.item, delta: -req.qty }, { kind: 'coins', delta: req.coins },
        { kind: 'request', id: req.id, status: 'done', coins: req.coins });
      break;
    }
    case 'homestead_upgrade': {
      const refusal = upgradeHomestead(c, s, now, events);
      if (refusal) return fail(refusal.code, refusal.detail);
      break;
    }
    case 'cast': case 'reel': case 'cook': case 'collect': case 'eat': {
      const refusal = cmd.type === 'cast' ? castLine(c, s, cmd, now, events)
        : cmd.type === 'reel' ? reelLine(c, s, cmd, now, events)
        : cmd.type === 'cook' ? startPot(c, s, cmd, now, events)
        : cmd.type === 'collect' ? collectPot(c, s, cmd, now, events)
        : eatDish(c, s, cmd, now, events, maxEnergy(c, s));
      if (refusal) return fail(refusal.code, refusal.detail);
      break;
    }
    default:
      return fail('unknown_command');
  }
  s.seq += 1;
  return { ok: true, state: s, events };
}

/** What the stall sells: seeds priced by their crop, goods (bait) by the goods table. */
export function stallOffer(c: P0Content, id: string): { price: number; skill: 'farming' | 'fishing' | 'cooking'; gate: number; daily: number } {
  const crop = cropBySeed(c, id);
  if (crop) return { price: crop.seed_price, skill: 'farming', gate: crop.gate, daily: 0 };
  const rod = rodById(c, id);
  if (rod) return { price: rod.price, skill: 'fishing', gate: rod.level, daily: 0 };
  const g = c.goods[id];
  return { price: g.price, skill: g.skill, gate: g.gate, daily: g.daily };
}

export function sellPrice(c: P0Content, id: string): number | null {
  if (itemKind(id) === 'crop') return cropById(c, id)?.price ?? null;
  if (itemKind(id) === 'fish') return fishById(c, id)?.price ?? null;
  return null;
}

function rollDay(c: P0Content, s: P0State, now: number): void {
  const key = dayKey(c, now);
  if (s.day.key !== key) s.day = emptyDay(key);
}

export { count, room };
