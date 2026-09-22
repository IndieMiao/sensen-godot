import { describe, expect, it } from 'vitest';
import { ensureBag, stacksCanMerge } from '../../src/domain/bag.js';
import type { Command } from '../../src/domain/commands.js';
import type { BagStack, FarmState } from '../../src/domain/state.js';
import { startJourney } from '../../src/domain/journey.js';
import { projectFarmState } from '../../src/domain/progress.js';
import { plot, content, editInventory, freshFarm, run, SH, T0 } from './helpers.js';

function fresh(): FarmState {
  const state = startJourney(freshFarm(), content);
  ensureBag(state, content);
  return state;
}
function act(state: FarmState, command: Command): FarmState {
  const result = run(state, command);
  if (!result.ok) throw new Error(`${command.type}: ${result.code} ${result.detail ?? ''}`);
  return result.state;
}
const project = (state: FarmState, now = T0) => projectFarmState(state, now, SH, content, plot);
const stack = (state: FarmState, item: string) => state.bag!.slots.find(stack => stack.item_id === item)!;
const qty = (state: FarmState, id: string) => [...state.bag!.slots, ...state.bag!.overflow]
  .filter(stack => stack.item_id === id).reduce((sum, stack) => sum + stack.quantity, 0);
function tight(state: FarmState): void { state.bag!.capacity = state.bag!.slots.length; }

