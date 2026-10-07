/**
 * Residents Pip and Old Kai (plan §9.4.3–9.4.4, §3.4.5, §7.6.3; Li Bai on SGODOT-228 b7d8b665 / 719ce953 / 4be9eb7d):
 * affinity in five stages (P0 counts and shows them), a first chat a day, one gift a day, the day's single gift meal
 * across all residents, and each resident's request line. Requests pay coins against the daily bonus cap, never XP.
 */
import { add, count, freeSlots, take } from './bag.js';
import { dishParts, itemKind, recipeById, type P0Content, type ResidentDef, type ResidentRequest } from './content.js';
import { recipeRarity } from './cooking.js';
import type { Refusal } from './fishing.js';
import type { P0Event } from './progress.js';
import { floorPrice, handOver, haveFor, noteDone, payBonus, pick } from './requests.js';
import { skillLevel, untilRollover } from './rules.js';
import type { P0State, ResidentState } from './state.js';

export function residentDef(c: P0Content, id: string): ResidentDef | null { return c.residents[id] ?? null; }

export function residentState(s: P0State, id: string): ResidentState {
  return s.residents[id] ??= { affinity: 0, chat_day: '', gift_day: '', next: 0, req: null, done_day: '' };
}

/** Stage index for points: 0 Stranger … 4 Kindred. */
export function stageIndex(c: P0Content, points: number): number {
  let i = 0;
  c.affinity.stages.forEach(([, from], k) => { if (points >= from) i = k; });
  return i;
}
const stageAt = (c: P0Content, name: string) => Math.max(0, c.affinity.stages.findIndex(([n]) => n === name));

/** Points change, never below the floor of the current stage (q(33): a stage never goes back). */
function addAffinity(c: P0Content, s: P0State, id: string, delta: number, reason: string, events: P0Event[], verdict?: string): void {
  const r = residentState(s, id);
  const floor = c.affinity.stages[stageIndex(c, r.affinity)][1];
  const before = r.affinity;
  r.affinity = Math.max(floor, r.affinity + delta);
  events.push({ kind: 'affinity', resident: id, delta: r.affinity - before, total: r.affinity,
    stage: c.affinity.stages[stageIndex(c, r.affinity)][0], reason, ...(verdict ? { verdict } : {}) });
}

/** The resident's next request, or why there is none: done for today, a stage away, or none left. */
export function requestState(c: P0Content, s: P0State, id: string): { req: ResidentRequest | null; state: 'open' | 'accepted' | 'wait' | 'stage' | 'none'; need_stage?: string } {
  const def = residentDef(c, id)!, r = residentState(s, id);
  if (r.req) return { req: def.requests.find(q => q.id === r.req!.id) ?? null, state: 'accepted' };
  const next = def.requests[r.next];
  if (!next) return { req: null, state: 'none' };
  if (def.one_per_day && r.done_day === s.day.key) return { req: next, state: 'wait' };
  if (stageIndex(c, r.affinity) < stageAt(c, next.stage)) return { req: next, state: 'stage', need_stage: next.stage };
  return { req: next, state: 'open' };
}

/** Units the bag holds for a resident request (sow requests count plots sown since accepting). */
export function progressOf(c: P0Content, s: P0State, id: string, q: ResidentRequest): number {
  if (q.need.kind === 'sow') return residentState(s, id).req?.progress ?? 0;
  return haveFor(c, s, q.need, q.need.id ? [q.need.id] : []);
}

/** Today's gift meal (§3.4.5): from Familiar, one a day across all residents; not given while the bag is full (q(33)). */
function offerGiftMeal(c: P0Content, s: P0State, id: string, events: P0Event[]): void {
  const def = residentDef(c, id)!;
  if (s.day.gift_meal || stageIndex(c, residentState(s, id).affinity) < stageAt(c, c.affinity.gift_meal_stage)) return;
  if (freeSlots(s) < 1) {   // a gift meal is its own stack, so it needs an empty slot
    events.push({ kind: 'gift_meal', resident: id, dish: def.gift_meal, given: false });
    return;
  }
  add(c, s, def.gift_meal, 1, { from: id, day: s.day.key });
  s.day.gift_meal = id;
  events.push({ kind: 'gift_meal', resident: id, dish: def.gift_meal, given: true }, { kind: 'item', id: def.gift_meal, delta: 1 });
}

/** Opening a resident's dialogue bar: +2 on the first chat of the day, then the day's gift meal if it is theirs to give. */
export function talk(c: P0Content, s: P0State, cmd: { resident?: unknown }, events: P0Event[]): Refusal | null {
  const id = String(cmd.resident ?? '');
  if (!residentDef(c, id)) return { code: 'bad_resident' };
  const r = residentState(s, id);
  if (r.chat_day !== s.day.key) {
    r.chat_day = s.day.key;
    addAffinity(c, s, id, c.affinity.first_chat, 'chat', events);
  }
  offerGiftMeal(c, s, id, events);
  return null;
}

