/**
 * Stall Board and Market Board (plan §9.6, §9.13.2): drawn per player from the template pool, refilled 4 h after a
 * delivery and 8 h after a drop; an untaken request is swapped after 72 h. Draws happen in settleBoards, which the
 * view runs on a copy and every command runs on the save: ids and draw times come from the slot (its refill time),
 * never from the request's clock, so the id a client saw is the id the next command finds. Draws use their own
 * stream seeded by player, board, slot and time, so they never shift the fishing or cooking rolls.
 */
import { dishParts, type BoardId, type P0Content, type RequestTemplate } from './content.js';
import type { Refusal } from './fishing.js';
import { boardSlots } from './homestead.js';
import type { P0Event } from './progress.js';
import { handOver, haveFor, floorPrice, noteDone, payBonus, pick } from './requests.js';
import { skillLevel, untilRollover } from './rules.js';
import type { BoardRequest, BoardSlot, P0State } from './state.js';

const H = 3_600_000;
export const BOARDS: readonly BoardId[] = ['stall', 'market'];

export function slotCount(c: P0Content, s: P0State, board: BoardId): number {
  return board === 'stall' ? boardSlots(c, s) : c.requests.boards.market.slots ?? 2;
}

function gateMet(c: P0Content, s: P0State, t: RequestTemplate): boolean {
  return t.gate.length === 0 || t.gate.some(([skill, level]) => skillLevel(c, s, skill) >= level);
}

/** §9.6.1: regional templates are drawn only where their climate is (P1: the home climate until travel lands). */
function climateMet(c: P0Content, t: RequestTemplate): boolean {
  return !t.climate?.length || t.climate.includes(c.profile.climate);
}

export function eligible(c: P0Content, s: P0State, board: BoardId): string[] {
  return c.requests.boards[board].templates.filter(id => {
    const t = c.requests.templates[id];
    return t.enabled !== false && gateMet(c, s, t) && climateMet(c, t);
  });
}

/** What an empty board shows while no template is open yet: the lowest gate (e.g. Market Basket · Farming Lv4). */
export function lockedTemplate(c: P0Content, s: P0State, board: BoardId): { template: string; gate: [string, number][] } | null {
  const closed = c.requests.boards[board].templates.filter(id => c.requests.templates[id].enabled !== false);
  if (eligible(c, s, board).length || !closed.length) return null;
  const low = (id: string) => Math.min(...c.requests.templates[id].gate.map(g => g[1]));
  const template = [...closed].sort((a, b) => low(a) - low(b))[0];
  return { template, gate: c.requests.templates[template].gate };
}

type Rand = () => number;

/** mulberry32 seeded from the slot's identity: the same slot at the same time always draws the same request. */
function slotRand(s: P0State, board: BoardId, slot: number, at: number): Rand {
  let h = 2166136261;
  for (const ch of `${s.player}:${board}:${slot}:${at}`) h = Math.imul(h ^ ch.charCodeAt(0), 16777619);
  let a = h | 0;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), a | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Quantity by the template's skill level: Lv1–3 2–3, Lv4–6 4–6, Lv7–10 6–10 (§9.6.2). */
function qtyFor(c: P0Content, s: P0State, t: RequestTemplate, draw: Rand): number {
  const level = skillLevel(c, s, t.skill);
  let band = c.requests.qty[0];
  for (const row of c.requests.qty) if (level >= row[0]) band = row;
  return band[1] + Math.floor(draw() * (band[2] - band[1] + 1));
}

/** Crops the player can already buy seeds for (§9.6.2: a request never asks for what can't be grown yet). */
function growable(c: P0Content, s: P0State): string[] {
  const level = skillLevel(c, s, 'farming');
  return c.crops.filter(cr => cr.gate <= level).map(cr => cr.id);
}

function drawRequest(c: P0Content, s: P0State, board: BoardId, slot: number, at: number): BoardRequest | null {
  const open = eligible(c, s, board);
  if (!open.length) return null;
  const draw = slotRand(s, board, slot, at);
  const taken = s.boards[board].map(sl => sl.req?.template);
  const fresh = open.filter(t => !taken.includes(t));
  const pool = fresh.length ? fresh : open;
  const template = pool[Math.floor(draw() * pool.length)];
  const t = c.requests.templates[template];
  let items: string[] = [];
  if (t.need.id) items = [t.need.id];   // a template naming one crop, fish or material asks for exactly that
  else if (t.need.kind === 'crop') {
    const crops = growable(c, s);
    for (let i = crops.length - 1; i > 0; i--) { const j = Math.floor(draw() * (i + 1)); [crops[i], crops[j]] = [crops[j], crops[i]]; }
    items = crops.slice(0, t.need.distinct ?? 1);
  }
  return {
    id: `${template}-${board}${slot}-${at.toString(36)}`, template, items, rarity: t.need.rarity,
    ...(t.need.style ? { style: t.need.style } : {}), kind: t.need.kind as BoardRequest['kind'],
    qty: qtyFor(c, s, t, draw), bonus: t.bonus, drawn_at: at, status: 'open',
  };
}

