import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseBlueprint } from '../src/parse.js';
import { metrics, spreadSeconds, ACTIONS_PER_ROUND, ACTION_S, MAX_FAR_BED_S } from '../src/fairness.js';
import type { Blueprint } from '../src/types.js';

const DIR = path.dirname(fileURLToPath(import.meta.url));
const corpus = JSON.parse(readFileSync(path.join(DIR, '..', 'golden', 'corpus.json'), 'utf8'));
const good = (name = 'tiny_1000'): Blueprint =>
  parseBlueprint(structuredClone(corpus.entries.find((e: { name: string }) => e.name === name).blueprint));

describe('fairness', () => {
  it('九格与十二格分别统计，含预留畦的最远距离不小于九格的', () => {
    const m = metrics(good());
    expect(m.far_bed_12_s).toBeGreaterThanOrEqual(m.far_bed_9_s);
    expect(m.walk_tour_12_s).toBeGreaterThanOrEqual(0);
    expect(m.errors).toEqual([]);
  });

  it('tour_s = 纯步行 + 36 次动作，动作时间不再稀释步行差', () => {
    const m = metrics(good());
    expect(m.tour_s).toBeCloseTo(m.walk_tour_9_s + ACTIONS_PER_ROUND * ACTION_S, 2);
  });

  it('cell_mm 放大后所有秒数按比例放大', () => {
    const a = metrics(good('tiny_1000'));
    const b = metrics(good('tiny_2500'));
    expect(b.walk_tour_9_s).toBeCloseTo(a.walk_tour_9_s * 2.5, 2);
    expect(b.far_bed_9_s).toBeCloseTo(a.far_bed_9_s * 2.5, 2);
  });

  it('预留畦太远时单独报错——r1 的指标只看初始三畦，看不到第四畦', () => {
    const bp = good();
    bp.cell_mm = 20_000; // 每格 20 m，两步就超 12 s 上限
    const m = metrics(bp);
    expect(m.errors.some(e => e.includes('含第四畦'))).toBe(true);
    expect(m.far_bed_12_s).toBeGreaterThan(MAX_FAR_BED_S);
  });

  it('spreadSeconds 给的是绝对差而不是比值', () => {
    expect(spreadSeconds([23.6, 25.2, 24.4])).toBeCloseTo(1.6, 6);
    expect(spreadSeconds([])).toBe(0);
  });
});
