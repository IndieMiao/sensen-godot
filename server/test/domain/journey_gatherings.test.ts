import { describe, expect, it } from 'vitest';
import type { Command } from '../../src/domain/commands.js';
import { reconcileJourney, startJourney } from '../../src/domain/journey.js';
import type { FarmState } from '../../src/domain/state.js';
import { content, editInventory, freshFarm, run } from './helpers.js';

function ready() {
  const s = startJourney(freshFarm(), content);
  s.journey!.facts.push(...content.journey.gatherings.requires, 'workbench', 'side_path', 'shared_meal', 'planter_crafted');
  s.journey!.workshop = { sequence: 0, stock: { planter: 1, lantern: 1 }, displays: {} };
  s.inventory.dishes = { tea: 3, salad: 3 };
  const ready = reconcileJourney(s, content);
  editInventory(ready, draft => { draft.journey!.workshop!.stock = { planter: 1, lantern: 1 }; });
  return ready;
}

function apply(s: FarmState, cmd: Command) {
  const r = run(s, cmd);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code}`);
  return r.state;
}
const plan = (s: FarmState, theme: string) => apply(s, { type: 'plan_journey_gathering', theme, sequence: s.journey!.gathering?.sequence ?? 0 });
const host = (s: FarmState, theme: string) => apply(plan(s, theme), { type: 'host_journey_gathering', theme, sequence: (s.journey!.gathering?.sequence ?? 0) + 1 });

describe('street gatherings', () => {
  it('unlocks only after all facilities and the neighbours story', () => {
    for (const fact of content.journey.gatherings.requires) {
      const s = ready();
      s.journey!.facts = s.journey!.facts.filter(f => f !== fact);
      expect(run(s, { type: 'plan_journey_gathering', theme: 'garden', sequence: 0 })).toMatchObject({ ok: false, code: 'NOT_AVAILABLE' });
      expect(s.journey!.gathering).toBeUndefined();
    }
  });

  it('planning, switching and cancelling preserve every resource', () => {
    const s = ready();
    const next = plan(plan(plan(s, 'garden'), 'lantern'), '');
    expect(next.inventory).toEqual(s.inventory);
    expect(next.wallet).toBe(s.wallet);
    expect(next.journey!.workshop).toEqual(s.journey!.workshop);
    expect(next.journey!.gathering).toEqual({ sequence: 3, memories: [] });
  });

  it.each(['__proto__', 'constructor', 'unknown', null, 7])('rejects malformed theme %s atomically', theme => {
    const s = ready();
    const before = structuredClone(s);
    expect(run(s, { type: 'plan_journey_gathering', theme, sequence: 0 } as Command)).toMatchObject({ ok: false });
    expect(s).toEqual(before);
  });

  it.each([-1, 1, 0.5, NaN, '0'])('rejects invalid or stale sequence %s', sequence => {
    expect(run(ready(), { type: 'plan_journey_gathering', theme: 'garden', sequence } as Command)).toMatchObject({ ok: false });
  });

  it('hosts with one dish and retains the handmade piece in the world', () => {
    const s = ready();
    const next = host(s, 'garden');
    expect(next.inventory.dishes).toEqual({ tea: 2, salad: 3 });
    expect(next.wallet).toBe(s.wallet + content.journey.gatherings.themes.garden.coins);
    expect(next.journey!.workshop).toEqual({ sequence: 1, stock: { planter: 0, lantern: 1 }, displays: {} });
    expect(next.journey!.gathering).toEqual({ sequence: 2, current: 'garden', memories: ['garden'] });
    expect(s.journey!.gathering).toBeUndefined();
  });

  it('reuses the retained piece for another meal without duplicating memories', () => {
    const first = host(ready(), 'garden');
    const second = host(first, 'garden');
    expect(second.journey!.workshop).toEqual(first.journey!.workshop);
    expect(second.journey!.gathering!.memories).toEqual(['garden']);
    expect(second.inventory.dishes.tea).toBe(1);
    expect(run(second, { type: 'host_journey_gathering', theme: 'garden', sequence: 3 })).toMatchObject({ ok: false });
  });

  it('returns the old piece when changing theme and packs the current piece only once', () => {
    const s = host(host(ready(), 'garden'), 'lantern');
    expect(s.journey!.workshop!.stock).toEqual({ planter: 1, lantern: 0 });
    expect(s.journey!.gathering!.memories).toEqual(['garden', 'lantern']);
    const planned = plan(s, 'garden');
    const next = apply(planned, { type: 'pack_journey_gathering', sequence: 5 });
    expect(next.journey!.workshop!.stock).toEqual({ planter: 1, lantern: 1 });
    expect(next.journey!.gathering).toEqual({ sequence: 6, planned: 'garden', memories: ['garden', 'lantern'] });
    expect(run(next, { type: 'pack_journey_gathering', sequence: 6 })).toMatchObject({ ok: false });
  });

  it('does not take a displayed piece or partially pay a failed meal', () => {
    for (const missing of ['dish', 'piece']) {
      const s = plan(ready(), 'garden');
      editInventory(s, draft => {
        if (missing === 'dish') draft.inventory.dishes.tea = 0;
        else {
          draft.journey!.workshop!.stock.planter = 0;
          draft.journey!.workshop!.displays.terrace = ['planter', '', ''];
        }
      });
      const before = structuredClone(s);
      expect(run(s, { type: 'host_journey_gathering', theme: 'garden', sequence: 1 })).toMatchObject({ ok: false, code: 'INSUFFICIENT_ITEMS' });
      expect(s).toEqual(before);
    }
  });

  it('requires the selected theme even when resources are available', () => {
    expect(run(plan(ready(), 'garden'), { type: 'host_journey_gathering', theme: 'lantern', sequence: 1 })).toMatchObject({ ok: false });
    expect(run(ready(), { type: 'host_journey_gathering', theme: 'garden', sequence: 0 })).toMatchObject({ ok: false });
  });

  it('replaces a selected discovery and leaves a hosted gathering when another goal is selected', () => {
    const s = ready();
    s.journey!.tracked_discovery = 'reed_garden';
    s.journey!.facts.push(...content.journey.discoveries.reed_garden.requires);
    const first = host(s, 'garden');
    expect(first.journey!.tracked_discovery).toBeUndefined();
    const next = apply(plan(first, 'lantern'), { type: 'track_journey_discovery', discovery: 'reed_garden' });
    expect(next.journey!.gathering!.planned).toBeUndefined();
    expect(next.journey!.gathering!.current).toBe('garden');
    expect(next.journey!.workshop).toEqual(first.journey!.workshop);
  });
});
