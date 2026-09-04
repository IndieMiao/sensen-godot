import { describe, it, expect, beforeAll, vi } from 'vitest';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import * as geos from '../src/geos.js';
import * as pipeline from '../src/pipeline.js';
import * as writer from '../src/writer.js';
import * as anchors from '../src/anchors.js';
import * as core from 'blueprint-core';
import * as config from '../src/config.js';
import * as cli from '../src/cli.js';
import { cellKey } from '../src/masks.js';
import type { Blueprint, Cell } from '../src/types.js';

function freshRoot(): string {
  return mkdtempSync(path.join(os.tmpdir(), 'cli-root-'));
}

function readBlueprint(outDir: string): Blueprint {
  return JSON.parse(readFileSync(path.join(outDir, 'farm_blueprint.json'), 'utf8')) as Blueprint;
}

function writeBlueprint(outDir: string, bp: Blueprint): void {
  writeFileSync(path.join(outDir, 'farm_blueprint.json'), JSON.stringify(bp, null, 1));
}

/**
 * 确定性地找一条**横向相邻**的 3 格可建造跑道，且三格到 spawn 的 BFS 距离都落在
 * [minDist, maxDist]。必须相邻是因为 blueprint-core 的 validate 要求田畦是同一行的
 * i, i+1, i+2——劳作以田畦为操作单元，行级工具一次覆盖同畦 3 格（PRD §6.3）。
 */
function farBuildableCells(bp: Blueprint, minDist: number, maxDist: number): Cell[] {
  const g = bp.grid[0];
  const dist = anchors.bfs(bp.masks.walkable, bp.anchors.spawn);
  const ok = (i: number, j: number) => {
    if (bp.masks.buildable[j][i] !== '1') return false;
    const d = dist.get(cellKey(i, j, g));
    return d !== undefined && d >= minDist && d <= maxDist;
  };
  for (let j = 0; j < g; j++)
    for (let i = 0; i + 2 < g; i++)
      if (ok(i, j) && ok(i + 1, j) && ok(i + 2, j)) return [[i, j], [i + 1, j], [i + 2, j]];
  return [];
}

describe('cli', () => {
  beforeAll(geos.initGeos);

  it('validateAll returns 0 for a freshly-built, untampered root', () => {
    const root = freshRoot();
    const { bp, overlay } = pipeline.syntheticSafe('grid_valid');
    pipeline.buildAndWrite(bp, overlay, root);
    expect(cli.validateAll(root)).toBe(0);
  });

  it('validateAll returns 1 on checksum mismatch', () => {
    const root = freshRoot();
    const { bp, overlay } = pipeline.syntheticSafe('grid_checksum');
    const outDir = pipeline.buildAndWrite(bp, overlay, root);
    const stored = readBlueprint(outDir);
    stored.checksum = 'deadbeef';
    writeBlueprint(outDir, stored);
    expect(cli.validateAll(root)).toBe(1);
  });

  it('validateAll returns 1 when a shipped blueprint fails validation (cultivable count != 9)', () => {
    const root = freshRoot();
    const { bp, overlay } = pipeline.syntheticSafe('grid_cultivable');
    const outDir = pipeline.buildAndWrite(bp, overlay, root);
    const stored = readBlueprint(outDir);
    const row = stored.masks.cultivable[0].split('');
    const flipIdx = row.indexOf('0');
    row[flipIdx] = '1'; // now 10 cultivable cells instead of 9
    stored.masks.cultivable[0] = row.join('');
    stored.checksum = writer.checksum(stored); // keep the checksum internally consistent so we hit the validation branch, not the checksum branch
    writeBlueprint(outDir, stored);
    expect(cli.validateAll(root)).toBe(1);
  });

  it('validateAll returns 1 when walk_tour spread exceeds the absolute 5s budget', () => {
    const a = pipeline.syntheticSafe('grid_a');
    const b = pipeline.syntheticSafe('grid_b');
    expect(a.bp.report!.errors).toEqual([]);

    // 把 b 的第一条畦挪到远处，制造 >5 秒的纯步行巡回差；每格仍须留在 12 秒可达上限内，
    // 否则会走 far_bed 分支而不是我们要测的 spread 分支。
    const cap = Math.floor((core.MAX_FAR_BED_S * core.WALK_SPEED) / config.CELL_M) - 1;
    const baseFarCells = Math.round((a.bp.report!.far_bed_9_s * core.WALK_SPEED) / config.CELL_M);
    const farCells = farBuildableCells(b.bp, baseFarCells * 2, cap);
    expect(farCells).toHaveLength(3);
    b.bp.anchors.beds[0].cells = farCells;
    for (const [i, j] of farCells) {
      const row = b.bp.masks.cultivable[j].split('');
      row[i] = '1';
      b.bp.masks.cultivable[j] = row.join('');
    }
    // 原来那三格从 cultivable 里去掉，保持总数 12
    for (const [i, j] of a.bp.anchors.beds[0].cells) {
      const row = b.bp.masks.cultivable[j].split('');
      if (!farCells.some(c => c[0] === i && c[1] === j)) row[i] = '0';
      b.bp.masks.cultivable[j] = row.join('');
    }
    b.bp.report = anchors.validate(b.bp);
    expect(b.bp.report.errors).toEqual([]); // 单份仍然合法
    const spread = core.spreadSeconds([a.bp.report!.walk_tour_9_s, b.bp.report.walk_tour_9_s]);
    expect(spread).toBeGreaterThan(core.MAX_WALK_TOUR_SPREAD_S);

    const root = freshRoot();
    pipeline.buildAndWrite(a.bp, a.overlay, root);
    pipeline.buildAndWrite(b.bp, b.overlay, root);
    const log = vi.spyOn(console, 'log').mockImplementation(() => {});
    try {
      expect(cli.validateAll(root)).toBe(1);
      expect(log.mock.calls.flat().some(line => typeof line === 'string' && line.includes('FAIRNESS FAIL'))).toBe(true);
    } finally {
      log.mockRestore();
    }
  });

  it('main([]) prints usage and returns exit code 2 without auto-running on import', async () => {
    expect(await cli.main([])).toBe(2);
  });
});
