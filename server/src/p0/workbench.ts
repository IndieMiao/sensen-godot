/**
 * The P0 workbench (plan §13.4, q(31) / q(44); SGODOT-231): Tools (Copper Pickaxe, Gather Gloves) and Supplies (Torch,
 * Compost). Costs come from Farm Storage first, then the bag. Supplies go to the bag, stacking first; with no room nothing
 * is made and nothing is taken. The Copper Pickaxe goes to Gear (Equip there); the gloves work at once. A level gate is
 * written on the button (LOCK-10), so it is only a refusal here.
 * TODO(P1): only at home; the P0 server trusts cmd.space (absent on older clients).
 */
import { add, count, room } from './bag.js';
import { itemName, type P0Content, type WorkbenchRecipe } from './content.js';
import type { Refusal } from './fishing.js';
import type { P0Event } from './progress.js';
import { skillLevel } from './rules.js';
import type { P0State } from './state.js';
import { haveTotal, missing, stored, takeStorageFirst } from './storage.js';

export function owned(s: P0State, r: WorkbenchRecipe): boolean {
  return r.to === 'gear' ? s.gear.picks.includes(r.out) : r.to === 'owned' ? s.owned.includes(r.out) : false;
}

/** Why a recipe can't be made now, in button order: owned, level gate, materials, bag room. */
export function craftBlock(c: P0Content, s: P0State, r: WorkbenchRecipe): Refusal | null {
  if (owned(s, r)) return { code: 'owned' };
  if (r.gate) {
    const [skill, level] = r.gate;
    if (skillLevel(c, s, skill) < level)
      return { code: 'locked', detail: { skill, level, xp_to_go: Math.max(0, c.skills[skill][level - 1] - s.skills[skill]) } };
  }
  const gap = missing(s, r.cost);
  if (gap) return { code: 'need_material', detail: gap };
  if (r.to === 'bag' && room(c, s, r.out) < r.qty) return { code: 'bag_full', detail: { room: room(c, s, r.out) } };
  return null;
}

export function craft(c: P0Content, s: P0State, cmd: { recipe?: unknown; space?: string }, events: P0Event[]): Refusal | null {
  if (cmd.space !== undefined && cmd.space !== 'home') return { code: 'not_home' };
  const r = c.workbench.recipes.find(x => x.id === String(cmd.recipe ?? ''));
  if (!r) return { code: 'bad_recipe' };
  const block = craftBlock(c, s, r);
  if (block) return block;
  for (const [item, qty] of r.cost) { takeStorageFirst(s, item, qty); events.push({ kind: 'item', id: item, delta: -qty }); }
  if (r.to === 'bag') { add(c, s, r.out, r.qty); events.push({ kind: 'item', id: r.out, delta: r.qty }); }
  else if (r.to === 'gear') s.gear.picks.push(r.out);   // §13.1.3: equipped with Equip at the workbench or in Gear (PICKAXE-DONE)
  else s.owned.push(r.out);
  events.push({ kind: 'craft', recipe: r.id, item: r.out, qty: r.qty, to: r.to });
  return null;
}

/** B2-06 facts per recipe: costs with storage and bag apart, the gate, owned / equipped, and the first block. */
export function workbenchView(c: P0Content, s: P0State) {
  return {
    tabs: c.workbench.tabs,
    recipes: c.workbench.recipes.map(r => {
      const block = craftBlock(c, s, r);
      return {
        id: r.id, tab: r.tab, item: r.out, name: itemName(c, r.out), qty: r.qty, to: r.to,
        have: r.to === 'bag' ? haveTotal(s, r.out) : null,                 // Supplies: You have 6 (bag + Farm Storage, B2-06)
        cost: r.cost.map(([id, need]) => ({ id, name: itemName(c, id), need, have: haveTotal(s, id), storage: stored(s, id), bag: haveTotal(s, id) - stored(s, id) })),
        gate: r.gate ? { skill: r.gate[0], level: r.gate[1], ok: skillLevel(c, s, r.gate[0]) >= r.gate[1],
          xp_to_go: Math.max(0, c.skills[r.gate[0]][r.gate[1] - 1] - s.skills[r.gate[0]]) } : null,
        owned: owned(s, r), equipped: r.to === 'gear' && s.gear.pick === r.out,
        can_craft: block === null, block,
      };
    }),
  };
}
