import { describe, expect, it } from 'vitest';
import { resourceNodes, startJourney } from '../../src/domain/journey.js';
import type { FarmState } from '../../src/domain/state.js';
import type { Command } from '../../src/domain/commands.js';
import { content, freshFarm, run } from './helpers.js';

const act = (state: FarmState, command: Command) => {
  const result = run(state, command);
  if (!result.ok) throw new Error(`${command.type}: ${result.code}`);
  return result.state;
};
const collect = (state: FarmState, place: string) => {
  for (const node of resourceNodes(state, content).filter(n => n.place === place))
    if (!state.journey!.exploration.collected.includes(node.id))
      state = act(state, { type: 'collect_resource', node_id: node.id, round: state.journey!.exploration.round });
  return state;
};
const ready = () => {
  const s = startJourney(freshFarm(), content);
  s.journey!.facts.push('workbench', 'side_path');
  s.journey!.unlocks.push('bistro');
  return s;
};

describe('Resource bundle choices', () => {
  it('offers a street stone walk after crafting and preserves it through other place refreshes', () => {
    let s = collect(ready(), 'bistro');
    const nursery = resourceNodes(s, content).filter(n => n.place === 'nursery');
    s = act(s, { type: 'next_exploration', round: 0, route: 'stone_walk' });
    expect(s.journey!.exploration.routes_by_place!.bistro).toBe('stone_walk');
    expect(resourceNodes(s, content).find(n => n.id === 'bistro_west')!.materials)
      .toEqual({ wood: 1, stone: 2, fiber: 1 });
    expect(resourceNodes(s, content).filter(n => n.place === 'nursery')).toEqual(nursery);
    const before = structuredClone(s);
    s = act(s, { type: 'collect_resource', node_id: 'bistro_west', round: 1, choice: 'primary' });
    expect(s.journey!.wood - before.journey!.wood).toBe(1);
    expect(s.journey!.materials!.stone - before.journey!.materials!.stone).toBe(2);
    expect(s.journey!.materials!.fiber - before.journey!.materials!.fiber).toBe(1);
    expect(run(s, { type: 'collect_resource', node_id: 'bistro_west', round: 1, choice: 'alternate' }).ok).toBe(false);
    expect(run(s, { type: 'next_exploration', round: 1, route: 'gardens' }).ok).toBe(false);
    s = collect(s, 'nursery');
    s = act(s, { type: 'next_exploration', round: 1, route: 'woodland' });
    expect(s.journey!.exploration.routes_by_place!.bistro).toBe('stone_walk');
    expect(s.journey!.exploration.collected).toContain('bistro_west');
    s = JSON.parse(JSON.stringify(s));
    const wood = s.journey!.wood;
    s = act(s, { type: 'collect_resource', node_id: 'bistro_east', round: 2, choice: 'alternate' });
    expect(s.journey!.wood).toBe(wood + 3);
    s = act(s, { type: 'next_exploration', round: 2, route: 'gardens' });
    expect(resourceNodes(s, content).find(n => n.id === 'bistro_east')!.materials).toEqual({ wood: 1, fiber: 3 });
  });

  it('does not unlock the stone walk before crafting or reroll unclaimed supplies', () => {
    let s = startJourney(freshFarm(), content);
    s.journey!.unlocks.push('bistro');
    s = collect(s, 'bistro');
    const before = structuredClone(s);
    expect(run(s, { type: 'next_exploration', round: 0, route: 'stone_walk' }).ok).toBe(false);
    expect(s).toEqual(before);
    s = ready();
    s.journey!.unlocks.push('crafting');
    expect(run(s, { type: 'next_exploration', round: 0, route: 'stone_walk' }).ok).toBe(false);
  });

  it('preserves every unclaimed old reward until that place starts a new trail', () => {
    let s = ready();
    const before = structuredClone(s);
    expect(run(s, { type: 'collect_resource', node_id: 'nursery_west', round: 0, choice: 'alternate' }).ok).toBe(false);
    expect(s).toEqual(before);
    s = collect(s, 'courtyard');
    s = act(s, { type: 'next_exploration', round: 0, route: 'riverside' });
    expect(s.journey!.exploration.branching_places).toEqual(['courtyard']);
    expect(resourceNodes(s, content).filter(n => n.place === 'nursery')).toEqual(resourceNodes(before, content).filter(n => n.place === 'nursery'));
    expect(run(s, { type: 'collect_resource', node_id: 'nursery_west', round: 1, choice: 'alternate' }).ok).toBe(false);
    expect(act(s, { type: 'collect_resource', node_id: 'nursery_west', round: 1 }).journey!.wood).toBe(s.journey!.wood + 1);
  });

  it('keeps the introductory trail free of bundle choices', () => {
    let s = collect(startJourney(freshFarm(), content), 'courtyard');
    s = act(s, { type: 'next_exploration', round: 0, route: 'riverside' });
    expect(s.journey!.exploration.branching_places).toBeUndefined();
    expect(run(s, { type: 'collect_resource', node_id: 'courtyard_west', round: 1, choice: 'alternate' }).ok).toBe(false);
  });

  it.each([
    ['nursery', 'woodland', 'nursery_west', { wood: 0, stone: 1, fiber: 0 }],
    ['nursery', 'woodland', 'side_path', { wood: 0, stone: 2, fiber: 0 }],
    ['courtyard', 'riverside', 'courtyard_west', { wood: 3, stone: 0, fiber: 0 }],
    ['bistro', 'gardens', 'bistro_east', { wood: 3, stone: 0, fiber: 0 }],
  ] as const)('takes only the chosen %s bundle at %s/%s', (place, route, node, amounts) => {
    let s = collect(ready(), place);
    s = act(s, { type: 'next_exploration', round: 0, route });
    const before = structuredClone(s);
    s = act(s, { type: 'collect_resource', node_id: node, round: 1, choice: 'alternate' });
    expect(s.journey!.wood - before.journey!.wood).toBe(amounts.wood);
    expect(s.journey!.materials!.stone - before.journey!.materials!.stone).toBe(amounts.stone);
    expect(s.journey!.materials!.fiber - before.journey!.materials!.fiber).toBe(amounts.fiber);
    expect(s.journey!.exploration.choices![node]).toBe('alternate');
    expect(s.inventory).toEqual(before.inventory);
    expect(s.wallet).toBe(before.wallet);
    for (const choice of ['primary', 'alternate'] as const)
      expect(run(s, { type: 'collect_resource', node_id: node, round: 1, choice }).ok).toBe(false);
    expect(before.journey!.exploration.collected).not.toContain(node);
  });

  it('keeps another place and its chosen bundle when a trail refreshes', () => {
    let s = collect(collect(ready(), 'courtyard'), 'bistro');
    s = act(s, { type: 'next_exploration', round: 0, route: 'riverside' });
    s = act(s, { type: 'collect_resource', node_id: 'courtyard_west', round: 1, choice: 'alternate' });
    s = act(s, { type: 'next_exploration', round: 1, route: 'gardens' });
    expect(s.journey!.exploration.choices!.courtyard_west).toBe('alternate');
    expect(s.journey!.exploration.collected).toContain('courtyard_west');
    expect(run(s, { type: 'collect_resource', node_id: 'courtyard_west', round: 2, choice: 'primary' }).ok).toBe(false);
    s = collect(s, 'courtyard');
    s = act(s, { type: 'next_exploration', round: 2, route: 'riverside' });
    expect(s.journey!.exploration.choices!.courtyard_west).toBeUndefined();
    const before = structuredClone(s);
    s = act(s, { type: 'collect_resource', node_id: 'courtyard_west', round: 3 });
    expect(s.journey!.wood - before.journey!.wood).toBe(1);
    expect(s.journey!.materials!.stone - before.journey!.materials!.stone).toBe(3);
    expect(s.journey!.exploration.choices!.courtyard_west).toBe('primary');
  });

  it('rejects locked alternatives, invalid choices and stale trail requests without writes', () => {
    let s = ready();
    s.journey!.facts = ['workbench'];
    s = collect(s, 'nursery');
    s = act(s, { type: 'next_exploration', round: 0, route: 'woodland' });
    const before = structuredClone(s);
    for (const command of [
      { type: 'collect_resource', node_id: 'nursery_west', round: 1, choice: 'alternate' },
      { type: 'collect_resource', node_id: 'nursery_west', round: 1, choice: '__proto__' },
      { type: 'collect_resource', node_id: 'nursery_west', round: 0, choice: 'primary' },
      { type: 'next_exploration', round: 1, route: 'woodland' },
    ] as Command[]) expect(run(s, command).ok).toBe(false);
    expect(s).toEqual(before);
  });
});
