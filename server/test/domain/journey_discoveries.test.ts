import { describe, expect, it } from 'vitest';
import type { Command } from '../../src/domain/commands.js';
import { resourceNodes, startJourney } from '../../src/domain/journey.js';
import { content, freshFarm, run } from './helpers.js';

function player() {
  let state = startJourney(freshFarm(), content);
  state.journey!.facts.push('first_harvest', 'met_nursery', 'met_bistro', 'workbench',
    'planter_crafted', 'planter_placed', 'shared_meal', 'side_path', 'crafted_lantern');
  state.journey!.unlocks.push('bistro', 'crop_C', 'crop_H', 'kitchen', 'tea');
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

describe('Handmade discoveries', () => {
  it('uses gathered materials to restore a corner and changes the material source for the next craft', () => {
    const p = player();
    p.act({ type: 'track_journey_discovery', discovery: 'stone_hollow' });
    p.collect('nursery');
    p.collect('courtyard');
    p.collect('bistro');
    p.act({ type: 'craft_journey_item', item: 'lantern', sequence: 0 });
    const before = structuredClone(p.state);
    p.act({ type: 'install_journey_discovery', discovery: 'stone_hollow', sequence: 1 });
    expect(p.state.journey!.workshop!.stock.lantern).toBe(0);
    expect(p.state.journey!.tracked_discovery).toBeUndefined();
    expect(p.state.wallet).toBe(before.wallet);
    p.act({ type: 'harvest_journey_discovery', discovery: 'stone_hollow', choice: 'stone', round: 0 });
    expect(p.state.journey!.materials!.stone).toBe(3);
    p.act({ type: 'next_exploration', route: 'woodland', round: 0 });
    p.act({ type: 'harvest_journey_discovery', discovery: 'stone_hollow', choice: 'timber', round: 1 });
    expect(p.state.journey!.discovery_choices!.stone_hollow).toBe('timber');
    expect(p.state.journey!.materials!.stone).toBe(3);
    expect(p.state.journey!.wood).toBe(before.journey!.wood + 3);
    expect(p.state.clock.player_day_id).toBe(before.clock.player_day_id);
  });

  it('freezes the selected reward across unrelated routes, JSON reloads and new request keys', () => {
    const p = player();
    p.state.journey!.workshop = { sequence: 0, stock: { planter: 1 }, displays: {} };
    p.act({ type: 'install_journey_discovery', discovery: 'reed_garden', sequence: 0 });
    const seeds = p.state.inventory.seeds.L.bound;
    p.act({ type: 'harvest_journey_discovery', discovery: 'reed_garden', choice: 'seeds', round: 0 });
    expect(p.state.inventory.seeds.L.bound).toBe(seeds + 2);
    p.collect('nursery');
    p.act({ type: 'next_exploration', route: 'woodland', round: 0 });
    const reloaded = JSON.parse(JSON.stringify(p.state));
    for (const choice of ['reeds', 'seeds'])
      expect(run(reloaded, { type: 'harvest_journey_discovery', discovery: 'reed_garden', choice, round: 1 }).ok).toBe(false);
    p.collect('courtyard');
    p.act({ type: 'next_exploration', route: 'riverside', round: 1 });
    p.act({ type: 'harvest_journey_discovery', discovery: 'reed_garden', choice: 'reeds', round: 2 });
    expect(p.state.journey!.materials!.fiber).toBe(3);
    expect(p.state.inventory.seeds.L.bound).toBe(seeds + 2);
  });

  it('turns a fountain into alternate cooking ingredients without granting both harvests', () => {
    const p = player();
    p.state.journey!.workshop = { sequence: 3, stock: { fountain: 1 }, displays: {} };
    p.act({ type: 'install_journey_discovery', discovery: 'kitchen_garden', sequence: 3 });
    p.act({ type: 'harvest_journey_discovery', discovery: 'kitchen_garden', choice: 'salad', round: 0 });
    p.act({ type: 'cook_dish', recipe: 'salad' });
    expect(p.state.inventory.dishes.salad).toBe(1);
    expect(p.state.inventory.produce.H).toBe(0);
    p.collect('bistro');
    p.act({ type: 'next_exploration', route: 'gardens', round: 0 });
    p.act({ type: 'harvest_journey_discovery', discovery: 'kitchen_garden', choice: 'flowers', round: 1 });
    p.act({ type: 'cook_dish', recipe: 'tea' });
    expect(p.state.inventory.dishes.tea).toBe(1);
  });

  it('never consumes a displayed piece or the original courtyard planter', () => {
    const p = player();
    p.state.decorations = [{ prop_id: 'planter', cell: [27, 3] }];
    p.state.journey!.workshop = { sequence: 1, stock: {}, displays: { seedbeds: ['lantern', '', ''] } };
    const before = structuredClone(p.state);
    expect(run(p.state, { type: 'install_journey_discovery', discovery: 'stone_hollow', sequence: 1 }).ok).toBe(false);
    expect(run(p.state, { type: 'install_journey_discovery', discovery: 'reed_garden', sequence: 1 }).ok).toBe(false);
    expect(p.state).toEqual(before);
  });

  it('rejects premature, repeated, stale and malformed actions atomically', () => {
    const p = player();
    p.state.journey!.workshop = { sequence: 5, stock: { lantern: 2 }, displays: {} };
    const before = structuredClone(p.state);
    for (const cmd of [
      { type: 'install_journey_discovery', discovery: 'stone_hollow', sequence: 4 },
      { type: 'harvest_journey_discovery', discovery: 'stone_hollow', choice: 'stone', round: 0 },
      { type: 'track_journey_discovery', discovery: '__proto__' },
      { type: 'install_journey_discovery', discovery: {}, sequence: 5 },
    ] as Command[]) expect(run(p.state, cmd).ok).toBe(false);
    expect(p.state).toEqual(before);
    p.act({ type: 'install_journey_discovery', discovery: 'stone_hollow', sequence: 5 });
    const installed = structuredClone(p.state);
    for (const cmd of [
      { type: 'install_journey_discovery', discovery: 'stone_hollow', sequence: 6 },
      { type: 'harvest_journey_discovery', discovery: 'stone_hollow', choice: 'stone', round: 1 },
      { type: 'harvest_journey_discovery', discovery: 'stone_hollow', choice: '__proto__', round: 0 },
    ] as Command[]) expect(run(p.state, cmd).ok).toBe(false);
    expect(p.state).toEqual(installed);
    const fresh = startJourney(freshFarm(), content);
    expect(run(fresh, { type: 'track_journey_discovery', discovery: 'stone_hollow' }).ok).toBe(false);
    p.act({ type: 'track_journey_discovery', discovery: 'reed_garden' });
    p.act({ type: 'track_journey_discovery', discovery: '' });
    expect(p.state.journey!.tracked_discovery).toBeUndefined();
  });
});
