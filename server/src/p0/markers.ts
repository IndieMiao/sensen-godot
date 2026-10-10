/**
 * Map pin markers (plan §9.5.2 as settled in q(48); SGODOT-232 data, SGODOT-227 draws them). One marker per place,
 * highest kind first, places ordered deliver > request > new (tracked before the rest); the map shows the first five
 * pins on screen. Places: "home" (the homestead pin), catalog pond ids, outpost ids (assets/p0/p0_outposts.json).
 * - deliver ✓: a request whose hand-in the bag already holds, taken or not, where it is handed in (Stall Board → home,
 *   Market Board → the market square, a resident's request → their outpost).
 * - request !: an open Market Board slot (market square), a resident's open request (their outpost), and a tracked fish
 *   request the bag is still short of → the pond for that fish: the beginner pond when its template has it, else the
 *   one nearest the farm (fixed, so the pin never jumps as the player walks). Only fish the player can land yet count
 *   (q(104)): a taken request for a fish above their Fishing level marks no pond until they reach it. Crop and dish
 *   requests stay off the map; the Stall Board's ! hangs on the farm's own stall, not on the home pin.
 * - new ◆: what a level opened at an outpost that the player has not walked in to see since (Worm Bait and the Reed Rod
 *   at the tackle shop, the Row Hoe at the market square) and a resident's second page of talk at Acquainted. Entering
 *   the outpost marks them seen (noteSeenAt, from presence). No locked or star pins in P0.
 * First session (q(48)): until Pond Catch is handed in, only tracked markers show (Reed Pond's !, then home's ✓), so
 * minutes 5–9 have one goal. `more` counts the other reasons at the same place behind the one shown, for the pin card's
 * ` · +N more` (q(103)); the Market Board's open slots are one reason (the card writes `Market Board · 2 requests`). A resident's open fish request lights their outpost only once the player can land such a
 * fish (Old Kai's Rare fish: Golden Koi, Fishing Lv4); it can still be taken in the shop before that.
 */
import { BOARDS, handIn, slotCount } from './boards.js';
import { pondFishIds } from './fishing_world.js';
import type { Need, OutpostDef, P0Content, ShopId } from './content.js';
import { matches } from './requests.js';
import { progressOf, requestState, stageIndex } from './residents.js';
import { skillLevel } from './rules.js';
import { catalog, offerOf, owns } from './shops.js';
import type { P0State } from './state.js';

export type MarkerKind = 'deliver' | 'request' | 'new';
export interface MapMarker {
  place: string; kind: MarkerKind;
  why: { request?: string; resident?: string; item?: string; tracked?: true };
  more?: number;   // other reasons at this place behind this one (q(103) ` · +N more`); absent when none
}

const RANK: Record<MarkerKind, number> = { deliver: 0, request: 1, new: 2 };
const ACQUAINTED = 1;   // c.affinity.stages[1]: the second page of talk opens here

const outpostOf = (c: P0Content, role: string) => c.outposts?.find(o => o.role === role)?.id ?? null;
const residentHome = (c: P0Content, id: string) => c.outposts?.find(o => o.residents.includes(id))?.id ?? null;

/** The ◆ keys an outpost holds right now: level-gated goods on its counter not yet owned, residents at Acquainted. */
export function newKeysAt(c: P0Content, s: P0State, o: OutpostDef): { key: string; item?: string; resident?: string }[] {
  const out: { key: string; item?: string; resident?: string }[] = [];
  if (o.role === 'tackle' || o.role === 'market') {
    for (const id of catalog(c, o.role as ShopId, s, o.id)) {
      const offer = offerOf(c, id);
      if (!offer?.skill || offer.gate < 2 || skillLevel(c, s, offer.skill) < offer.gate) continue;
      if (offer.once && owns(c, s, id)) continue;
      out.push({ key: `item:${id}`, item: id });
    }
  }
  for (const r of o.residents) {
    if (stageIndex(c, s.residents[r]?.affinity ?? 0) >= ACQUAINTED) out.push({ key: `talk:${r}`, resident: r });
  }
  return out;
}

/** Walking into an outpost looks at what is new there (q(48): seen once in the shop). */
export function noteSeenAt(c: P0Content, s: P0State, place: string): void {
  const o = c.outposts?.find(x => x.id === place);
  if (!o) return;
  s.seen ??= [];
  for (const { key } of newKeysAt(c, s, o)) if (!s.seen.includes(key)) s.seen.push(key);
}

/** Fish ids a request takes: the named ones, else every catchable fish of that rarity. */
function fishFor(c: P0Content, items: string[], need: Pick<Need, 'kind' | 'rarity'>): string[] {
  if (items.length) return items.filter(id => id.startsWith('fish_'));
  return c.fish.filter(f => matches(c, need, [], f.id)).map(f => f.id);
}

