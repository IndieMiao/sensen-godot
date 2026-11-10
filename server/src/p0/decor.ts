/**
 * Decorate (P1, SGODOT-284; plan §9.11.6, §8.3, q(24), q(29)): the Homestead Stall's Decor page and the yard. Decor is
 * bought at the stall into Farm Storage (q(29): never the bag), never sold back or gifted. Placing a piece takes one
 * from storage onto the yard grid (P0Garden's 0.65 m cells, content decor.yard); Move is free; Store puts it back.
 * Pieces placed count against homestead.decor_max (20 + 4 per level above 1). Placement mode itself is the shared shell
 * (P0Ui.begin_placement, 刘邦's SGODOT-241); this file only judges a spot and keeps the save.
 */
import type { P0Content } from './content.js';
import type { Refusal } from './fishing.js';
import type { P0Event } from './progress.js';
import type { P0State } from './state.js';
import { putInStorage, stored } from './storage.js';
import { bedCells } from './garden.js';

export interface DecorItem { name: string; blurb?: string; price: number; size: [number, number]; pieces: number; homestead: number; buy: boolean }
type Rect = [number, number, number, number];
/** The yard on the garden grid: walk (the yard), field (not yard), objects (what stands there), paths (kept clear);
 * wing: the cells Homestead Lv8's Kitchen Wing stands on from its level (q(303), SGODOT-450); paths2: more cells kept
 * clear for a client that says `yard2` (yard v2, v4q(12): the way to the rest bench past the porch, and to the mailbox —
 * a yard full of decor walled both off, 后裔's walk check 11-10). */
export interface DecorYard { walk: Rect; field: Rect[]; objects: Rect[]; paths: Rect[]; wing?: DecorWing; paths2?: Rect[]; grow?: DecorGrow[] }
/** yard2 (v4q(12) ③ ④): the walk rect from a Homestead level on — Lv13 row 19, Lv14 columns 19–20. */
export interface DecorGrow { homestead: number; walk: Rect }
/** What the client draws of the yard (x-p0-features): wing8 — Lv8's Kitchen Wing (q(303)); yard2 — yard v2 (v4q(12)).
 * An older client keeps the yard as it knows it. */
export interface YardFeatures { wing8?: boolean; yard2?: boolean }
export interface DecorWing { homestead: number; cells: [number, number][] }
/** A placed piece: x, y = its top-left cell; rot 1 turns a w × h piece to h × w. */
export interface PlacedDecor { uid: number; id: string; x: number; y: number; rot: 0 | 1 }

type WithDecor = P0Content & { decor?: { items: Record<string, DecorItem>; yard: DecorYard } };
export const decorOf = (c: P0Content) => (c as WithDecor).decor;
export const isDecor = (c: P0Content, id: string) => !!decorOf(c)?.items[id];

/** §8.3.2: 20 + 4 × (Homestead level − 1), at most decor_max.max when the content sets one (SGODOT-355 b1: the yard has
 * 58 free cells since the field took the whole grid, the mine mouth left and the bench kept its cell; 52 from Lv9, 6
 * cells to walk on — the user, 11-02, 丁22, v4q(1) ⑤). yard2 (v4q(12) ①, overturns 丁22): no max — at most the cells
 * the yard can take now (yardRoom); the paths keep the ways open, not the cap. Pieces over it stay (q(303)). */
export function decorCap(c: P0Content, s: P0State, f: YardFeatures = {}): number {
  const m = (c.homestead as { decor_max?: { base: number; per_level: number; max?: number } }).decor_max ?? { base: 20, per_level: 4 };
  const byLevel = m.base + m.per_level * Math.max(0, s.homestead.level - 1);
  return Math.min(byLevel, f.yard2 ? yardRoom(c, s, f) : m.max ?? Infinity);
}

/** The yard's walk rect for this client: yard2 (v4q(12) ③ ④) grows it with the Homestead level (decor.yard.grow, the
 * last one reached); else the content's walk, whatever the level. */
export function yardWalk(c: P0Content, s: P0State, f: YardFeatures = {}): Rect {
  const yard = decorOf(c)!.yard;
  let walk = yard.walk;
  if (f.yard2) for (const g of yard.grow ?? []) if (s.homestead.level >= g.homestead) walk = g.walk;
  return walk;
}

/** The cells the yard can take now (v4q(12) ①): every cell of the walk a 1 × 1 piece may stand on, the pieces already
 * placed not counted against it — so off the field, the beds, objects, paths, the wing and the yard's facilities (the
 * Compost Bin: placing one lowers the cap by one). */
export function yardRoom(c: P0Content, s: P0State, f: YardFeatures = {}): number {
  const bare = { ...s, decor: undefined };
  const [x0, y0, w, h] = yardWalk(c, s, f);
  let n = 0;
  for (let y = y0; y < y0 + h; y++) for (let x = x0; x < x0 + w; x++) if (!yardBlock(c, bare, [[x, y]], { x, y }, {}, f)) n++;
  return n;
}

