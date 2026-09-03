/** CLI：build <id> [--refetch] | build-all [--refetch] | synthetic | validate-all | regions */
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import * as config from './config.js';
import * as pipeline from './pipeline.js';
import * as writer from './writer.js';
import * as anchors from './anchors.js';
import * as geos from './geos.js';
import type { Blueprint } from './types.js';

function shippedBlueprints(): { file: string; bp: Blueprint }[] {
  if (!existsSync(config.BLUEPRINTS_DIR)) return [];
  const out: { file: string; bp: Blueprint }[] = [];
  for (const id of readdirSync(config.BLUEPRINTS_DIR)) {
    const dir = path.join(config.BLUEPRINTS_DIR, id);
    for (const rev of readdirSync(dir)) {
      const file = path.join(dir, rev, 'farm_blueprint.json');
      if (existsSync(file)) out.push({ file, bp: JSON.parse(readFileSync(file, 'utf8')) as Blueprint });
    }
  }
  return out;
}

function validateAll(): number {
  const reports: Record<string, ReturnType<typeof anchors.validate>> = {};
  for (const { file, bp } of shippedBlueprints()) {
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

async function main(argv: string[]): Promise<number> {
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
    for (const cand of config.loadCandidates()) {
      const { bp, overlay } = await pipeline.buildCandidate(cand, 1, refetch);
      console.log(cand.layoutPatchId, JSON.stringify(bp.report));
      pipeline.buildAndWrite(bp, overlay, config.BLUEPRINTS_DIR);
    }
    return 0;
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

main(process.argv.slice(2)).then(code => process.exit(code), err => { console.error(err); process.exit(1); });
