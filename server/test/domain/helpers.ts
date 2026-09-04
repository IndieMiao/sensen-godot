import { DateTime } from 'luxon';
import { DEFAULT_CONTENT_DIR, loadContent } from '../../src/domain/content.js';
import type { Command } from '../../src/domain/commands.js';
import { applyAt, type Ctx } from '../../src/domain/reducer.js';
import { issueChapterZeroGrants, materializeDay } from '../../src/domain/handlers/day.js';
import { makeCtx } from '../../src/domain/reducer.js';
import { createInitialState, type FarmState } from '../../src/domain/state.js';
import type { Result } from '../../src/domain/errors.js';

export const content = loadContent(DEFAULT_CONTENT_DIR);
export const SH = 'Asia/Shanghai';
export const at = (iso: string) => DateTime.fromISO(iso, { setZone: true }).toMillis();
export const T0 = at('2026-09-04T10:00:00+08:00');
export const HOUR = 3600_000;

export const BEDS = ['1,1', '2,1', '3,1', '1,2', '2,2', '3,2', '1,3', '2,3', '3,3'];
export const RESERVED = ['5,1', '6,1', '7,1'];

export const blueprint: Ctx['blueprint'] = {
  cultivable: new Set([...BEDS, ...RESERVED]),
  reserved: new Set(RESERVED),
};

/** 建场后的初始状态，含第 0 章 Grant（6R 教学 + 3L）。 */
export function freshFarm(now = T0): FarmState {
  const s = createInitialState({
    player_day_id: '2026-09-04', field_condition: content.weather.script[0], now,
    wallet: content.economy.initial_wallet, bed_cells: BEDS, reserved_cells: RESERVED,
  });
  return issueChapterZeroGrants(s, makeCtx(s, now, SH, content, blueprint));
}

export const run = (s: FarmState, cmd: Command, now = T0): Result<FarmState> =>
  applyAt(s, cmd, now, SH, content, blueprint);

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
  const r = materializeDay(s, makeCtx(s, now, SH, content, blueprint));
  return r.state;
}