/** The pond a tracked fish request points to: the beginner pond if it has one of them, else the nearest to the farm. */
export function pondFor(c: P0Content, fish: string[]): string | null {
  const city = c.profile.city.toLowerCase();
  const fits = Object.entries(c.fishing.places)
    .filter(([id, p]) => p.city === city && fish.some(f => pondFishIds(c, id).has(f)));
  const beginner = fits.find(([, p]) => p.beginner);
  if (beginner) return beginner[0];
  const farm = c.profile.farm_at;
  const dist = (at?: [number, number]) => (farm && at ? (at[0] - farm[0]) ** 2 + ((at[1] - farm[1]) * Math.cos(farm[0] * Math.PI / 180)) ** 2 : Infinity);
  return fits.sort((a, b) => dist(a[1].at) - dist(b[1].at))[0]?.[0] ?? null;
}

/** Of these fish, the ones the player can land now somewhere in P0 (its level reached, a pond or river has it). */
function landable(c: P0Content, s: P0State, fish: string[]): string[] {
  const held = pondFishIds(c), level = skillLevel(c, s, 'fishing');
  return fish.filter(id => {
    const f = c.fish.find(x => x.id === id);
    return !!f && f.level <= level && held.has(id);
  });
}

/** The tutorial request is still on the Stall Board: the first session, one goal on the map. */
const firstSession = (c: P0Content, s: P0State) => (s.boards.stall ?? []).some(sl => sl.req?.id === c.requests.tutorial.id);

export function mapMarkers(c: P0Content, s: P0State, now: number): MapMarker[] {
  const all: MapMarker[] = [];
  const reason = new Map<MapMarker, string>();   // what counts as one reason for `more`: the Market Board's open slots share one
  for (const board of BOARDS) {
    const place = board === 'stall' ? 'home' : outpostOf(c, 'market');
    for (const slot of (s.boards[board] ?? []).slice(0, slotCount(c, s, board))) {   // the slots the board shows
      const r = slot.req;
      if (!r || !place) continue;
      const tracked = r.status === 'accepted';
      if (handIn(c, s, r)) all.push({ place, kind: 'deliver', why: { request: r.id, ...(tracked ? { tracked: true as const } : {}) } });
      else if (tracked && r.kind === 'visit' && r.visit) all.push({ place: r.visit.place, kind: 'request', why: { request: r.id, tracked: true } });   // Stamp Run: go there
      else if (tracked && r.kind === 'fish' && r.where !== 'not_home') {   // only the fish the player can land yet (q(104)); Far Pond: ponds elsewhere, no pin
        const pond = pondFor(c, landable(c, s, fishFor(c, r.items, { kind: 'fish', rarity: r.rarity })));
        if (pond) all.push({ place: pond, kind: 'request', why: { request: r.id, tracked: true } });
      } else if (!tracked && board === 'market') {
        const m: MapMarker = { place, kind: 'request', why: { request: r.id } };
        all.push(m);
        reason.set(m, 'board:market');
      }
    }
  }
  for (const id of Object.keys(c.residents)) {
    const place = residentHome(c, id);
    const st = requestState(c, s, id, now);
    if (!place || !st.req || (st.state !== 'open' && st.state !== 'accepted')) continue;
    const q = st.req, tracked = st.state === 'accepted';
    const ready = q.need.kind !== 'sow' || tracked ? progressOf(c, s, id, q) >= q.qty : false;
    if (ready) all.push({ place, kind: 'deliver', why: { request: q.id, resident: id, ...(tracked ? { tracked: true as const } : {}) } });
    else if (tracked && q.need.kind === 'fish') {
      const pond = pondFor(c, landable(c, s, fishFor(c, q.need.id ? [q.need.id] : [], q.need)));
      if (pond) all.push({ place: pond, kind: 'request', why: { request: q.id, resident: id, tracked: true } });
    } else if (!tracked && (q.need.kind !== 'fish' || landable(c, s, fishFor(c, q.need.id ? [q.need.id] : [], q.need)).length)) {
      all.push({ place, kind: 'request', why: { request: q.id, resident: id } });
    }
  }
  for (const o of c.outposts ?? []) {
    for (const k of newKeysAt(c, s, o)) {
      if (s.seen?.includes(k.key)) continue;
      all.push({ place: o.id, kind: 'new', why: { ...(k.item ? { item: k.item } : {}), ...(k.resident ? { resident: k.resident } : {}) } });
    }
  }
  // one marker per place, the strongest; then deliver > request > new, tracked first within a kind
  const order = (m: MapMarker) => RANK[m.kind] * 2 + (m.why.tracked ? 0 : 1);
  const best = new Map<string, MapMarker>(), reasons = new Map<string, Set<string>>();
  const kept = firstSession(c, s) ? all.filter(m => m.why.tracked) : all;
  for (const m of kept.sort((a, b) => order(a) - order(b))) {
    if (!best.has(m.place)) best.set(m.place, m);
    if (!reasons.has(m.place)) reasons.set(m.place, new Set());
    reasons.get(m.place)!.add(reason.get(m) ?? `${m.kind}:${m.why.request ?? ''}:${m.why.resident ?? ''}:${m.why.item ?? ''}`);
  }
  return [...best.values()].map(m => {
    const more = reasons.get(m.place)!.size - 1;
    return more > 0 ? { ...m, more } : m;
  });
}
