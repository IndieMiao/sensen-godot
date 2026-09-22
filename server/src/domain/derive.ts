/**
 * 从状态与时间派生出「现在应该是什么样」，**不修改状态**。
 *
 * 成熟是派生的：`cells` 里没有 `ripe` 状态，收获判定用 `ready_at <= now`。原设计让照料
 * 只写 `ready_at`、收获却要求状态已是 `ripe`，中间没有任何东西负责这次转换，作物会永久
 * 停在 `growing`（Codex 二审 Critical 2）。
 *
 * 读路径（GET /farms/me）用 derive 但**不落库、不改版本**；写路径在拿到行锁后采样一次
 * `effectiveNow`，同一个值贯穿 derive 与 reducer（Codex 三审 C2）。
 */
import type { Content, FieldCondition } from './content.js';
import type { FarmState } from './state.js';
import { daysBetween, nextDayStartMs, playerDayId } from './time.js';

export interface Derived {
  player_day_id: string;
  /** 跨过的玩家日数 > 0 时需要 materializeDay。 */
  days_elapsed: number;
  weather_day_index: number;
  field_condition: FieldCondition;
  /** 下一章索引；只有上一章 done 且未到 6 时才前进。 */
  chapter_index: number;
  opens_new_chapter: boolean;
  next_chapter_opens_at: number | null;
  ripe_cells: string[];
}

/** 田况按 weather_day_index 循环——章节冻结在 6 之后天气仍要继续（Codex 三审 N-I2）。 */
export function conditionFor(weatherDayIndex: number, script: FieldCondition[]): FieldCondition {
  return script[((weatherDayIndex % script.length) + script.length) % script.length];
}

export function derive(s: FarmState, now: number, timezone: string, c: Content): Derived {
  const day = playerDayId(now, timezone);
  const elapsed = Math.max(0, daysBetween(s.clock.player_day_id, day));
  const weatherIndex = s.clock.weather_day_index + elapsed;
  const lastChapter = c.chapters.chapters.length - 1;
  const prevDone = s.chapters[s.clock.chapter_index]?.status === 'done';
  // 每个玩家日最多激活一个新章节（PRD §9.1 L667）；漏一天后继续未完成章节，不跳章。
  const activatedDay = s.chapters[s.clock.chapter_index]?.activated_day ?? s.clock.player_day_id;
  const opens = !s.journey && prevDone && activatedDay < day && s.clock.chapter_index < lastChapter;
  const ripe: string[] = [];
  for (const [id, cell] of Object.entries(s.cells))
    if (cell && cell.state === 'growing' && cell.ready_at !== null && cell.ready_at <= now) ripe.push(id);
  return {
    player_day_id: day,
    days_elapsed: elapsed,
    weather_day_index: weatherIndex,
    field_condition: elapsed > 0
      ? (s.qa?.weather?.[String(weatherIndex)] ?? conditionFor(weatherIndex, c.weather.script))
      : (s.qa?.weather?.[String(s.clock.weather_day_index)] ?? s.clock.field_condition),
    chapter_index: opens ? s.clock.chapter_index + 1 : s.clock.chapter_index,
    opens_new_chapter: opens,
    next_chapter_opens_at: !s.journey && prevDone && !opens && s.clock.chapter_index < lastChapter
      ? nextDayStartMs(now, timezone) : null,
    ripe_cells: ripe.sort(),
  };
}
