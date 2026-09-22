import { describe, expect, it } from 'vitest';
import type { Command } from '../../src/domain/commands.js';
import { mineRocks } from '../../src/domain/content.js';
import { startJourney } from '../../src/domain/journey.js';
import { apply, makeCtx } from '../../src/domain/reducer.js';
import type { FarmState } from '../../src/domain/state.js';
import { plot, content, editInventory, freshFarm, run, SH, T0 } from './helpers.js';

const act = (state: FarmState, command: Command): FarmState => {
  const result = run(state, command);
  if (!result.ok) throw new Error(`${command.type}: ${result.code} ${result.detail}`);
  return result.state;
};
const enter = () => act(startJourney(freshFarm(), content), { type: 'enter_mine', run: 0 });
const defeat = (state: FarmState): FarmState => {
  let hp = state.mine!.combat!.monsters[String(state.mine!.floor)];
  while (hp.some(value => value > 0)) {
    const result = run(state, { type: 'mine_combat', run: state.mine!.run, floor: state.mine!.floor,
      sequence: state.mine!.combat!.sequence, targets: hp.flatMap((value, i) => value > 0 ? [`slime_${i + 1}`] : []) },
    T0 + (state.mine!.combat!.sequence + 1) * 1000);
    if (!result.ok) throw new Error(result.code);
    state = result.state;
    hp = state.mine!.combat!.monsters[String(state.mine!.floor)];
  }
  return state;
};
const clear = (state: FarmState): FarmState => {
  for (const rock of mineRocks(content.mining, state.mine!.floor))
    state = act(state, { type: 'mine_rock', run: state.mine!.run, floor: state.mine!.floor, node_id: rock.id });
  return defeat(state);
};
const complete = (): FarmState => {
  let state = enter();
  for (let floor = 1; floor <= content.mining.floors; floor++) {
    state = clear(state);
    if (floor < content.mining.floors) state = act(state, { type: 'descend_mine', run: 0, floor });
  }
  return state;
};

