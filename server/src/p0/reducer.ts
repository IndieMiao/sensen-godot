/** P0 command reducer: one command → new state + events, or a typed refusal. Never mutates the input. */
import { cropById, cropBySeed, rodById, type P0Content } from './content.js';
import { add, count, room, take } from './bag.js';
import { collectPot, eatDish, startPot } from './cooking.js';
import { boardCommand, settleBoards, tracked } from './boards.js';
import { expireGiftMeals, giftResident, noteSown, residentRequestCommand, talk } from './residents.js';
import { castLine, reelLine, type FishCommand } from './fishing.js';
import { upgradeHomestead } from './homestead.js';
import { energyDetail, gainXp, spendEnergy, type P0Event } from './progress.js';
import { notePresence, restReadyIn } from './presence.js';
import { claimParcel, PARCEL_LIMIT, settleParcels } from './parcels.js';
import { dayKey, maxEnergy, scaledXp, settleEnergy, skillLevel, xpPercent } from './rules.js';
import { buyback, buyItem, drink, moveStorage, offerOf, sellItem, setLock } from './shops.js';
import { emptyDay, type P0State, type Plot } from './state.js';

export type { P0Event } from './progress.js';

/** Every command may carry `expect_seq`: the state version the client saw. A mismatch is refused as
 * `stale_state` without applying, so a retry after a lost response can never apply twice (SGODOT-211). */
export type P0Command = P0CommandBody & { expect_seq?: number; space?: string };

