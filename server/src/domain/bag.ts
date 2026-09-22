import type { Command } from './commands.js';
import { CROP_IDS, DECORATION_IDS, ITEM_CATEGORIES, EQUIPMENT_SLOTS, equipmentSlots, type Content, type CropId, type DishId, type ItemDefinition, type JourneyMaterial } from './content.js';
import { err, ok, type Result } from './errors.js';
import type { Ctx } from './reducer.js';
import type { BagStack, BagState, FarmState } from './state.js';

type Lot = 'bought' | 'bound';
type Holding = { item_id: string; seed_lot?: Lot; quantity: number };
const keyOf = (item: Pick<BagStack, 'item_id' | 'seed_lot'>): string => `${item.item_id}:${item.seed_lot ?? ''}`;
export const allBagStacks = (bag: BagState): BagStack[] => [...bag.overflow, ...bag.slots,
  ...Object.values(bag.equipped).filter((stack): stack is BagStack => Boolean(stack))];
const validQuantity = (value: unknown): value is number => Number.isSafeInteger(value) && Number(value) > 0;
const definition = (content: Content, id: string): ItemDefinition | undefined =>
  Object.hasOwn(content.items.items, id) ? content.items.items[id] : undefined;

/** The former courtyard palette owned one of each unlocked prop, independently of workshop stock. */
export function importLegacyCourtyardStock(state: FarmState): void {
  if (!state.journey) return;
  const all = state.journey.unlocks.includes('decorations') || state.growth_choice.purchase !== null;
  const entitled = all ? DECORATION_IDS : state.journey.facts.includes('planter_crafted') ? ['planter'] : [];
  const unplaced = entitled.filter(id => !state.decorations?.some(prop => prop.prop_id === id));
  if (!unplaced.length) return;
  const workshop = state.journey.workshop ??= { sequence: 0, stock: {}, displays: {} };
  for (const id of unplaced) workshop.stock[id] = (workshop.stock[id] ?? 0) + 1;
}

function holdings(state: FarmState, content: Content): Map<string, Holding> {
  const values = new Map<string, Holding>();
  for (const [item_id, item] of Object.entries(content.items.items)) {
    const { kind, id } = item.source;
    const add = (quantity: number, seed_lot?: Lot) => {
      if (!Number.isSafeInteger(quantity) || quantity < 0) throw new Error(`Invalid inventory quantity: ${item_id}`);
      const holding = { item_id, quantity, ...(seed_lot ? { seed_lot } : {}) };
      values.set(keyOf(holding), holding);
    };
    switch (kind) {
      case 'seed':
        add(state.inventory.seeds[id as CropId].bought, 'bought');
        add(state.inventory.seeds[id as CropId].bound, 'bound');
        break;
      case 'produce': add(state.inventory.produce[id as CropId]); break;
      case 'dish': add(state.inventory.dishes[id as DishId] ?? 0); break;
      case 'material': add(id === 'wood' ? state.journey?.wood ?? 0 : state.journey?.materials?.[id as Exclude<JourneyMaterial, 'wood'>] ?? 0); break;
      case 'prop': add(state.journey?.workshop?.stock[id] ?? 0); break;
      case 'tool':
        if (id === 'hand_tools') add(1);
        else if (id === 'row_tool') add(Number(state.tools.row_tool));
        break;
      case 'equipment': break;
    }
  }
  return values;
}

function newStack(bag: BagState, holding: Holding, content: Content): BagStack {
  const id = bag.next_id++;
  return { id: `bag_${id}`, item_id: holding.item_id, quantity: holding.quantity, quality: 'normal',
    ...(holding.seed_lot ? { seed_lot: holding.seed_lot } : {}),
    ...(content.items.items[holding.item_id].max_stack === 1 ? { instance_id: `item_${id}` } : {}) };
}

