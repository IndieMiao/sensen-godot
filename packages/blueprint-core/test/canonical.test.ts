import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { canonical, checksum } from '../src/canonical.js';
import { parseBlueprint, BlueprintError } from '../src/parse.js';

const DIR = path.dirname(fileURLToPath(import.meta.url));
const corpus = JSON.parse(readFileSync(path.join(DIR, '..', 'golden', 'corpus.json'), 'utf8')) as {
  entries: { name: string; blueprint: unknown; canonical: string; checksum: string }[];
  rejects: { name: string; blueprint: unknown; reject: string }[];
};

/**
 * golden/corpus.json 由一份独立的 Python 实现生成（见 git 历史里的生成脚本），
 * 不是把 TS 实现的输出抄回来——否则实现写错时 golden 也跟着错，测试永远绿。
 * Godot 侧 tests/blueprint/test_canonical.gd 加载同一个文件做同样的断言。
 */
describe('canonical golden corpus', () => {
  for (const e of corpus.entries) {
    it(`${e.name} 的 canonical 与 checksum 逐字节一致`, () => {
      const bp = parseBlueprint(e.blueprint);
      expect(canonical(bp)).toBe(e.canonical);
      expect(checksum(bp)).toBe(e.checksum);
    });
  }
  for (const r of corpus.rejects) {
    it(`${r.name} 被拒绝为 ${r.reject}`, () => {
      expect(() => parseBlueprint(r.blueprint)).toThrowError(
        expect.objectContaining({ code: r.reject }) as unknown as BlueprintError,
      );
    });
  }
});

describe('canonical 覆盖 r1 没覆盖的字段', () => {
  const base = () => parseBlueprint(structuredClone(corpus.entries[0].blueprint));
  it('grid 改变 checksum 必变', () => {
    const a = base();
    const b = base();
    b.grid = [2, 8];
    expect(checksum(a)).not.toBe(checksum(b));
  });
  it('cell_mm 改变 checksum 必变', () => {
    const a = base();
    const b = base();
    b.cell_mm = 2000;
    expect(checksum(a)).not.toBe(checksum(b));
  });
  it('play_area_mm 改变 checksum 必变', () => {
    const a = base();
    const b = base();
    b.play_area_mm = 8000;
    expect(checksum(a)).not.toBe(checksum(b));
  });
  it('reserved_bed 改变 checksum 必变', () => {
    const a = base();
    const b = base();
    b.anchors.reserved_bed.cells[0] = [2, 0];
    expect(checksum(a)).not.toBe(checksum(b));
  });
  it('name 改变 checksum 不变（改名安全）', () => {
    const a = base();
    const b = base();
    b.name = 'Renamed';
    expect(checksum(a)).toBe(checksum(b));
  });
});
