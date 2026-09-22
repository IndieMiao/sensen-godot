/**
 * 新农场的初始状态。从 http/app.ts 的 buildFarmRow 抽出来，因为预置农场（domain/presets.ts）
 * 也要走同一条路——两处各写一份，第 0 章 Grant 迟早对不上。
 */
import type { PlotLayout } from './plot.js';
import type { Content } from './content.js';
import type { Ctx } from './reducer.js';
import { createInitialState, type FarmState } from './state.js';
import { playerDayId } from './time.js';

export function initialFarmState(
  content: Content, _plot: PlotLayout, timezone: string, now: number,
): FarmState {
  // 开局一格未开垦：地面属性决定哪些格「能」开垦，玩家自己决定「要」开垦哪些。
  const state = createInitialState({
    player_day_id: playerDayId(now, timezone), field_condition: content.weather.script[0], now,
    wallet: content.economy.initial_wallet,
  });
  // 第 0 章 Grant 在建场时发（不经过换日路径）。
  for (const [crop, n] of Object.entries(content.chapters.chapters[0].grants))
    if (!crop.startsWith('_')) state.inventory.seeds[crop as 'R'].bound += n ?? 0;
  state.chapters[0].grants_issued = true;
  return state;
}
