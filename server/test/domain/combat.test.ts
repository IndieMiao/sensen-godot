import { describe, expect, it } from 'vitest';
import { addBagItem, allBagStacks } from '../../src/domain/bag.js';
import { characterStats } from '../../src/domain/character.js';
import type { Command } from '../../src/domain/commands.js';
import { startJourney } from '../../src/domain/journey.js';
import { projectFarmState } from '../../src/domain/progress.js';
import { apply, makeCtx } from '../../src/domain/reducer.js';
import type { FarmState } from '../../src/domain/state.js';
import { plot, content, editInventory, freshFarm, run, SH, T0 } from './helpers.js';

const act = (state: FarmState, command: Command, now = T0): FarmState => {
  const result = run(state, command, now);
  if (!result.ok) throw new Error(`${command.type}: ${result.code}`);
  return result.state;
};
const entered = (floor = 3) => {
  let state = act(startJourney(freshFarm(), content), { type: 'enter_mine', run: 0 });
  state = act(state, { type: 'equip_bag_item', sequence: state.bag!.sequence, stack_id: state.bag!.slots.find(v => v.item_id === 'rusty_sword')!.id });
  state.mine!.floor = floor;
  return state;
};
const strike = (s: FarmState, targets = ['slime_1'], hurt_by?: string): Command => ({
  type: 'mine_combat', run: s.mine!.run, floor: s.mine!.floor, sequence: s.mine!.combat!.sequence, targets,
  ...(hurt_by ? { hurt_by } : {}),
});
export function defeatFloor(state: FarmState): FarmState {
  while (state.mine!.combat!.monsters[String(state.mine!.floor)].some(hp => hp > 0)) {
    const targets = state.mine!.combat!.monsters[String(state.mine!.floor)].flatMap((hp, i) => hp > 0 ? [`slime_${i + 1}`] : []);
    state = act(state, strike(state, targets), T0 + (state.mine!.combat!.sequence + 1) * 1000);
  }
  return state;
}

