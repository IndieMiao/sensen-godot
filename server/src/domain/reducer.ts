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
import { materializeDay } from './handlers/day.js';
import { applyEconomy } from './handlers/economy.js';
import { applyFarming } from './handlers/farming.js';
import { applyResidents } from './handlers/residents.js';
import { applySettings } from './handlers/settings.js';
import type { FarmState } from './state.js';

export interface Ctx {
  now: number;
  timezone: string;
  content: Content;
  /** 蓝图约束：哪些格可耕、哪三格属预留畦。 */
  blueprint: { cultivable: Set<string>; reserved: Set<string> };
  derived: Derived;
}

export function makeCtx(
  s: FarmState, now: number, timezone: string, content: Content,
  blueprint: Ctx['blueprint'],
): Ctx {
  return { now, timezone, content, blueprint, derived: derive(s, now, timezone, content) };
}

export function apply(s: FarmState, cmd: Command, ctx: Ctx): Result<FarmState> {
  // 时钟单调守卫：正式农场由调用方 clamp 成 max(采样, last)，到这里只可能相等或前进。
  if (ctx.now < s.clock.last_effective_now) return err('CLOCK_REGRESSION');

  // 先把跨过的玩家日物化（换日、开章、发 Grant），再执行命令本身。
  const day = materializeDay(s, ctx);
  if (!day.ok) return day;
  const base = day.state;

  const farming = applyFarming(base, cmd, ctx);
  if (farming) return farming;
  const economy = applyEconomy(base, cmd, ctx);
  if (economy) return economy;
  const residents = applyResidents(base, cmd, ctx);
  if (residents) return residents;
  const settings = applySettings(base, cmd, ctx);
  if (settings) return settings;

  return err('NOT_AVAILABLE', `命令 ${cmd.type} 尚未实现（Task 5）`);
}

/** 便捷入口：调用方通常没有现成的 Derived。 */
export function applyAt(
  s: FarmState, cmd: Command, now: number, timezone: string, content: Content,
  blueprint: Ctx['blueprint'],
): Result<FarmState> {
  return apply(s, cmd, makeCtx(s, now, timezone, content, blueprint));
}

export type { FieldCondition };