/** Instances and every variant property participate; a quality label alone is not an identity. */
export function stacksCanMerge(a: BagStack, b: BagStack): boolean {
  if (a.instance_id || b.instance_id || a.item_id !== b.item_id || a.quality !== b.quality || a.seed_lot !== b.seed_lot) return false;
  const attrs = (stack: BagStack) => Object.entries(stack.attributes ?? {}).sort(([a], [b]) => a.localeCompare(b));
  return JSON.stringify(attrs(a)) === JSON.stringify(attrs(b));
}

export function addBagItem(bag: BagState, holding: Holding, content: Content, allowOverflow = false): boolean {
  let remaining = holding.quantity;
  const max = content.items.items[holding.item_id].max_stack;
  const variant: BagStack = { id: '', item_id: holding.item_id, quantity: remaining, quality: 'normal',
    ...(holding.seed_lot ? { seed_lot: holding.seed_lot } : {}) };
  for (const stack of bag.slots) {
    if (max === 1 || !stacksCanMerge(stack, variant)) continue;
    const moved = Math.min(remaining, max - stack.quantity);
    stack.quantity += moved;
    remaining -= moved;
    if (!remaining) return true;
  }
  while (remaining > 0 && bag.slots.length < bag.capacity) {
    const quantity = Math.min(remaining, max);
    bag.slots.push(newStack(bag, { ...holding, quantity }, content));
    remaining -= quantity;
  }
  if (remaining > 0 && !allowOverflow) return false;
  for (const stack of bag.overflow) {
    if (max === 1 || !stacksCanMerge(stack, variant)) continue;
    const moved = Math.min(remaining, max - stack.quantity);
    stack.quantity += moved;
    remaining -= moved;
    if (!remaining) return true;
  }
  while (remaining > 0) {
    const quantity = Math.min(remaining, max);
    bag.overflow.push(newStack(bag, { ...holding, quantity }, content));
    remaining -= quantity;
  }
  return true;
}

function removeHolding(bag: BagState, holding: Holding): boolean {
  let remaining = holding.quantity;
  // Old overflow is spendable immediately, without making the player shuffle it into a free slot.
  for (const area of [bag.overflow, bag.slots]) {
    for (const stack of area) {
      if (keyOf(stack) !== keyOf(holding)) continue;
      const removed = Math.min(stack.quantity, remaining);
      stack.quantity -= removed;
      remaining -= removed;
      if (!remaining) break;
    }
    for (let index = area.length - 1; index >= 0; index--) if (!area[index].quantity) area.splice(index, 1);
    if (!remaining) return true;
  }
  return false;
}

/** Rebuild legacy read models from canonical ownership, including reserved and overflow holdings. */
export function projectBagAggregates(state: FarmState, content: Content): void {
  if (!state.bag) return;
  const quantities = new Map<string, number>();
  for (const stack of allBagStacks(state.bag)) quantities.set(keyOf(stack), (quantities.get(keyOf(stack)) ?? 0) + stack.quantity);
  for (const [item_id, item] of Object.entries(content.items.items)) {
    const { kind, id } = item.source;
    const amount = quantities.get(`${item_id}:`) ?? 0;
    switch (kind) {
      case 'seed': state.inventory.seeds[id as CropId] = {
        bought: quantities.get(`${item_id}:bought`) ?? 0, bound: quantities.get(`${item_id}:bound`) ?? 0,
      }; break;
      case 'produce': state.inventory.produce[id as CropId] = amount; break;
      case 'dish':
        if (amount || Object.hasOwn(state.inventory.dishes, id)) state.inventory.dishes[id as DishId] = amount;
        break;
      case 'material':
        if (!state.journey) break;
        if (id === 'wood') state.journey.wood = amount;
        else if (amount || state.journey.materials && Object.hasOwn(state.journey.materials, id)) {
          state.journey.materials ??= { stone: 0, fiber: 0 };
          state.journey.materials[id as Exclude<JourneyMaterial, 'wood'>] = amount;
        }
        break;
      case 'prop':
        if (state.journey && (amount || state.journey.workshop && Object.hasOwn(state.journey.workshop.stock, id))) {
          state.journey.workshop ??= { sequence: 0, stock: {}, displays: {} };
          state.journey.workshop.stock[id] = amount;
        }
        break;
      case 'tool': if (id === 'row_tool') state.tools.row_tool = amount > 0; break;
      case 'equipment': break;
    }
  }
}

