import { describe, expect, it } from 'vitest';
import { allBagStacks, ensureBag } from '../../src/domain/bag.js';
import type { Command } from '../../src/domain/commands.js';
import { startJourney } from '../../src/domain/journey.js';
import { opportunityAvailable, opportunityNeeds } from '../../src/domain/opportunities.js';
import { projectFarmState } from '../../src/domain/progress.js';
import type { FarmState } from '../../src/domain/state.js';
import { plot, content, editInventory, freshFarm, run, SH, T0 } from './helpers.js';
import { requestsFixture } from '../../tools/prepare_requests_qa.js';

const project = (state: FarmState) => projectFarmState(state, T0, SH, content, plot);
function ready(): FarmState {
  const state = startJourney(freshFarm(), content);
  state.journey!.facts.push('workbench', 'shared_meal');
  state.journey!.unlocks.push('bistro', 'kitchen', 'tea', 'crafting', 'crop_H');
  ensureBag(state, content);
  editInventory(state, draft => {
    draft.journey!.wood = 20;
    draft.journey!.materials = { stone: 10, fiber: 10, copper_ore: 10, rock_salt: 10 };
    draft.journey!.workshop = { sequence: 0, stock: { crate: 5, planter: 5 }, displays: {} };
    draft.inventory.produce = { R: 10, L: 10, C: 10, H: 10, T: 0 };
    draft.inventory.dishes = { salad: 5, tea: 5, vegetable_soup: 5 };
  });
  return project(state);
}
function act(state: FarmState, cmd: Command): FarmState {
  const result = run(state, cmd);
  if (!result.ok) throw new Error(`${cmd.type}: ${result.code} ${result.detail ?? ''}`);
  return result.state;
}
const accept = (state: FarmState, slot: string) => act(state, {
  type: 'accept_opportunity', slot, sequence: state.journey!.opportunities[slot].sequence,
});
const deliver = (state: FarmState, slot: string) => act(state, {
  type: 'fulfill_opportunity', slot, sequence: state.journey!.opportunities[slot].sequence,
});
const quantity = (state: FarmState, id: string) => allBagStacks(state.bag!).filter(stack => stack.item_id === id)
  .reduce((sum, stack) => sum + stack.quantity, 0);