describe('Unified bag ownership', () => {
  it('migrates every old holding once, keeps seed lots apart, and preserves a completed mine', () => {
    const old = startJourney(freshFarm(), content);
    old.inventory.seeds.R.bought = 203;
    old.inventory.produce.R = 123;
    old.inventory.dishes.vegetable_soup = 41;
    old.journey!.wood = 104;
    old.journey!.materials = { stone: 9, fiber: 2, copper_ore: 8, rock_salt: 6 };
    old.journey!.workshop = { sequence: 7, stock: { crate: 43 }, displays: { waystation: ['crate', '', ''] } };
    old.tools.row_tool = true;
    old.mine = { version: 1, run: 8, floor: 0, deepest_floor: 5, broken: {}, cleared_floors: [1, 2, 3, 4, 5], elevator_unlocked: true };
    const before = structuredClone(old);
    const migrated = project(old);
    expect(old).toEqual(before);
    expect(migrated.inventory).toEqual(old.inventory);
    expect(migrated.journey!.workshop).toEqual(old.journey!.workshop);
    expect(migrated.mine).toEqual(old.mine);
    expect(migrated.bag!.equipped.main_hand).toMatchObject({ item_id: 'row_tool', quantity: 1 });
    expect(stack(migrated, 'hand_tools').instance_id).toBeTruthy();
    expect(migrated.bag!.slots.filter(s => s.item_id === 'seed_R').map(s => [s.seed_lot, s.quantity]))
      .toEqual([['bought', 99], ['bought', 99], ['bought', 5], ['bound', 6]]);
    expect(qty(migrated, 'crate')).toBe(43);
    expect(project(JSON.parse(JSON.stringify(migrated)))).toEqual(migrated);
    expect(project(old)).toEqual(migrated);
  });

  it('retains excess old holdings in overflow and spends overflow first while the bag remains full', () => {
    const old = startJourney(freshFarm(), content);
    old.inventory.produce.R = 3000;
    const state = project(old);
    expect(state.bag!.slots).toHaveLength(24);
    expect(state.bag!.overflow.length).toBeGreaterThan(0);
    expect(qty(state, 'R')).toBe(3000);
    const slots = structuredClone(state.bag!.slots);
    const next = act(state, { type: 'sell_at_stall', items: [{ kind: 'produce', id: 'R', qty: 1 }] });
    expect(next.bag!.slots).toEqual(slots);
    expect(qty(next, 'R')).toBe(2999);
    expect(next.inventory.produce.R).toBe(2999);
    expect(next.wallet).toBe(state.wallet + content.journey.crops.R.unit_price);
  });

  it('never imports forged or stale aggregate counters after the canonical bag exists', () => {
    const state = fresh();
    const canonical = structuredClone(state.bag);
    state.inventory.produce.R = 999;
    state.inventory.seeds.R.bound = 0;
    state.journey!.wood = 999;
    state.journey!.materials = { stone: 999, fiber: 999 };
    state.tools.row_tool = true;
    const projected = project(state);
    expect(projected.bag).toEqual(canonical);
    expect(projected.inventory.produce.R).toBe(0);
    expect(projected.inventory.seeds.R.bound).toBe(6);
    expect(projected.journey!.wood).toBe(0);
    expect(projected.journey!.materials).toEqual({ stone: 0, fiber: 0 });
    expect(projected.tools.row_tool).toBe(false);
  });

  it('rejects a full-bag mine reward without breaking a rock or clearing a floor', () => {
    let state = act(fresh(), { type: 'enter_mine', run: 0 });
    tight(state);
    const before = structuredClone(state);
    expect(run(state, { type: 'mine_rock', run: 0, floor: 1, node_id: 'rock_1' }))
      .toMatchObject({ ok: false, code: 'BAG_FULL' });
    expect(state).toEqual(before);
    const seed = stack(state, 'seed_R');
    state = act(state, { type: 'discard_bag_stack', sequence: state.bag!.sequence, stack_id: seed.id, quantity: seed.quantity });
    state.bag!.capacity += 1;
    state = act(state, { type: 'mine_rock', run: 0, floor: 1, node_id: 'rock_1' });
    expect(state.mine!.broken['1']).toContain('rock_1');
    expect(qty(state, 'stone')).toBe(content.mining.stone_per_rock);
  });

  it('rejects full-bag gathering, crop harvest and seed purchases without costs or world changes', () => {
    const state = fresh();
    tight(state);
    state.cells['1,1'] = { ...state.cells['1,1'], state: 'growing', crop: 'R',
      watered_at: T0 - 1, ready_at: T0 - 1 };
    const before = structuredClone(state);
    for (const command of [
      { type: 'collect_resource', node_id: 'nursery_west', round: 0 },
      { type: 'harvest_cells', cell_ids: ['1,1'] },
      { type: 'buy_seeds', crop: 'R', qty: 1 },
    ] as Command[]) expect(run(state, command)).toMatchObject({ ok: false, code: 'BAG_FULL' });
    expect(state).toEqual(before);
  });

  it('uses existing stack room even with every slot occupied', () => {
    const state = fresh();
    editInventory(state, draft => { draft.inventory.seeds.R.bought = 98; });
    tight(state);
    const next = act(state, { type: 'buy_seeds', crop: 'R', qty: 1 });
    expect(next.bag!.slots).toHaveLength(state.bag!.capacity);
    expect(next.inventory.seeds.R.bought).toBe(99);
    expect(run(next, { type: 'buy_seeds', crop: 'R', qty: 1 })).toMatchObject({ ok: false, code: 'BAG_FULL' });
  });

  it('cooks and crafts into space freed by their complete cost, with no partial charge on failure', () => {
    const state = fresh();
    state.journey!.facts.push('workbench');
    state.journey!.unlocks.push('kitchen');
    editInventory(state, draft => {
      draft.inventory.produce.R = 1;
      draft.inventory.produce.L = 1;
      draft.journey!.wood = 2;
      draft.journey!.materials = { stone: 1, fiber: 0, copper_ore: 3, rock_salt: 1 };
    });
    tight(state);
    const cooked = act(state, { type: 'cook_dish', recipe: 'vegetable_soup' });
    expect(qty(cooked, 'vegetable_soup')).toBe(1);
    expect(qty(cooked, 'rock_salt')).toBe(0);
    const crafted = act(cooked, { type: 'craft_journey_item', item: 'crate', sequence: 0 });
    expect(qty(crafted, 'crate')).toBe(1);
    expect(qty(crafted, 'copper_ore')).toBe(0);
    const blocked = fresh();
    blocked.journey!.unlocks.push('kitchen');
    editInventory(blocked, draft => {
      draft.inventory.produce.R = 2;
      draft.inventory.produce.L = 2;
      draft.journey!.materials = { stone: 0, fiber: 0, rock_salt: 2 };
    });
    tight(blocked);
    const before = structuredClone(blocked);
    expect(run(blocked, { type: 'cook_dish', recipe: 'vegetable_soup' })).toMatchObject({ ok: false, code: 'BAG_FULL' });
    expect(blocked).toEqual(before);
  });

  it('leaves a displayed prop placed if its return cannot fit', () => {
    const state = fresh();
    state.journey!.facts.push('workbench', 'project_waystation_0', 'project_waystation_1');
    state.journey!.workshop = { sequence: 4, stock: {}, displays: { waystation: ['crate', '', ''] } };
    tight(state);
    const before = structuredClone(state);
    expect(run(state, { type: 'display_journey_item', project: 'waystation', slot: 0, item: '', sequence: 4 }))
      .toMatchObject({ ok: false, code: 'BAG_FULL' });
    expect(state).toEqual(before);
  });

  it('preserves automatic milestone rewards in overflow and does not duplicate them on repeated reads', () => {
    const state = fresh();
    tight(state);
    state.journey!.facts.push('shared_meal');
    const next = project(state);
    expect(next.journey!.completed).toContain('first_meal');
    expect(next.inventory.seeds.H.bound).toBe(2);
    expect(next.bag!.overflow).toContainEqual(expect.objectContaining({ item_id: 'seed_H', seed_lot: 'bound', quantity: 2 }));
    expect(project(next)).toEqual(next);
    expect(project(state)).toEqual(next);
  });

  it('does not duplicate equipped tool instances when buying or repeatedly projecting the row upgrade', () => {
    const state = fresh();
    state.wallet = 1000;
    state.journey!.unlocks.push('growth');
    const bought = act(state, { type: 'purchase_growth_choice', choice: 'tool', transaction_id: 'tool-purchase' });
    expect(bought.bag!.equipped.main_hand?.item_id).toBe('row_tool');
    expect(qty(bought, 'hand_tools')).toBe(1);
    expect(qty(bought, 'row_tool')).toBe(0);
    expect(bought.tools.row_tool).toBe(true);
    expect(project(bought)).toEqual(bought);
    const hand = stack(bought, 'hand_tools');
    tight(bought);
    const swapped = act(bought, { type: 'equip_bag_item', sequence: bought.bag!.sequence, stack_id: hand.id });
    expect(swapped.bag!.equipped.main_hand).toEqual(hand);
    expect(swapped.tools.row_tool).toBe(true);
    expect(qty(swapped, 'row_tool')).toBe(1);
    expect(project(swapped)).toEqual(swapped);
    expect(run(swapped, { type: 'unequip_bag_item', sequence: swapped.bag!.sequence }))
      .toMatchObject({ ok: false, code: 'BAG_FULL' });
    swapped.bag!.capacity += 1;
    const removed = act(swapped, { type: 'unequip_bag_item', sequence: swapped.bag!.sequence });
    expect(removed.bag!.equipped.main_hand).toBeNull();
    expect(qty(removed, 'hand_tools')).toBe(1);
    expect(removed.tools.row_tool).toBe(true);
    expect(project(removed)).toEqual(removed);
  });

  it('does not charge for a row upgrade when there is no room to store the equipped hand tools', () => {
    const state = fresh();
    state.wallet = 1000;
    state.journey!.unlocks.push('growth');
    tight(state);
    const before = structuredClone(state);
    expect(run(state, { type: 'purchase_growth_choice', choice: 'tool', transaction_id: 'full-bag' }))
      .toMatchObject({ ok: false, code: 'BAG_FULL' });
    expect(state).toEqual(before);
  });
});