describe('Starter mine', () => {
  it('starts immediately for a new or old journey save without changing existing possessions', () => {
    const old = startJourney(freshFarm(), content);
    const before = structuredClone(old);
    const state = act(old, { type: 'enter_mine', run: 0 });
    expect(old).toEqual(before);
    expect(state.mine).toMatchObject({ run: 0, floor: 1, deepest_floor: 1, broken: {},
      cleared_floors: [], elevator_unlocked: false });
    expect(state.inventory).toEqual(old.inventory);
    expect(state.journey).toEqual(old.journey);
    expect(state.wallet).toBe(old.wallet);
    expect(run(freshFarm(), { type: 'enter_mine', run: 0 }).ok).toBe(false);
  });

  it('opens floors one through four by rocks and requires the elite for the elevator', () => {
    let state = enter();
    for (let floor = 1; floor <= content.mining.floors; floor++) {
      expect(state.mine!.floor).toBe(floor);
      expect(state.mine!.elevator_unlocked).toBe(false);
      expect(run(state, { type: 'use_mine_elevator', run: 0, floor }).ok).toBe(false);
      expect(run(state, { type: 'descend_mine', run: 0, floor }).ok).toBe(false);
      for (const rock of mineRocks(content.mining, floor)) {
        const before = state.journey!.materials?.stone ?? 0;
        state = act(state, { type: 'mine_rock', run: 0, floor, node_id: rock.id });
        expect(state.journey!.materials!.stone - before).toBe(content.mining.stone_per_rock);
        if (rock !== content.mining.rocks.at(-1)) {
          expect(state.mine!.cleared_floors).not.toContain(floor);
          expect(run(state, { type: 'descend_mine', run: 0, floor }).ok).toBe(false);
        }
      }
      state = defeat(state);
      expect(state.mine!.cleared_floors).toContain(floor);
      if (floor < content.mining.floors) state = act(state, { type: 'descend_mine', run: 0, floor });
    }
    expect(state.mine!.elevator_unlocked).toBe(true);
    expect(state.mine!.cleared_floors).toEqual([1, 2, 3, 4, 5]);
    expect(state.journey!.materials!.stone).toBe(24);
    expect(run(state, { type: 'descend_mine', run: 0, floor: 5 }).ok).toBe(false);
    state = act(state, { type: 'use_mine_elevator', run: 0, floor: 5 });
    expect(state.mine!.floor).toBe(1);
    state = act(state, { type: 'use_mine_elevator', run: 0, floor: 1 });
    expect(state.mine!.floor).toBe(5);
    state = act(state, { type: 'ascend_mine', run: 0, floor: 5 });
    expect(state.mine!.floor).toBe(4);
    expect(run(state, { type: 'use_mine_elevator', run: 0, floor: 4 }).ok).toBe(false);
  });

  it('persists mined rocks across exits, serialization and climbing back to explored floors', () => {
    let state = clear(enter());
    state = act(state, { type: 'descend_mine', run: 0, floor: 1 });
    state = act(state, { type: 'mine_rock', run: 0, floor: 2, node_id: 'rock_1' });
    const before = structuredClone(state);
    state = act(state, { type: 'leave_mine', run: 0, floor: 2 });
    state = act(JSON.parse(JSON.stringify(state)), { type: 'enter_mine', run: 0 });
    expect(state.mine!.floor).toBe(1);
    expect(state.mine!.deepest_floor).toBe(2);
    expect(state.mine!.broken).toEqual(before.mine!.broken);
    expect(state.journey!.materials).toEqual(before.journey!.materials);
    state = act(state, { type: 'descend_mine', run: 0, floor: 1 });
    expect(run(state, { type: 'mine_rock', run: 0, floor: 2, node_id: 'rock_1' }))
      .toMatchObject({ ok: false, code: 'ALREADY_CLAIMED' });
    state = act(state, { type: 'ascend_mine', run: 0, floor: 2 });
    expect(state.mine!.floor).toBe(1);
  });

  it('allows an explicit new expedition only after floor five is complete and the player is outside', () => {
    let state = enter();
    expect(run(state, { type: 'restart_mine', run: 0 }).ok).toBe(false);
    state = act(state, { type: 'leave_mine', run: 0, floor: 1 });
    expect(run(state, { type: 'restart_mine', run: 0 }).ok).toBe(false);
    state = complete();
    expect(run(state, { type: 'restart_mine', run: 0 }).ok).toBe(false);
    state = act(state, { type: 'leave_mine', run: 0, floor: 5 });
    const rewards = structuredClone(state.journey!.materials);
    state = act(state, { type: 'restart_mine', run: 0 });
    expect(state.mine).toEqual({ version: 1, run: 1, floor: 0, deepest_floor: 1, broken: {},
      cleared_floors: [], elevator_unlocked: true });
    expect(state.journey!.materials).toEqual(rewards);
    expect(run(state, { type: 'enter_mine', run: 0 }).ok).toBe(false);
    state = act(state, { type: 'enter_mine', run: 1 });
    state = act(state, { type: 'use_mine_elevator', run: 1, floor: 1 });
    expect(state.mine!.floor).toBe(5);
    expect(state.mine!.broken).toEqual({});
    expect(run(state, { type: 'mine_rock', run: 1, floor: 5, node_id: 'rock_1' }).ok).toBe(false);
    expect(state.journey!.materials).toEqual(rewards);
  });

  it.each([
    { type: 'mine_rock', run: 0, floor: 1, node_id: '__proto__' },
    { type: 'mine_rock', run: 0, floor: 2, node_id: 'rock_1' },
    { type: 'mine_rock', run: 1, floor: 1, node_id: 'rock_1' },
    { type: 'mine_rock', run: -1, floor: 1, node_id: 'rock_1' },
    { type: 'mine_rock', run: 0, floor: 1.5, node_id: 'rock_1' },
    { type: 'mine_rock', run: 0, floor: 0, node_id: 'rock_1' },
    { type: 'enter_mine', run: 0 },
    { type: 'ascend_mine', run: 0, floor: 1 },
  ] as Command[])('rejects unreachable, forged or stale commands atomically: %j', command => {
    const state = enter();
    const before = structuredClone(state);
    expect(run(state, command).ok).toBe(false);
    expect(state).toEqual(before);
  });

  it('draws rewards independently of request time and mining order, ignoring supplied reward fields', () => {
    const original = enter();
    const command = { type: 'mine_rock' as const, run: 0, floor: 1, node_id: 'rock_1' };
    const direct = act(original, command);
    const afterOther = act(act(original, { ...command, node_id: 'rock_2' }), command);
    expect(afterOther.mine!.last_drop).toEqual(direct.mine!.last_drop);
    const late = run(original, command, T0 + 1000);
    expect(late.ok && late.state.mine!.last_drop).toEqual(direct.mine!.last_drop);
    const forged = act(original, { ...command, materials: { copper_ore: 999 }, seed: 'chosen' } as Command);
    expect(forged).toEqual(direct);
    const dropsByFarm = ['owner-farm-a', 'owner-farm-b'].map(farmId => content.mining.rocks.map(rock => {
      const result = apply(original, { ...command, node_id: rock.id }, makeCtx(original, T0, SH, content, plot, T0, farmId));
      return result.ok ? result.state.mine!.last_drop!.materials : null;
    }));
    expect(dropsByFarm[0]).not.toEqual(dropsByFarm[1]);
  });

  it('uses earned copper ore for a displayable crate and earned rock salt for a sellable soup', () => {
    let state = complete();
    expect(state.journey!.materials!.copper_ore).toBeGreaterThanOrEqual(3);
    expect(state.journey!.materials!.rock_salt).toBeGreaterThanOrEqual(1);
    state = act(state, { type: 'leave_mine', run: 0, floor: 5 });
    state.journey!.facts.push('workbench', 'project_waystation_0', 'project_waystation_1');
    state.journey!.unlocks.push('kitchen');
    editInventory(state, draft => {
      draft.journey!.wood = 2;
      draft.inventory.produce.R = 1;
      draft.inventory.produce.L = 1;
    });
    const before = structuredClone(state);
    state = act(state, { type: 'craft_journey_item', item: 'crate', sequence: 0 });
    expect(state.journey!.materials!.copper_ore).toBe(before.journey!.materials!.copper_ore! - 3);
    expect(state.journey!.materials!.stone).toBe(before.journey!.materials!.stone - 1);
    expect(state.journey!.wood).toBe(0);
    expect(state.journey!.workshop!.stock.crate).toBe(1);
    state = act(state, { type: 'display_journey_item', project: 'waystation', slot: 0, item: 'crate', sequence: 1 });
    expect(state.journey!.workshop!.displays.waystation[0]).toBe('crate');
    expect(state.journey!.workshop!.stock.crate).toBe(0);
    state = act(state, { type: 'display_journey_item', project: 'waystation', slot: 0, item: '', sequence: 2 });
    expect(state.journey!.workshop!.displays.waystation[0]).toBe('');
    expect(state.journey!.workshop!.stock.crate).toBe(1);
    expect(run(state, { type: 'display_journey_item', project: 'waystation', slot: 0, item: '', sequence: 2 }).ok).toBe(false);
    state = act(state, { type: 'cook_dish', recipe: 'vegetable_soup' });
    expect(state.inventory.dishes.vegetable_soup).toBe(1);
    expect(state.inventory.produce.R).toBe(0);
    expect(state.inventory.produce.L).toBe(0);
    expect(state.journey!.materials!.rock_salt).toBe(before.journey!.materials!.rock_salt! - 1);
    state = act(state, { type: 'sell_at_stall', items: [{ kind: 'dish', id: 'vegetable_soup', qty: 1 }] });
    expect(state.wallet).toBe(before.wallet + content.journey.dish_prices.vegetable_soup);
    expect(state.inventory.dishes.vegetable_soup).toBe(0);
  });

  it('treats missing old-save mineral and soup counts as zero and keeps costs atomic', () => {
    const state = startJourney(freshFarm(), content);
    state.journey!.facts.push('workbench');
    state.journey!.unlocks.push('kitchen');
    state.journey!.wood = 2;
    state.journey!.materials = { stone: 5, fiber: 2 };
    state.inventory.produce.R = 1;
    state.inventory.produce.L = 1;
    const before = structuredClone(state);
    for (const command of [
      { type: 'craft_journey_item', item: 'crate', sequence: 0 },
      { type: 'cook_dish', recipe: 'vegetable_soup' },
      { type: 'sell_at_stall', items: [{ kind: 'dish', id: 'vegetable_soup', qty: 1 }] },
    ] as Command[]) expect(run(state, command)).toMatchObject({ ok: false, code: 'INSUFFICIENT_ITEMS' });
    expect(state).toEqual(before);
    state.journey!.materials.rock_salt = 1;
    state.engineering.reserved.R = 1;
    expect(run(state, { type: 'cook_dish', recipe: 'vegetable_soup' }).ok).toBe(false);
    expect(state.journey!.materials.rock_salt).toBe(1);
    expect(state.inventory.produce.R).toBe(1);
  });
});
