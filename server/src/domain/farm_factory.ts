/**
 * 新农场的初始状态。从 http/app.ts 的 buildFarmRow 抽出来，因为预置农场（domain/presets.ts）
 * 也要走同一条路——两处各写一份，第 0 章 Grant 迟早对不上。
 */
import type { Content } from './content.js';
import type { Ctx } from './reducer.js';
import { createInitialState, type FarmState } from './state.js';
import { playerDayId } from './time.js';

export function initialFarmState(
  content: Content, sets: Ctx['blueprint'], timezone: string, now: number,
): FarmState {
  const { cultivable, reserved } = sets;
  const state = createInitialState({
    player_day_id: playerDayId(now, timezone), field_condition: content.weather.script[0], now,
    wallet: content.economy.initial_wallet,
    bed_cells: [...cultivable].filter(x => !reserved.has(x)),
    reserved_cells: [...reserved],
  });
  // 第 0 章 Grant 在建场时发（不经过换日路径）。
  for (const [crop, n] of Object.entries(content.chapters.chapters[0].grants))
    if (!crop.startsWith('_')) state.inventory.seeds[crop as 'R'].bound += n ?? 0;
  state.chapters[0].grants_issued = true;
  return state;
}
