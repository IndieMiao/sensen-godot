import { describe, expect, it } from 'vitest';
import { beginFieldGrowth } from '../../src/domain/field_growth.js';
import { startJourney } from '../../src/domain/journey.js';
import { visitorSnapshot } from '../../src/http/dto.js';
import { derive } from '../../src/domain/derive.js';
import { BEDS, RESERVED, T0, SH, content, freshFarm, run, runAll } from './helpers.js';

describe('new farm field progression', () => {
  const fresh = () => beginFieldGrowth(startJourney(freshFarm(), content), BEDS, content);
  it('starts at four, opens six after sowing, and nine after six actual harvests', () => {
    let state = fresh();
    const order = state.field_progress!.order;
    expect(order.slice(0, 4)).toEqual([BEDS[0], BEDS[1], BEDS[3], BEDS[4]]);
    expect(run(state, { type: 'clear_cells', cell_ids: [order[4]] })).toMatchObject({ ok: false, code: 'CELL_LOCKED' });
    const first = order.slice(0, 4);
    state = runAll(state, [
      [{ type: 'clear_cells', cell_ids: first }], [{ type: 'till_cells', cell_ids: first }],
      [{ type: 'sow_cells', cell_ids: first, crop: 'R', lot: 'bound' }],
      [{ type: 'apply_care', cell_ids: first, kind: 'water' }],
    ]);
    expect(state.field_progress).toMatchObject({ planted: 4, harvested: 0, plots: 6 });
    const extra = order.slice(4, 6);
    state = runAll(state, [
      [{ type: 'clear_cells', cell_ids: extra }], [{ type: 'till_cells', cell_ids: extra }],
      [{ type: 'sow_cells', cell_ids: extra, crop: 'R', lot: 'bound' }],
      [{ type: 'apply_care', cell_ids: extra, kind: 'water' }],
    ]);
    const before = structuredClone(state);
    expect(run(state, { type: 'harvest_cells', cell_ids: order.slice(0, 6) }, T0 + 1000)).toMatchObject({ ok: false, code: 'NOT_RIPE' });
    expect(state).toEqual(before);
    state = runAll(state, [[{ type: 'harvest_cells', cell_ids: order.slice(0, 6) }, T0 + 180000]]);
    expect(state.field_progress).toMatchObject({ planted: 6, harvested: 6, plots: 9 });
    expect(run(state, { type: 'clear_cells', cell_ids: order.slice(6) }, T0 + 180000).ok).toBe(true);
    expect(run(state, { type: 'clear_cells', cell_ids: RESERVED }, T0 + 180000)).toMatchObject({ ok: false, code: 'CELL_LOCKED' });
  });

  it('does not shrink legacy farms or reapply onboarding when starting the journey', () => {
    const old = freshFarm();
    old.cells[BEDS[8]].state = 'growing';
    old.cells[BEDS[8]].ready_at = T0 + 12345;
    const joined = startJourney(old, content);
    expect(joined.field_progress).toBeUndefined();
    expect(joined.cells).toEqual(old.cells);
    expect(run(joined, { type: 'clear_cells', cell_ids: BEDS.slice(0, 8) }).ok).toBe(true);
    expect(() => beginFieldGrowth(joined, BEDS, content)).toThrow('untouched');
  });

  it('publishes only unlocked cell IDs for visual rendering, without progress counters', () => {
    const state = fresh();
    const snapshot = visitorSnapshot({ id: 'farm', owner_id: 'private', region_id: 'shanghai', layout_patch_id: 'sh_a',
      blueprint_revision: 2, version: 0, location_visible: true, visit_access: 'anyone', state }, derive(state, T0, SH, content), 1, T0);
    expect(snapshot.unlocked_cell_ids).toEqual(state.field_progress!.order.slice(0, 4));
    expect(snapshot).not.toHaveProperty('field_progress');
    expect(snapshot).not.toHaveProperty('owner_id');
  });
});
