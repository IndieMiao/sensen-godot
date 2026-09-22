import { describe, expect, it } from 'vitest';
import { resourceNodes, startJourney } from '../../src/domain/journey.js';
import { stageOf } from '../../src/domain/handlers/residents.js';
import type { Command } from '../../src/domain/commands.js';
import { content, editInventory, freshFarm, run, T0 } from './helpers.js';
import { ensureBag } from '../../src/domain/bag.js';

function player() {
  let state = startJourney(freshFarm(), content);
  const act = (cmd: Command) => {
    const result = run(state, cmd);
    if (!result.ok) throw new Error(`${cmd.type}: ${result.code} ${result.detail ?? ''}`);
    state = result.state;
  };
  const collect = (place: string) => {
    for (const node of resourceNodes(state, content).filter(n => n.place === place))
      if (!state.journey!.exploration.collected.includes(node.id))
        act({ type: 'collect_resource', node_id: node.id, round: state.journey!.exploration.round });
  };
  return { get state() { return state; }, act, collect };
}

describe('Journey continuation', () => {
  it('refreshes a finished destination while keeping untouched resources and their rewards', () => {
    const p = player();
    p.state.journey!.unlocks.push('bistro');
    p.state.journey!.exploration.route = 'woodland';
    p.collect('courtyard');
    const nursery = resourceNodes(p.state, content).filter(n => n.place === 'nursery');
    p.act({ type: 'next_exploration', round: 0, route: 'riverside' });
    expect(resourceNodes(p.state, content).filter(n => n.place === 'nursery')).toEqual(nursery);
    expect(p.state.journey!.exploration.collected).toEqual([]);
    p.collect('courtyard');
    expect(p.state.journey!.materials!.stone).toBe(8);
    p.act({ type: 'next_exploration', round: 1, route: 'riverside' });
    expect(p.state.journey!.exploration.round).toBe(2);
    expect(resourceNodes(p.state, content).filter(n => n.place === 'nursery')).toEqual(nursery);
    expect(run(p.state, { type: 'next_exploration', round: 2, route: 'woodland' }).ok).toBe(false);
    expect(run(p.state, { type: 'collect_resource', node_id: 'courtyard_east', round: 1 }).ok).toBe(false);
  });

  it('keeps collection receipts and the nursery basket across another destination refresh', () => {
    const p = player();
    p.state.journey!.facts.push('project_seedbeds_0', 'project_seedbeds_1', 'workbench');
    p.act({ type: 'use_journey_facility', project: 'seedbeds', choice: 'lettuce', sequence: 0 });
    p.act({ type: 'collect_resource', node_id: 'nursery_west', round: 0 });
    p.collect('courtyard');
    p.act({ type: 'next_exploration', round: 0, route: 'riverside' });
    expect(p.state.journey!.exploration.collected).toEqual(['seedbeds', 'nursery_west']);
    expect(run(p.state, { type: 'collect_resource', node_id: 'nursery_west', round: 1 }).ok).toBe(false);
    expect(run(p.state, { type: 'use_journey_facility', project: 'seedbeds', choice: 'lettuce', sequence: 1 }).ok).toBe(false);
    p.collect('nursery');
    p.act({ type: 'next_exploration', round: 1, route: 'woodland' });
    p.act({ type: 'use_journey_facility', project: 'seedbeds', choice: 'lettuce', sequence: 1 });
  });

  it('makes repeat crafts, unlocks a recipe, conserves displayed stock and rejects stale commands', () => {
    const p = player();
    ensureBag(p.state, content);
    p.state.journey!.facts.push('workbench', 'planter_crafted', 'side_path', 'project_seedbeds_0', 'project_seedbeds_1');
    editInventory(p.state, draft => {
      draft.journey!.wood = 20;
      draft.journey!.materials = { stone: 20, fiber: 20 };
    });
    expect(run(p.state, { type: 'craft_journey_item', item: 'fountain', sequence: 0 }).ok).toBe(false);
    for (const sequence of [0, 1]) p.act({ type: 'craft_journey_item', item: 'planter', sequence });
    p.act({ type: 'craft_journey_item', item: 'lantern', sequence: 2 });
    p.act({ type: 'craft_journey_item', item: 'fountain', sequence: 3 });
    expect(p.state.journey!.workshop!.stock).toEqual({ planter: 2, lantern: 1, fountain: 1 });
    expect(p.state.journey!.materials).toEqual({ stone: 14, fiber: 13 });
    p.act({ type: 'display_journey_item', project: 'seedbeds', slot: 0, item: 'planter', sequence: 4 });
    p.act({ type: 'display_journey_item', project: 'seedbeds', slot: 0, item: 'lantern', sequence: 5 });
    expect(p.state.journey!.workshop!.stock).toEqual({ planter: 2, lantern: 0, fountain: 1 });
    p.act({ type: 'display_journey_item', project: 'seedbeds', slot: 0, item: '', sequence: 6 });
    expect(p.state.journey!.workshop!.stock.lantern).toBe(1);
    const wallet = p.state.wallet;
    p.act({ type: 'deliver_journey_item', item: 'planter', sequence: 7 });
    expect(p.state.wallet).toBe(wallet + content.journey.workshop.recipes.planter.coins);
    const before = structuredClone(p.state);
    for (const command of [
      { type: 'deliver_journey_item', item: 'planter', sequence: 7 },
      { type: 'craft_journey_item', item: '__proto__', sequence: 8 },
      { type: 'display_journey_item', project: '__proto__', slot: 0, item: 'planter', sequence: 8 },
      { type: 'display_journey_item', project: 'seedbeds', slot: 3, item: 'planter', sequence: 8 },
      { type: 'display_journey_item', project: 'terrace', slot: 0, item: 'planter', sequence: 8 },
    ] as Command[]) expect(run(p.state, command).ok).toBe(false);
    expect(p.state).toEqual(before);
  });

  it('cannot craft, deliver or display resources that are not owned', () => {
    const p = player();
    ensureBag(p.state, content);
    p.state.journey!.facts.push('workbench', 'planter_crafted', 'project_seedbeds_0', 'project_seedbeds_1');
    for (const command of [
      { type: 'craft_journey_item', item: 'planter', sequence: 0 },
      { type: 'deliver_journey_item', item: 'planter', sequence: 0 },
      { type: 'display_journey_item', project: 'seedbeds', slot: 0, item: 'planter', sequence: 0 },
    ] as Command[]) expect(run(p.state, command).ok).toBe(false);
    expect(p.state.journey!.workshop).toBeUndefined();
  });

  it.each(['nursery_keeper', 'bistro_owner', 'restorer'] as const)('advances %s through action stories in the same day, once per story', resident => {
    const p = player();
    p.state.journey!.unlocks.push('gifts', 'bistro');
    p.state.journey!.facts.push('workbench', 'planter_crafted', 'shared_meal', 'project_seedbeds_1', 'project_terrace_1', 'crafted_lantern');
    p.state.journey!.wood = 5;
    p.state.journey!.materials = { stone: 3, fiber: 3 };
    p.state.inventory.produce = { R: 3, L: 3, C: 3, H: 3, T: 0 };
    p.state.inventory.dishes.tea = 2;
    if (resident === 'bistro_owner') p.state.residents[resident].points = 25;
    p.act({ type: 'talk_to_resident', resident_id: resident });
    const stories = content.journey.stories[resident];
    expect(run(p.state, { type: 'complete_journey_story', resident_id: resident, story: stories[1].id }).ok).toBe(false);
    for (const story of stories) {
      p.act({ type: 'complete_journey_story', resident_id: resident, story: story.id });
      const before = structuredClone(p.state);
      expect(run(p.state, { type: 'complete_journey_story', resident_id: resident, story: story.id }).ok).toBe(false);
      expect(p.state).toEqual(before);
    }
    p.act({ type: 'give_gift', resident_id: resident, crop: content.relationships.gift_clues[resident][0] });
    expect(stageOf(p.state.residents[resident], { content })).toBe('familiar');
    expect(p.state.clock.player_day_id).toBe(freshFarm().clock.player_day_id);
  });

  it('allows old saves past the gift cap, then limits gifts per exploration with no daily wait', () => {
    const p = player();
    p.state.journey!.unlocks.push('gifts');
    p.state.inventory.produce.R = 3;
    p.state.residents.nursery_keeper.gifts_given = 2;
    p.act({ type: 'give_gift', resident_id: 'nursery_keeper', crop: 'R' });
    expect(run(p.state, { type: 'give_gift', resident_id: 'nursery_keeper', crop: 'R' }).ok).toBe(false);
    p.collect('courtyard');
    p.act({ type: 'next_exploration', route: 'riverside', round: 0 });
    p.act({ type: 'give_gift', resident_id: 'nursery_keeper', crop: 'R' });
    expect(p.state.residents.nursery_keeper.gifts_given).toBe(4);
    const legacy = freshFarm();
    legacy.clock.chapter_index = 4;
    legacy.residents.nursery_keeper.gifts_given = 2;
    legacy.inventory.produce.R = 1;
    expect(run(legacy, { type: 'give_gift', resident_id: 'nursery_keeper', crop: 'R' }, T0).ok).toBe(false);
  });
});