describe('Mine realtime combat settlement', () => {
  it('supplies exactly one weapon independently of a full bag and keeps tool ownership', () => {
    let state = startJourney(freshFarm(), content);
    state = projectFarmState(state, T0, SH, content, plot);
    state.bag!.capacity = state.bag!.slots.length;
    const tool = structuredClone(state.bag!.equipped.main_hand);
    state = act(state, { type: 'enter_mine', run: 0 });
    const sword = structuredClone(allBagStacks(state.bag!).find(v => v.item_id === "rusty_sword"));
    expect(sword?.item_id).toBe('rusty_sword');
    expect(state.bag!.overflow).toContainEqual(sword);
    state = act(state, { type: 'leave_mine', run: 0, floor: 1 });
    state = act(JSON.parse(JSON.stringify(state)), { type: 'enter_mine', run: 0 });
    expect(allBagStacks(state.bag!)).toContainEqual(sword);
    expect(state.bag!.equipped.main_hand).toEqual(tool);
    expect(allBagStacks(state.bag!).filter(stack => stack.item_id === 'rusty_sword')).toHaveLength(1);
  });

  it('uses 0, 0, 1, 3, 1 enemies and persists partial enemy HP across re-entry', () => {
    let state = entered();
    expect(Object.values(state.mine!.combat!.monsters).map(values => values.length)).toEqual([0, 0, 1, 3, 1]);
    state = act(state, strike(state));
    expect(state.mine!.combat!.monsters['3']).toEqual([24]);
    expect(state.character!.hp).toBe(100);
    state = act(state, { type: 'leave_mine', run: 0, floor: 3 });
    state = act(JSON.parse(JSON.stringify(state)), { type: 'enter_mine', run: 0 });
    expect(state.mine!.combat!.monsters['3']).toEqual([24]);
  });

  it.each([3, 4])('opens floor %i by rocks while leaving live monsters and their rewards intact', floor => {
    let state = entered(floor);
    for (const rock of content.mining.rocks) state = act(state, { type: 'mine_rock', run: 0, floor, node_id: rock.id });
    expect(state.mine!.cleared_floors).toContain(floor);
    const monsters = structuredClone(state.mine!.combat!.monsters[String(floor)]);
    expect(monsters.every(hp => hp > 0)).toBe(true);
    state = act(state, { type: 'descend_mine', run: 0, floor });
    state = act(state, { type: 'ascend_mine', run: 0, floor: floor + 1 });
    expect(state.mine!.combat!.monsters[String(floor)]).toEqual(monsters);
  });

  it.each([3, 4])('opens floor %i by monsters while preserving unmined rocks', floor => {
    const state = defeatFloor(entered(floor));
    expect(state.mine!.cleared_floors).toContain(floor);
    expect(state.mine!.broken[String(floor)] ?? []).toEqual([]);
    expect(Object.keys(state.mine!.combat!.last_result!.loot!)).not.toHaveLength(0);
    const before = structuredClone(state);
    expect(run(state, strike(state), T0 + 10000).ok).toBe(false);
    expect(state).toEqual(before);
    expect(act(state, { type: 'descend_mine', run: 0, floor }).mine!.floor).toBe(floor + 1);
  });

  it('requires elite defeat for first elevator unlock and respawns only in a new run', () => {
    let state = entered(5);
    for (const rock of content.mining.rocks) expect(run(state, { type: 'mine_rock', run: 0, floor: 5, node_id: rock.id }).ok).toBe(false);
    expect(state.mine!.elevator_unlocked).toBe(false);
    expect(state.mine!.combat!.monsters['5']).toEqual([300]);
    state = defeatFloor(state);
    expect(state.mine!.elevator_unlocked).toBe(true);
    expect(Object.keys(state.mine!.combat!.last_result!.loot!)).toHaveLength(1);
    state = act(state, { type: 'leave_mine', run: 0, floor: 5 });
    state = act(state, { type: 'restart_mine', run: 0 });
    state = act(state, { type: 'enter_mine', run: 1 });
    expect(state.mine!.combat!.monsters['5']).toEqual([300]);
    expect(state.mine!.elevator_unlocked).toBe(true);
  });

  it('bounds attacks and hurt using real time, not accelerated farming time', () => {
    let state = entered(4);
    state = act(state, strike(state, ['slime_1', 'slime_2'], 'slime_3'));
    expect(state.character!.hp).toBe(90);
    const before = structuredClone(state);
    expect(run(state, strike(state), T0 + 500).ok).toBe(false);
    expect(run(state, strike(state, [], 'slime_3'), T0 + 999).ok).toBe(false);
    expect(state).toEqual(before);
    state = act(state, strike(state, ['slime_1'], 'slime_3'), T0 + 1000);
    expect(state.character!.hp).toBe(80);
    expect(state.mine!.combat!.monsters['4']).toEqual([10, 24, 38]);
  });

  it('rejects stale or forged IDs, duplicate targets and empty commands; empty hands use defaults atomically', () => {
    const state = entered();
    const before = structuredClone(state);
    for (const command of [strike(state, ['__proto__']), strike(state, ['slime_2']), strike(state, ['slime_1', 'slime_1']),
      strike(state, []), { ...strike(state), run: 1 }, { ...strike(state), floor: 0 }, { ...strike(state), sequence: -1 }]) {
      expect(run(state, command).ok).toBe(false);
    }
    expect(state).toEqual(before);
    state.bag!.equipped.main_hand = null;
    expect(act(state, strike(state)).mine!.combat!.monsters["3"]).toEqual([37]);
  });

  it('settles combat drops into overflow when the bag is full without preventing defeat', () => {
    const state = entered(5);
    state.mine!.combat!.monsters['5'] = [1];
    editInventory(state, draft => {
      draft.inventory.seeds.R.bound = 99;
      draft.inventory.seeds.L.bound = 99;
      draft.journey!.materials ??= { stone: 0, fiber: 0 };
      draft.journey!.materials!.copper_ore = 99;
      draft.journey!.materials!.rock_salt = 99;
    });
    state.bag!.capacity = state.bag!.slots.length;
    const next = act(state, strike(state));
    expect(next.mine!.combat!.monsters['5']).toEqual([0]);
    expect(next.bag!.overflow.map(stack => [stack.item_id, stack.quantity])).toEqual(Object.entries(next.mine!.combat!.last_result!.loot!));
    expect(next.bag!.overflow.length).toBe(1);
    expect(state.bag!.overflow).toEqual([]);
  });

  it('rescues a defeated player with possessions and progress, and requires the farm for resting', () => {
    let state = entered(5);
    state.character!.hp = 10;
    const before = structuredClone(state);
    expect(run(state, { type: 'rest_character' }).ok).toBe(false);
    state = act(state, strike(state, [], 'slime_1'));
    expect(state.character!.hp).toBe(1);
    expect(state.mine!.floor).toBe(0);
    expect(state.mine!.combat!.last_result!.rescued).toBe(true);
    expect(state.bag).toEqual(before.bag);
    expect(state.wallet).toBe(before.wallet);
    expect(state.mine!.broken).toEqual(before.mine!.broken);
    state = act(state, { type: 'rest_character' });
    expect(state.character!.hp).toBe(100);
  });

  it('a lethal sword strike prevents a simultaneous hit from that monster', () => {
    const state = entered();
    state.mine!.combat!.monsters['3'] = [1];
    expect(act(state, strike(state, ['slime_1'], 'slime_1')).character!.hp).toBe(100);
  });

  it('preserves cleared legacy floors and elevator and supplies a weapon to an old in-mine save', () => {
    const state = entered(5);
    delete state.mine!.combat;
    delete state.character;
    state.bag!.equipped.main_hand = null;
    state.mine!.cleared_floors = [1, 3, 5];
    state.mine!.elevator_unlocked = true;
    const next = act(state, { type: 'use_mine_elevator', run: 0, floor: 5 });
    expect(next.mine!.combat!.monsters['3']).toEqual([0]);
    expect(next.mine!.combat!.monsters['4']).toEqual([38, 38, 38]);
    expect(next.mine!.combat!.monsters['5']).toEqual([0]);
    expect(next.bag!.equipped.main_hand!.item_id).toBe('rusty_sword');
    expect(next.mine!.elevator_unlocked).toBe(true);
  });

  it.each([0, 1, 75, 150])('upgrades old elite HP %i once, preserving its remaining fraction and ownership', hp => {
    const state = entered(5);
    state.mine!.combat!.version = 1;
    state.mine!.combat!.monsters['5'] = [hp];
    state.mine!.combat!.monsters['3'] = [0];
    state.mine!.broken['4'] = content.mining.rocks.map(rock => rock.id);
    const before = structuredClone(state);
    const projected = projectFarmState(state, T0, SH, content, plot);
    expect(projected.mine!.combat!.version).toBe(2);
    expect(projected.mine!.combat!.monsters['5']).toEqual([hp * 2]);
    expect(projected.mine!.cleared_floors).toEqual(hp === 0 ? [3, 4, 5] : [3, 4]);
    expect(projected.mine!.elevator_unlocked).toBe(hp === 0);
    expect(projected.bag).toEqual(before.bag);
    expect(projected.wallet).toBe(before.wallet);
    expect(projected.mine!.broken).toEqual(before.mine!.broken);
    expect(projectFarmState(projected, T0, SH, content, plot)).toEqual(projected);
    expect(state).toEqual(before);
  });

  it('rolls one seed or mineral reward per kill, stable across timing, target order and forged fields', () => {
    const original = entered(4);
    original.mine!.combat!.monsters['4'] = [1, 1, 1];
    const resolve = (farmId: string, targets: string[], now = T0, state = original) => {
      const result = apply(state, { ...strike(state, targets), loot: { copper_ore: 999 } } as unknown as Command,
        makeCtx(state, now, SH, content, plot, now, farmId));
      if (!result.ok) throw Error(result.code);
      return result.state;
    };
    const draws = new Set<string>();
    for (let farm = 0; farm < 40; farm++) {
      const id = `loot-farm-${farm}`;
      const direct = resolve(id, ['slime_1']);
      const loot = direct.mine!.combat!.last_result!.loot!;
      expect(Object.keys(loot)).toHaveLength(1);
      expect(content.mining.combat.monsters.slime.loot.some(drop => loot[drop.item_id] === drop.quantity)).toBe(true);
      expect(resolve(id, ['slime_1'], T0 + 10000).mine!.combat!.last_result!.loot).toEqual(loot);
      const other = resolve(id, ['slime_2']);
      expect(resolve(id, ['slime_1'], T0 + 1000, other).mine!.combat!.last_result!.loot).toEqual(loot);
      const both = resolve(id, ['slime_1', 'slime_2']);
      expect(resolve(id, ['slime_2', 'slime_1']).mine!.combat!.last_result!.loot).toEqual(both.mine!.combat!.last_result!.loot);
      const [item, quantity] = Object.entries(loot)[0];
      const count = (state: FarmState) => allBagStacks(state.bag!).filter(stack => stack.item_id === item)
        .reduce((sum, stack) => sum + stack.quantity, 0);
      expect(count(direct) - count(original)).toBe(quantity);
      if (item.startsWith('seed_')) expect(allBagStacks(direct.bag!).some(stack => stack.item_id === item && stack.seed_lot === 'bound')).toBe(true);
      draws.add(item);
    }
    expect([...draws].sort()).toEqual(['copper_ore', 'rock_salt', 'seed_L', 'seed_R']);
  });
});

