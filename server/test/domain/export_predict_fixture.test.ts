import { describe, it } from 'vitest';
import { writeFileSync } from 'node:fs';
import { content, plot, run, T0, freshFarm, soilCells } from './helpers.js';
import type { FarmState } from '../../src/domain/state.js';

/**
 * 生成客户端预测层的对账夹具：这里跑的是**真实的服务端归约器**，
 * 所以 tests/fixtures/farm_predict_sequence.json 里的每一格状态都是服务端的原话。
 * 客户端 CellPredictor 必须逐字复现它。
 */
describe('fixture', () => {
  it('exports the four-step sequence', () => {
    const cells = soilCells(4);
    let s: FarmState = freshFarm();
    const steps: unknown[] = [];
    const HOUR = 3600_000;
    const script = [
      { name: 'till', type: 'till_cells', cmd: { type: 'till_cells', cell_ids: cells }, now: T0 },
      { name: 'sow', type: 'sow_cells', cmd: { type: 'sow_cells', cell_ids: cells, crop: 'R', lot: 'bound' }, now: T0 },
      { name: 'water', type: 'water_cells', cmd: { type: 'water_cells', cell_ids: cells }, now: T0 },
      { name: 'harvest', type: 'harvest_cells', cmd: { type: 'harvest_cells', cell_ids: cells }, now: T0 + 4 * HOUR },
    ] as const;
    for (const step of script) {
      const r = run(s, step.cmd as never, step.now);
      if (!r.ok) throw new Error(`${step.name}: ${r.code} ${r.detail ?? ''}`);
      s = r.state;
      steps.push({ name: step.name, type: step.type, now: step.now, cell_ids: cells,
        crop: 'crop' in step.cmd ? step.cmd.crop : undefined,
        lot: 'lot' in step.cmd ? step.cmd.lot : undefined,
        cells: Object.fromEntries(cells.map(id => [id, s.cells[id] ?? null])) });
    }
    const cultivable: string[] = [];
    for (let j = 0; j < plot.gy && cultivable.length < 24; j++)
      for (let i = 0; i < plot.gx && cultivable.length < 24; i++)
        if (plot.till[j * plot.gx + i] === 1) cultivable.push(`${i},${j}`);
    writeFileSync('../tests/fixtures/farm_predict_sequence.json', JSON.stringify({
      _source: '由 server 的真实归约器导出（server/test/domain/export_predict_fixture.test.ts）。',
      _contract: '客户端 CellPredictor 必须逐字复现这里的每一格状态；荒地表示为 null。',
      cultivable, cells0: {}, steps,
    }, null, 1) + '\n');
  });
});
