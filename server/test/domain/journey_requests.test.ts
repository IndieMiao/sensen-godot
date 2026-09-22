import { describe, expect, it } from 'vitest';
import type { Command } from '../../src/domain/commands.js';
import type { FarmState } from '../../src/domain/state.js';
import { reconcileJourney, startJourney } from '../../src/domain/journey.js';
import { content, editInventory, freshFarm, run } from './helpers.js';
import { ensureBag } from '../../src/domain/bag.js';
import { ensureCharacter } from '../../src/domain/character.js';

function ready() {
  const s = startJourney(freshFarm(), content);
  s.journey!.facts.push('workbench', 'planter_crafted', 'shared_meal', 'side_path',
    'crafted_lantern', 'project_terrace_0', 'project_terrace_1');
  s.journey!.wood = 8;
  s.journey!.materials = { stone: 5, fiber: 5 };
  s.inventory.produce.L = 2;
  s.inventory.dishes.salad = 1;
  return reconcileJourney(s, content);
}
function apply(s: FarmState, cmd: Command) {
  const result = run(s, cmd);
  if (!result.ok) throw new Error(`${cmd.type}: ${result.code}`);
  return result.state;
}
const track = (s: FarmState, slot = 'nursery', tracking = true) => apply(s, {
  type: 'track_journey_opportunity', slot, sequence: s.journey!.opportunities[slot].sequence, tracking,
});

describe('neighbour request tracking', () => {
  it('tracks, switches and cancels exact offers without costs, rewards or advancing requests', () => {
    const s = ready();
    ensureBag(s, content);
    ensureCharacter(s, content);
    const before = structuredClone(s);
    const pinned = track(s);
    expect(pinned.journey!.tracked_opportunity).toEqual({ slot: 'nursery', sequence: 0 });
    const switched = track(pinned, 'restorer');
    expect(switched.journey!.tracked_opportunity).toEqual({ slot: 'restorer', sequence: 0 });
    expect(track(switched, 'restorer', false)).toEqual({ ...s,
      journey: { ...s.journey, facility_uses: {}, opportunities: { ...s.journey!.opportunities,
        nursery: { ...s.journey!.opportunities.nursery, accepted: true },
        restorer: { ...s.journey!.opportunities.restorer, accepted: true } } } });
    expect(s).toEqual(before);
  });

  it.each([
    { slot: 'missing' }, { slot: '__proto__' }, { slot: 'constructor' }, { slot: null },
    { sequence: 1 }, { sequence: -1 }, { sequence: 0.5 }, { sequence: '0' },
    { tracking: 'true' }, { tracking: null }, { tracking: false },
  ])('rejects stale or malformed commands atomically: %j', fields => {
    const s = ready(), before = structuredClone(s);
    const cmd = { type: 'track_journey_opportunity', slot: 'nursery', sequence: 0, tracking: true, ...fields } as Command;
    expect(run(s, cmd).ok).toBe(false);
    expect(s).toEqual(before);
  });

  it('rejects locked requests, repeated pins and cancelling another request', () => {
    const fresh = startJourney(freshFarm(), content);
    expect(run(fresh, { type: 'track_journey_opportunity', slot: 'bistro', sequence: 0, tracking: true }).ok).toBe(false);
    fresh.journey!.opportunities.nursery.variant = 1;
    expect(run(fresh, { type: 'track_journey_opportunity', slot: 'nursery', sequence: 0, tracking: true }).ok).toBe(false);
    const pinned = track(ready());
    expect(run(pinned, { type: 'track_journey_opportunity', slot: 'nursery', sequence: 0, tracking: true }).ok).toBe(false);
    expect(run(pinned, { type: 'track_journey_opportunity', slot: 'restorer', sequence: 0, tracking: false }).ok).toBe(false);
  });

  it.each(['fulfill_opportunity', 'decline_opportunity'] as const)('%s clears only its own pin and leaves the next request untracked', type => {
    const s = track(ready());
    s.journey!.opportunities.restorer.accepted = true;
    const other = apply(s, { type, slot: 'restorer', sequence: 0 });
    expect(other.journey!.tracked_opportunity).toEqual(s.journey!.tracked_opportunity);
    const done = apply(other, { type, slot: 'nursery', sequence: 0 });
    expect(done.journey!.tracked_opportunity).toBeUndefined();
    expect(done.journey!.opportunities.nursery.sequence).toBe(1);
    expect(run(done, { type: 'track_journey_opportunity', slot: 'nursery', sequence: 0, tracking: true }).ok).toBe(false);
  });

  it('keeps the pin when a delivery fails and does not override it during unrelated construction', () => {
    const s = track(ready());
    editInventory(s, draft => { draft.inventory.produce.L = 0; });
    expect(run(s, { type: 'fulfill_opportunity', slot: 'nursery', sequence: 0 }).ok).toBe(false);
    const built = apply(s, { type: 'build_journey_project', project: 'waystation', stage: 0 });
    expect(built.journey!.tracked_project).toBeUndefined();
    expect(built.journey!.tracked_opportunity).toEqual(s.journey!.tracked_opportunity);
  });

  it.each([
    { type: 'track_journey_project', project: 'waystation' },
    { type: 'track_journey_discovery', discovery: 'stone_hollow' },
    { type: 'plan_journey_gathering', theme: 'garden', sequence: 0 },
    { type: 'plan_journey_display', project: 'terrace', slot: 2, item: 'planter', sequence: 0 },
  ] as Command[])('honours an explicit change of purpose in both directions: %j', cmd => {
    const requested = track(ready());
    if (cmd.type === 'plan_journey_gathering') requested.journey!.facts.push(...content.journey.gatherings.requires);
    const changed = apply(requested, cmd);
    expect(changed.journey!.tracked_opportunity).toBeUndefined();
    const returned = track(changed);
    expect(returned.journey!.tracked_project).toBeUndefined();
    expect(returned.journey!.tracked_discovery).toBeUndefined();
    expect(returned.journey!.gathering?.planned).toBeUndefined();
    expect(returned.journey!.workshop?.planned).toBeUndefined();
    expect(returned.inventory).toEqual(requested.inventory);
    expect(returned.wallet).toBe(requested.wallet);
    expect(returned.journey!.opportunities).toEqual(requested.journey!.opportunities);
  });
});
