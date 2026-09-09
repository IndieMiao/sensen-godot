/**
 * 纯函数 reducer：`(state, command, ctx) -> Ok | Err`。**唯一算数的地方**。
 *
 * 三条硬约束：
 *   1. 不做 IO、不读 `Date.now()`、不读环境变量。时间由 ctx 注入，且是调用方在拿到行锁
 *      后采样的同一个值（spec §7.3）。
 *   2. 失败即整体丢弃：返回 Err 时调用方不写任何状态改动，所以 handler 可以放心地在
 *      副本上边改边校验。
 *   3. 数值只从 ctx.content 取，代码里不写游戏数值字面量。
 */
import type { Content, FieldCondition } from './content.js';
import type { Command } from './commands.js';
import { derive, type Derived } from './derive.js';
import { err, ok, type Result } from './errors.js';
import { applyEconomy } from './handlers/economy.js';
import { applyDecorations } from './handlers/decorations.js';
import { applyFarming } from './handlers/farming.js';
import { applyResidents } from './handlers/residents.js';
import { applyQa } from './handlers/qa.js';
import { applySettings } from './handlers/settings.js';
import type { FarmState } from './state.js';
import { projectFarmState, recordChapterProgress } from './progress.js';
import { applyJourney, journeyContent } from './journey.js';

export interface Ctx {
  /** **有效**时间（QA 变换之后）；一切派生量都吃它。 */
  now: number;
  /** 真实墙钟。只有 QA 命令用它重新锚定倍率——用有效时间锚定会自我放大。 */
  realNow?: number;
  timezone: string;
  content: Content;
  /** 蓝图约束：哪些格可耕、哪三格属预留畦。 */
  blueprint: { cultivable: Set<string>; reserved: Set<string> };
  derived: Derived;
}

export function makeCtx(
  s: FarmState, now: number, timezone: string, content: Content,
  blueprint: Ctx['blueprint'], realNow?: number,
): Ctx {
  return {
    now, realNow: realNow ?? now, timezone, content: journeyContent(s, content), blueprint,
    derived: derive(s, now, timezone, content),
  };
}

export function apply(s: FarmState, cmd: Command, ctx: Ctx): Result<FarmState> {
  // 时钟单调守卫：正式农场由调用方 clamp 成 max(采样, last)，到这里只可能相等或前进。
  if (ctx.now < s.clock.last_effective_now) return err('CLOCK_REGRESSION');

  // 先把跨过的玩家日物化（换日、开章、发 Grant），再执行命令本身。
  const base = projectFarmState(s, ctx.now, ctx.timezone, ctx.content, ctx.blueprint);
  const currentCtx = { ...ctx, content: journeyContent(base, ctx.content), derived: derive(base, ctx.now, ctx.timezone, ctx.content) };
  for (const handler of [applyJourney, applyFarming, applyEconomy, applyResidents, applyDecorations, applySettings, applyQa]) {
    const result = handler(base, cmd, currentCtx);
    if (!result) continue;
    if (!result.ok) return result;
    const progressed = recordChapterProgress(base, result.state, cmd, currentCtx);
    const next = projectFarmState(progressed, ctx.now, ctx.timezone, ctx.content, ctx.blueprint);
    const completed = next.handbook.filter(entry => entry.kind === 'chapter_done'
      && !s.handbook.some(old => old.kind === entry.kind && old.key === entry.key));
    const milestones = next.journey?.completed.filter(id => !s.journey?.completed.includes(id)) ?? [];
    return ok(next, [...result.events, ...completed.map(entry => ({ type: 'chapter_done', chapter: Number(entry.key) })),
      ...milestones.map(id => ({ type: 'milestone_unlocked', id }))]);
  }

  return err('NOT_AVAILABLE', `命令 ${cmd.type} 尚未实现（Task 5）`);
}

/** 便捷入口：调用方通常没有现成的 Derived。 */
export function applyAt(
  s: FarmState, cmd: Command, now: number, timezone: string, content: Content,
  blueprint: Ctx['blueprint'], realNow?: number,
): Result<FarmState> {
  return apply(s, cmd, makeCtx(s, now, timezone, content, blueprint, realNow));
}

export type { FieldCondition };
