/** CLI：build <id> [--refetch] | build-all [--refetch] | synthetic | validate-all | regions */
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import * as config from './config.js';
import * as pipeline from './pipeline.js';
import * as writer from './writer.js';
import * as anchors from './anchors.js';
import * as geos from './geos.js';
import type { Blueprint } from './types.js';

function shippedBlueprints(root: string): { file: string; bp: Blueprint }[] {
  if (!existsSync(root)) return [];
  const out: { file: string; bp: Blueprint }[] = [];
  for (const id of readdirSync(root)) {
    const dir = path.join(root, id);
    for (const rev of readdirSync(dir)) {
      const file = path.join(dir, rev, 'farm_blueprint.json');
      if (existsSync(file)) out.push({ file, bp: JSON.parse(readFileSync(file, 'utf8')) as Blueprint });
    }
  }
  return out;
}

export function validateAll(root: string = config.BLUEPRINTS_DIR): number {
  const reports: Record<string, ReturnType<typeof anchors.validate>> = {};
  for (const { file, bp } of shippedBlueprints(root)) {
    if (writer.checksum(bp) !== bp.checksum) { console.log(`CHECKSUM MISMATCH ${file}`); return 1; }
    const r = anchors.validate(bp);
    if (r.errors.length) { console.log(`INVALID ${file}: ${r.errors.join('; ')}`); return 1; }
    reports[bp.layout_patch_id] = r;
  }
  for (const key of ['far_bed_s', 'tour_s'] as const) {
    const vals = Object.entries(reports).filter(([id]) => !id.startsWith('safe')).map(([, r]) => r[key]);
    if (!vals.length) continue;
    const min = Math.min(...vals), max = Math.max(...vals);
    const spread = (max - min) / Math.max(min, 1e-9);
    console.log(`${key}: min=${min} max=${max} spread=${(spread * 100).toFixed(1)}%`);
    if (spread > 0.10) { console.log(`FAIRNESS FAIL on ${key}`); return 1; }
  }
  console.log(`OK ${Object.keys(reports).length} blueprints`);
  return 0;
}

export async function main(argv: string[]): Promise<number> {
  await geos.initGeos();
  const cmd = argv[0] ?? 'help';
  const refetch = argv.includes('--refetch');
  if (cmd === 'build') {
    const { bp, overlay } = await pipeline.buildCandidate(config.candidate(argv[1]), 1, refetch);
    console.log(JSON.stringify(bp.report));
    console.log(pipeline.buildAndWrite(bp, overlay, config.BLUEPRINTS_DIR));
    return 0;
  }
  if (cmd === 'build-all') {
    let failed = false;
    for (const cand of config.loadCandidates()) {
      try {
        const { bp, overlay } = await pipeline.buildCandidate(cand, 1, refetch);
        console.log(cand.layoutPatchId, JSON.stringify(bp.report));
        pipeline.buildAndWrite(bp, overlay, config.BLUEPRINTS_DIR);
      } catch (err) {
        failed = true;
        console.log(`FAILED ${cand.layoutPatchId}: ${err instanceof Error ? err.message : String(err)}`);
      }
    }
    return failed ? 1 : 0;
  }
  if (cmd === 'synthetic') {
    const { bp, overlay } = pipeline.syntheticSafe();
    console.log(pipeline.buildAndWrite(bp, overlay, config.BLUEPRINTS_DIR));
    return 0;
  }
  if (cmd === 'validate-all') return validateAll();
  if (cmd === 'regions') {
    const byRegion: Record<string, writer.ShippedCandidate[]> = {};
    for (const cand of config.loadCandidates()) {
      if (existsSync(path.join(config.BLUEPRINTS_DIR, cand.layoutPatchId, 'r1', 'farm_blueprint.json')))
        (byRegion[cand.regionId] ??= []).push({ layout_patch_id: cand.layoutPatchId, revision: 1, name: cand.name });
    }
    writer.writeRegions(config.loadRegions(), byRegion, config.REGIONS_OUT);
    console.log(config.REGIONS_OUT);
    return 0;
  }
  console.log('usage: pnpm cli build <id> [--refetch] | build-all [--refetch] | synthetic | validate-all | regions');
  return 2;
}

// 只有作为入口脚本直接运行时才执行（`pnpm cli ...` / `tsx src/cli.ts ...`），import 本模块做测试时不会触发。
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2)).then(code => process.exit(code), err => { console.error(err); process.exit(1); });
}
