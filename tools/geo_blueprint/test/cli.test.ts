import { describe, it, expect, beforeAll, vi } from 'vitest';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import * as geos from '../src/geos.js';
import * as pipeline from '../src/pipeline.js';
import * as writer from '../src/writer.js';
import * as anchors from '../src/anchors.js';
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

/** Deterministically finds 3 buildable, spawn-reachable cells whose BFS distance falls in [minDist, maxDist]. */
function farBuildableCells(bp: Blueprint, minDist: number, maxDist: number): Cell[] {
  const g = bp.grid[0];
  const dist = anchors.bfs(bp.masks.walkable, bp.anchors.spawn);
  const out: Cell[] = [];
  for (let j = 0; j < g && out.length < 3; j++) {
    for (let i = 0; i < g && out.length < 3; i++) {
      if (bp.masks.buildable[j][i] !== '1') continue;
      const d = dist.get(cellKey(i, j, g));
      if (d !== undefined && d >= minDist && d <= maxDist) out.push([i, j]);
    }
  }
  return out;
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

  it('validateAll returns 1 when far_bed_s spread exceeds 10% across non-safe blueprints', () => {
    const a = pipeline.syntheticSafe('grid_a');
    const b = pipeline.syntheticSafe('grid_b');
    expect(a.bp.report!.errors).toEqual([]);

    const baseFarCells = Math.round((a.bp.report!.far_bed_s * config.WALK_SPEED) / config.CELL_M);
    const cap = Math.floor((config.MAX_FAR_BED_S * config.WALK_SPEED) / config.CELL_M) - 1; // stay under the 12s validity cap
    const farCells = farBuildableCells(b.bp, baseFarCells * 2, cap);
    expect(farCells).toHaveLength(3);
    b.bp.anchors.beds[0].cells = farCells;
    b.bp.report = anchors.validate(b.bp);
    expect(b.bp.report.errors).toEqual([]); // still individually valid
    const spread = (b.bp.report.far_bed_s - a.bp.report!.far_bed_s) / a.bp.report!.far_bed_s;
    expect(spread).toBeGreaterThan(0.10); // genuinely exceeds the 10% fairness threshold

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