describe('Bag management commands', () => {
  it('splits and partially merges with stable IDs, exact totals, and persisted sequence checks', () => {
    const initial = fresh();
    editInventory(initial, draft => { draft.journey!.wood = 150; });
    const first = stack(initial, 'wood');
    const split = act(initial, { type: 'split_bag_stack', sequence: initial.bag!.sequence, stack_id: first.id, quantity: 25 });
    expect(stack(split, 'wood')).toMatchObject({ id: first.id, quantity: 74 });
    expect(qty(split, 'wood')).toBe(150);
    const remainder = split.bag!.slots.filter(s => s.item_id === 'wood')[1];
    const merged = act(split, { type: 'merge_bag_stacks', sequence: split.bag!.sequence, source_id: remainder.id, target_id: first.id });
    expect(stack(merged, 'wood').quantity).toBe(99);
    expect(merged.bag!.slots.find(s => s.id === remainder.id)?.quantity).toBe(26);
    expect(qty(merged, 'wood')).toBe(150);
    expect(run(JSON.parse(JSON.stringify(merged)), { type: 'split_bag_stack', sequence: initial.bag!.sequence, stack_id: first.id, quantity: 1 }))
      .toMatchObject({ ok: false, code: 'BAG_CHANGED' });
  });

  it('refuses incompatible quality, seed lot, attributes and independent instances', () => {
    const base: BagStack = { id: 'bag_1', item_id: 'wood', quantity: 1, quality: 'normal' };
    for (const change of [{ quality: 'fine' }, { seed_lot: 'bound' }, { item_id: 'stone' },
      { attributes: { origin: 'special' } }, { instance_id: 'item_2' }])
      expect(stacksCanMerge(base, { ...base, ...change } as BagStack)).toBe(false);
    expect(stacksCanMerge({ ...base, attributes: { a: 1, b: 'two' } }, { ...base, attributes: { b: 'two', a: 1 } })).toBe(true);
    const state = fresh();
    editInventory(state, draft => { draft.inventory.seeds.R.bought = 2; });
    const bought = state.bag!.slots.find(s => s.item_id === 'seed_R' && s.seed_lot === 'bought')!;
    const bound = state.bag!.slots.find(s => s.item_id === 'seed_R' && s.seed_lot === 'bound')!;
    expect(run(state, { type: 'merge_bag_stacks', sequence: state.bag!.sequence, source_id: bought.id, target_id: bound.id }))
      .toMatchObject({ ok: false, code: 'INVALID_BAG_ACTION' });
  });

  it('sorts and consolidates without changing variants, possessions or tool instances', () => {
    const state = fresh();
    editInventory(state, draft => { draft.journey!.wood = 150; });
    const initial = stack(state, 'wood');
    const split = act(state, { type: 'split_bag_stack', sequence: state.bag!.sequence, stack_id: initial.id, quantity: 25 });
    split.bag!.slots.filter(s => s.item_id === 'wood')[2].quality = 'fine';
    const sorted = act(split, { type: 'sort_bag', sequence: split.bag!.sequence, mode: 'category' });
    expect(qty(sorted, 'wood')).toBe(150);
    expect(sorted.bag!.slots.filter(s => s.item_id === 'wood').map(s => [s.quality, s.quantity]))
      .toEqual([['fine', 25], ['normal', 99], ['normal', 26]]);
    expect(sorted.bag!.equipped).toEqual(split.bag!.equipped);
    expect(sorted.inventory).toEqual(split.inventory);
    expect(project(sorted)).toEqual(sorted);
  });

  it('claims only available overflow space without losing a remainder', () => {
    const old = startJourney(freshFarm(), content);
    old.journey!.wood = 3000;
    const state = project(old);
    const wood = stack(state, 'wood');
    const discarded = act(state, { type: 'discard_bag_stack', sequence: state.bag!.sequence, stack_id: wood.id, quantity: 2 });
    const source = discarded.bag!.overflow[0];
    const claimed = act(discarded, { type: 'claim_bag_overflow', sequence: discarded.bag!.sequence, stack_id: source.id });
    expect(stack(claimed, 'wood').quantity).toBe(99);
    expect(claimed.bag!.overflow.find(s => s.id === source.id)?.quantity).toBe(source.quantity - 2);
    expect(qty(claimed, 'wood')).toBe(2998);
    expect(run(claimed, { type: 'claim_bag_overflow', sequence: claimed.bag!.sequence, stack_id: source.id }))
      .toMatchObject({ ok: false, code: 'BAG_FULL' });
  });

  it('protects reserved produce and all tools from discarding', () => {
    const state = fresh();
    editInventory(state, draft => { draft.inventory.produce.R = 3; });
    state.engineering.reserved.R = 2;
    const produce = stack(state, 'R');
    expect(run(state, { type: 'discard_bag_stack', sequence: state.bag!.sequence, stack_id: produce.id, quantity: 2 }))
      .toMatchObject({ ok: false, code: 'INSUFFICIENT_ITEMS' });
    const discarded = act(state, { type: 'discard_bag_stack', sequence: state.bag!.sequence, stack_id: produce.id, quantity: 1 });
    expect(discarded.inventory.produce.R).toBe(2);
    expect(discarded.engineering.reserved.R).toBe(2);
    const unequipped = act(discarded, { type: 'unequip_bag_item', sequence: discarded.bag!.sequence });
    const hand = stack(unequipped, 'hand_tools');
    expect(run(unequipped, { type: 'discard_bag_stack', sequence: unequipped.bag!.sequence, stack_id: hand.id, quantity: 1 }))
      .toMatchObject({ ok: false, code: 'INVALID_BAG_ACTION' });
  });

  it.each([
    { type: 'split_bag_stack', stack_id: 'bag_2', quantity: 0 },
    { type: 'split_bag_stack', stack_id: 'bag_2', quantity: 0.5 },
    { type: 'split_bag_stack', stack_id: 'bag_2', quantity: 6 },
    { type: 'discard_bag_stack', stack_id: '__proto__', quantity: 1 },
    { type: 'discard_bag_stack', stack_id: 'bag_2', quantity: Number.MAX_SAFE_INTEGER + 1 },
    { type: 'merge_bag_stacks', source_id: 'bag_2', target_id: 'bag_2' },
    { type: 'sort_bag', mode: '__proto__' },
    { type: 'equip_bag_item', stack_id: 'bag_2' },
    { type: 'claim_bag_overflow', stack_id: 'bag_999' },
  ])('rejects invalid input atomically: %j', fields => {
    const state = fresh();
    const before = structuredClone(state);
    expect(run(state, { ...fields, sequence: state.bag!.sequence } as Command).ok).toBe(false);
    expect(state).toEqual(before);
  });

  it('rejects split at capacity without changing the original stack', () => {
    const state = fresh();
    tight(state);
    const before = structuredClone(state);
    expect(run(state, { type: 'split_bag_stack', sequence: state.bag!.sequence, stack_id: stack(state, 'seed_R').id, quantity: 1 }))
      .toMatchObject({ ok: false, code: 'BAG_FULL' });
    expect(state).toEqual(before);
  });
});