export function grantStarterRod(bag: BagState, content: Content): void {
  if (bag.starter_rod_granted) return;
  const id = content.character.starter_rod;
  let rod = allBagStacks(bag).find(stack => stack.item_id === id);
  if (!rod) rod = newStack(bag, { item_id: id, quantity: 1 }, content);
  if (!bag.equipped.fishing_rod) {
    bag.slots = bag.slots.filter(stack => stack.id !== rod!.id);
    bag.overflow = bag.overflow.filter(stack => stack.id !== rod!.id);
    bag.equipped.fishing_rod = rod;
  } else if (!allBagStacks(bag).some(stack => stack.id === rod!.id)) {
    (bag.slots.length < bag.capacity ? bag.slots : bag.overflow).push(rod);
  }
  bag.starter_rod_granted = true;
}

/** Only absent bags import legacy counters. Subsequent reads cannot turn stale counters into items. */
export function ensureBag(state: FarmState, content: Content): void {
  // 内容表新增作物时，老存档还没有它的仓位。先补 0 再算持有量，
  // 否则 holdings() 会把 undefined 当成非法数量抛出去。
  for (const id of CROP_IDS) {
    state.inventory.seeds[id] ??= { bought: 0, bound: 0 };
    state.inventory.produce[id] ??= 0;
  }
  if (!state.bag) {
    importLegacyCourtyardStock(state);
    const bag: BagState = { version: 1, sequence: 0, capacity: content.items.capacity, next_id: 1,
      slots: [], overflow: [], equipped: { tool: null, accessory: null } };
    const old = holdings(state, content);
    const hand = newStack(bag, { item_id: 'hand_tools', quantity: 1 }, content);
    bag.equipped.tool = state.tools.row_tool ? newStack(bag, { item_id: 'row_tool', quantity: 1 }, content) : hand;
    if (state.tools.row_tool) bag.slots.push(hand);
    for (const holding of old.values()) {
      if (!holding.quantity || content.items.items[holding.item_id].source.kind === 'tool') continue;
      addBagItem(bag, holding, content, true);
    }
    state.bag = bag;
  }
  const bag = state.bag;
  let changed = false;
  if (bag.version === 1) {
    const old = bag.equipped;
    const main = old.weapon ?? old.tool ?? null;
    for (const extra of [old.weapon, old.tool]) if (extra && extra !== main) {
      (bag.slots.length < bag.capacity ? bag.slots : bag.overflow).push(extra);
    }
    bag.equipped = { main_hand: main, gloves: old.accessory ?? null, fishing_rod: null, ring_1: null, ring_2: null, necklace: null };
    bag.version = 2;
    changed = true;
  }
  for (const slot of EQUIPMENT_SLOTS) if (!(slot in bag.equipped)) { bag.equipped[slot] = null; changed = true; }
  // Current preview supplies a starter rod once. A future quest can call the same grant explicitly.
  if (content.character.auto_grant_starter_rod && !bag.starter_rod_granted) {
    grantStarterRod(bag, content); changed = true;
  }
  if (changed) bag.sequence++;

  projectBagAggregates(state, content);
}