/** The cells a piece covers at x, y. */
export function cellsOf(c: P0Content, id: string, x: number, y: number, rot: number): [number, number][] {
  const [w, h] = decorOf(c)!.items[id].size;
  const [cw, ch] = rot ? [h, w] : [w, h];
  const out: [number, number][] = [];
  for (let dy = 0; dy < ch; dy++) for (let dx = 0; dx < cw; dx++) out.push([x + dx, y + dy]);
  return out;
}

const inRect = ([x, y]: [number, number], [rx, ry, rw, rh]: Rect) => x >= rx && y >= ry && x < rx + rw && y < ry + rh;

/** The Kitchen Wing on the yard (q(303), SGODOT-450): from its Homestead level its cells are the house's own, as its
 * walls are (`Space taken`), for a client that draws the wing (feature `wing8`); an older one keeps the yard as it was. */
export const wingOf = (c: P0Content): DecorWing | undefined => decorOf(c)?.yard.wing;
export const wingUp = (c: P0Content, s: P0State, wing8: boolean): boolean => {
  const w = wingOf(c);
  return wing8 && !!w && s.homestead.level >= w.homestead;
};

/** What stands on the wing's cells, or null when nothing: the cells taken, each piece with any cell on them (pieces
 * first: the one the player is shown first, 450 spec v1.1 §4), then the yard facilities. Nothing is moved: the player
 * clears them (the user, 548). */
export function wingTaken(c: P0Content, s: P0State): { cells: [number, number][]; pieces: { uid: number; item: string; x: number; y: number; rot: number }[];
    facilities: { id: number; kind: string; x: number; y: number }[] } | null {
  const w = wingOf(c);
  if (!w) return null;
  const on = new Set(w.cells.map(([x, y]) => `${x},${y}`));
  const hit = new Set<string>();
  const pieces = [], facilities = [];
  for (const p of s.decor?.placed ?? []) {
    if (!isDecor(c, p.id)) continue;
    const over = cellsOf(c, p.id, p.x, p.y, p.rot).filter(([x, y]) => on.has(`${x},${y}`));
    if (!over.length) continue;
    for (const [x, y] of over) hit.add(`${x},${y}`);
    pieces.push({ uid: p.uid, item: p.id, x: p.x, y: p.y, rot: p.rot });
  }
  for (const f of s.facilities ?? []) {
    if (!f.cell || !on.has(`${f.cell[0]},${f.cell[1]}`)) continue;
    hit.add(`${f.cell[0]},${f.cell[1]}`);
    facilities.push({ id: f.id, kind: f.kind, x: f.cell[0], y: f.cell[1] });
  }
  if (!pieces.length && !facilities.length) return null;
  return { cells: w.cells.filter(([x, y]) => hit.has(`${x},${y}`)), pieces, facilities };
}

/** Why a piece can't stand there — `Outside your yard` (decor_outside), `Space taken` (decor_overlap: an object or
 * another piece), `Keep the path clear` (decor_path, q(120)) — or null when it can. */
export function spotBlock(c: P0Content, s: P0State, id: string, x: number, y: number, rot: number, ignore?: number,
    f: YardFeatures = {}): Refusal | null {
  return yardBlock(c, s, cellsOf(c, id, x, y, rot), { x, y }, { uid: ignore }, f);
}

/** The same judgement for any cells in the yard: decor pieces and the yard's facilities (the Compost Bin, 刘邦,
 * q(118) ③) keep out of each other's cells; `ignore` leaves out the one being moved; `f`: the client's yard — wing8,
 * the Kitchen Wing's cells taken once it stands (wingUp); yard2, paths2 kept clear too. */
export function yardBlock(c: P0Content, s: P0State, cells: [number, number][], at: { x: number; y: number },
    ignore: { uid?: number; facility?: number } = {}, f: YardFeatures = {}): Refusal | null {
  const yard = decorOf(c)!.yard;
  // off the field, and off the beds the homestead has beyond it (Homestead Lv7's 40–47 on the field's edge, q(172))
  const beds = bedCells(c, s), walk = yardWalk(c, s, f);
  if (cells.some(cell => !inRect(cell, walk) || yard.field.some(r => inRect(cell, r)) || beds.has(`${cell[0]},${cell[1]}`)))
    return { code: 'decor_outside', detail: at };
  const taken = new Set<string>();
  for (const p of s.decor?.placed ?? []) if (p.uid !== ignore.uid) for (const [px, py] of cellsOf(c, p.id, p.x, p.y, p.rot)) taken.add(`${px},${py}`);
  for (const x of s.facilities ?? []) if (x.cell && x.id !== ignore.facility) taken.add(`${x.cell[0]},${x.cell[1]}`);
  if (wingUp(c, s, !!f.wing8)) for (const [x, y] of yard.wing?.cells ?? []) taken.add(`${x},${y}`);
  if (cells.some(cell => yard.objects.some(r => inRect(cell, r)) || taken.has(`${cell[0]},${cell[1]}`))) return { code: 'decor_overlap', detail: at };
  const paths = f.yard2 ? [...yard.paths, ...yard.paths2 ?? []] : yard.paths;
  if (cells.some(cell => paths.some(r => inRect(cell, r)))) return { code: 'decor_path', detail: at };
  return null;
}

