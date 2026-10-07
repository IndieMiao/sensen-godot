/**
 * Gathering spots and coming home (plan §13.2, §10.4.8, q(40) / q(44); SGODOT-231). A spot is gathered with one tap,
 * 0 Energy, and is ready again 8 h after it was gathered. Its material goes straight to Farm Storage (+1 with Gather
 * Gloves); the Reed Bank's worms go to the bag, any that don't fit go to storage with the reeds. Coming home moves the
 * seven materials from the bag to storage; seeds, fertilizer, bait and torches stay with the player.
 * TODO(P1): only at home; the P0 server trusts cmd.space (absent on older clients).
 */
import { add, room, take } from './bag.js';
import type { P0Content } from './content.js';
import type { Refusal } from './fishing.js';
import type { P0Event } from './progress.js';
import type { P0State } from './state.js';
import { putInStorage } from './storage.js';

const H = 3_600_000;

export function hasGloves(c: P0Content, s: P0State): boolean { return s.owned.includes(c.gather.gloves); }

/** What one gather gives now: the material with the gloves' +1, then the side yield (worms) as listed. */
export function spotYield(c: P0Content, s: P0State, spot: string): [string, number][] {
  const def = c.gather.spots[spot];
  return def.yield.map(([id, qty], i) => [id, i === 0 && hasGloves(c, s) ? qty + c.gather.gloves_bonus : qty]);
}

export function gather(c: P0Content, s: P0State, cmd: { spot?: unknown; space?: string }, now: number, events: P0Event[]): Refusal | null {
  if (cmd.space !== undefined && cmd.space !== 'home') return { code: 'not_home' };
  const id = String(cmd.spot ?? ''), def = c.gather.spots[id];
  if (!def) return { code: 'bad_spot' };
  if (s.homestead.level < def.homestead) return { code: 'homestead_level', detail: { need: def.homestead } };
  const ready = s.gather.ready_at[id] ?? 0;
  if (now < ready) return { code: 'not_ready', detail: { ready_in: ready - now } };
  if (now - s.gather.last_at < c.gather.tempo_ms) return { code: 'too_early', detail: { ready_in: c.gather.tempo_ms - (now - s.gather.last_at) } };
  const items: [string, number, 'storage' | 'bag'][] = [];
  spotYield(c, s, id).forEach(([item, qty], i) => {
    // The material goes to storage; side yields (worms, a carried consumable) go to the bag as far as they fit.
    const toBag = i === 0 ? 0 : Math.min(qty, room(c, s, item));
    if (toBag > 0) { add(c, s, item, toBag); items.push([item, toBag, 'bag']); events.push({ kind: 'item', id: item, delta: toBag }); }
    if (qty - toBag > 0) { putInStorage(s, item, qty - toBag); items.push([item, qty - toBag, 'storage']); }
  });
  s.gather.ready_at[id] = now + c.gather.regen_h * H;
  s.gather.last_at = now;
  events.push({ kind: 'gather', spot: id, items, ready_in: c.gather.regen_h * H });
  return null;
}

/**
 * q(40): the first command or space read back at home moves the bag's materials (content.materials) into Farm Storage.
 * Called from presence.notePresence; events is null on the read path, so the last move is kept in storage_auto for the
 * client to float once.
 */
export function storeMaterials(c: P0Content, s: P0State, now: number, events: P0Event[] | null): void {
  const moved = new Map<string, number>();
  for (const b of s.bag) if (!b.gift && c.materials[b.id]) moved.set(b.id, (moved.get(b.id) ?? 0) + b.qty);
  if (!moved.size) return;
  for (const [id, qty] of moved) { take(s.bag, id, qty, 'skip'); putInStorage(s, id, qty); }
  const items = [...moved];
  s.storage_auto = { at: now, items };
  events?.push({ kind: 'stored', items, reason: 'home' });
}

/** §13.2 spots as facts: open (Homestead level), ready or how long until, and what a gather would give now. */
export function gatherView(c: P0Content, s: P0State, now: number) {
  return {
    gloves: hasGloves(c, s),
    spots: Object.entries(c.gather.spots).map(([id, def]) => {
      const ready_in = Math.max(0, (s.gather.ready_at[id] ?? 0) - now);
      const open = s.homestead.level >= def.homestead;
      return { id, name: def.name, open, homestead: def.homestead, ready: open && ready_in === 0, ready_in, yield: spotYield(c, s, id) };
    }),
  };
}