/** Translate one legacy transaction's complete delta; removals free space before any gain is admitted. */
export function reconcileBagChanges(before: FarmState, after: FarmState, content: Content, allowOverflow = false): Result<FarmState> {
  const next = structuredClone(after);
  const initial = structuredClone(before);
  ensureBag(initial, content);
  next.bag = structuredClone(initial.bag!);
  const old = holdings(initial, content);
  const target = structuredClone(after);
  for (const id of CROP_IDS) {
    target.inventory.seeds[id] ??= { bought: 0, bound: 0 };
    target.inventory.produce[id] ??= 0;
  }
  const wanted = holdings(target, content);
  for (const [key, holding] of wanted) {
    const removed = (old.get(key)?.quantity ?? 0) - holding.quantity;
    if (removed > 0 && !removeHolding(next.bag, { ...holding, quantity: removed }))
      return err('INSUFFICIENT_ITEMS', holding.item_id);
  }
  for (const [key, holding] of wanted) {
    const gained = holding.quantity - (old.get(key)?.quantity ?? 0);
    if (gained <= 0) continue;
    // Buying the existing row upgrade keeps its established immediate activation.
    if (holding.item_id === 'row_tool') {
      const previous = next.bag.equipped.main_hand;
      if (previous) {
        if (next.bag.slots.length < next.bag.capacity) next.bag.slots.push(previous);
        else if (allowOverflow) next.bag.overflow.push(previous);
        else return err('BAG_FULL');
      }
      next.bag.equipped.main_hand = newStack(next.bag, { ...holding, quantity: gained }, content);
    } else if (!addBagItem(next.bag, { ...holding, quantity: gained }, content, allowOverflow)) return err('BAG_FULL');
  }
  if (JSON.stringify(next.bag) !== JSON.stringify(initial.bag)) next.bag.sequence += 1;
  projectBagAggregates(next, content);
  return ok(next);
}

function moveOverflow(bag: BagState, source: BagStack, content: Content): number {
  const original = source.quantity;
  const max = content.items.items[source.item_id].max_stack;
  for (const target of bag.slots) {
    if (!stacksCanMerge(target, source)) continue;
    const moved = Math.min(source.quantity, max - target.quantity);
    source.quantity -= moved;
    target.quantity += moved;
    if (!source.quantity) break;
  }
  if (source.quantity > 0 && bag.slots.length < bag.capacity) {
    bag.slots.push({ ...source });
    source.quantity = 0;
  }
  if (!source.quantity) bag.overflow = bag.overflow.filter(stack => stack !== source);
  return original - source.quantity;
}

function consolidate(stacks: BagStack[], content: Content): BagStack[] {
  const compact: BagStack[] = [];
  for (const source of stacks) {
    const max = content.items.items[source.item_id].max_stack;
    for (const target of compact) {
      if (!stacksCanMerge(target, source)) continue;
      const moved = Math.min(source.quantity, max - target.quantity);
      source.quantity -= moved;
      target.quantity += moved;
      if (!source.quantity) break;
    }
    if (source.quantity) compact.push(source);
  }
  return compact;
}

const BAG_COMMANDS = new Set(['split_bag_stack', 'merge_bag_stacks', 'sort_bag', 'discard_bag_stack',
  'equip_bag_item', 'unequip_bag_item', 'claim_bag_overflow']);

