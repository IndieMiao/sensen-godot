import { describe, expect, it } from 'vitest';
import type { Command } from '../../src/domain/commands.js';
import { freshFarm, run } from './helpers.js';

function fundedFarm() {
  const state = freshFarm();
  state.clock.chapter_index = 5;
  state.wallet = 1000;
  state.inventory.produce = { R: 5, L: 5, C: 5, H: 5 };
  state.inventory.dishes = { salad: 2, tea: 1 };
  return state;
}

describe('economy inputs from untrusted JSON', () => {
  it.each(['reserve_engineering', 'withdraw_engineering', 'submit_engineering'])(
    '%s rejects malformed quantities and unknown materials without changing assets', type => {
      for (const items of [null, [], {}, { C: -1 }, { C: 0 }, { C: 0.5 }, { C: '1' },
        { R: 1 }, { unknown: 1 }, { C: 1, H: -1 }, { C: Number.MAX_SAFE_INTEGER + 1 }]) {
        const state = fundedFarm();
        state.engineering.reserved = { C: 1, H: 1 };
        const before = structuredClone(state);
        const result = run(state, { type, items } as unknown as Command);
        expect(result.ok, JSON.stringify({ type, items })).toBe(false);
        expect(state).toEqual(before);
      }
    },
  );

  it('caps reservations and submissions to the remaining quota atomically', () => {
    const state = fundedFarm();
    state.engineering.reserved = { C: 1 };
    state.engineering.submitted = { C: 1 };
    expect(run(state, { type: 'reserve_engineering', items: { H: 1, C: 1 } }).ok).toBe(false);
    expect(state.engineering.reserved).toEqual({ C: 1 });
    state.engineering.reserved.C = 2;
    expect(run(state, { type: 'submit_engineering', items: { C: 2 } }).ok).toBe(false);
    const withdrawn = run(state, { type: 'withdraw_engineering', items: { C: 2 } });
    expect(withdrawn.ok && withdrawn.state.engineering.reserved.C).toBe(0);
    expect(withdrawn.ok && withdrawn.state.inventory.produce.C).toBe(5);
  });

  it.each([
    { type: 'set_growth_intent', choice: 'other' },
    { type: 'purchase_growth_choice', choice: 'other', transaction_id: 'tx' },
    { type: 'purchase_growth_choice', choice: 'field' },
    { type: 'purchase_growth_choice', choice: 'field', transaction_id: '' },
    { type: 'purchase_growth_choice', choice: 'field', transaction_id: ' '.repeat(2) },
    { type: 'purchase_growth_choice', choice: 'field', transaction_id: 'x'.repeat(129) },
    { type: 'choose_nursery_appearance', appearance: 'other' },
    { type: 'resolve_life_choice', chapter: 5, choice: 'other' },
    { type: 'resolve_life_choice', chapter: '5', choice: 'keep' },
    { type: 'talk_to_resident', resident_id: 'toString' },
    { type: 'give_gift', resident_id: '__proto__', crop: 'R' },
    { type: 'submit_request', request_id: 'constructor' },
    { type: 'claim_subsidy', subsidy_id: 'toString' },
    { type: 'cook_dish', recipe: 'toString' },
    { type: 'buy_seeds', crop: 'toString', qty: 1 },
    { type: 'buy_seeds', crop: 'unknown', qty: 1 },
    { type: 'sow_cells', cell_ids: ['1,1'], crop: 'toString', lot: 'bought' },
    { type: 'sow_cells', cell_ids: ['1,1'], crop: 'R', lot: 'unknown' },
    { type: 'sell_at_stall', items: [null] },
    { type: 'sell_at_stall', items: [{ kind: 'unknown', id: 'salad', qty: 1 }] },
    { type: 'sell_at_stall', items: [{ kind: 'produce', id: '__proto__', qty: 1 }] },
  ])('rejects $type invalid enum or identifier', malformed => {
    const state = fundedFarm();
    const before = structuredClone(state);
    expect(run(state, malformed as unknown as Command).ok).toBe(false);
    expect(state).toEqual(before);
  });

  it('records the final paid route even when an earlier intent was different', () => {
    const state = fundedFarm();
    state.growth_choice.intent = 'tool';
    const result = run(state, { type: 'purchase_growth_choice', choice: 'field', transaction_id: 'tx' });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.state.growth_choice.intent).toBe('field');
    expect(result.state.growth_choice.purchase).toBe('field');
    expect(result.state.wallet).toBe(516);
    expect(result.state.beds_unlocked).toBe(4);
    expect(result.state.inventory.seeds.H.bought).toBe(3);
  });
});
