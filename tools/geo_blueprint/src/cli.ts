/** CLI：build <id> [--refetch] | build-all [--refetch] | synthetic | validate-all | regions */
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import * as core from 'blueprint-core';
import * as config from './config.js';
import * as pipeline from './pipeline.js';
import * as writer from './writer.js';
import * as anchors from './anchors.js';
import * as geos from './geos.js';
import type { Blueprint } from './types.js';

/**
 * 列出要校验的蓝图。**只看每个 id 的最高 revision**：revision 不可变（PRD §4.5），
 * 旧 revision 是历史存档，用的是当时的 canonical 文法，拿今天的公式去校验必然不匹配。
 * 2026-09-04 canonical 收紧后 r1 就落在这一类里——它不是坏数据，只是不再是当前契约。
 */
function shippedBlueprints(root: string): { file: string; bp: Blueprint }[] {
  if (!existsSync(root)) return [];
  const out: { file: string; bp: Blueprint }[] = [];
  for (const id of readdirSync(root)) {
    const dir = path.join(root, id);
    if (!statSync(dir).isDirectory()) continue;
    const revs = readdirSync(dir)
      .map(r => ({ name: r, n: Number(/^r(\d+)$/.exec(r)?.[1] ?? NaN) }))
      .filter(r => Number.isInteger(r.n))
      .sort((a, b) => b.n - a.n);
    for (const rev of revs.slice(0, 1)) {
      const file = path.join(dir, rev.name, 'farm_blueprint.json');
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
  // 公平门槛是绝对秒数（2026-09-04 决策③）。r1 用的是相对差值 + 一个掺了 18 秒常数动作
  // 时间的 tour_s：常数取 18 时算出 6.8% 过线，取 0（纯步行）时算出 29% 不过线——同一批
  // 蓝图换个常数就在过线与不过线之间跳，衡量不了任何东西。far_bed 的相对差值更是结构性
  // 恒为 0（选畦永远优先离出生点最近的三条）。现在只看玩家真能感知的绝对秒数，并且把
  // 第四畦（扩地路线的 12 格）一起纳入——r1 的指标完全看不到它。
  const shipped = Object.entries(reports).filter(([id]) => !id.startsWith('safe'));
  for (const key of ['walk_tour_9_s', 'walk_tour_12_s'] as const) {
    const vals = shipped.map(([, r]) => r[key]);
    if (!vals.length) continue;
    const spread = core.spreadSeconds(vals);
    console.log(`${key}: min=${Math.min(...vals)} max=${Math.max(...vals)} spread=${spread.toFixed(2)}s`);
    if (spread > core.MAX_WALK_TOUR_SPREAD_S) {
      console.log(`FAIRNESS FAIL on ${key}: ${spread.toFixed(2)}s > ${core.MAX_WALK_TOUR_SPREAD_S}s`);
      return 1;
    }
  }
  for (const [id, r] of shipped) console.log(`${id}: far9=${r.far_bed_9_s}s far12=${r.far_bed_12_s}s tour=${r.tour_s}s`);
  console.log(`OK ${Object.keys(reports).length} blueprints`);
  return 0;
}

export async function main(argv: string[]): Promise<number> {
  await geos.initGeos();
  const cmd = argv[0] ?? 'help';
  const refetch = argv.includes('--refetch');
  // r1 已出货且 revision 不可变（PRD §4.5）：canonical 收紧后不能原地改写 r1 的 checksum，
  // 只能出新 revision。--revision 2 从同一份 cache 重出，几何完全不变。
  const revIdx = argv.indexOf('--revision');
  const revision = revIdx >= 0 ? Number(argv[revIdx + 1]) : 1;
  if (!Number.isInteger(revision) || revision < 1) { console.log('--revision 必须是正整数'); return 2; }
  if (cmd === 'build') {
    const { bp, overlay } = await pipeline.buildCandidate(config.candidate(argv[1]), revision, refetch);
    console.log(JSON.stringify(bp.report));
    console.log(pipeline.buildAndWrite(bp, overlay, config.BLUEPRINTS_DIR));
    return 0;
  }
  if (cmd === 'build-all') {
    let failed = false;
    for (const cand of config.loadCandidates()) {
      try {
        const { bp, overlay } = await pipeline.buildCandidate(cand, revision, refetch);
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
    const { bp, overlay } = pipeline.syntheticSafe('safe_grid', revision);
    console.log(pipeline.buildAndWrite(bp, overlay, config.BLUEPRINTS_DIR));
    return 0;
  }
  if (cmd === 'validate-all') return validateAll();
  if (cmd === 'regions') {
    const byRegion: Record<string, writer.ShippedCandidate[]> = {};
    for (const cand of config.loadCandidates()) {
      if (existsSync(path.join(config.BLUEPRINTS_DIR, cand.layoutPatchId, `r${revision}`, 'farm_blueprint.json')))
        (byRegion[cand.regionId] ??= []).push({ layout_patch_id: cand.layoutPatchId, revision, name: cand.name });
    }
    writer.writeRegions(config.loadRegions(), byRegion, config.REGIONS_OUT);
    console.log(config.REGIONS_OUT);
    return 0;
  }
  console.log('usage: pnpm cli build <id> [--refetch] [--revision N] | build-all [--refetch] [--revision N] | synthetic [--revision N] | validate-all | regions [--revision N]');
  return 2;
}

// 只有作为入口脚本直接运行时才执行（`pnpm cli ...` / `tsx src/cli.ts ...`），import 本模块做测试时不会触发。
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2)).then(code => process.exit(code), err => { console.error(err); process.exit(1); });
}
