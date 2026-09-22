import { describe, expect, it } from 'vitest';
import type { Command } from '../../src/domain/commands.js';
import { reconcileJourney, startJourney } from '../../src/domain/journey.js';
import { content, editInventory, freshFarm, run } from './helpers.js';

function ready() {
  const state = startJourney(freshFarm(), content);
  state.journey!.facts.push('met_nursery', 'met_bistro', 'workbench', 'planter_crafted',
    'planter_placed', 'shared_meal', 'side_path');
  state.journey!.unlocks.push('bistro', 'crop_C', 'crop_H', 'kitchen', 'tea');
  state.journey!.wood = 8;
  state.journey!.materials = { stone: 4, fiber: 4 };
  return reconcileJourney(state, content);
}

function apply(state: ReturnType<typeof ready>, cmd: Command) {
  const result = run(state, cmd);
  if (!result.ok) throw new Error(`${cmd.type}: ${result.code}`);
  return result.state;
}

describe('Player-selected construction goals', () => {
  it('continues a newly started project through its next stage without a separate tracking action', () => {
    let state = apply(ready(), { type: 'build_journey_project', project: 'terrace', stage: 0 });
    expect(state.journey!.tracked_project).toBe('terrace');
    expect(state.journey!.wood).toBe(5);
    expect(state.journey!.materials!.fiber).toBe(2);
    editInventory(state, draft => { draft.inventory.dishes = { salad: 1, tea: 1 }; });
    state = apply(state, { type: 'build_journey_project', project: 'terrace', stage: 1 });
    expect(state.journey!.tracked_project).toBeUndefined();
  });

  it('does not change an explicit project or discovery goal when starting another construction', () => {
    const project = apply(ready(), { type: 'track_journey_project', project: 'waystation' });
    const built = apply(project, { type: 'build_journey_project', project: 'terrace', stage: 0 });
    expect(built.journey!.tracked_project).toBe('waystation');
    const discovery = apply(ready(), { type: 'track_journey_discovery', discovery: 'stone_hollow' });
    const otherBuilt = apply(discovery, { type: 'build_journey_project', project: 'terrace', stage: 0 });
    expect(otherBuilt.journey!.tracked_discovery).toBe('stone_hollow');
    expect(otherBuilt.journey!.tracked_project).toBeUndefined();
  });

  it('does not start tracking when construction fails or when loading an existing partial project', () => {
    const state = ready();
    state.journey!.wood = 0;
    const before = structuredClone(state);
    expect(run(state, { type: 'build_journey_project', project: 'terrace', stage: 0 }).ok).toBe(false);
    expect(state).toEqual(before);
    state.journey!.facts.push('project_terrace_0');
    expect(reconcileJourney(state, content).journey!.tracked_project).toBeUndefined();
  });

  it('persists a chosen goal without granting progress or spending resources', () => {
    const before = ready();
    const state = apply(before, { type: 'track_journey_project', project: 'terrace' });
    expect(state.journey!.tracked_project).toBe('terrace');
    expect(state.journey!.facts).toEqual(before.journey!.facts);
    expect(state.inventory).toEqual(before.inventory);
    expect(state.wallet).toBe(before.wallet);
    expect(state.journey!.wood).toBe(before.journey!.wood);
    expect(state.journey!.materials).toEqual(before.journey!.materials);
    expect(JSON.parse(JSON.stringify(state)).journey.tracked_project).toBe('terrace');
  });

  it('keeps one selected goal across project/discovery switching and cancellation', () => {
    let state = apply(ready(), { type: 'track_journey_discovery', discovery: 'stone_hollow' });
    state = apply(state, { type: 'track_journey_project', project: 'terrace' });
    expect(state.journey!.tracked_discovery).toBeUndefined();
    state = apply(state, { type: 'track_journey_project', project: 'waystation' });
    expect(state.journey!.tracked_project).toBe('waystation');
    state = apply(state, { type: 'track_journey_project', project: '' });
    expect(state.journey!.tracked_project).toBeUndefined();
    state = apply(state, { type: 'track_journey_project', project: 'terrace' });
    state = apply(state, { type: 'track_journey_discovery', discovery: 'stone_hollow' });
    expect(state.journey!.tracked_project).toBeUndefined();
    expect(state.journey!.tracked_discovery).toBe('stone_hollow');
  });

  it('retains the project through stages and failed construction, and clears only at completion', () => {
    let state = apply(ready(), { type: 'track_journey_project', project: 'terrace' });
    state = apply(state, { type: 'build_journey_project', project: 'terrace', stage: 0 });
    expect(state.journey!.tracked_project).toBe('terrace');
    expect(state.journey!.wood).toBe(5);
    expect(state.journey!.materials!.fiber).toBe(2);
    const before = structuredClone(state);
    expect(run(state, { type: 'build_journey_project', project: 'terrace', stage: 1 }).ok).toBe(false);
    expect(state).toEqual(before);
    editInventory(state, draft => { draft.inventory.dishes = { salad: 1, tea: 1 }; });
    state = apply(state, { type: 'build_journey_project', project: 'terrace', stage: 1 });
    expect(state.inventory.dishes).toEqual({ salad: 0, tea: 0 });
    expect(state.journey!.tracked_project).toBeUndefined();
    expect(run(state, { type: 'track_journey_project', project: 'terrace' }).ok).toBe(false);
  });

  it('does not clear a different project when another construction completes', () => {
    let state = apply(ready(), { type: 'track_journey_project', project: 'terrace' });
    state.journey!.facts.push('project_seedbeds_0');
    editInventory(state, draft => { draft.inventory.produce.L = 1; });
    state = apply(state, { type: 'build_journey_project', project: 'seedbeds', stage: 1 });
    expect(state.journey!.tracked_project).toBe('terrace');
  });

  it('rejects unknown, unavailable and malformed goals without losing the previous selection', () => {
    const state = apply(ready(), { type: 'track_journey_project', project: 'terrace' });
    const before = structuredClone(state);
    for (const project of ['__proto__', 'missing', {}, null])
      expect(run(state, { type: 'track_journey_project', project } as Command).ok).toBe(false);
    expect(state).toEqual(before);
    const fresh = startJourney(freshFarm(), content);
    expect(run(fresh, { type: 'track_journey_project', project: 'terrace' }).ok).toBe(false);
  });
});