function spotArgs(cmd: { x?: unknown; y?: unknown; rot?: unknown }): { x: number; y: number; rot: 0 | 1 } | null {
  const x = Number(cmd.x), y = Number(cmd.y), rot = Number(cmd.rot ?? 0);
  if (!Number.isInteger(x) || !Number.isInteger(y) || (rot !== 0 && rot !== 1)) return null;
  return { x, y, rot: rot as 0 | 1 };
}

/** place_decor {item, x, y, rot?}: one from Farm Storage onto the yard. */
export function placeDecor(c: P0Content, s: P0State, cmd: { item?: unknown; x?: unknown; y?: unknown; rot?: unknown }, events: P0Event[],
    f: YardFeatures = {}): Refusal | null {
  const id = String(cmd.item ?? '');
  if (!isDecor(c, id)) return { code: 'bad_item' };
  const at = spotArgs(cmd);
  if (!at) return { code: 'bad_spot' };
  if (stored(s, id) < 1) return { code: 'not_stored', detail: { item: id } };
  s.decor ??= { placed: [], count: 0 };
  const cap = decorCap(c, s, f);
  if (s.decor.placed.length >= cap) return { code: 'decor_cap', detail: { cap, used: s.decor.placed.length } };
  const block = spotBlock(c, s, id, at.x, at.y, at.rot, undefined, f);
  if (block) return block;
  s.storage[id] -= 1;
  if (s.storage[id] <= 0) delete s.storage[id];
  const piece: PlacedDecor = { uid: ++s.decor.count, id, ...at };
  s.decor.placed.push(piece);
  events.push({ kind: 'decor', action: 'placed', uid: piece.uid, item: id, x: at.x, y: at.y, rot: at.rot });
  return null;
}

/** move_decor {uid, x, y, rot?}: free (§9.11.6). */
export function moveDecor(c: P0Content, s: P0State, cmd: { uid?: unknown; x?: unknown; y?: unknown; rot?: unknown }, events: P0Event[],
    f: YardFeatures = {}): Refusal | null {
  const piece = s.decor?.placed.find(p => p.uid === Number(cmd.uid));
  if (!piece) return { code: 'bad_decor' };
  const at = spotArgs(cmd);
  if (!at) return { code: 'bad_spot' };
  const block = spotBlock(c, s, piece.id, at.x, at.y, at.rot, piece.uid, f);
  if (block) return block;
  Object.assign(piece, at);
  events.push({ kind: 'decor', action: 'moved', uid: piece.uid, item: piece.id, x: at.x, y: at.y, rot: at.rot });
  return null;
}

/** store_decor {uid}: back to Farm Storage. */
export function storeDecor(c: P0Content, s: P0State, cmd: { uid?: unknown }, events: P0Event[]): Refusal | null {
  const i = s.decor?.placed.findIndex(p => p.uid === Number(cmd.uid)) ?? -1;
  if (i < 0) return { code: 'bad_decor' };
  const [piece] = s.decor!.placed.splice(i, 1);
  putInStorage(s, piece.id, 1);
  events.push({ kind: 'decor', action: 'stored', uid: piece.uid, item: piece.id, x: piece.x, y: piece.y, rot: piece.rot });
  return null;
}

/** view.decor: the yard's pieces, what storage holds, the cap, and the catalog facts the Decor page needs. yard2:
 * next_cap, the cap at the next Homestead level (null at the top) — the yard's cells count in it, so the client's
 * `Home LvN adds N` reads it rather than the level's formula (v4q(12) 画面). */
export function decorView(c: P0Content, s: P0State, f: YardFeatures = {}) {
  const d = decorOf(c);
  if (!d) return null;
  const top = Math.max(...c.homestead.levels.map(l => l.level));
  const next = f.yard2 ? { next_cap: s.homestead.level < top ? decorCap(c, { ...s, homestead: { ...s.homestead, level: s.homestead.level + 1 } }, f) : null } : {};
  return {
    placed: s.decor?.placed ?? [], cap: decorCap(c, s, f), used: s.decor?.placed.length ?? 0, ...next,
    stored: Object.fromEntries(Object.keys(d.items).filter(id => stored(s, id) > 0).map(id => [id, stored(s, id)])),
  };
}