describe('Request acceptance and tracking', () => {
  it('accepts multiple requests while tracking one, without spending resources or advancing offers', () => {
    const original = ready();
    const initial = structuredClone(original);
    let state = accept(original, 'nursery');
    expect(state.journey!.opportunities.nursery).toMatchObject({ accepted: true, sequence: 0, variant: 0 });
    expect(state.journey!.tracked_opportunity).toEqual({ slot: 'nursery', sequence: 0 });
    state = accept(state, 'restorer');
    expect(state.journey!.opportunities.nursery.accepted).toBe(true);
    expect(state.journey!.opportunities.restorer.accepted).toBe(true);
    expect(state.journey!.tracked_opportunity).toEqual({ slot: 'restorer', sequence: 0 });
    expect(state.bag).toEqual(initial.bag);
    expect(state.wallet).toBe(initial.wallet);
    expect(state.residents).toEqual(initial.residents);
    expect(original).toEqual(initial);
    const before = structuredClone(state);
    expect(run(state, { type: 'accept_opportunity', slot: 'restorer', sequence: 0 }))
      .toMatchObject({ ok: false, code: 'ALREADY_CLAIMED' });
    expect(state).toEqual(before);
  });

  it('cancelling or changing a map goal does not abandon accepted requests', () => {
    let state = accept(ready(), 'nursery');
    state = act(state, { type: 'track_journey_opportunity', slot: 'nursery', sequence: 0, tracking: false });
    expect(state.journey!.tracked_opportunity).toBeUndefined();
    expect(state.journey!.opportunities.nursery.accepted).toBe(true);
    state = act(state, { type: 'track_journey_project', project: 'seedbeds' });
    expect(state.journey!.tracked_project).toBe('seedbeds');
    expect(state.journey!.opportunities.nursery.accepted).toBe(true);
    state = act(state, { type: 'track_journey_opportunity', slot: 'nursery', sequence: 0, tracking: true });
    expect(state.journey!.tracked_project).toBeUndefined();
    expect(state.journey!.opportunities.nursery.sequence).toBe(0);
  });

  it('accepting honours the existing exclusive project, discovery, display and gathering focus', () => {
    const state = ready();
    state.journey!.tracked_project = 'seedbeds';
    state.journey!.tracked_discovery = 'stone_hollow';
    state.journey!.workshop!.planned = { project: 'terrace', slot: 0, item: 'crate' };
    state.journey!.gathering = { sequence: 3, planned: 'garden', memories: [] };
    const next = accept(state, 'restorer');
    expect(next.journey!.tracked_project).toBeUndefined();
    expect(next.journey!.tracked_discovery).toBeUndefined();
    expect(next.journey!.workshop!.planned).toBeUndefined();
    expect(next.journey!.workshop!.sequence).toBe(state.journey!.workshop!.sequence + 1);
    expect(next.journey!.gathering!.planned).toBeUndefined();
    expect(next.journey!.gathering!.sequence).toBe(3);
  });

  it('abandoning invalidates the old sequence but keeps the same offer and another request focus', () => {
    let state = accept(accept(ready(), 'restorer'), 'nursery');
    const before = structuredClone(state);
    state = act(state, { type: 'abandon_opportunity', slot: 'restorer', sequence: 0 });
    expect(state.journey!.opportunities.restorer).toMatchObject({ accepted: false, sequence: 1, variant: 0 });
    expect(state.journey!.tracked_opportunity).toEqual(before.journey!.tracked_opportunity);
    expect(state.bag).toEqual(before.bag);
    expect(state.wallet).toBe(before.wallet);
    expect(state.residents).toEqual(before.residents);
    expect(state.journey!.contributions).toEqual(before.journey!.contributions);
    for (const type of ['fulfill_opportunity', 'accept_opportunity', 'decline_opportunity', 'abandon_opportunity'] as const)
      expect(run(state, { type, slot: 'restorer', sequence: 0 })).toMatchObject({ ok: false, code: 'REQUEST_DONE' });
    expect(run(state, { type: 'abandon_opportunity', slot: 'restorer', sequence: 1 }))
      .toMatchObject({ ok: false, code: 'REQUEST_DONE' });
    state = accept(state, 'restorer');
    state = deliver(state, 'restorer');
    expect(state.journey!.opportunities.restorer.last_completed?.sequence).toBe(1);
    expect(state.wallet).toBe(before.wallet + 9);
  });

  it('skipping clears acceptance, rotates to a frozen next offer and never creates completion evidence', () => {
    const state = accept(ready(), 'restorer');
    const next = act(state, { type: 'decline_opportunity', slot: 'restorer', sequence: 0 });
    expect(next.journey!.opportunities.restorer).toEqual({ accepted: false, sequence: 1, variant: 1 });
    expect(next.journey!.tracked_opportunity).toBeUndefined();
    expect(next.wallet).toBe(state.wallet);
    expect(next.bag).toEqual(state.bag);
    expect(next.journey!.contributions).toEqual(state.journey!.contributions);
    expect(project(JSON.parse(JSON.stringify(next)))).toEqual(next);
  });

  it.each([1, 2, 3])('returns offer %s to timber-only recovery without requiring crops, crafting or mine rewards', variant => {
    let state = ready();
    state.wallet = 0;
    state.journey!.opportunities.restorer.variant = variant;
    editInventory(state, draft => {
      draft.journey!.wood = 3;
      draft.journey!.materials!.copper_ore = 0;
      draft.journey!.workshop!.stock.crate = 0;
      draft.inventory.produce.R = 0;
    });
    state = accept(state, 'restorer');
    const before = structuredClone(state);
    state = act(state, { type: 'decline_opportunity', slot: 'restorer', sequence: 0, timber_only: true });
    expect(state.journey!.opportunities.restorer).toMatchObject({ variant: 0, sequence: 1, accepted: false });
    expect(state.journey!.tracked_opportunity).toBeUndefined();
    expect(state.bag).toEqual(before.bag);
    expect(state.wallet).toBe(0);
    expect(state.journey!.opportunities.restorer.last_completed).toBeUndefined();
    state = deliver(accept(state, 'restorer'), 'restorer');
    expect(state.wallet).toBe(9);
    expect(state.journey!.wood).toBe(0);
  });

  it('rejects malformed or irrelevant timber-only changes and retains an already accepted timber offer', () => {
    const state = accept(ready(), 'restorer');
    const before = structuredClone(state);
    expect(run(state, { type: 'decline_opportunity', slot: 'restorer', sequence: 0, timber_only: true }))
      .toMatchObject({ ok: false, code: 'ALREADY_CLAIMED' });
    for (const payload of [{ slot: 'nursery', timber_only: true }, { slot: 'restorer', timber_only: 'true' },
      { slot: 'restorer', timber_only: 1 }, { slot: 'restorer', timber_only: null }])
      expect(run(state, { type: 'decline_opportunity', sequence: 0, ...payload } as Command))
        .toMatchObject({ ok: false, code: 'NOT_AVAILABLE' });
    expect(state).toEqual(before);
    const ordinary = act(state, { type: 'decline_opportunity', slot: 'restorer', sequence: 0, timber_only: false });
    expect(ordinary.journey!.opportunities.restorer.variant).toBe(1);
  });

  it.each(['accept_opportunity', 'abandon_opportunity', 'decline_opportunity', 'fulfill_opportunity', 'track_journey_opportunity'] as const)
  ('uses the same shared-meal gate for %s', type => {
    const state = ready();
    state.journey!.facts = state.journey!.facts.filter(fact => fact !== 'shared_meal');
    state.journey!.opportunities.bistro.accepted = true;
    state.journey!.tracked_opportunity = { slot: 'bistro', sequence: 0 };
    expect(opportunityAvailable(state, 'bistro', content)).toBe(false);
    expect(run(state, { type, slot: 'bistro', sequence: 0, tracking: true } as Command))
      .toMatchObject({ ok: false, code: 'NOT_AVAILABLE' });
  });

  it('does not allow delivery before acceptance, even when every requested item is present', () => {
    const state = ready();
    expect(run(state, { type: 'fulfill_opportunity', slot: 'nursery', sequence: 0 }))
      .toMatchObject({ ok: false, code: 'REQUEST_DONE' });
    const accepted = act(state, { type: 'track_journey_opportunity', slot: 'nursery', sequence: 0, tracking: true });
    expect(accepted.journey!.opportunities.nursery.accepted).toBe(true);
    expect(deliver(accepted, 'nursery').wallet).toBe(state.wallet + 18);
  });

  it.each([{ slot: '__proto__', sequence: 0 }, { slot: 'nursery', sequence: -1 },
    { slot: 'nursery', sequence: 0.5 }, { slot: 'nursery', sequence: '0' }])('rejects malformed acceptance atomically: %j', payload => {
    const state = ready();
    const before = structuredClone(state);
    expect(run(state, { type: 'accept_opportunity', ...payload } as Command).ok).toBe(false);
    expect(state).toEqual(before);
  });
});

