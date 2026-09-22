/**
 * 自由格子种田的四步闭环：开垦 → 播种 → 浇水 → 收割。
 *
 * 取代原来按 9 格固定田畦逐日断言金额的七日账本（它的每一条前提——固定畦、教学萝卜、
 * 天气三选一照料、渐进解锁——都已随 SGODOT-128 退役）。这里断言的是**不变量**，
 * 不是精确目标值：内容表可以调数值而不必来改断言。
 */
import { describe, expect, it } from 'vitest';
import { CROP_IDS } from '../../src/domain/content.js';
import { MAX_TILLED_CELLS } from '../../src/domain/handlers/farming.js';
import { isPlaceable, isTillable } from '../../src/domain/plot.js';
import { BEDS, content, HOUR, T0, freshFarm, plot, run, soilCells } from './helpers.js';

describe('four-step farming loop', () => {
  it('starts with no tilled ground at all', () => {
    expect(Object.keys(freshFarm().cells)).toHaveLength(0);
  });

  it('runs till → sow → water → harvest on player-chosen cells', () => {
    const cells = BEDS.slice(0, 3);
    let s = freshFarm();

    const tilled = run(s, { type: 'till_cells', cell_ids: cells });
    expect(tilled.ok).toBe(true);
    if (!tilled.ok) return;
    s = tilled.state;
    for (const id of cells) expect(s.cells[id]).toMatchObject({ state: 'tilled', crop: null });

    const sown = run(s, { type: 'sow_cells', cell_ids: cells, crop: 'R', lot: 'bound' });
    expect(sown.ok).toBe(true);
    if (!sown.ok) return;
    s = sown.state;
    // 播下但未浇水：作物停在起点，ready_at 保持 null，永远不会自己成熟。
    for (const id of cells) expect(s.cells[id]).toMatchObject({ state: 'sown', ready_at: null });

    const watered = run(s, { type: 'water_cells', cell_ids: cells });
    expect(watered.ok).toBe(true);
    if (!watered.ok) return;
    s = watered.state;
    const duration = content.crops.crops.R.duration_ms;
    for (const id of cells)
      expect(s.cells[id]).toMatchObject({ state: 'growing', ready_at: T0 + duration });

    // 没熟之前收不了
    expect(run(s, { type: 'harvest_cells', cell_ids: cells }, T0 + duration - 1).ok).toBe(false);

    const before = s.inventory.produce.R;
    const harvested = run(s, { type: 'harvest_cells', cell_ids: cells }, T0 + duration);
    expect(harvested.ok).toBe(true);
    if (!harvested.ok) return;
    s = harvested.state;
    expect(s.inventory.produce.R).toBe(before + 3 * content.crops.crops.R.yield);
    // 收完回到已开垦，下一轮直接播种
    for (const id of cells) expect(s.cells[id]).toMatchObject({ state: 'tilled', crop: null });
  });

  it('keeps crop durations on the real-time hour scale', () => {
    for (const id of CROP_IDS) expect(content.crops.crops[id].duration_ms).toBeGreaterThanOrEqual(HOUR);
  });

  it('refuses to till ground the layout marks unfarmable', () => {
    const paved = `${plot.anchors.house[0]},${plot.anchors.house[1]}`;
    expect(isTillable(plot, paved)).toBe(false);
    const r = run(freshFarm(), { type: 'till_cells', cell_ids: [paved] });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.code).toBe('CELL_NOT_CULTIVABLE');
  });

  it('refuses to till the same cell twice', () => {
    const one = BEDS.slice(0, 1);
    const first = run(freshFarm(), { type: 'till_cells', cell_ids: one });
    expect(first.ok).toBe(true);
    if (!first.ok) return;
    const again = run(first.state, { type: 'till_cells', cell_ids: one });
    expect(again.ok).toBe(false);
    if (!again.ok) expect(again.code).toBe('WRONG_STATE');
  });

  it('gives empty tilled ground back to the wild, freeing the budget', () => {
    const one = BEDS.slice(0, 1);
    const tilled = run(freshFarm(), { type: 'till_cells', cell_ids: one });
    expect(tilled.ok).toBe(true);
    if (!tilled.ok) return;
    const cleared = run(tilled.state, { type: 'clear_plot', cell_ids: one });
    expect(cleared.ok).toBe(true);
    // 荒地不进状态：铲平之后这个 key 彻底消失，而不是留一个 'wild' 槽。
    if (cleared.ok) expect(cleared.state.cells[one[0]!]).toBeUndefined();
  });

  it('caps how much ground one farm can hold open at once', () => {
    let s = freshFarm();
    const all = soilCells(MAX_TILLED_CELLS + 1);
    expect(all.length).toBe(MAX_TILLED_CELLS + 1);
    for (let n = 0; n < MAX_TILLED_CELLS; n += 64) {
      const batch = all.slice(n, Math.min(n + 64, MAX_TILLED_CELLS));
      const r = run(s, { type: 'till_cells', cell_ids: batch });
      expect(r.ok).toBe(true);
      if (!r.ok) return;
      s = r.state;
    }
    expect(Object.keys(s.cells)).toHaveLength(MAX_TILLED_CELLS);
    const over = run(s, { type: 'till_cells', cell_ids: [all[MAX_TILLED_CELLS]!] });
    expect(over.ok).toBe(false);
    if (!over.ok) expect(over.code).toBe('PLOT_LIMIT_REACHED');
  });

  it('separates "can be farmed" from "can hold a prop"', () => {
    // 路可放置不可开垦，土两者皆可，建筑两者皆不可。这就是用户要的两类地面属性。
    const path = '29,35';
    expect(isTillable(plot, path)).toBe(false);
    expect(isPlaceable(plot, path)).toBe(true);
    expect(isTillable(plot, BEDS[0]!)).toBe(true);
    expect(isPlaceable(plot, BEDS[0]!)).toBe(true);
  });
});
