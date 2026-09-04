/**
 * QA 时钟：只在白名单农场上生效的时间变换。
 *
 * 服务端的一切派生量都吃 `now`，所以加速时间**不能靠客户端本地跑快**——那样客户端会
 * 看到作物熟了、服务端却说没熟。正确做法是把变换放在服务端唯一的时间入口：真实时间
 * 先经 `effectiveNow` 变换，再喂给 derive 与 reducer。
 *
 * 变换是分段线性的：每次改倍率就重新锚定一次，所以历史时间不会被追溯性拉伸，
 * 有效时间也永远不会倒退（`clock.last_effective_now` 的单调守卫因此仍然成立）。
 */
import type { FieldCondition } from './content.js';

export interface QaClock {
  /** 倍率；1 = 正常。改倍率时重新锚定。 */
  scale: number;
  /** 锚点：这一刻的真实时间与有效时间。 */
  anchor_real: number;
  anchor_effective: number;
  /** qa_skip_days 累积的跳跃量（毫秒）。 */
  offset_ms: number;
  /** 天气覆写：weather_day_index → 田况。 */
  weather: Record<string, FieldCondition>;
}

export const DAY_MS = 24 * 3600_000;
/** 倍率上限：再高就会让一次请求跨过几十个玩家日，materializeDay 要循环很久。 */
export const MAX_SCALE = 1440;

export function initialQa(now: number): QaClock {
  return { scale: 1, anchor_real: now, anchor_effective: now, offset_ms: 0, weather: {} };
}

/** 缺字段的老农场按「未加速」补齐，不用改库。 */
export function normalizeQa(q: Partial<QaClock> | undefined, now: number): QaClock {
  const base = initialQa(now);
  if (!q) return base;
  return {
    scale: typeof q.scale === 'number' && q.scale > 0 ? q.scale : base.scale,
    anchor_real: typeof q.anchor_real === 'number' ? q.anchor_real : base.anchor_real,
    anchor_effective: typeof q.anchor_effective === 'number' ? q.anchor_effective : base.anchor_effective,
    offset_ms: typeof q.offset_ms === 'number' ? q.offset_ms : 0,
    weather: q.weather ?? {},
  };
}

/** 真实时间 → 有效时间。正式农场（scale=1、offset=0）下是恒等变换。 */
export function effectiveNow(q: QaClock | undefined, realNow: number): number {
  if (!q) return realNow;
  const c = normalizeQa(q, realNow);
  return Math.round(c.anchor_effective + (realNow - c.anchor_real) * c.scale) + c.offset_ms;
}

/** 改倍率：先把当前有效时间钉成新锚点，再换倍率——否则已经过去的时间会被追溯拉伸。 */
export function reanchor(q: QaClock, realNow: number, scale: number): QaClock {
  const c = normalizeQa(q, realNow);
  return { ...c, anchor_real: realNow, anchor_effective: effectiveNow(c, realNow) - c.offset_ms, scale };
}
