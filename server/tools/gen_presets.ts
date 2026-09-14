/**
 * 生成随包兜底快照 assets/farm/presets/<layout>.json（PRD §11.2：远端不可用时自动用本地快照）。
 * 用与线上播种**同一个** buildPresetFarm，所以 farm_id 与线上那座一致。
 * 时间固定，文件可复现——重跑不产生无意义的 diff。
 *   node_modules/.bin/tsx tools/gen_presets.ts
 */
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { DEFAULT_CONTENT_DIR, loadContent } from '../src/domain/content.js';
import { derive } from '../src/domain/derive.js';
import { PRESET_SPECS, buildPresetFarm } from '../src/domain/presets.js';
import { blueprintSets, loadBlueprint } from '../src/http/app.js';
import { snapshotSlot, visitorSnapshot } from '../src/http/dto.js';
import { at } from '../test/domain/helpers.js';

const ROOT = path.resolve(DEFAULT_CONTENT_DIR, '..', '..', '..');
const content = loadContent(DEFAULT_CONTENT_DIR);
type Regions = { regions: { id: string; timezone: string }[] };
const regions: Regions = JSON.parse(readFileSync(path.join(DEFAULT_CONTENT_DIR, 'regions.json'), 'utf8'));
const OUT = path.join(ROOT, 'assets', 'farm', 'presets');
mkdirSync(OUT, { recursive: true });

// 建在 10:00，快照取 16:00：萝卜（4 小时）已熟、生菜（8 小时）还在长——繁茂那座一眼有层次。
const T_BUILD = at('2026-09-04T10:00:00+08:00');
const T_SNAP = T_BUILD + 6 * 3600_000;

for (const spec of PRESET_SPECS) {
  const bp = loadBlueprint(path.join(ROOT, 'assets', 'blueprints'), spec.layout, spec.revision);
  if (!bp) throw new Error(`蓝图 ${spec.layout} r${spec.revision} 校验失败`);
  const tz = regions.regions.find(r => r.id === spec.region)!.timezone;
  const farm = buildPresetFarm(spec, blueprintSets(bp), content, tz, T_BUILD);
  const snap = visitorSnapshot(farm, derive(farm.state, T_SNAP, tz, content), 1, snapshotSlot(T_SNAP), [], spec.avatar_ref);
  const file = path.join(OUT, `${spec.id ?? spec.layout}.json`);
  writeFileSync(file, JSON.stringify(snap, null, 2) + '\n');
  const ripe = snap.cells.filter(c => c.ripe).length;
  const growing = snap.cells.filter(c => c.state === 'growing').length;
  console.log(`${spec.layout} (${spec.style}) → ${path.relative(ROOT, file)}  growing=${growing} ripe=${ripe} farm_id=${snap.farm_id}`);
}
