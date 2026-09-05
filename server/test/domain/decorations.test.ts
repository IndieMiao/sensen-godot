import { describe, expect, it } from 'vitest';
import type { Command } from '../../src/domain/commands.js';
import { DECORATION_IDS } from '../../src/domain/content.js';
import type { DecorationPlacement } from '../../src/domain/state.js';
import { content, freshFarm, run } from './helpers.js';

const placement = (prop_id: DecorationPlacement['prop_id'], offset_q: [number, number]): DecorationPlacement =>
  ({ anchor_id: 'courtyard', prop_id, offset_q });
const defaults = () => DECORATION_IDS.map(id => placement(id, [...content.decorations.props[id].default_offset_q]));
function unlocked() {
  const state = freshFarm();
  state.clock.chapter_index = 5;
  state.growth_choice.purchase = 'tool';
  return state;
}

describe('courtyard decoration placement', () => {
  it('requires a paid growth choice, including for an empty save', () => {
    const state = freshFarm();
    state.clock.chapter_index = 5;
    state.growth_choice.intent = 'tool';
    for (const props of [[], defaults()]) {
      const result = run(state, { type: 'save_decorations', props });
      expect(!result.ok && result.code).toBe('DECORATION_LOCKED');
    }
  });

  it.each(['tool', 'field'] as const)('allows all six free props after %s purchase without changing farm assets', choice => {
    const state = unlocked();
    state.growth_choice.purchase = choice;
    const before = structuredClone(state);
    const props = defaults();
    const result = run(state, { type: 'save_decorations', props });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.state.decorations).toEqual(props);
    expect(result.state.wallet).toBe(before.wallet);
    expect(result.state.inventory).toEqual(before.inventory);
    expect(result.state.cells).toEqual(before.cells);
    expect(result.state.xp).toEqual(before.xp);
    expect(state).toEqual(before);
    props[0].offset_q[0] = 100;
    expect(result.state.decorations![0].offset_q[0]).toBe(-4);
  });

  it('atomically replaces the list and allows removing every decoration', () => {
    const state = unlocked();
    state.decorations = defaults();
    const replacement = [placement('bench', [4, 3])];
    const result = run(state, { type: 'save_decorations', props: replacement });
    expect(result.ok && result.state.decorations).toEqual(replacement);
    if (!result.ok) return;
    const cleared = run(result.state, { type: 'save_decorations', props: [] });
    expect(cleared.ok && cleared.state.decorations).toEqual([]);
  });

  it('accepts an older domain-2 farm with no decorations field', () => {
    const state = unlocked();
    delete state.decorations;
    const result = run(state, { type: 'save_decorations', props: [placement('planter', [-6, 5])] });
    expect(result.ok && result.state.decorations).toEqual([placement('planter', [-6, 5])]);
    expect(state).not.toHaveProperty('decorations');
  });

  it.each([
    null, {}, [null], [placement('bench', [-4, 3]), placement('bench', [4, 3])],
    [{ anchor_id: 'farm', prop_id: 'bench', offset_q: [-4, 3] }],
    [{ anchor_id: 'courtyard', prop_id: 'toString', offset_q: [-4, 3] }],
    [{ anchor_id: 'courtyard', prop_id: 'bench', offset_q: ['-4', 3] }],
    [{ anchor_id: 'courtyard', prop_id: 'bench', offset_q: [-4, 3, 0] }],
    [{ anchor_id: 'courtyard', prop_id: 'bench', offset_q: [-4, 3], owner_id: 'private' }],
    [placement('bench', [-4.5, 3])], [placement('bench', [0, 4])],
    [placement('bench', [-7, 4])], [placement('bench', [-4, 6])],
    [placement('bench', [-6, 3])], [placement('bench', [5, 3])],
    [placement('bench', [-4, 3]), placement('planter', [0, 4])],
    Array(7).fill(placement('bench', [-4, 3])),
  ])('rejects malformed or blocked layout %# without overwriting the previous layout', props => {
    const state = unlocked();
    state.decorations = [placement('lantern', [3, 5])];
    const before = structuredClone(state);
    const result = run(state, { type: 'save_decorations', props } as unknown as Command);
    expect(!result.ok && result.code).toBe('INVALID_DECORATION');
    expect(state).toEqual(before);
  });

  it('rejects overlapping props but permits exactly one meter of spacing', () => {
    const state = unlocked();
    const close = run(state, { type: 'save_decorations', props: [
      placement('bench', [-4, 3]), placement('planter', [-3, 3]),
    ] });
    expect(!close.ok && close.code).toBe('DECORATION_OVERLAP');
    expect(run(state, { type: 'save_decorations', props: [
      placement('bench', [-4, 3]), placement('planter', [-4, 5]),
    ] }).ok).toBe(true);
  });
});