type P0CommandBody =
  | { type: 'till'; plot: number }
  | { type: 'sow'; plot?: number; plots?: number[]; seed: string }   // plots: up to 3 with the Row Hoe (§9.11.2)
  | { type: 'fertilize'; plot: number; item?: string }
  | { type: 'water'; plot: number }
  | { type: 'harvest'; plot: number }
  | { type: 'buy'; item: string; qty: number; shop?: string }
  | { type: 'equip'; item: string }
  | { type: 'sell'; item: string; qty: number | 'all'; shop?: string }
  | { type: 'drink'; item: string; shop?: string }
  | { type: 'lock' | 'unlock'; item: string }
  | { type: 'store' | 'take_out'; item: string; qty: number | 'all' }
  | { type: 'rest' }
  | FishCommand
  | { type: 'cook'; items?: string[]; recipe?: string }
  | { type: 'collect'; taps?: number[] }
  | { type: 'eat'; item: string }
  | { type: 'accept' | 'deliver' | 'drop'; request: string }
  | { type: 'homestead_upgrade' }
  | { type: 'talk'; resident: string }
  | { type: 'gift'; resident: string; item: string }
  | { type: 'claim_parcel'; key: string }
  | { type: 'claim_parcels'; keys: string[] }   // Claim all: the keys on screen, so a retry never takes a newer parcel
  | { type: 'read_inbox'; keys: string[] };

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
  settleBoards(c, s, now);
  settleParcels(c, s, now);
  notePresence(c, s, cmd.space, now, events);   // before the command: a session gap of ≥ 2 h already counts as having left
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
      // One plot, or up to the equipped hoe's count (Row Hoe: Sow ×3 · 6 Energy, still 2 per plot, §9.11.2).
      const ids: unknown[] = Array.isArray(cmd.plots) ? cmd.plots : [cmd.plot];
      const most = s.gear.hoe === c.tools.row_hoe.id ? c.tools.row_hoe.sow : 1;
      if (ids.length < 1 || ids.length > most || new Set(ids).size !== ids.length) return fail('bad_plot', { most });
      const plots = ids.map(plotOf);
      if (plots.some(p => !p)) return fail('bad_plot');
      const wrong = plots.find(p => p!.state !== 'tilled');
      if (wrong) return fail('wrong_state', { plot: wrong.id, state: wrong.state });
      const crop = cropBySeed(c, String(cmd.seed));
      if (!crop) return fail('bad_item');
      const n = plots.length, seeds = count(s.bag, crop.seed);
      if (seeds < n) return fail('no_seed', { seed: crop.seed, need: n, have: seeds });
      if (s.energy.value < crop.energy * n) return fail('need_energy', energyDetail(c, s, now, crop.energy * n));
      spendEnergy(c, s, now, crop.energy * n, events, 'sow');
      take(s.bag, crop.seed, n);
      events.push({ kind: 'item', id: crop.seed, delta: -n });
      // §4.2.1: the level difference is locked at the moment the player pays.
      const pct = xpPercent(c, skillLevel(c, s, 'farming'), crop.level);
      noteSown(c, s, n);
      for (const plot of plots as Plot[]) {
        plot.state = 'sown';
        plot.crop = crop.id;
        plot.xp_pct = pct;
        delete plot.ready_at; delete plot.fert;
      }
      break;
    }
    case 'fertilize': {
      // §5.5: one Compost per plot, any time after sowing and before it is ripe; 0 Energy; never stacks.
      const plot = plotOf(cmd.plot);
      if (!plot) return fail('bad_plot');
      const ripe = plot.state === 'growing' && (plot.ready_at ?? Infinity) <= now;
      if ((plot.state !== 'sown' && plot.state !== 'growing') || ripe || !plot.crop) return fail('wrong_state', { state: ripe ? 'ready' : plot.state });
      if (plot.fert) return fail('fertilized');
      const item = String(cmd.item ?? 'fert_compost'), fert = c.goods[item];
      if (!fert?.grow_mult) return fail('bad_item');
      if (count(s.bag, item) < 1) return fail('no_item', { item });
      take(s.bag, item, 1);
      events.push({ kind: 'item', id: item, delta: -1 });
      plot.fert = true;
      if (plot.state === 'growing') {
        const grow = cropById(c, plot.crop)!.grow_h * 3_600_000;
        plot.ready_at = Math.max(now, plot.ready_at! - Math.round(grow * (1 - fert.grow_mult)));
      }
      break;
    }
    case 'water': {
      const plot = plotOf(cmd.plot);
      if (!plot) return fail('bad_plot');
      if (plot.state !== 'sown' || !plot.crop) return fail('wrong_state', { state: plot.state });
      const crop = cropById(c, plot.crop)!;
      plot.state = 'growing';
      plot.ready_at = now + Math.round(crop.grow_h * 3_600_000 * (plot.fert ? c.goods.fert_compost.grow_mult ?? 1 : 1));
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
      delete plot.crop; delete plot.xp_pct; delete plot.ready_at; delete plot.fert;
      break;
    }
    case 'buy': case 'sell': case 'drink': case 'lock': case 'unlock': case 'store': case 'take_out': {
      const refusal = cmd.type === 'buy' ? buyItem(c, s, cmd, events)
        : cmd.type === 'sell' ? sellItem(c, s, cmd, now, events)
        : cmd.type === 'drink' ? drink(c, s, cmd, now, events)
        : cmd.type === 'lock' || cmd.type === 'unlock' ? setLock(c, s, cmd, cmd.type === 'lock')
        : moveStorage(c, s, cmd, cmd.type === 'store', events);
      if (refusal) return fail(refusal.code, refusal.detail);
      break;
    }
    case 'rest': {
      if (s.day.rest >= 1) return fail('rest_used');
      // q(41): at home, 2 h after last leaving it. Older clients send no space; they keep the old rule.
      if (cmd.space !== undefined) {
        if (cmd.space !== 'home') return fail('not_home');
        const wait = restReadyIn(c, s, now);
        if (wait === null || wait > 0) return fail('away_short', { ready_in: wait, away_h: c.energy.rest_away_h });
      }
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
      const id = String(cmd.item);
      if (s.gear.rods.includes(id) && rodById(c, id)) s.gear.rod = id;
      else if (s.gear.hoes.includes(id)) s.gear.hoe = id;
      else return fail('not_owned');
      break;
    }
    case 'accept': case 'deliver': case 'drop': {
      const id = String(cmd.request ?? '');
      const refusal = id.startsWith('req_res_') ? residentRequestCommand(c, s, cmd.type, id, now, events, tracked(s))
        : boardCommand(c, s, cmd.type, id, now, events);
      if (refusal) return fail(refusal.code, refusal.detail);
      break;
    }
    case 'talk': case 'gift': {
      const refusal = cmd.type === 'talk' ? talk(c, s, cmd, events) : giftResident(c, s, cmd, events);
      if (refusal) return fail(refusal.code, refusal.detail);
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
    case 'claim_parcel': {
      const refusal = claimParcel(c, s, now, String(cmd.key), events);
      if (refusal) return fail(refusal.code, refusal.detail);
      break;
    }
    case 'claim_parcels': {
      if (!Array.isArray(cmd.keys) || cmd.keys.length > PARCEL_LIMIT || cmd.keys.some(k => typeof k !== 'string')) return fail('bad_parcel');
      // Claim all takes what the free slots hold, in the order shown; the rest stays for later.
      let took = 0;
      for (const key of new Set(cmd.keys)) {
        if (s.inbox.parcels.some(p => p.key === key) && !claimParcel(c, s, now, key, events)) took += 1;
      }
      if (took === 0 && s.inbox.parcels.some(p => cmd.keys.includes(p.key))) return fail('bag_full', { slots: 1 });
      break;
    }
    case 'read_inbox': {
      if (!Array.isArray(cmd.keys) || cmd.keys.length > 100 || cmd.keys.some(k => typeof k !== 'string')) return fail('bad_parcel');
      for (const u of s.inbox.updates) if (cmd.keys.includes(u.key)) u.read = true;
      break;
    }
    default:
      return fail('unknown_command');
  }
  s.seq += 1;
  return { ok: true, state: s, events };
}

/** What the Homestead Stall / Tackle Shop list shows for one item (view). */
export function stallOffer(c: P0Content, id: string): { price: number; skill: 'farming' | 'fishing' | 'cooking'; gate: number; daily: number } {
  const o = offerOf(c, id)!;
  return { price: o.price, skill: o.skill ?? 'farming', gate: o.gate, daily: o.daily };
}

/** Full price at the Homestead Stall (crops, fish; dishes and materials at their buyback), or null when it can't be sold there. */
export function sellPrice(c: P0Content, id: string): number | null {
  const b = buyback(c, 'homestead', id);
  return 'code' in b ? null : b.unit;
}

function rollDay(c: P0Content, s: P0State, now: number): void {
  const key = dayKey(c, now);
  if (s.day.key !== key) s.day = emptyDay(key);
  expireGiftMeals(s);
}

export { count, room };
