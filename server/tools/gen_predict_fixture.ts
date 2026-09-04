/**
 * 用**真实服务端归约器**跑一条农事序列，把每步之后的 cells 落成 fixture。
 * GDScript 预测器重放同一条序列，逐格比对——这是跨语言状态机一致性的唯一硬证据。
 */
import { writeFileSync } from 'node:fs';
import { BEDS, RESERVED, T0, blueprint, content, freshFarm, run } from '../test/domain/helpers.js';
import type { Command } from '../src/domain/commands.js';
import type { FarmState } from '../src/domain/state.js';

const THREE = BEDS.slice(0, 3);
const steps: [string, Command, number][] = [
  ['clear', { type: 'clear_cells', cell_ids: THREE }, T0],
  ['till', { type: 'till_cells', cell_ids: THREE }, T0],
  ['sow', { type: 'sow_cells', cell_ids: THREE, crop: 'R', lot: 'bound' }, T0],
  ['care', { type: 'apply_care', cell_ids: THREE, kind: content.weather.care_action[content.weather.script[0]] }, T0],
  ['harvest', { type: 'harvest_cells', cell_ids: THREE }, T0 + 10 * 60_000],
];

let s: FarmState = freshFarm();
const out: any = {
  cultivable: [...BEDS, ...RESERVED],
  reserved: RESERVED,
  cells0: s.cells,
  field_condition: s.clock.field_condition,
  care_kind: content.weather.care_action[content.weather.script[0]],
  crop: 'R',
  steps: [] as any[],
};
for (const [name, cmd, now] of steps) {
  const r = run(s, cmd, now);
  if (!r.ok) throw new Error(`${name}: ${r.code} ${r.detail ?? ''}`);
  s = r.state;
  out.steps.push({ name, type: cmd.type, cell_ids: THREE, now, cells: s.cells });
}
writeFileSync(process.argv[2], JSON.stringify(out, null, 2));
console.log('steps:', out.steps.map((x: any) => x.name).join(' → '));
