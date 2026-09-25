import { fishingPondPresence } from './fishing_fixture.js';
import { describe, expect, it } from 'vitest';
import { apply, makeCtx } from '../../src/domain/reducer.js';
import { initialFishingSimulation, stepFishing, type FishingPresence } from '../../src/domain/fishing.js';
import { allBagStacks, ensureBag } from '../../src/domain/bag.js';
import type { Command } from '../../src/domain/commands.js';
import type { FarmState } from '../../src/domain/state.js';
import { content, freshFarm, plot, SH, T0 } from './helpers.js';

const location: FishingPresence = fishingPondPresence(content);
function send(s: FarmState, cmd: Command, now = T0, presence: FishingPresence | null = location, config = content) {
  const ctx = makeCtx(s, now, SH, config, plot, now, 'owner-farm');
  ctx.fishingPresence = presence ? { ...presence, pond: fishingPondPresence(config).pond } : null;
  return apply(s, cmd, ctx);
}
function accepted(s: FarmState, cmd: Command, now = T0, config = content) {
  const r = send(s, cmd, now, location, config);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code}`);
  return r.state;
}
function cast(tier = 1) {
  const config = structuredClone(content);
  config.fishing.sites.farm_pond.fish_weights = [1, 2, 3, 4].map(n => Number(n === tier));
  let state = accepted(freshFarm(), { type: 'cast_fishing', sequence: 0, site_id: 'test_pond' }, T0, config);
  const now = state.fishing!.active!.bite_at;
  state = accepted(state, { type: 'hook_fishing', sequence: 1 }, now, config);
  return { state, config, now };
}
export function play(seed: number, tier: number, skilled = true) {
  const s = initialFishingSimulation(seed, content.fishing);
  let inputs = '';
  while (s.outcome === 'playing') {
    const held = skilled && s.fish > s.bar + s.velocity * .15;
    inputs += held ? '1' : '0';
    stepFishing(s, held, content.fishing.tiers[String(tier)], content.fishing);
  }
  return { inputs, result: s };
}
const fishCount = (s: FarmState) => allBagStacks(s.bag!).filter(stack => stack.item_id.startsWith('fish_')).reduce((sum, stack) => sum + stack.quantity, 0);

describe('authoritative fishing loop', () => {
  it.each([null, { ...location, space: 'mine' }, { ...location, x: 25 }])('rejects casts outside the authenticated fishing spot: %j', p => {
    expect(send(freshFarm(), { type: 'cast_fishing', sequence: 0, site_id: 'test_pond' }, T0, p)).toMatchObject({ ok: false, code: 'FISHING_LOCATION' });
  });
  it('rejects unknown sites and cannot replace an active cast to reroll its fish', () => {
    expect(send(freshFarm(), { type: 'cast_fishing', sequence: 0, site_id: '__proto__' })).toMatchObject({ ok: false });
    const { state } = cast();
    expect(send(state, { type: 'cast_fishing', sequence: 1, site_id: 'test_pond' })).toMatchObject({ ok: false, code: 'FISHING_ACTIVE' });
  });
  it('requires a real bite window and permits only one hook', () => {
    const state = accepted(freshFarm(), { type: 'cast_fishing', sequence: 0, site_id: 'test_pond' });
    const active = state.fishing!.active!;
    for (const now of [active.bite_at - 1, active.hook_until + 1])
      expect(send(state, { type: 'hook_fishing', sequence: 1 }, now)).toMatchObject({ ok: false, code: 'FISHING_TIMING' });
    const hooked = accepted(state, { type: 'hook_fishing', sequence: 1 }, active.bite_at);
    expect(send(hooked, { type: 'hook_fishing', sequence: 1 }, active.bite_at)).toMatchObject({ ok: false, code: 'FISHING_CHANGED' });
  });
  it.each([1, 2, 3, 4])('captures tier %i using a verified trace and sells exactly its catalog value', tier => {
    const { state, config, now } = cast(tier);
    const active = state.fishing!.active!;
    const { inputs, result } = play(active.seed, tier);
    expect(result.outcome).toBe('caught');
    const settled = accepted(state, { type: 'finish_fishing', sequence: 1, inputs }, now + inputs.length * 50, config);
    expect(fishCount(settled)).toBe(1);
    expect(settled.cells).toEqual(state.cells);
    expect(settled.fishing!.active).toBeNull();
    const stack = settled.bag!.slots.find(s => s.item_id === active.fish_id)!;
    const wallet = settled.wallet;
    const sold = accepted(settled, { type: 'sell_fish', sequence: settled.bag!.sequence, stack_id: stack.id, quantity: 1 }, now + inputs.length * 50, config);
    expect(sold.wallet).toBe(wallet + config.fishing.fish[active.fish_id].price);
    expect(fishCount(sold)).toBe(0);
    expect(send(settled, { type: 'finish_fishing', sequence: 1, inputs }, now + inputs.length * 50, location, config)).toMatchObject({ ok: false, code: 'FISHING_CHANGED' });
    expect(send(sold, { type: 'sell_fish', sequence: settled.bag!.sequence, stack_id: stack.id, quantity: 1 }, now + inputs.length * 50, location, config)).toMatchObject({ ok: false, code: 'BAG_CHANGED' });
  });
  it('rejects accelerated, malformed, incomplete and overlong input traces atomically', () => {
    const { state, now } = cast();
    const before = structuredClone(state);
    const trace = play(state.fishing!.active!.seed, 1).inputs;
    for (const inputs of ['', '2', 'true', '1', '0'.repeat(601), null, []])
      expect(send(state, { type: 'finish_fishing', sequence: 1, inputs } as Command, now + 40000)).toMatchObject({ ok: false });
    expect(send(state, { type: 'finish_fishing', sequence: 1, inputs: trace }, now)).toMatchObject({ ok: false, code: 'FISHING_INPUT' });
    expect(state).toEqual(before);
  });
  it('no input loses the fish, and cancellation cannot grant a catch', () => {
    const { state, now } = cast();
    const trace = play(state.fishing!.active!.seed, 1, false);
    expect(trace.result.outcome).toBe('escaped');
    const escaped = accepted(state, { type: 'finish_fishing', sequence: 1, inputs: trace.inputs }, now + trace.inputs.length * 50);
    expect(fishCount(escaped)).toBe(0);
    const cancelled = accepted(state, { type: 'cancel_fishing', sequence: 1 }, now);
    expect(fishCount(cancelled)).toBe(0);
    expect(cancelled.fishing!.active).toBeNull();
  });
  it('rejects settlement after moving, reconnecting or expiry; cancellation still recovers the cast', () => {
    const { state, now } = cast();
    const inputs = play(state.fishing!.active!.seed, 1).inputs;
    for (const p of [{ ...location, x: 30 }, { ...location, nonce: 'connection-2' }, null])
      expect(send(state, { type: 'finish_fishing', sequence: 1, inputs }, now + 30000, p)).toMatchObject({ ok: false, code: 'FISHING_LOCATION' });
    expect(send(state, { type: 'finish_fishing', sequence: 1, inputs }, now + 60000)).toMatchObject({ ok: false, code: 'FISHING_TIMING' });
    expect(send(state, { type: 'cancel_fishing', sequence: 1 }, now + 60000, null)).toMatchObject({ ok: true, state: { fishing: { active: null } } });
  });
  it('preserves a catch in overflow when the bag is full, including sale without moving stacks', () => {
    const { state, now } = cast();
    state.bag!.capacity = state.bag!.slots.length;
    const inputs = play(state.fishing!.active!.seed, 1).inputs;
    const caught = accepted(state, { type: 'finish_fishing', sequence: 1, inputs }, now + inputs.length * 50);
    expect(caught.fishing!.last!.overflow).toBe(true);
    const stack = caught.bag!.overflow.find(s => s.item_id.startsWith('fish_'))!;
    expect(stack.quantity).toBe(1);
    const sold = accepted(caught, { type: 'sell_fish', sequence: caught.bag!.sequence, stack_id: stack.id, quantity: 1 }, now + inputs.length * 50);
    expect(fishCount(sold)).toBe(0);
  });
  it('preserves fish through unrelated inventory reconciliation and rejects selling other items', () => {
    const { state, now } = cast();
    const inputs = play(state.fishing!.active!.seed, 1).inputs;
    const caught = accepted(state, { type: 'finish_fishing', sequence: 1, inputs }, now + inputs.length * 50);
    const bought = accepted(caught, { type: 'buy_seeds', crop: 'R', qty: 1 }, now + inputs.length * 50);
    expect(fishCount(bought)).toBe(1);
    const seed = bought.bag!.slots.find(s => s.item_id === 'seed_R')!;
    expect(send(bought, { type: 'sell_fish', sequence: bought.bag!.sequence, stack_id: seed.id, quantity: 1 }, now + inputs.length * 50)).toMatchObject({ ok: false });
    const legacy = freshFarm(); ensureBag(legacy, content);
    expect(legacy.fishing).toBeUndefined();
  });
});
