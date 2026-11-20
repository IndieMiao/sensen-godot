// TEMP (not committed): Lv1 and Lv3 copies of the cookreal shot base (443 farm exit shots).
import { readFileSync, writeFileSync } from 'node:fs';
import { loadP0Content } from '../src/p0/content.js';
import { plotCount } from '../src/p0/garden.js';
const c = loadP0Content();
const dir = '/Volumes/ACASIS/herdr-worktrees/sensen-godot/nezha-programer-wt/output/nezha-b2/shots/';
const base = JSON.parse(readFileSync(dir + 'cookreal.base.json', 'utf8'));
for (const level of [1, 3]) {
  const d = structuredClone(base);
  const s: any = Object.values(d)[0];
  s.homestead.level = level;
  const n = plotCount(c, s);
  s.plots = s.plots.slice(0, n);
  writeFileSync(dir + `lv${level}x.base.json`, JSON.stringify(d));
  console.log('level', level, 'plots', n);
}
