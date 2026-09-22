import { describe, expect, it } from 'vitest';
import { allBagStacks, ensureBag } from '../../src/domain/bag.js';
import { characterStats, craftingMaterials, gatheringMaterials } from '../../src/domain/character.js';
import type { Command } from '../../src/domain/commands.js';
import { resourceNodes, startJourney } from '../../src/domain/journey.js';
import { projectFarmState } from '../../src/domain/progress.js';
import type { FarmState } from '../../src/domain/state.js';
import { plot, content, editInventory, freshFarm, run, SH, T0 } from './helpers.js';
import { characterFixture } from '../../tools/prepare_character_qa.js';

const project = (state: FarmState) => projectFarmState(state, T0, SH, content, plot);
function fresh(): FarmState {
  const state = startJourney(freshFarm(), content);
  state.journey!.facts.push('workbench', 'planter_crafted');
  state.journey!.unlocks.push('kitchen', 'tea');
  ensureBag(state, content);
  editInventory(state, draft => {
    draft.journey!.wood = 30;
    draft.journey!.materials = { stone: 30, fiber: 30, copper_ore: 30, rock_salt: 30 };
    draft.inventory.dishes = { salad: 5, tea: 5, vegetable_soup: 5 };
  });
  return project(state);
}
const stack = (state: FarmState, id: string) => state.bag!.slots.find(value => value.item_id === id)!;
const quantity = (state: FarmState, id: string) => allBagStacks(state.bag!).filter(value => value.item_id === id)
  .reduce((sum, value) => sum + value.quantity, 0);
const remaining = (state: FarmState, id: string) => state.character!.buffs.find(value => value.source_item_id === id)?.remaining_uses ?? 0;
function act(state: FarmState, command: Command): FarmState {
  const result = run(state, command);
  if (!result.ok) throw new Error(`${command.type}: ${result.code} ${result.detail ?? ''}`);
  return result.state;
}
const craft = (state: FarmState, item_id: string) => act(state, { type: 'craft_equipment', item_id, sequence: state.bag!.sequence });
const equip = (state: FarmState, item_id: string) => act(state, { type: 'equip_bag_item', stack_id: stack(state, item_id).id, sequence: state.bag!.sequence });
const eat = (state: FarmState, item_id: string) => act(state, { type: 'use_bag_item', stack_id: stack(state, item_id).id, sequence: state.bag!.sequence });

