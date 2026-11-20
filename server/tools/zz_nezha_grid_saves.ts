// TEMP (not committed): two saves for the 355 b1 grid shots — a new player (8 beds) and Lv17 (41 beds + 10 trees + 12 sprinklers).
import { writeFileSync } from 'node:fs';
import { loadP0Content } from '../src/p0/content.js';
import { freshState } from '../src/p0/state.js';
import { addPlots, plotCount } from '../src/p0/garden.js';
const c = loadP0Content();
const now = Date.now(), H = 3_600_000;
const out = (name: string, s: unknown) => writeFileSync(`/Volumes/ACASIS/herdr-worktrees/sensen-godot/nezha-programer-wt/output/nezha-341-meal/srv/${name}.json`, JSON.stringify({ 'p0-shot-nezha': s }));
const fresh = freshState(c, 'p0-shot-nezha', now, 7);
fresh.travel.pending = false;
console.log('new player plots', fresh.plots.length, plotCount(c, fresh));
out('grid_lv1', fresh);
const guided = freshState(c, 'p0-shot-nezha', now, 7, { guide: true });
guided.travel.pending = false;
console.log('guided new player plots', guided.plots.length, 'guide step', guided.guide?.step);
out('grid_lv1_guide', guided);
const s = freshState(c, 'p0-shot-nezha', now, 7);
s.travel.pending = false;
s.homestead.level = 17;
s.energy = { value: 300, tick_ms: now };
const grid = c.garden.plots;
const at = (col: number, row: number) => grid.findIndex(([x, y]) => x === col && y === row);
const sprinklers = [[0, 3], [3, 3], [6, 3], [1, 1], [4, 1], [7, 1], [0, -1], [3, -1], [6, -1], [2, 0], [5, 0], [-1, 1]].map(([x, y]) => at(x, y));
const trees = [[-1, -2], [0, -2], [1, -2], [2, -2], [3, -2], [4, -2], [5, -2], [6, -2], [7, -2], [-1, -1]].map(([x, y]) => at(x, y));
if (sprinklers.includes(-1) || trees.includes(-1)) throw new Error('bad cell');
s.facilities = sprinklers.map((plot, i) => ({ id: i + 1, kind: 'sprinkler', plot, under: 'tilled' as const }));
const crops = ['crop_radish', 'crop_lettuce', 'crop_carrot', 'crop_potato', 'crop_tomato', 'crop_cabbage'];
s.plots = grid.map((_, id) => {
  if (trees.includes(id)) return { id, state: 'growing' as const, crop: 'crop_apple', ready_at: now + 30 * H, picks: 1, xp_pct: 100 };
  if (sprinklers.includes(id)) return { id, state: 'tilled' as const };
  return { id, state: 'growing' as const, crop: crops[id % crops.length], ready_at: now + ((id * 7) % 20) * H, xp_pct: 100 };
});
addPlots(c, s);
console.log('lv17 open', plotCount(c, s), 'plots', s.plots.length, 'annuals', s.plots.filter(p => p.crop && p.crop !== 'crop_apple').length);
out('grid_lv17', s);

// #624 walkthrough (不知火舞): a Lv1 field full of annuals with a ninth bed open and empty (a tree chopped), Farming Lv8
// saves for the greenhouse at Lv12 (30 beds: no whole 4×4 yet) and Lv13 (32 beds, an apple tree inside the middle block).
const full = freshState(c, 'p0-shot-nezha', now, 7);
full.travel.pending = false;
full.plots = Array.from({ length: 9 }, (_, id) => id < 8
  ? { id, state: 'growing' as const, crop: 'crop_lettuce', ready_at: now + 5 * H, xp_pct: 100 }
  : { id, state: 'tilled' as const });
console.log('full open', plotCount(c, full));
out('grid_lv1_full', full);
const grower = (level: number) => {
  const g = freshState(c, 'p0-shot-nezha', now, 7);
  g.travel.pending = false;
  g.homestead.level = level;
  g.skills.farming = c.skills.farming[7];
  g.coins = 1000;
  g.storage = { wood: 40, stone: 30, copper_ore: 20 };
  g.energy = { value: 250, tick_ms: now };
  g.plots = [];
  addPlots(c, g);
  return g;
};
const g12 = grower(12);
console.log('lv12 open', plotCount(c, g12));
out('grid_gh12', g12);
const g13 = grower(13);
const t = at(3, 2);
g13.plots[t] = { id: t, state: 'growing' as const, crop: 'crop_apple', ready_at: now + 30 * H, picks: 1, xp_pct: 100 };
addPlots(c, g13);
console.log('lv13 open', plotCount(c, g13), 'tree at', t);
out('grid_gh13', g13);
