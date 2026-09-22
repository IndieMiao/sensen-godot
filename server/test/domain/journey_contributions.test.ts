import { describe, expect, it } from 'vitest';
import { startJourney } from '../../src/domain/journey.js';
import { content, freshFarm, run } from './helpers.js';

describe('Street contributions', () => {
  it.each(Object.keys(content.journey.opportunities))('records the fulfilled %s offer and consumes the exact existing cost', slot => {
    let state = startJourney(freshFarm(), content);
    state.journey!.unlocks.push('bistro', 'tea', 'crop_H', 'kitchen', 'crafting');
    state.journey!.facts.push('shared_meal');
    state.journey!.wood = 30;
    state.journey!.materials = { stone: 30, fiber: 30, copper_ore: 30, rock_salt: 30 };
    state.journey!.workshop = { sequence: 0, stock: { crate: 10 }, displays: {} };
    state.inventory.produce = { R: 10, L: 10, C: 10, H: 10, T: 0 };
    state.inventory.dishes = { salad: 10, tea: 10, vegetable_soup: 10 };
    for (const offer of content.journey.opportunities[slot]) {
      state.journey!.opportunities[slot].accepted = true;
      const sequence = state.journey!.opportunities[slot].sequence;
      const before = structuredClone(state);
      const command = { type: 'fulfill_opportunity' as const, slot, sequence };
      const result = run(state, command);
      expect(result.ok).toBe(true);
      if (!result.ok) throw new Error(result.code);
      state = result.state;
      expect(state.journey!.contributions?.[offer.effect]).toBe(Math.min(content.journey.contribution_steps,
        (before.journey!.contributions?.[offer.effect] ?? 0) + 1));
      expect(state.journey!.wood).toBe(before.journey!.wood - offer.wood);
      expect(state.wallet).toBe(before.wallet + offer.coins);
      for (const [id, qty] of Object.entries(offer.produce))
        expect(state.inventory.produce[id as keyof typeof offer.produce]).toBe(before.inventory.produce[id as keyof typeof offer.produce] - qty!);
      for (const [id, qty] of Object.entries(offer.dishes))
        expect(state.inventory.dishes[id as keyof typeof offer.dishes]).toBe((before.inventory.dishes[id as keyof typeof offer.dishes] ?? 0) - qty!);
      for (const [id, qty] of Object.entries(offer.materials ?? {}))
        expect(state.journey!.materials![id as 'copper_ore']).toBe(before.journey!.materials![id as 'copper_ore']! - qty!);
      for (const [id, qty] of Object.entries(offer.props ?? {}))
        expect(state.journey!.workshop!.stock[id]).toBe(before.journey!.workshop!.stock[id] - qty!);
      expect(run(state, command).ok).toBe(false);
    }
  });

  it('does not turn declines, failed deliveries or old offer sequences into construction', () => {
    const state = startJourney(freshFarm(), content);
    state.journey!.opportunities.restorer.sequence = 30;
    state.journey!.opportunities.restorer.accepted = true;
    const failed = run(state, { type: 'fulfill_opportunity', slot: 'restorer', sequence: 30 });
    expect(failed.ok).toBe(false);
    expect(state.journey!.contributions).toBeUndefined();
    const declined = run(state, { type: 'decline_opportunity', slot: 'restorer', sequence: 30 });
    expect(declined.ok).toBe(true);
    if (!declined.ok) throw new Error(declined.code);
    expect(declined.state.journey!.contributions).toBeUndefined();
    expect(declined.state.wallet).toBe(state.wallet);
  });

  it('caps the physical stages while repeat commissions remain paid and atomic', () => {
    let state = startJourney(freshFarm(), content);
    state.journey!.wood = 60;
    state.journey!.opportunities.restorer.accepted = true;
    state.journey!.contributions = { benches: content.journey.contribution_steps, leaves: 2 };
    const before = structuredClone(state);
    const result = run(state, { type: 'fulfill_opportunity', slot: 'restorer', sequence: 0 });
    expect(result.ok).toBe(true);
    if (!result.ok) throw new Error(result.code);
    state = result.state;
    expect(state.journey!.contributions).toEqual(before.journey!.contributions);
    expect(state.wallet).toBe(before.wallet + content.journey.opportunities.restorer[0].coins);
    expect(before.journey!.wood).toBe(60);
  });
});