export function applyBag(state: FarmState, cmd: Command, ctx: Ctx): Result<FarmState> | null {
  if (!BAG_COMMANDS.has(cmd.type)) return null;
  if (!('sequence' in cmd) || !Number.isSafeInteger(cmd.sequence) || cmd.sequence !== state.bag?.sequence)
    return err('BAG_CHANGED');
  const next = structuredClone(state);
  const bag = next.bag!;
  const stackId = (value: unknown): value is string => typeof value === 'string' && /^bag_[1-9][0-9]*$/.test(value);
  const sourceId = 'stack_id' in cmd ? cmd.stack_id : '';
  const slot = bag.slots.find(stack => stack.id === sourceId);
  const overflow = bag.overflow.find(stack => stack.id === sourceId);
  switch (cmd.type) {
    case 'split_bag_stack': {
      if (!stackId(cmd.stack_id) || !slot || !validQuantity(cmd.quantity) || cmd.quantity >= slot.quantity
        || slot.instance_id || ctx.content.items.items[slot.item_id].max_stack === 1) return err('INVALID_BAG_ACTION');
      if (bag.slots.length >= bag.capacity) return err('BAG_FULL');
      const id = bag.next_id++;
      slot.quantity -= cmd.quantity;
      bag.slots.push({ ...structuredClone(slot), id: `bag_${id}`, quantity: cmd.quantity });
      break;
    }
    case 'merge_bag_stacks': {
      if (!stackId(cmd.source_id) || !stackId(cmd.target_id) || cmd.source_id === cmd.target_id)
        return err('INVALID_BAG_ACTION');
      const source = bag.slots.find(stack => stack.id === cmd.source_id);
      const target = bag.slots.find(stack => stack.id === cmd.target_id);
      if (!source || !target || !stacksCanMerge(source, target)) return err('INVALID_BAG_ACTION');
      const moved = Math.min(source.quantity, ctx.content.items.items[target.item_id].max_stack - target.quantity);
      if (moved < 1) return err('INVALID_BAG_ACTION');
      source.quantity -= moved;
      target.quantity += moved;
      bag.slots = bag.slots.filter(stack => stack.quantity > 0);
      break;
    }
    case 'sort_bag': {
      if (cmd.mode !== 'category' && cmd.mode !== 'name') return err('INVALID_BAG_ACTION');
      bag.slots = consolidate(bag.slots, ctx.content);
      bag.overflow = consolidate(bag.overflow, ctx.content);
      for (const source of [...bag.overflow]) moveOverflow(bag, source, ctx.content);
      const compare = (a: BagStack, b: BagStack): number => {
        const da = ctx.content.items.items[a.item_id];
        const db = ctx.content.items.items[b.item_id];
        return (cmd.mode === 'category' ? ITEM_CATEGORIES.indexOf(da.category) - ITEM_CATEGORIES.indexOf(db.category) : 0)
          || da.name.localeCompare(db.name, 'en') || a.quality.localeCompare(b.quality, 'en')
          || (a.seed_lot ?? '').localeCompare(b.seed_lot ?? '', 'en') || a.id.localeCompare(b.id, 'en', { numeric: true });
      };
      bag.slots.sort(compare);
      bag.overflow.sort(compare);
      break;
    }
    case 'discard_bag_stack': {
      const stack = slot ?? overflow;
      const item = stack && definition(ctx.content, stack.item_id);
      if (!stackId(cmd.stack_id) || !stack || !item?.discardable || !validQuantity(cmd.quantity)
        || cmd.quantity > stack.quantity) return err('INVALID_BAG_ACTION');
      if (item.source.kind === 'produce') {
        const crop = item.source.id as CropId;
        if (next.inventory.produce[crop] - (next.engineering.reserved[crop] ?? 0) < cmd.quantity)
          return err('INSUFFICIENT_ITEMS', crop);
      }
      stack.quantity -= cmd.quantity;
      bag.slots = bag.slots.filter(item => item.quantity > 0);
      bag.overflow = bag.overflow.filter(item => item.quantity > 0);
      break;
    }
    case 'equip_bag_item': {
      const allowed = slot ? equipmentSlots(ctx.content, slot.item_id) : [];
      const target = cmd.slot ?? allowed.find(name => !bag.equipped[name]) ?? allowed[0];
      if (!stackId(cmd.stack_id) || !slot || !target || !allowed.includes(target))
        return err('INVALID_BAG_ACTION');
      const index = bag.slots.indexOf(slot);
      const previous = bag.equipped[target];
      bag.slots.splice(index, 1);
      if (previous) bag.slots.splice(index, 0, previous);
      bag.equipped[target] = slot;
      break;
    }
    case 'unequip_bag_item': {
      const target = cmd.slot ?? 'main_hand';
      if (!EQUIPMENT_SLOTS.includes(target)) return err('INVALID_BAG_ACTION');
      const equipped = bag.equipped[target];
      if (!equipped) return err('INVALID_BAG_ACTION');
      if (bag.slots.length >= bag.capacity) return err('BAG_FULL');
      bag.slots.push(equipped);
      bag.equipped[target] = null;
      break;
    }
    case 'claim_bag_overflow':
      if (!stackId(cmd.stack_id) || !overflow) return err('INVALID_BAG_ACTION');
      if (!moveOverflow(bag, overflow, ctx.content)) return err('BAG_FULL');
      break;
    default: return null;
  }
  bag.sequence += 1;
  projectBagAggregates(next, ctx.content);
  return ok(next, [{ type: 'bag_changed', action: cmd.type }]);
}
