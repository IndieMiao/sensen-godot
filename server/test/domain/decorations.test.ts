import { describe, expect, it } from 'vitest';
import type { Command } from '../../src/domain/commands.js';
import { DECORATION_IDS } from '../../src/domain/content.js';
import type { DecorationPlacement } from '../../src/domain/state.js';
import { content, freshFarm, run } from './helpers.js';

const placement = (prop_id: DecorationPlacement['prop_id'], cell: [number, number]): DecorationPlacement =>
  ({ prop_id, cell });
const defaults = () => DECORATION_IDS.map(id => placement(id, [...content.decorations.props[id].default_cell]));
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
    props[0].cell[0] = 100;
    expect(result.state.decorations![0].cell[0]).toBe(content.decorations.props.bench.default_cell[0]);
  });

  it('atomically replaces the list and allows removing every decoration', () => {
    const state = unlocked();
    state.decorations = defaults();
    const replacement = [placement('bench', [28, 3])];
    const result = run(state, { type: 'save_decorations', props: replacement });
    expect(result.ok && result.state.decorations).toEqual(replacement);
    if (!result.ok) return;
    const cleared = run(result.state, { type: 'save_decorations', props: [] });
    expect(cleared.ok && cleared.state.decorations).toEqual([]);
  });

  it('accepts an older domain-2 farm with no decorations field', () => {
    const state = unlocked();
    delete state.decorations;
    const result = run(state, { type: 'save_decorations', props: [placement('planter', [27, 3])] });
    expect(result.ok && result.state.decorations).toEqual([placement('planter', [27, 3])]);
    expect(state).not.toHaveProperty('decorations');
  });

  it.each([
    null, {}, [null], [placement('bench', [24, 3]), placement('bench', [28, 3])],
    [{ prop_id: 'bench', cell: [24, 3], anchor_id: 'farm' }],
    [{ prop_id: 'toString', cell: [24, 3] }],
    [{ prop_id: 'bench', cell: ['24', 3] }],
    [{ prop_id: 'bench', cell: [24, 3, 0] }],
    [{ prop_id: 'bench', cell: [24, 3], owner_id: 'private' }],
        [placement('bench', [24.5, 3])],              // 非整数格
    [placement('bench', [28, 38])],               // 房子占的格
    [placement('bench', [25, 36])],               // 矿口
    [placement('bench', [2, 30])],                // 西侧崖壁
    [placement('bench', [-1, 3])],                // 越界
    [placement('bench', [63, 63])],               // 北面崖壁
    [placement('bench', [24, 3]), placement('planter', [24, 3])],
    Array(7).fill(placement('bench', [24, 3])),
  ])('rejects malformed or blocked layout %# without overwriting the previous layout', props => {
    const state = unlocked();
    state.decorations = [placement('lantern', [3, 5])];
    const before = structuredClone(state);
    const result = run(state, { type: 'save_decorations', props } as unknown as Command);
    expect(!result.ok && result.code).toBe('INVALID_DECORATION');
    expect(state).toEqual(before);
  });

  it('rejects props whose footprints overlap but allows them side by side', () => {
    const state = unlocked();
    const close = run(state, { type: 'save_decorations', props: [
      placement('bench', [24, 3]), placement('planter', [25, 3]),
    ] });
    // bench 占 2×1（[24,3] 与 [25,3]），planter 再放 [25,3] 就压上去了。
    expect(!close.ok && close.code).toBe('INVALID_DECORATION');
    expect(run(state, { type: 'save_decorations', props: [
      placement('bench', [24, 3]), placement('planter', [24, 5]),
    ] }).ok).toBe(true);
  });
});
