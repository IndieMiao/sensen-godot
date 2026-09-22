import { mainHandStats } from '../../src/domain/character.js';
import { DateTime } from 'luxon';
import { DEFAULT_CONTENT_DIR, loadContent } from '../../src/domain/content.js';
import type { Command } from '../../src/domain/commands.js';
import { applyAt, type Ctx } from '../../src/domain/reducer.js';
import { issueChapterZeroGrants, materializeDay } from '../../src/domain/handlers/day.js';
import { makeCtx } from '../../src/domain/reducer.js';
import { createInitialState, type FarmState } from '../../src/domain/state.js';
import type { Result } from '../../src/domain/errors.js';
import { ensureBag, reconcileBagChanges } from '../../src/domain/bag.js';
import { isTillable, loadPlot, type PlotLayout } from '../../src/domain/plot.js';

export const content = loadContent(DEFAULT_CONTENT_DIR);
export const SH = 'Asia/Shanghai';
export const at = (iso: string) => DateTime.fromISO(iso, { setZone: true }).toMillis();
export const T0 = at('2026-09-04T10:00:00+08:00');
export const HOUR = 3600_000;

/** 真实的农场地面布局；开垦与放置的合法性都由它判定。 */
export const plot: PlotLayout = loadPlot(content.farm_plot);

/** 一小片连续可开垦格，用来代替过去写死的 9 格三畦。 */
export function soilCells(count: number): string[] {
  const out: string[] = [];
  for (let j = 0; j < plot.gy && out.length < count; j++)
    for (let i = 0; i < plot.gx && out.length < count; i++)
      if (isTillable(plot, `${i},${j}`)) out.push(`${i},${j}`);
  return out;
}

/** 默认工作面：9 格可开垦的地（取代过去写死的三条田畦）。 */
export const BEDS = soilCells(9);
/** 扩地路线用的额外三格；过去是「预留畦」，现在只是另外三块随便开的地。 */
export const EXTRA_SOIL = soilCells(12).slice(9);

/** 建场后的初始状态，含第 0 章 Grant。cells 开局为空——地由玩家自己开。 */
export function freshFarm(now = T0): FarmState {
  const s = createInitialState({
    player_day_id: '2026-09-04', field_condition: content.weather.script[0], now,
    wallet: content.economy.initial_wallet,
  });
  return issueChapterZeroGrants(s, makeCtx(s, now, SH, content, plot));
}

/** Ordinary fixture actions include time to gather. Pass realNow explicitly for timing/abuse tests. */
export const run = (s: FarmState, cmd: Command, now = T0, realNow?: number): Result<FarmState> => {
  const hand = mainHandStats(s, content);
  const collection = ['harvest_cells', 'collect_resource', 'harvest_journey_discovery', 'mine_rock'].includes(cmd.type);
  const work = 1000 / Math.min(hand.crop_power, hand.ore_power, hand.wood_power) * ('cell_ids' in cmd ? cmd.cell_ids.length : 1);
  return applyAt(s, cmd, now, SH, content, plot, realNow ?? (collection ? Math.max(now, (s.character?.last_gather_at ?? -Infinity) + work + 1) : now));
};

/** Explicit fixture editing keeps the bag authoritative, including after earlier real commands. */
export function editInventory(state: FarmState, edit: (draft: FarmState) => void): void {
  const before = structuredClone(state);
  ensureBag(before, content);
  const draft = structuredClone(before);
  edit(draft);
  const result = reconcileBagChanges(before, draft, content, true);
  if (!result.ok) throw new Error(`Inventory fixture failed: ${result.code}`);
  Object.assign(state, result.state);
}

/** 依次执行；任一条失败就抛，测试里不用每步判 ok。 */
export function runAll(s: FarmState, steps: [Command, number?][], base = T0): FarmState {
  let cur = s;
  for (const [cmd, now] of steps) {
    const r = run(cur, cmd, now ?? base);
    if (!r.ok) throw new Error(`${cmd.type} 失败: ${r.code} ${r.detail ?? ''}`);
    cur = r.state;
  }
  return cur;
}

/** 把状态推进到某个时刻并物化玩家日（不执行任何命令）。 */
export function advance(s: FarmState, now: number): FarmState {
  const r = materializeDay(s, makeCtx(s, now, SH, content, plot));
  return r.state;
}