describe('Combat equipment and recovery meals', () => {
  it('swaps the main hand while retaining the former weapon, derives glove-slot stats, and never heals through equipment swaps', () => {
    let state = entered();
    state.character!.hp = 70;
    const tool = structuredClone(state.bag!.equipped.main_hand);
    for (const id of ['trail_boots', 'copper_sword']) addBagItem(state.bag!, { item_id: id, quantity: 1 }, content);
    for (const id of ['trail_boots', 'copper_sword']) state = act(state, { type: 'equip_bag_item',
      stack_id: state.bag!.slots.find(stack => stack.item_id === id)!.id, sequence: state.bag!.sequence });
    expect(characterStats(state, content)).toMatchObject({ max_hp: 120, defense: 2, move_speed: 4.25 });
    expect(state.character!.hp).toBe(70);
    state = act(state, strike(state, ['slime_1'], 'slime_1'));
    expect(state.character!.hp).toBe(62);
    expect(state.mine!.combat!.monsters['3']).toEqual([14]);
    expect(state.bag!.slots).toContainEqual(tool);
    expect(state.bag!.equipped.main_hand?.item_id).toBe("copper_sword");
    state.character!.hp = 120;
    state = act(state, { type: 'unequip_bag_item', slot: 'gloves', sequence: state.bag!.sequence });
    expect(state.character!.hp).toBe(100);
  });

  it('heals when a meal buff is already active without extending its uses or consuming at full health', () => {
    let state = entered();
    editInventory(state, draft => { draft.inventory.dishes.vegetable_soup = 4; });
    state.character!.hp = 10;
    const eat = (s: FarmState) => act(s, { type: 'use_bag_item', sequence: s.bag!.sequence,
      stack_id: s.bag!.slots.find(stack => stack.item_id === 'vegetable_soup')!.id });
    state = eat(state);
    expect(state.character!.hp).toBe(50);
    state.character!.buffs[0].remaining_uses = 1;
    state = eat(eat(state));
    expect(state.character!.hp).toBe(100);
    expect(state.character!.buffs[0].remaining_uses).toBe(1);
    expect(run(state, { type: 'use_bag_item', sequence: state.bag!.sequence,
      stack_id: state.bag!.slots.find(stack => stack.item_id === 'vegetable_soup')!.id })).toMatchObject({ ok: false, code: 'EFFECT_ACTIVE' });
  });
});