/** Bring both boards up to now: slot count follows the Homestead level; empty slots refill; untaken requests expire. */
export function settleBoards(c: P0Content, s: P0State, now: number): void {
  for (const board of BOARDS) {
    const slots = s.boards[board];
    // §14.1.2: a Stall Board slot added in the account's first 72 h (slot 2 at creation, slot 3 from a Homestead Lv3
    // reached that early) stays empty until created_at + refill_h, so the first session has one request; a slot added
    // later fills at once.
    while (slots.length < slotCount(c, s, board))
      slots.push({ req: null, refill_at: board === 'stall' ? s.created_at + c.requests.refill_h * H : s.created_at });
    slots.forEach((sl: BoardSlot, i) => {
      // The tutorial request is once per account and never swapped out.
      while (sl.req?.status === 'open' && sl.req.id !== c.requests.tutorial.id && now >= sl.req.drawn_at + c.requests.expire_h * H) {
        const at = sl.req.drawn_at + c.requests.expire_h * H;
        sl.req = drawRequest(c, s, board, i, at);
        sl.refill_at = at;
      }
      if (!sl.req && now >= sl.refill_at) sl.req = drawRequest(c, s, board, i, sl.refill_at);
    });
  }
}

/**
 * §14.1.2: a Stall Board slot added in the account's first refill_h (72 h) stays empty until created_at + refill_h —
 * slot 2 at creation, and any slot a Homestead upgrade adds in that time. Until it fills it is a held slot (q(99),
 * 李白 / 不知火舞; wording 周瑜 on #168): the view draws it as a plain empty slot with no countdown and leaves it out of
 * `Next request`, which counts only slots refilling after a delivery or a drop. The rule itself is unchanged.
 */
export function heldSlot(c: P0Content, s: P0State, board: BoardId, sl: BoardSlot): boolean {
  return board === 'stall' && !sl.req && sl.refill_at === s.created_at + c.requests.refill_h * H;
}

export function findBoardRequest(s: P0State, id: string): { board: BoardId; slot: BoardSlot } | null {
  for (const board of BOARDS) for (const slot of s.boards[board]) if (slot.req?.id === id) return { board, slot };
  return null;
}

export function tracked(s: P0State): number {
  return BOARDS.reduce((n, b) => n + s.boards[b].filter(sl => sl.req?.status === 'accepted').length, 0)
    + Object.values(s.residents).filter(r => r.req).length;
}

/** The bag units a board request would take now, or null when short. */
export function handIn(c: P0Content, s: P0State, r: BoardRequest): [string, number][] | null {
  if (r.items.length > 1) {   // Market Basket: N of each of the drawn crops
    const out: [string, number][] = [];
    for (const item of r.items) {
      const part = pick(c, s, { kind: r.kind }, [item], r.qty);
      if (!part) return null;
      out.push(...part);
    }
    return out;
  }
  return pick(c, s, { kind: r.kind, rarity: r.rarity, style: r.style }, r.items, r.qty);
}

/** Coins for a hand-in: floor prices, a dish quality bonus on the whole request (lowest quality handed in), the bonus capped daily. */
export function payout(c: P0Content, r: BoardRequest, parts: [string, number][]): { base: number; bonus: number } {
  const quality = r.kind === 'dish' && parts.length ? Math.min(...parts.map(([id]) => dishParts(id).quality)) : 0;
  const mult = 1 + (c.requests.quality_bonus[quality] ?? 0);
  const floor = parts.reduce((n, [id, q]) => n + floorPrice(c, id) * q, 0);
  return { base: Math.floor(floor * mult + 1e-9), bonus: Math.floor(r.bonus * mult + 1e-9) };
}

export function boardCommand(c: P0Content, s: P0State, type: 'accept' | 'deliver' | 'drop', id: string, now: number, events: P0Event[]): Refusal | null {
  const found = findBoardRequest(s, id);
  if (!found) return { code: s.req_done.includes(id) ? 'request_done' : 'bad_request' };
  const { slot } = found, r = slot.req!;
  if (type === 'accept') {
    if (r.status === 'accepted') return { code: 'already_accepted' };
    if (tracked(s) >= c.requests.track_max) return { code: 'track_limit', detail: { max: c.requests.track_max } };
    r.status = 'accepted';
    events.push({ kind: 'request', id, status: 'accepted', coins: 0 });
    return null;
  }
  if (type === 'drop') {
    slot.req = null;
    slot.refill_at = now + c.requests.drop_refill_h * H;
    events.push({ kind: 'request', id, status: 'dropped', coins: 0 });
    return null;
  }
  if (s.day.sys_done >= c.quotas.sys_requests.cap)
    return { code: 'daily_limit', detail: { cap: c.quotas.sys_requests.cap, resets_in: untilRollover(c, now) } };
  const parts = handIn(c, s, r);
  if (!parts) {
    const short = r.items.length > 1 ? r.items.find(item => haveFor(c, s, { kind: r.kind }, [item]) < r.qty)! : null;
    return { code: 'not_enough', detail: short
      ? { item: short, need: r.qty, have: haveFor(c, s, { kind: r.kind }, [short]) }
      : { item: r.items[0] ?? null, need: r.qty, have: haveFor(c, s, { kind: r.kind, rarity: r.rarity, style: r.style }, r.items) } };
  }
  for (const [item, n] of parts) { handOver(c, s, item, n); events.push({ kind: 'item', id: item, delta: -n }); }
  const pay = payout(c, r, parts);
  const bonus = payBonus(c, s, pay.bonus);
  s.coins += pay.base + bonus;
  s.day.sys_done += 1;
  slot.req = null;
  slot.refill_at = now + c.requests.done_refill_h * H;
  noteDone(s, id);
  events.push({ kind: 'coins', delta: pay.base + bonus }, { kind: 'request', id, status: 'done', coins: pay.base + bonus, bonus });
  return null;
}