/** §7.6.3 / §9.4.4: liked style and ≥ Fine +3, liked +2, any dish +1; Perfect +1 (cap 4); Cooking Lv9 +1 (cap 5); Mystery Dish −2. */
export function giftPoints(c: P0Content, s: P0State, def: ResidentDef, item: string): { delta: number; verdict: string } {
  const g = c.affinity.gift, { base, quality } = dishParts(item);
  if (base === c.cooking.mystery.id) return { delta: g.mystery, verdict: 'not_a_fan' };
  const recipe = recipeById(c, base)!;
  const liked = recipe.style === def.likes;
  let delta = liked && recipeRarity(c, recipe) >= 2 ? g.loved_fine : liked ? g.liked : g.any;
  const verdict = delta === g.loved_fine ? 'loved' : delta === g.liked ? 'liked' : 'received';
  let cap = g.cap;
  if (quality === 2) delta += g.perfect;
  if (skillLevel(c, s, 'cooking') >= g.chef_touch.cooking) { delta += g.chef_touch.bonus; cap = g.chef_touch.cap; }
  return { delta: Math.min(delta, cap), verdict };
}

export function giftResident(c: P0Content, s: P0State, cmd: { resident?: unknown; item?: unknown }, events: P0Event[]): Refusal | null {
  const id = String(cmd.resident ?? ''), item = String(cmd.item ?? '');
  const def = residentDef(c, id);
  if (!def) return { code: 'bad_resident' };
  // K-3: only dishes are gifts (crops are not); the Mystery Dish is accepted with −2 (q(33)).
  const known = itemKind(item) === 'dish' && (dishParts(item).base === c.cooking.mystery.id || !!recipeById(c, dishParts(item).base));
  if (!known) return { code: 'not_giftable', detail: { item } };
  const r = residentState(s, id);
  if (r.gift_day === s.day.key) return { code: 'gift_used_today' };
  if (count(s.bag, item) < 1) return { code: 'not_enough', detail: { item, have: 0 } };
  take(s.bag, item, 1);   // a gift meal from another resident may be passed on (§12.4: Gifted dishes can go to residents)
  events.push({ kind: 'item', id: item, delta: -1 });
  r.gift_day = s.day.key;
  const pts = giftPoints(c, s, def, item);
  addAffinity(c, s, id, pts.delta, 'gift', events, pts.verdict);
  return null;
}

/** accept / deliver for a resident request (req_res_*): one line per resident, in order, one a day for Pip. */
export function residentRequestCommand(c: P0Content, s: P0State, type: 'accept' | 'deliver' | 'drop', reqId: string, now: number,
  events: P0Event[], trackedCount: number): Refusal | null {
  const owner = Object.keys(c.residents).find(id => c.residents[id].requests.some(q => q.id === reqId));
  if (!owner) return { code: s.req_done.includes(reqId) ? 'request_done' : 'bad_request' };
  if (type === 'drop') return { code: 'cannot_drop' };
  const st = requestState(c, s, owner), r = residentState(s, owner);
  if (st.req?.id !== reqId) return { code: s.req_done.includes(reqId) ? 'request_done' : 'not_available' };
  if (type === 'accept') {
    if (st.state === 'accepted') return { code: 'already_accepted' };
    if (st.state === 'wait') return { code: 'request_wait', detail: { next_in: untilRollover(c, now) } };
    if (st.state === 'stage') return { code: 'request_stage', detail: { stage: st.need_stage } };
    if (trackedCount >= c.requests.track_max) return { code: 'track_limit', detail: { max: c.requests.track_max } };
    r.req = { id: reqId, at: now, progress: 0 };
    events.push({ kind: 'request', id: reqId, status: 'accepted', coins: 0 });
    return null;
  }
  if (st.state !== 'accepted') return { code: 'not_accepted' };
  const q = st.req!;
  let floor = 0;   // floor value of what is handed in: paid in full, like a system request (q(44))
  if (q.need.kind === 'sow') {
    if (r.req!.progress < q.qty) return { code: 'not_ready', detail: { progress: r.req!.progress, need: q.qty } };
  } else {
    const parts = pick(c, s, q.need, q.need.id ? [q.need.id] : [], q.qty);
    if (!parts) return { code: 'not_enough', detail: { need: q.qty, have: progressOf(c, s, owner, q) } };
    for (const [item, n] of parts) {
      handOver(c, s, item, n);
      floor += floorPrice(c, item) * n;
      events.push({ kind: 'item', id: item, delta: -n });
    }
  }
  // q(44): the part of the listed coins above the floor is the resident's reward and shares the 100-coin daily cap.
  const bonus = payBonus(c, s, Math.max(0, q.coins - floor));
  const coins = floor + bonus;
  s.coins += coins;
  r.req = null;
  r.next += 1;
  r.done_day = s.day.key;
  noteDone(s, reqId);
  events.push({ kind: 'coins', delta: coins }, { kind: 'request', id: reqId, status: 'done', coins, bonus });
  addAffinity(c, s, owner, c.affinity.request, 'request', events);
  return null;
}

/** Plots sown count towards an accepted sow request (Pip ②: "plant five plots for me"). */
export function noteSown(c: P0Content, s: P0State, plots: number): void {
  for (const [id, def] of Object.entries(c.residents)) {
    const r = s.residents[id];
    const q = r?.req && def.requests.find(x => x.id === r.req!.id);
    if (q && q.need.kind === 'sow') r!.req!.progress = Math.min(q.qty, r!.req!.progress + plots);
  }
}

/** §3.4.5: an uneaten gift meal is gone at the 04:00 rollover. */
export function expireGiftMeals(s: P0State): void {
  s.bag = s.bag.filter(b => !b.gift || b.gift.day === s.day.key);
}