describe('Unified request delivery and recovery', () => {
  it('prepares isolated available and shortage scenarios without preaccepting or completing requests', () => {
    const original = ready();
    const before = structuredClone(original);
    const available = project(requestsFixture(original, content, 'materials'));
    expect(original).toEqual(before);
    for (const slot of ['nursery', 'bistro', 'restorer']) {
      expect(available.journey!.opportunities[slot].accepted).toBe(false);
      expect(available.journey!.opportunities[slot].sequence).toBe(1);
      expect(available.journey!.opportunities[slot].last_completed).toBeUndefined();
      expect(deliver(accept(available, slot), slot).wallet).toBeGreaterThan(available.wallet);
    }
    expect(available.journey!.tracked_opportunity).toBeUndefined();
    const shortage = project(requestsFixture(original, content, 'shortage'));
    for (const slot of ['bistro', 'restorer']) {
      const accepted = accept(shortage, slot);
      expect(run(accepted, { type: 'fulfill_opportunity', slot, sequence: accepted.journey!.opportunities[slot].sequence }))
        .toMatchObject({ ok: false, code: 'INSUFFICIENT_ITEMS' });
    }
    for (const id of ['crate', 'vegetable_soup', 'copper_ore', 'rock_salt']) expect(quantity(shortage, id)).toBe(0);
    expect(quantity(shortage, 'seed_R')).toBeGreaterThan(0);
    expect(quantity(shortage, 'R')).toBeGreaterThan(0);
  });
  it('normalizes old and extended needs, including overlapping wood fields', () => {
    expect(opportunityNeeds({ ...content.journey.opportunities.restorer[1], materials: { wood: 2, copper_ore: 3 }, props: { crate: 1 } }))
      .toEqual({ wood: 4, R: 1, copper_ore: 3, crate: 1 });
  });

  it('spends copper across a partial overflow and bag stacks without consuming equipment or meal uses', () => {
    let state = ready();
    state.journey!.opportunities.restorer.variant = 2;
    editInventory(state, draft => { draft.journey!.materials!.copper_ore = 4; });
    const copper = state.bag!.slots.find(stack => stack.item_id === 'copper_ore')!;
    state = act(state, { type: 'split_bag_stack', sequence: state.bag!.sequence, stack_id: copper.id, quantity: 1 });
    const extra = state.bag!.slots.find(stack => stack.item_id === 'copper_ore' && stack.id !== copper.id)!;
    state.bag!.slots = state.bag!.slots.filter(stack => stack !== extra);
    state.bag!.overflow.push(extra);
    state.character!.buffs = [{ id: 'mining_meal', source_item_id: 'vegetable_soup', remaining_uses: 2 }];
    state = accept(state, 'restorer');
    const before = structuredClone(state);
    const next = deliver(state, 'restorer');
    expect(quantity(next, 'copper_ore')).toBe(1);
    expect(next.bag!.overflow.find(stack => stack.id === extra.id)).toBeUndefined();
    expect(next.bag!.slots.find(stack => stack.id === copper.id)?.quantity).toBe(1);
    expect(next.bag!.equipped).toEqual(before.bag!.equipped);
    expect(next.character).toEqual(before.character);
    expect(next.wallet).toBe(before.wallet + 18);
    expect(next.journey!.opportunities.restorer.last_completed).toEqual({ offer_id: 'copper_for_repairs', resident_id: 'restorer',
      sequence: 0, consumed: { copper_ore: 3 }, coins: 18, effect: 'benches', contribution: 1 });
  });

  it('delivers a stocked handmade piece while preserving the displayed copy and emitting the exact receipt', () => {
    let state = ready();
    state.journey!.opportunities.restorer.variant = 3;
    state.journey!.workshop!.displays.waystation = ['crate', '', ''];
    const crate = state.bag!.slots.find(stack => stack.item_id === 'crate')!;
    state.bag!.slots = state.bag!.slots.filter(stack => stack !== crate);
    state.bag!.overflow.push(crate);
    state = accept(state, 'restorer');
    const before = structuredClone(state);
    const result = run(state, { type: 'fulfill_opportunity', slot: 'restorer', sequence: 0 });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.state.journey!.workshop!.stock.crate).toBe(4);
    expect(result.state.journey!.workshop!.sequence).toBe(before.journey!.workshop!.sequence + 1);
    expect(result.state.journey!.workshop!.displays).toEqual(before.journey!.workshop!.displays);
    expect(result.state.bag!.overflow.find(stack => stack.id === crate.id)?.quantity).toBe(4);
    expect(result.events[0]).toEqual({ type: 'opportunity_completed', slot: 'restorer', offer_id: 'crate_for_deliveries',
      resident_id: 'restorer', sequence: 0, consumed: { crate: 1 }, coins: 26, effect: 'baskets', contribution: 1 });
    expect(project(JSON.parse(JSON.stringify(result.state)))).toEqual(result.state);
  });

  it('delivers soup, retains unrelated accepted requests and returns no repeat friendship points', () => {
    let state = ready();
    state.journey!.opportunities.bistro.variant = 2;
    state = accept(accept(state, 'bistro'), 'nursery');
    const before = structuredClone(state);
    const next = deliver(state, 'bistro');
    expect(quantity(next, 'vegetable_soup')).toBe(4);
    expect(next.wallet).toBe(before.wallet + 24);
    expect(next.residents).toEqual(before.residents);
    expect(next.journey!.opportunities.nursery.accepted).toBe(true);
    expect(next.journey!.tracked_opportunity).toEqual(before.journey!.tracked_opportunity);
    expect(next.journey!.opportunities.bistro.last_completed?.consumed).toEqual({ vegetable_soup: 1 });
  });

  it('retains acceptance and all state on missing minerals, missing stock or reserved crops', () => {
    for (const scenario of ['mineral', 'prop', 'reserved']) {
      let state = ready();
      const slot = scenario === 'reserved' ? 'nursery' : 'restorer';
      if (scenario !== 'reserved') state.journey!.opportunities.restorer.variant = scenario === 'mineral' ? 2 : 3;
      editInventory(state, draft => {
        if (scenario === 'mineral') draft.journey!.materials!.copper_ore = 2;
        if (scenario === 'prop') draft.journey!.workshop!.stock.crate = 0;
      });
      if (scenario === 'prop') state.journey!.workshop!.displays.waystation = ['crate', '', ''];
      if (scenario === 'reserved') state.engineering.reserved.L = 9;
      state = accept(state, slot);
      const before = structuredClone(state);
      expect(run(state, { type: 'fulfill_opportunity', slot, sequence: 0 })).toMatchObject({ ok: false, code: 'INSUFFICIENT_ITEMS' });
      expect(state).toEqual(before);
      expect(state.journey!.opportunities[slot].accepted).toBe(true);
      expect(state.journey!.opportunities[slot].last_completed).toBeUndefined();
    }
  });

  it('keeps the last completion through later decline or abandonment and caps physical progress only', () => {
    let state = ready();
    state.journey!.contributions = { benches: content.journey.contribution_steps };
    state = deliver(accept(state, 'restorer'), 'restorer');
    const completion = structuredClone(state.journey!.opportunities.restorer.last_completed);
    expect(completion?.contribution).toBe(content.journey.contribution_steps);
    expect(completion?.coins).toBe(9);
    state = act(state, { type: 'decline_opportunity', slot: 'restorer', sequence: 1 });
    state = accept(state, 'restorer');
    state = act(state, { type: 'abandon_opportunity', slot: 'restorer', sequence: 2 });
    expect(state.journey!.opportunities.restorer.last_completed).toEqual(completion);
    expect(state.journey!.opportunities.restorer.sequence).toBe(3);
    expect(state.wallet).toBe(ready().wallet + 9);
  });

  it('migrates only a valid legacy pin, preserving domain-17 bag, character and mine data without fabricated history', () => {
    const old = ready();
    old.journey!.opportunities.restorer = { variant: 1, sequence: 29 };
    old.journey!.tracked_opportunity = { slot: 'restorer', sequence: 29 };
    old.character!.buffs = [{ id: 'crafting_tea', source_item_id: 'tea', remaining_uses: 2 }];
    old.mine = { version: 1, run: 9, floor: 5, deepest_floor: 5, broken: { '5': ['rock_1'] }, cleared_floors: [1, 2, 3, 4], elevator_unlocked: true };
    const before = structuredClone(old);
    const upgraded = project(old);
    expect(old).toEqual(before);
    expect(upgraded.journey!.opportunities.restorer).toEqual({ variant: 1, sequence: 29, accepted: true });
    expect(upgraded.journey!.opportunities.nursery.accepted).toBeUndefined();
    expect(upgraded.journey!.contributions).toEqual(old.journey!.contributions);
    expect(upgraded.bag!.slots.filter(v => v.item_id !== "rusty_sword")).toEqual(old.bag!.slots);
    expect(upgraded.bag!.overflow).toEqual(old.bag!.overflow);
    expect(upgraded.bag!.equipped.main_hand).toEqual(old.bag!.equipped.main_hand);
    expect(upgraded.bag!.equipped.gloves).toEqual(old.bag!.equipped.gloves);
    expect(upgraded.bag!.slots.some(v => v.item_id === 'rusty_sword')).toBe(true);
    expect(upgraded.bag!.sequence).toBe(old.bag!.sequence + 1);
    expect(upgraded.character).toEqual({ ...old.character, starter_weapon_granted: true });
    expect(upgraded.mine).toEqual(old.mine);
    expect(project(upgraded)).toEqual(upgraded);
    const stale = structuredClone(old);
    stale.journey!.tracked_opportunity!.sequence = 28;
    expect(project(stale).journey!.opportunities.restorer.accepted).toBeUndefined();
  });
});
