import { describe, expect, it } from 'vitest';
import type { Command } from '../../src/domain/commands.js';
import type { FarmState } from '../../src/domain/state.js';
import { reconcileJourney, startJourney } from '../../src/domain/journey.js';
import { content, freshFarm, run } from './helpers.js';

function ready() {
  const s = startJourney(freshFarm(), content);
  s.journey!.facts.push('workbench', 'planter_crafted', 'side_path', 'crafted_lantern',
    'shared_meal', 'project_terrace_0', 'project_terrace_1', 'project_seedbeds_0', 'project_seedbeds_1');
  s.journey!.wood = 5;
  s.journey!.materials = { stone: 5, fiber: 5 };
  s.journey!.workshop = { sequence: 0, stock: {}, displays: {} };
  return reconcileJourney(s, content);
}
function apply(s: FarmState, cmd: Command) {
  const r = run(s, cmd);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code}`);
  return r.state;
}
const plan = (s: FarmState, item = 'fountain', slot = 0) => apply(s, {
  type: 'plan_journey_display', project: 'terrace', slot, item, sequence: s.journey!.workshop!.sequence,
});

describe('handmade display plans', () => {
  it('plans, switches and cancels without consuming or granting resources', () => {
    const original = ready();
    const first = plan(original);
    expect(first.journey!.workshop!.planned).toEqual({ item: 'fountain', project: 'terrace', slot: 0 });
    const next = plan(plan(first, 'planter', 2), '', 2);
    expect(next).toEqual({ ...original, journey: { ...original.journey,
      facility_uses: {}, workshop: { ...original.journey!.workshop, sequence: 3 } } });
    expect(original.journey!.workshop!.planned).toBeUndefined();
  });

  it('retains the original destination through crafting and completes only on placement there', () => {
    const first = plan(ready());
    let next = apply(first, { type: 'craft_journey_item', item: 'fountain', sequence: 1 });
    expect(next.journey!.materials).toEqual({ stone: 1, fiber: 3 });
    expect(next.journey!.workshop!.planned).toEqual(first.journey!.workshop!.planned);
    next = apply(next, { type: 'display_journey_item', project: 'seedbeds', slot: 1, item: 'fountain', sequence: 2 });
    expect(next.journey!.workshop!.planned).toEqual(first.journey!.workshop!.planned);
    next = apply(next, { type: 'display_journey_item', project: 'seedbeds', slot: 1, item: '', sequence: 3 });
    next = apply(next, { type: 'display_journey_item', project: 'terrace', slot: 0, item: 'fountain', sequence: 4 });
    expect(next.journey!.workshop!.planned).toBeUndefined();
    expect(next.journey!.workshop!.stock.fountain).toBe(0);
    expect(next.journey!.workshop!.displays.terrace).toEqual(['fountain', '', '']);
    expect(run(next, { type: 'display_journey_item', project: 'terrace', slot: 0, item: 'fountain', sequence: 4 }).ok).toBe(false);
  });

  it.each([
    { item: '__proto__' }, { item: 'constructor' }, { item: null }, { project: 'missing' },
    { project: 'waystation' }, { slot: -1 }, { slot: 3 }, { slot: 0.5 }, { slot: '0' },
    { sequence: 1 }, { sequence: -1 }, { sequence: 0.5 }, { sequence: '0' },
  ])('rejects unavailable or malformed plans atomically: %j', fields => {
    const s = ready(), before = structuredClone(s);
    const command = { type: 'plan_journey_display', project: 'terrace', slot: 0, item: 'fountain', sequence: 0, ...fields } as Command;
    expect(run(s, command).ok).toBe(false);
    expect(s).toEqual(before);
  });

  it('rejects locked recipes, occupied positions and repeated plans', () => {
    const s = ready();
    s.journey!.facts = s.journey!.facts.filter(f => f !== 'crafted_lantern');
    expect(run(s, { type: 'plan_journey_display', project: 'terrace', slot: 0, item: 'fountain', sequence: 0 }).ok).toBe(false);
    s.journey!.workshop!.displays.terrace = ['planter', '', ''];
    expect(run(s, { type: 'plan_journey_display', project: 'terrace', slot: 0, item: 'planter', sequence: 0 }).ok).toBe(false);
    const planned = plan(ready());
    expect(run(planned, { type: 'plan_journey_display', project: 'terrace', slot: 0, item: 'fountain', sequence: 1 }).ok).toBe(false);
    expect(run(planned, { type: 'plan_journey_display', project: 'terrace', slot: 2, item: '', sequence: 1 }).ok).toBe(false);
  });

  it('keeps exactly the explicit goal and does not replace it during unrelated construction', () => {
    const s = ready();
    s.journey!.tracked_project = 'waystation';
    s.journey!.gathering = { sequence: 2, current: 'garden', planned: 'lantern', memories: ['garden'] };
    const planned = plan(s);
    expect(planned.journey!.tracked_project).toBeUndefined();
    expect(planned.journey!.gathering).toEqual({ sequence: 2, current: 'garden', memories: ['garden'] });
    const built = apply(planned, { type: 'build_journey_project', project: 'waystation', stage: 0 });
    expect(built.journey!.tracked_project).toBeUndefined();
    expect(built.journey!.workshop!.planned).toEqual(planned.journey!.workshop!.planned);
    const tracked = apply(planned, { type: 'track_journey_project', project: 'waystation' });
    expect(tracked.journey!.workshop!.planned).toBeUndefined();
    expect(tracked.journey!.workshop!.sequence).toBe(2);
    expect(tracked.journey!.gathering!.current).toBe('garden');
  });
});