describe('Courtyard and bag share the same handmade ownership', () => {
  const planter = { prop_id: 'planter' as const, cell: [27, 3] as [number, number] };

  it('puts the first crafted planter in the bag and consumes it for its first placement', () => {
    const state = fresh();
    state.journey!.facts.push('workbench');
    editInventory(state, draft => { draft.journey!.wood = 2; });
    const crafted = act(state, { type: 'journey_action', action: 'craft_planter' });
    expect(qty(crafted, 'planter')).toBe(1);
    expect(crafted.journey!.workshop!.stock.planter).toBe(1);
    expect(crafted.journey!.workshop!.sequence).toBe(1);
    const placed = act(crafted, { type: 'save_decorations', props: [planter] });
    expect(qty(placed, 'planter')).toBe(0);
    expect(placed.journey!.workshop!.stock.planter).toBe(0);
    expect(placed.journey!.unlocks).toContain('decorations');
    expect(placed.bag!.slots.some(s => ['bench', 'lantern', 'sign'].includes(s.item_id))).toBe(false);
    const moved = act(placed, { type: 'save_decorations', props: [{ ...planter, cell: [28, 5] as [number, number], rotation_q: 1 }] });
    expect(moved.bag).toEqual(placed.bag);
    expect(moved.journey!.workshop!.sequence).toBe(placed.journey!.workshop!.sequence);
    const returned = act(moved, { type: 'save_decorations', props: [] });
    expect(qty(returned, 'planter')).toBe(1);
    expect(returned.decorations).toEqual([]);
    expect(project(returned)).toEqual(returned);
    const placedAgain = act(returned, { type: 'save_decorations', props: [planter] });
    expect(qty(placedAgain, 'planter')).toBe(0);
    expect(run(placedAgain, { type: 'save_decorations', props: [planter,
      { prop_id: 'lantern', cell: [29, 3] }] })).toMatchObject({ ok: false, code: 'INSUFFICIENT_ITEMS' });
  });

  it('rolls back the first craft and a courtyard return when their output cannot fit', () => {
    const state = fresh();
    state.journey!.facts.push('workbench');
    editInventory(state, draft => { draft.journey!.wood = 3; });
    tight(state);
    const before = structuredClone(state);
    expect(run(state, { type: 'journey_action', action: 'craft_planter' })).toMatchObject({ ok: false, code: 'BAG_FULL' });
    expect(state).toEqual(before);
    state.journey!.facts.push('planter_crafted');
    state.decorations = [planter];
    const placed = structuredClone(state);
    expect(run(state, { type: 'save_decorations', props: [] })).toMatchObject({ ok: false, code: 'BAG_FULL' });
    expect(state).toEqual(placed);
  });

  it('migrates each old courtyard entitlement once, separately from existing workshop stock', () => {
    const old = startJourney(freshFarm(), content);
    old.journey!.facts.push('workbench', 'planter_crafted');
    old.journey!.unlocks.push('decorations');
    old.journey!.workshop = { sequence: 4, stock: { planter: 2, crate: 3 }, displays: {} };
    old.decorations = [planter];
    const original = structuredClone(old);
    const migrated = project(old);
    expect(old).toEqual(original);
    expect(qty(migrated, 'planter')).toBe(2);
    expect(qty(migrated, 'crate')).toBe(4);
    for (const id of ['bench', 'lantern', 'fountain', 'sign']) expect(qty(migrated, id)).toBe(1);
    expect(migrated.decorations).toEqual(old.decorations);
    expect(migrated.journey!.workshop!.sequence).toBe(4);
    expect(project(migrated)).toEqual(migrated);
    expect(project(old)).toEqual(migrated);
  });

  it('imports only the old first planter when the full courtyard palette was never unlocked', () => {
    const old = startJourney(freshFarm(), content);
    old.journey!.facts.push('workbench', 'planter_crafted');
    const migrated = project(old);
    expect(qty(migrated, 'planter')).toBe(1);
    expect(qty(migrated, 'bench')).toBe(0);
    expect(act(migrated, { type: 'save_decorations', props: [planter] }).journey!.workshop!.stock.planter).toBe(0);
  });

  it('converts a legacy free palette even when its non-journey bag was already initialized', () => {
    const legacy = freshFarm();
    legacy.growth_choice.purchase = 'tool';
    legacy.tools.row_tool = true;
    legacy.decorations = [planter];
    const beforeJourney = project(legacy);
    expect(qty(beforeJourney, 'bench')).toBe(0);
    const migrated = act(beforeJourney, { type: 'start_journey' });
    expect(qty(migrated, 'planter')).toBe(0);
    expect(qty(migrated, 'bench')).toBe(1);
    expect(qty(migrated, 'crate')).toBe(1);
    expect(migrated.decorations).toEqual([planter]);
    expect(act(migrated, { type: 'start_journey' })).toEqual(migrated);
    expect(project(migrated)).toEqual(migrated);
  });
});
