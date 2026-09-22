/**
 * 导演模式命令。只有白名单玩家能发（HTTP 层 403 拦截），这里只管语义。
 *
 * 三条都**改的是服务端时间**，不是客户端时间：客户端本地跑快会看到作物熟了、
 * 服务端却说没熟。
 */
import type { Command } from '../commands.js';
import { FIELD_CONDITIONS, type FieldCondition } from '../content.js';
import { err, ok, type Result } from '../errors.js';
import type { Ctx } from '../reducer.js';
import type { FarmState } from '../state.js';
import { DAY_MS, MAX_SCALE, normalizeQa, reanchor } from '../qa.js';

export function applyQa(s: FarmState, cmd: Command, ctx: Ctx): Result<FarmState> | null {
  switch (cmd.type) {
    case 'qa_set_clock': {
      if (!Number.isFinite(cmd.scale) || cmd.scale <= 0 || cmd.scale > MAX_SCALE)
        return err('BAD_QA_PARAM', `倍率须在 (0, ${MAX_SCALE}]`);
      const next = structuredClone(s);
      next.qa = reanchor(normalizeQa(next.qa, ctx.realNow ?? ctx.now), ctx.realNow ?? ctx.now, cmd.scale);
      return ok(next, [{ type: 'qa_clock', scale: cmd.scale }]);
    }

    case 'qa_skip_days': {
      if (!Number.isInteger(cmd.days) || cmd.days < 1 || cmd.days > 30)
        return err('BAD_QA_PARAM', 'days 须是 1..30 的整数');
      const next = structuredClone(s);
      const q = normalizeQa(next.qa, ctx.realNow ?? ctx.now);
      // 只往前跳：回拨会撞上 clock.last_effective_now 的单调守卫，且会让已发的
      // Grant 与已结的摊位日凭空复活。
      next.qa = { ...q, offset_ms: q.offset_ms + cmd.days * DAY_MS };
      return ok(next, [{ type: 'qa_skip', days: cmd.days }]);
    }

    case 'qa_set_weather': {
      const next = structuredClone(s);
      const q = normalizeQa(next.qa, ctx.realNow ?? ctx.now);
      const allowed = new Set<string>(FIELD_CONDITIONS);
      const weather: Record<string, FieldCondition> = { ...q.weather };
      for (const [k, v] of Object.entries(cmd.overrides)) {
        if (!/^\d+$/.test(k)) return err('BAD_QA_PARAM', `天气覆写的键须是天气日索引：${k}`);
        if (!allowed.has(v)) return err('BAD_QA_PARAM', `未知田况 ${v}`);
        weather[k] = v as FieldCondition;
      }
      next.qa = { ...q, weather };
      return ok(next, [{ type: 'qa_weather', count: Object.keys(cmd.overrides).length }]);
    }

    default:
      return null;
  }
}
