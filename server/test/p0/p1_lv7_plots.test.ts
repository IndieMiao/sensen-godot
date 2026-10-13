import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { addPlots, bedCells, plotCount, plotYardCell } from '../../src/p0/garden.js';
import { applyP0, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, upgradeState, type P0State } from '../../src/p0/state.js';

// q(172) (SGODOT-282): Homestead Lv7 brings 8 more plots, 40–47, on the field's lattice just outside it — six in front
// of the first row (row −1), two on the left edge (col −1). What stood on them makes way: a decor piece goes back to Farm
// Storage (q(120)'s `… · back in Farm Storage`), the Compost Bin moves beside the workbench; Decorate keeps off the
// beds from then on. Harvest All takes the front row like any other.
const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 13, 2, 0, 0);
const H = 3_600_000;
const HOME = { space: 'home' } as const;

function at(level: number): P0State {
  const s = { ...freshState(c, 'player-lv7-plots', T0, 7), created_at: T0 - 8 * 24 * H, fires: 1 };
  s.homestead.level = level;
  addPlots(c, s);
  return s;
}
function ready(s: P0State): P0State {
  const next = c.homestead.levels.find(l => l.level === s.homestead.level + 1)!;
  s.skills = { farming: 99_999, fishing: 99_999, cooking: s.skills.cooking };
  for (const [id, n] of next.materials) s.storage[id] = (s.storage[id] ?? 0) + n;
  s.coins = next.coins + 40;
  return s;
}
function step(s: P0State, cmd: P0Command, now = T0): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return { s: r.state, ev: r.events };
}
const cellKey = (id: number) => plotYardCell(c, id)!.join(',');

describe('Homestead Lv7: plots 40–47 (q(172))', () => {
  it('sit on the yard cells of layout C3: (2,1) (4,1) (6,1) (8,1) (12,1) (14,1), then (2,3) (2,9)', () => {
    expect([40, 41, 42, 43, 44, 45, 46, 47].map(cellKey)).toEqual(['2,1', '4,1', '6,1', '8,1', '12,1', '14,1', '2,3', '2,9']);
    expect(cellKey(0)).toBe('4,3');   // plot 0 where P0Garden.PLOT_ORIGIN puts it
    expect(plotCount(c, at(6))).toBe(40);
    expect(plotCount(c, at(7))).toBe(48);
  });

  it('the upgrade adds them wild; a piece on one goes back to Farm Storage, the Compost Bin moves beside the workbench', () => {
    const s = ready(at(6));
    s.decor = { placed: [{ uid: 1, id: 'deco_planter', x: 4, y: 1, rot: 0 }, { uid: 2, id: 'deco_lantern', x: 3, y: 1, rot: 0 }], count: 2 };
    s.facilities = [{ id: 1, kind: 'compost_bin', plot: -1, cell: [2, 3] }];
    s.facility_count = 1;
    const { s: after, ev } = step(s, { type: 'homestead_upgrade' });
    expect(after.plots.filter(p => p.id >= 40).map(p => [p.id, p.state])).toEqual([40, 41, 42, 43, 44, 45, 46, 47].map(id => [id, 'wild']));
    expect(ev).toContainEqual({ kind: 'plots_added', plots: [40, 41, 42, 43, 44, 45, 46, 47], reason: 'homestead' });
    // the planter on bed 41 goes back; the lantern in the walkway beside it stays
    expect(after.decor!.placed.map(p => p.uid)).toEqual([2]);
    expect(after.storage.deco_planter).toBe(1);
    expect(ev).toContainEqual({ kind: 'decor', action: 'stored', uid: 1, item: 'deco_planter', x: 4, y: 1, rot: 0, reason: 'plots' });
    // the Compost Bin on bed 46 moves to a legal yard cell beside the workbench (its three cells 16–18, row 16)
    const bin = after.facilities![0];
    expect(bin.cell).not.toEqual([2, 3]);
    expect(Math.abs(bin.cell![1] - 16)).toBeLessThanOrEqual(1);
    expect(bedCells(c, after).has(bin.cell!.join(','))).toBe(false);
    expect(ev).toContainEqual(expect.objectContaining({ kind: 'facility', action: 'moved', facility: 1, facility_kind: 'compost_bin',
      x: bin.cell![0], y: bin.cell![1], reason: 'plots' }));
  });

  it('Decorate may use those cells below Lv7, not from it (`Outside your yard`); the walkways between stay open', () => {
    const six = at(6);
    six.storage = { deco_planter: 2 };
    expect(applyP0(c, six, { type: 'place_decor', item: 'deco_planter', x: 4, y: 1, ...HOME }, T0)).toMatchObject({ ok: true });
    const seven = at(7);
    seven.storage = { deco_planter: 2 };
    expect(applyP0(c, seven, { type: 'place_decor', item: 'deco_planter', x: 4, y: 1, ...HOME }, T0)).toMatchObject({ ok: false, code: 'decor_outside' });
    expect(applyP0(c, seven, { type: 'place_decor', item: 'deco_planter', x: 2, y: 9, ...HOME }, T0)).toMatchObject({ ok: false, code: 'decor_outside' });
    expect(applyP0(c, seven, { type: 'place_decor', item: 'deco_planter', x: 3, y: 1, ...HOME }, T0)).toMatchObject({ ok: true });
  });

  it('Harvest All takes the front row (row −1) as any other', () => {
    const s = at(7);
    s.skills.farming = c.skills.farming[8];   // Lv9
    s.bag = [];
    for (const id of [40, 41, 42, 43, 44, 45]) s.plots[s.plots.findIndex(p => p.id === id)] = { id, state: 'growing', crop: 'crop_radish', ready_at: T0 + 4 * H, xp_pct: 100 };
    const r = step(s, { type: 'harvest', plot: 40, plots: [40, 41, 42, 43, 44, 45] }, T0 + 5 * H);
    expect(r.s.bag.find(b => b.id === 'crop_radish')?.qty).toBe(6);
    // and a row with a plot that is not one is still refused
    const bad = applyP0(c, s, { type: 'harvest', plot: 40, plots: [40, 99] }, T0 + 5 * H);
    expect(bad).toMatchObject({ ok: false, code: 'bad_plot' });
  });

  it('a save already at Lv7 when this version arrives gets 40–47 on load, its pieces there back in storage', () => {
    const old = at(7);
    old.plots = old.plots.filter(p => p.id < 40);
    old.decor = { placed: [{ uid: 1, id: 'deco_planter', x: 14, y: 1, rot: 0 }], count: 1 };
    const loaded = upgradeState(c, structuredClone(old), T0);
    expect(loaded.plots.filter(p => p.id >= 40)).toHaveLength(8);
    expect(loaded.decor!.placed).toEqual([]);
    expect(loaded.storage.deco_planter).toBe(1);
  });
});
