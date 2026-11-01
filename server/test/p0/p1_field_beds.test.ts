import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { addPlots, plotYardCell } from '../../src/p0/garden.js';
import { applyP0, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';

// SGODOT-355 b1 (不知火舞 approved 哪吒's grid, 11-02; replaces q(172)'s Lv7 front row): the field is the whole 9 × 7 grid,
// yard x 2–18, y −1–11. Decorate keeps off all of it — open beds, beds still to open and the walkways between
// (decor.yard.field [1, −2, 19, 15]) — so a bed opens on bare ground; a piece a save from before still has there goes back
// to Farm Storage when its bed opens (q(120)). Harvest All takes a row of the grid as before.
const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 13, 2, 0, 0);
const H = 3_600_000;
const HOME = { space: 'home' } as const;
const at = (col: number, row: number) => c.garden.plots.findIndex(([x, y]) => x === col && y === row);

function home(level: number): P0State {
  const s = { ...freshState(c, 'player-field-beds', T0, 7), created_at: T0 - 8 * 24 * H, fires: 1 };
  s.homestead.level = level;
  addPlots(c, s);
  return s;
}
function ready(s: P0State): P0State {
  const next = c.homestead.levels.find(l => l.level === s.homestead.level + 1)!;
  s.skills = { farming: 99_999, fishing: 99_999, cooking: 99_999 };
  for (const [id, n] of next.materials) s.storage[id] = (s.storage[id] ?? 0) + n;
  s.coins = next.coins + 40;
  return s;
}
function step(s: P0State, cmd: P0Command, now = T0): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return { s: r.state, ev: r.events };
}
const cell = (id: number) => plotYardCell(c, id)!;

describe('the field and Decorate (SGODOT-355 b1)', () => {
  it('a bed sits on the yard grid at origin + 2 × [col, row]: the first in front of the farmhouse door, the last at the front corner', () => {
    expect(cell(0)).toEqual([8, 11]);
    expect(cell(at(-1, -2))).toEqual([2, -1]);
    expect(cell(at(7, -2))).toEqual([18, -1]);
  });

  it('Decorate keeps off the whole field — an open bed, a bed still to open, the walkways — and stays free behind the fence row', () => {
    const s = home(1);
    s.storage = { deco_planter: 3 };
    for (const [x, y] of [cell(0), cell(at(-1, -2)), [9, 10], [3, -2]] as [number, number][])
      expect(applyP0(c, s, { type: 'place_decor', item: 'deco_planter', x, y, ...HOME }, T0)).toMatchObject({ ok: false, code: 'decor_outside' });
    expect(applyP0(c, s, { type: 'place_decor', item: 'deco_planter', x: 3, y: 15, ...HOME }, T0)).toMatchObject({ ok: true });
  });

  it('a piece a save from before still has where a bed opens goes back to Farm Storage on the upgrade', () => {
    const s = ready(home(1));
    const [x, y] = cell(8);   // the first bed Lv2 opens
    s.decor = { placed: [{ uid: 1, id: 'deco_planter', x, y, rot: 0 }], count: 1 };
    const { s: after, ev } = step(s, { type: 'homestead_upgrade' });
    expect(after.decor!.placed).toEqual([]);
    expect(after.storage.deco_planter).toBe(1);
    expect(ev).toContainEqual({ kind: 'decor', action: 'stored', uid: 1, item: 'deco_planter', x, y, rot: 0, reason: 'plots' });
  });

  it('Harvest All takes a row of the grid as before', () => {
    const s = home(5);   // the back row (row 4) is open end to end
    s.skills.farming = c.skills.farming[8];   // Lv9
    s.bag = [];
    const row = [-1, 0, 1, 2, 3, 4].map(col => at(col, 4));
    for (const id of row) s.plots[s.plots.findIndex(p => p.id === id)] = { id, state: 'growing', crop: 'crop_radish', ready_at: T0 + 4 * H, xp_pct: 100 };
    const r = step(s, { type: 'harvest', plot: row[0], plots: row }, T0 + 5 * H);
    expect(r.s.bag.find(b => b.id === 'crop_radish')?.qty).toBe(6);
    expect(applyP0(c, s, { type: 'harvest', plot: row[0], plots: [row[0], 99] }, T0 + 5 * H)).toMatchObject({ ok: false, code: 'bad_plot' });
  });
});
