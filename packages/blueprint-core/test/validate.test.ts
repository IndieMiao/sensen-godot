import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseBlueprint } from '../src/parse.js';
import { validate, CULTIVABLE_CELLS } from '../src/validate.js';
import type { Blueprint } from '../src/types.js';

const DIR = path.dirname(fileURLToPath(import.meta.url));
const corpus = JSON.parse(readFileSync(path.join(DIR, '..', 'golden', 'corpus.json'), 'utf8'));
const good = (): Blueprint => parseBlueprint(structuredClone(corpus.entries[0].blueprint));

/** 每条 validate 规则各一个反例——只测"好蓝图通过"证明不了规则真的在跑。 */
describe('validate', () => {
  it('合法蓝图无错误', () => {
    expect(validate(good())).toEqual([]);
  });

  it('spawn 不在 walkable 上时直接短路', () => {
    const bp = good();
    bp.masks.walkable[0] = '0111';
    const errs = validate(bp);
    expect(errs).toEqual(['spawn 不在 walkable 上']);
  });

  it('锚点不可达被抓出', () => {
    const bp = good();
    // 用一圈 0 把 house(3,0) 围死：它自身可站，但邻格全不可走
    bp.masks.walkable = ['1110', '1110', '1111', '1111'];
    bp.masks.walkable[0] = '1101';
    expect(validate(bp).some(e => e.includes('house 从 spawn 不可达'))).toBe(true);
  });

  it('田畦格不在 cultivable 上被抓出', () => {
    const bp = good();
    bp.masks.cultivable[1] = '0011'; // 抹掉 bed0 的 (1,1)
    expect(validate(bp).some(e => e.includes('不在 cultivable 上'))).toBe(true);
  });

  it('初始畦与预留畦重叠被抓出', () => {
    const bp = good();
    bp.anchors.reserved_bed.cells = [...bp.anchors.beds[0].cells];
    expect(validate(bp).some(e => e.includes('重叠'))).toBe(true);
  });

  it('三格不相邻被抓出', () => {
    const bp = good();
    bp.anchors.beds[0].cells = [[1, 1], [3, 1], [2, 1]];
    expect(validate(bp).some(e => e.includes('不是同一行相邻'))).toBe(true);
  });

  it(`cultivable 格数不等于 ${CULTIVABLE_CELLS} 被抓出`, () => {
    const bp = good();
    bp.masks.cultivable[0] = '1111';
    expect(validate(bp).some(e => e.includes('cultivable 格数'))).toBe(true);
  });
});