describe('Character equipment and compatible saves', () => {
  it('adds empty character and accessory state to a domain-16 bag without minting items or replacing old tools', () => {
    const old = fresh();
    editInventory(old, draft => { draft.tools.row_tool = true; });
    delete old.character;
    delete old.bag!.equipped.gloves;
    old.mine = { version: 1, run: 4, floor: 0, deepest_floor: 5, cleared_floors: [1, 2, 3, 4, 5], broken: {}, elevator_unlocked: true };
    const before = structuredClone(old);
    const current = project(old);
    expect(old).toEqual(before);
    expect(current.character).toEqual({ version: 1, buffs: [], hp: 100 });
    expect(current.bag).toEqual({ ...old.bag, sequence: old.bag!.sequence + 1, equipped: { ...old.bag!.equipped, gloves: null } });
    expect(current.mine).toEqual(old.mine);
    expect(characterStats(current, content).tool_scope).toBe(3);
    expect(allBagStacks(current.bag!).filter(value => content.items.items[value.item_id].source.kind === 'equipment' && value.item_id !== 'starter_fishing_rod')).toEqual([]);
    expect(project(JSON.parse(JSON.stringify(current)))).toEqual(current);
  });

  it('crafts unique instances, changes the proper slot and preserves tool ownership through swaps and projections', () => {
    let state = fresh();
    editInventory(state, draft => { draft.tools.row_tool = true; });
    const oldMaterials = structuredClone(state.journey!.materials);
    state = craft(state, 'copper_pickaxe');
    expect(state.bag!.equipped.main_hand?.item_id).toBe('row_tool');
    expect(state.journey!.materials!.copper_ore).toBe(oldMaterials!.copper_ore! - 4);
    expect(stack(state, 'copper_pickaxe').instance_id).toBeTruthy();
    const identity = structuredClone(stack(state, 'copper_pickaxe'));
    state.bag!.capacity = state.bag!.slots.length;
    state = equip(state, 'copper_pickaxe');
    expect(state.bag!.equipped.main_hand).toEqual(identity);
    expect(characterStats(state, content)).toEqual({ ...content.character.base, mining_bonus: 1 });
    expect(state.tools.row_tool).toBe(true);
    expect(project(state)).toEqual(state);
    expect(run(state, { type: 'craft_equipment', item_id: 'copper_pickaxe', sequence: state.bag!.sequence }))
      .toMatchObject({ ok: false, code: 'EQUIPMENT_OWNED' });
    expect(run(state, { type: 'unequip_bag_item', sequence: state.bag!.sequence }))
      .toMatchObject({ ok: false, code: 'BAG_FULL' });
    state.bag!.capacity += 2;
    state = equip(craft(state, 'foraging_gloves'), 'foraging_gloves');
    state = equip(craft(state, 'artisan_apron'), 'artisan_apron');
    expect(state.bag!.equipped.gloves?.item_id).toBe('artisan_apron');
    expect(characterStats(state, content)).toEqual({ ...content.character.base, mining_bonus: 1, craft_savings: 1 });
    state = act(state, { type: 'unequip_bag_item', slot: 'gloves', sequence: state.bag!.sequence });
    expect(state.bag!.equipped.gloves).toBeNull();
    expect(characterStats(state, content).craft_savings).toBe(0);
    expect(allBagStacks(state.bag!).find(value => value.item_id === 'copper_pickaxe')).toEqual(identity);
    expect(project(JSON.parse(JSON.stringify(state)))).toEqual(state);
  });

  it('rejects unknown equipment, missing workbench, stale sequence, duplicate overflow ownership and discarding equipment', () => {
    let state = fresh();
    state.journey!.facts = [];
    expect(run(state, { type: 'craft_equipment', item_id: 'copper_pickaxe', sequence: state.bag!.sequence }))
      .toMatchObject({ ok: false, code: 'NOT_AVAILABLE' });
    expect(run(state, { type: 'craft_equipment', item_id: '__proto__', sequence: state.bag!.sequence }))
      .toMatchObject({ ok: false, code: 'INVALID_BAG_ACTION' });
    state.journey!.facts.push('workbench');
    state = craft(state, 'copper_pickaxe');
    const item = stack(state, 'copper_pickaxe');
    expect(run(state, { type: 'discard_bag_stack', stack_id: item.id, quantity: 1, sequence: state.bag!.sequence }))
      .toMatchObject({ ok: false, code: 'INVALID_BAG_ACTION' });
    state.bag!.slots = state.bag!.slots.filter(value => value !== item);
    state.bag!.overflow.push(item);
    expect(run(state, { type: 'craft_equipment', item_id: 'copper_pickaxe', sequence: state.bag!.sequence }))
      .toMatchObject({ ok: false, code: 'EQUIPMENT_OWNED' });
    expect(run(state, { type: 'craft_equipment', item_id: 'artisan_apron', sequence: state.bag!.sequence - 1 }))
      .toMatchObject({ ok: false, code: 'BAG_CHANGED' });
  });

  it('uses exact costs across stacks and only admits equipment if the complete transaction fits', () => {
    const state = fresh();
    editInventory(state, draft => {
      draft.journey!.wood = 3;
      draft.journey!.materials!.copper_ore = 4;
      draft.journey!.materials!.stone = 2;
    });
    const split = act(state, { type: 'split_bag_stack', sequence: state.bag!.sequence, stack_id: stack(state, 'copper_ore').id, quantity: 2 });
    split.bag!.capacity = split.bag!.slots.length;
    const crafted = craft(split, 'copper_pickaxe');
    expect(quantity(crafted, 'copper_ore')).toBe(0);
    expect(quantity(crafted, 'stone')).toBe(0);
    expect(quantity(crafted, 'wood')).toBe(0);
    expect(quantity(crafted, 'copper_pickaxe')).toBe(1);
    const blocked = eat(fresh(), 'tea');
    blocked.bag!.capacity = blocked.bag!.slots.length;
    const before = structuredClone(blocked);
    expect(run(blocked, { type: 'craft_equipment', item_id: 'copper_pickaxe', sequence: blocked.bag!.sequence }))
      .toMatchObject({ ok: false, code: 'BAG_FULL' });
    expect(blocked).toEqual(before);
    expect(remaining(blocked, 'tea')).toBe(3);
  });
});

