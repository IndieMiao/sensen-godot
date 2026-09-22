import { describe, expect, it } from 'vitest';
import { DEFAULT_CONTENT_DIR, loadContent } from '../../src/domain/content.js';
import { loadPlot, isTillable, isPlaceable, isWalkable } from '../../src/domain/plot.js';

/**
 * 农场地面属性的对账测试。checksum 是两端光栅化结果的指纹：
 * 改了 farm_plot.json 而只更新一端的实现，这里立刻变红。
 */
describe('farm plot', () => {
  it('rasterizes to the checksum written in the data file', () => {
    const content = loadContent(DEFAULT_CONTENT_DIR);
    const plot = loadPlot(content.farm_plot);
    expect(plot.gx).toBe(64);
    expect(plot.cellMm).toBe(750);
    // JSON 里写死的 checksum 必须等于实际光栅化的结果
    expect(plot.checksum).toBe(content.farm_plot.layouts.homestead_a.checksum);
    let till = 0;
    for (let j = 0; j < plot.gy; j++) for (let i = 0; i < plot.gx; i++)
      if (isTillable(plot, `${i},${j}`)) till++;
    // 2495：房子周围新增的 homestead_yard（草地，不可开垦）从可耕地里划走了 184 格。
    // 那圈院子是给既有美术构图留的地方——栅栏、树、灌木要长在不会被开垦的地上。
    expect(till).toBe(3003);
    // 建筑不可开垦不可放置；路可放置不可开垦
    expect(isTillable(plot, '28,38')).toBe(false);
    expect(isPlaceable(plot, '28,38')).toBe(false);
    expect(isTillable(plot, '29,35')).toBe(false);
    expect(isPlaceable(plot, '29,35')).toBe(true);
    expect(isWalkable(plot, '29,35')).toBe(true);
    // 房前院子：踩得上、放得下道具，但不能开垦
    expect(isTillable(plot, '24,38')).toBe(false);
    expect(isWalkable(plot, '24,38')).toBe(true);
    expect(isPlaceable(plot, '24,38')).toBe(true);
  });
});
