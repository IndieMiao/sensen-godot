import { describe, expect, it } from 'vitest';
import { projectFarmState } from '../../src/domain/progress.js';
import type { FarmState } from '../../src/domain/state.js';
import { blueprint, content, freshFarm, HOUR, run, SH, T0 } from './helpers.js';

function awaitingChoice(): FarmState {
  const state = freshFarm();
  state.clock.chapter_index = 6;
  state.chapters[6] = { status: 'done', activated_day: state.clock.player_day_id,
    step_flags: { engineering_quota_complete: true, shared_scene_done: true }, grants_issued: true };
  state.life_choices = { 1: 'gift', 2: 'keep', 3: 'gift', 4: 'sold', 5: 'sold' };
  state.wallet = 123;
  state.xp.total = 211;
  state.inventory.produce.L = 2;
  state.nursery = { stage: 'built', appearance: 'b' };
  state.engineering.submitted = { C: 2, H: 4 };
  state.growth_choice.purchase = 'field';
  state.residents.nursery_keeper = { points: 52, first_met_day: state.clock.player_day_id,
    talked_day: state.clock.player_day_id, gifts_given: 1, request_done: true, shared_event_done: true };
  return state;
}

describe('first-week summary', () => {
  it('does not freeze three life choices as a sale ending before the last choice', () => {
    const state = awaitingChoice();
    const projected = projectFarmState(state, T0, SH, content, blueprint);
    expect(projected.week_summary).toBeUndefined();
    expect(projected.handbook.some(entry => entry.kind === 'week_summary')).toBe(false);
    const result = run(state, { type: 'resolve_life_choice', chapter: 6, choice: 'keep' }, T0 + 1);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.state.week_summary).toMatchObject({ life_priority: true, life_choice_count: 4,
      choices: { 6: 'keep' }, photo_variant: 'personalized',
      journal_pages: ['shared_harvest', 'familiar_faces'], next_week_clue: 'resident_seed_exchange',
      completed_at: T0 + 1, wallet: 123, xp: 211, growth_choice: 'field',
      nursery: { stage: 'built', appearance: 'b' },
      relationships: { nursery_keeper: { points: 52, stage: 'familiar' } } });
    expect(result.state.inventory.produce.L).toBe(1);
  });

  it('creates a valid standard ending for only three gift/keep choices with the actual sale income', () => {
    const state = awaitingChoice();
    const sold = run(state, { type: 'sell_at_stall', items: [{ kind: 'produce', id: 'L', qty: 1 }] });
    expect(sold.ok).toBe(true);
    if (!sold.ok) return;
    expect(sold.state.week_summary).toBeUndefined();
    const result = run(sold.state, { type: 'resolve_life_choice', chapter: 6, choice: 'sold' });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.state.week_summary).toMatchObject({ life_priority: false, life_choice_count: 3,
      choices: { 6: 'sold' }, photo_variant: 'standard', journal_pages: [],
      next_week_clue: 'nursery_next_stage', wallet: state.wallet + content.crops.crops.L.unit_price });
  });

  it('waits for the shared scene even when the last harvest choice is already saved', () => {
    const state = awaitingChoice();
    state.chapters[6].status = 'active';
    state.chapters[6].step_flags = { engineering_quota_complete: true };
    state.residents.nursery_keeper.shared_event_done = false;
    state.life_choices[6] = 'keep';
    expect(projectFarmState(state, T0, SH, content, blueprint).week_summary).toBeUndefined();
    const result = run(state, { type: 'attend_shared_event', event_id: 'nursery_activity' });
    expect(result.ok && result.state.week_summary?.life_priority).toBe(true);
  });

  it('does not write a summary after a rejected final choice', () => {
    const state = awaitingChoice();
    const before = structuredClone(state);
    const result = run(state, { type: 'resolve_life_choice', chapter: 6, choice: 'gift' });
    expect(!result.ok && result.code).toBe('REQUEST_MISMATCH');
    expect(state).toEqual(before);
  });

  it('freezes the summary and creates only one handbook entry across later commands and days', () => {
    const result = run(awaitingChoice(), { type: 'resolve_life_choice', chapter: 6, choice: 'keep' });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const summary = structuredClone(result.state.week_summary);
    const bought = run(result.state, { type: 'buy_seeds', crop: 'R', qty: 1 });
    expect(bought.ok).toBe(true);
    if (!bought.ok) return;
    expect(bought.state.wallet).toBe(119);
    expect(bought.state.week_summary).toEqual(summary);
    const projected = projectFarmState(bought.state, T0 + 48 * HOUR, SH, content, blueprint);
    expect(projected.week_summary).toEqual(summary);
    expect(projected.handbook.filter(entry => entry.kind === 'week_summary')).toEqual([
      { kind: 'week_summary', key: 'first_week', day: summary!.completed_day, life_priority: true },
    ]);
    expect(projected.clock.weather_day_index).toBeGreaterThan(bought.state.clock.weather_day_index);
  });

  it('projects old completed saves deterministically without changing their stored state', () => {
    const state = awaitingChoice();
    state.life_choices[6] = 'keep';
    const before = structuredClone(state);
    const first = projectFarmState(state, T0 + HOUR, SH, content, blueprint);
    const later = projectFarmState(state, T0 + 2 * HOUR, SH, content, blueprint);
    expect(first.week_summary).toEqual(later.week_summary);
    expect(first.week_summary?.completed_at).toBe(state.clock.last_effective_now);
    expect(state).toEqual(before);
    const accepted = run(state, { type: 'buy_seeds', crop: 'R', qty: 1 }, T0 + 2 * HOUR);
    expect(accepted.ok && accepted.state.week_summary).toEqual(first.week_summary);
  });
});