describe('Consumables and successful-action effects', () => {
  it('consumes the selected variant stack once, allows different effects, rejects repeated effects, and accepts overflow food', () => {
    let state = fresh();
    const salad = stack(state, 'salad');
    salad.quality = 'fine';
    salad.attributes = { origin: 'garden' };
    state = eat(state, 'salad');
    expect(stack(state, 'salad')).toMatchObject({ quality: 'fine', attributes: { origin: 'garden' }, quantity: 4 });
    const before = structuredClone(state);
    expect(run(state, { type: 'use_bag_item', stack_id: salad.id, sequence: state.bag!.sequence }))
      .toMatchObject({ ok: false, code: 'EFFECT_ACTIVE' });
    expect(state).toEqual(before);
    state = eat(state, 'tea');
    const soup = stack(state, 'vegetable_soup');
    state.bag!.slots = state.bag!.slots.filter(value => value !== soup);
    state.bag!.overflow.push(soup);
    state = act(state, { type: 'use_bag_item', stack_id: soup.id, sequence: state.bag!.sequence });
    expect(state.character!.buffs).toHaveLength(3);
    expect(state.bag!.overflow.find(value => value.id === soup.id)?.quantity).toBe(4);
    expect(project(JSON.parse(JSON.stringify(state)))).toEqual(state);
    expect(run(state, { type: 'use_bag_item', stack_id: stack(state, 'wood').id, sequence: state.bag!.sequence }))
      .toMatchObject({ ok: false, code: 'INVALID_BAG_ACTION' });
    expect(run(state, { type: 'use_bag_item', stack_id: salad.id, sequence: state.bag!.sequence - 1 }))
      .toMatchObject({ ok: false, code: 'BAG_CHANGED' });
  });

  it('adds to the greatest chosen resource, uses fixed ties, and consumes salad on exactly three successful collections', () => {
    let state = eat(equip(craft(fresh(), 'foraging_gloves'), 'foraging_gloves'), 'salad');
    expect(gatheringMaterials(state, { fiber: 2, stone: 2, wood: 2 }, content).materials).toEqual({ fiber: 2, stone: 2, wood: 4 });
    expect(gatheringMaterials(state, { wood: 1, stone: 2, fiber: 4 }, content).materials).toEqual({ wood: 1, stone: 2, fiber: 6 });
    const ids = ['nursery_west', 'nursery_east', 'courtyard_west', 'courtyard_east'];
    for (let index = 0; index < ids.length; index++) {
      const node = resourceNodes(state, content).find(value => value.id === ids[index])!;
      const base = node.materials.wood!;
      const before = state.journey!.wood;
      const result = run(state, { type: 'collect_resource', node_id: ids[index], round: 0 });
      expect(result.ok).toBe(true);
      if (!result.ok) return;
      state = result.state;
      const expected = base + (index < 3 ? 2 : 1);
      expect(state.journey!.wood - before).toBe(expected);
      expect(result.events[0]).toMatchObject({ type: 'resource_collected', wood: expected, materials: { wood: expected } });
      expect(remaining(state, 'salad')).toBe(Math.max(0, 2 - index));
    }
    expect(characterStats(state, content).gather_bonus).toBe(1);
    state = eat(state, 'salad');
    expect(remaining(state, 'salad')).toBe(3);
  });

  it('does not spend salad on non-collection rewards, repeated nodes or full-bag failures', () => {
    let state = eat(fresh(), 'salad');
    state.journey!.facts.push('discovery_reed_garden');
    const discovery = content.journey.discoveries.reed_garden;
    state.journey!.facts.push(...discovery.requires);
    const choice = Object.keys(discovery.choices)[0];
    state = act(state, { type: 'harvest_journey_discovery', discovery: 'reed_garden', choice, round: 0 });
    expect(remaining(state, 'salad')).toBe(3);
    state = act(state, { type: 'collect_resource', node_id: 'nursery_west', round: 0 });
    expect(remaining(state, 'salad')).toBe(2);
    expect(run(state, { type: 'collect_resource', node_id: 'nursery_west', round: 0 })).toMatchObject({ ok: false, code: 'ALREADY_CLAIMED' });
    editInventory(state, draft => { draft.journey!.wood = 99; });
    state.bag!.capacity = state.bag!.slots.length;
    const before = structuredClone(state);
    expect(run(state, { type: 'collect_resource', node_id: 'nursery_east', round: 0 })).toMatchObject({ ok: false, code: 'BAG_FULL' });
    expect(state).toEqual(before);
  });

  it('adds only stone to mining, keeps the stable mineral roll and expires soup after three rocks', () => {
    const base = act(fresh(), { type: 'enter_mine', run: 0 });
    let state = eat(equip(craft(base, 'copper_pickaxe'), 'copper_pickaxe'), 'vegetable_soup');
    for (let index = 0; index < 4; index++) {
      const command: Command = { type: 'mine_rock', run: 0, floor: 1, node_id: `rock_${index + 1}` };
      const plain = act(base, command);
      state = act(state, command);
      expect(state.mine!.last_drop!.materials).toEqual({ ...plain.mine!.last_drop!.materials,
        stone: content.mining.stone_per_rock + (index < 3 ? 2 : 1) });
      expect(remaining(state, 'vegetable_soup')).toBe(Math.max(0, 2 - index));
    }
  });

  it('rolls back the last rock, ladder and soup use together when its reward cannot fit', () => {
    let state = eat(act(fresh(), { type: 'enter_mine', run: 0 }), 'vegetable_soup');
    state.mine!.floor = 4;
    state.mine!.broken['4'] = content.mining.rocks.slice(0, -1).map(rock => rock.id);
    editInventory(state, draft => { draft.journey!.materials!.stone = 99; });
    state.bag!.capacity = state.bag!.slots.length;
    const before = structuredClone(state);
    expect(run(state, { type: 'mine_rock', run: 0, floor: 4, node_id: content.mining.rocks.at(-1)!.id }))
      .toMatchObject({ ok: false, code: 'BAG_FULL' });
    expect(state).toEqual(before);
    state.bag!.capacity += 2;
    state = act(state, { type: 'mine_rock', run: 0, floor: 4, node_id: content.mining.rocks.at(-1)!.id });
    expect(state.mine!.cleared_floors).toContain(4);
    expect(state.mine!.elevator_unlocked).toBe(false);
    expect(remaining(state, 'vegetable_soup')).toBe(2);
  });

  it('applies apron before tea, keeps every basic cost at least one and never discounts minerals', () => {
    let state = eat(equip(craft(fresh(), 'artisan_apron'), 'artisan_apron'), 'tea');
    expect(craftingMaterials(state, { wood: 2, stone: 2, fiber: 3, copper_ore: 4, rock_salt: 2 }, content))
      .toEqual({ materials: { wood: 1, stone: 1, fiber: 3, copper_ore: 4, rock_salt: 2 },
        actual_saved: { wood: 1, stone: 1 }, equipment_saved: 1, meal_saved: 1 });
    const noTea = craftingMaterials(state, { wood: 2, stone: 1, copper_ore: 3 }, content);
    expect(noTea.meal_saved).toBe(0);
    const before = state.journey!.wood;
    state = act(state, { type: 'craft_journey_item', item: 'crate', sequence: state.journey!.workshop!.sequence });
    expect(state.journey!.wood).toBe(before - 1);
    expect(remaining(state, 'tea')).toBe(3);
    for (let index = 0; index < 3; index++) {
      const result = run(state, { type: 'craft_journey_item', item: 'planter', sequence: state.journey!.workshop!.sequence });
      expect(result.ok).toBe(true);
      if (!result.ok) return;
      state = result.state;
      expect(result.events[0]).toMatchObject({ actual_saved: { wood: 1, fiber: 1 } });
      expect(remaining(state, 'tea')).toBe(2 - index);
    }
  });

  it('uses effective discounts for equipment and first planter, but not construction or cooking', () => {
    let state = eat(fresh(), 'tea');
    state.journey!.facts = ['workbench'];
    editInventory(state, draft => { draft.journey!.wood = 1; });
    const first = run(state, { type: 'journey_action', action: 'craft_planter' });
    expect(first.ok).toBe(true);
    if (!first.ok) return;
    expect(first.events[0]).toMatchObject({ type: 'world_changed', actual_saved: { wood: 1 } });
    state = first.state;
    expect(remaining(state, 'tea')).toBe(2);
    editInventory(state, draft => {
      draft.journey!.wood = 1;
      draft.inventory.produce.R = 1;
      draft.inventory.produce.L = 1;
    });
    state = act(state, { type: 'cook_dish', recipe: 'vegetable_soup' });
    expect(remaining(state, 'tea')).toBe(2);
    state = craft(state, 'foraging_gloves');
    expect(state.journey!.wood).toBe(0);
    expect(remaining(state, 'tea')).toBe(1);
    state.journey!.facts.push('shared_meal');
    editInventory(state, draft => { draft.journey!.wood = 1; });
    expect(run(state, { type: 'journey_action', action: 'clear_side_path' })).toMatchObject({ ok: false, code: 'INSUFFICIENT_ITEMS' });
    expect(remaining(state, 'tea')).toBe(1);
  });

  it('does not spend tea or materials on insufficient costs, stale workshop or full-bag craft', () => {
    const state = eat(fresh(), 'tea');
    editInventory(state, draft => { draft.journey!.materials!.copper_ore = 0; });
    const before = structuredClone(state);
    expect(run(state, { type: 'craft_equipment', item_id: 'copper_pickaxe', sequence: state.bag!.sequence }))
      .toMatchObject({ ok: false, code: 'INSUFFICIENT_ITEMS' });
    expect(run(state, { type: 'craft_journey_item', item: 'planter', sequence: -1 }))
      .toMatchObject({ ok: false, code: 'ALREADY_CLAIMED' });
    editInventory(state, draft => { draft.journey!.workshop!.stock.planter = 20; });
    state.bag!.capacity = state.bag!.slots.length;
    const tight = structuredClone(state);
    expect(run(state, { type: 'craft_journey_item', item: 'planter', sequence: state.journey!.workshop!.sequence }))
      .toMatchObject({ ok: false, code: 'BAG_FULL' });
    expect(state).toEqual(tight);
    expect(state.character).toEqual(before.character);
  });
});

describe('Isolated emulator fixtures', () => {
  it('provides all three real equipment recipes without pregranting the equipment', () => {
    const original = fresh();
    const before = structuredClone(original);
    let state = project(characterFixture(original, content, 'materials'));
    expect(original).toEqual(before);
    expect(state.bag!.overflow).toEqual([]);
    expect(allBagStacks(state.bag!).some(stack => content.items.items[stack.item_id].source.kind === 'equipment' && stack.item_id !== 'starter_fishing_rod')).toBe(false);
    for (const item of ['copper_pickaxe', 'foraging_gloves', 'artisan_apron']) {
      state = craft(state, item);
      expect(quantity(state, item)).toBe(1);
    }
    for (const food of Object.keys(content.character.consumables)) expect(quantity(state, food)).toBe(5);
  });

  it('guarantees full-bag mine rollback, then admits every possible mineral roll after discarding the first stack', () => {
    let state = project(characterFixture(fresh(), content, 'full'));
    expect(state.bag!.slots).toHaveLength(24);
    expect(state.bag!.equipped.main_hand?.item_id).toBe('copper_pickaxe');
    state = act(state, { type: 'enter_mine', run: state.mine!.run });
    const before = structuredClone(state);
    for (const rock of content.mining.rocks) expect(run(state,
      { type: 'mine_rock', run: state.mine!.run, floor: 1, node_id: rock.id }))
      .toMatchObject({ ok: false, code: 'BAG_FULL' });
    expect(state).toEqual(before);
    const discarded = state.bag!.slots[0];
    state = act(state, { type: 'discard_bag_stack', sequence: state.bag!.sequence, stack_id: discarded.id, quantity: discarded.quantity });
    for (const rock of content.mining.rocks) {
      const mined = act(state, { type: 'mine_rock', run: state.mine!.run, floor: 1, node_id: rock.id });
      expect(mined.mine!.last_drop!.materials.stone).toBe(content.mining.stone_per_rock + 2);
      expect(remaining(mined, 'vegetable_soup')).toBe(2);
      expect(mined.bag!.slots).toHaveLength(24);
      expect(mined.bag!.overflow).toEqual(before.bag!.overflow);
    }
  });
});
