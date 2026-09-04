/**
 * 玩家日物化：换日、开新章、发章节 Grant。
 *
 * **顺序是有意义的，不能重排**（Codex 二审 N-C1）。库存里的绑定种子只按作物聚合存
 * （`seeds[crop].bound`），分不清「上一章剩下的」和「本章刚发的」。若写成「发 Grant →
 * 清 bound」，D6 刚发的 C/H/L 各 1 会被同一步清掉，玩家得多花 24 金币补买，钱包变成
 * 281、账户价值 521，PRD §7.5 的 305/545 全错。
 *
 * 正确顺序：
 *   1. 推进时钟（player_day_id / weather_day_index / field_condition）
 *   2. 只在**真正开新章**时：先清空全部 bound → 开章 → 发本章 Grant
 *   3. 不开新章时不动 bound——漏一天不该惩罚玩家（PRD L665 不跳章不作废）
 *
 * `chapters[n].grants_issued` 是 Grant 的幂等键：同一章重复物化不会重复发放。
 */
import type { CropId } from '../content.js';
import { ok, type Ok } from '../errors.js';
import type { Ctx } from '../reducer.js';
import type { FarmState } from '../state.js';

export function materializeDay(s: FarmState, ctx: Ctx): Ok<FarmState> {
  const d = ctx.derived;
  if (d.days_elapsed === 0 && !d.opens_new_chapter) return ok(s);

  const next: FarmState = structuredClone(s);
  next.clock.player_day_id = d.player_day_id;
  next.clock.weather_day_index = d.weather_day_index;
  next.clock.field_condition = d.field_condition;

  // 每日额度按玩家日重置（PRD §6.4 L431 摊位、L534 回购箱）。
  next.stall = { day: d.player_day_id, settled: 0 };
  next.buyback = { ...next.buyback, day: d.player_day_id, sold: 0 }; // week_total 跨日累计
  next.xp.harvest_counted = { day: d.player_day_id, plants: 0 };

  if (d.opens_new_chapter) {
    // 1. 先清：绑定种子是一次性剧情 Grant，不能跨章囤积（PRD §7.5 L526）。
    for (const id of Object.keys(next.inventory.seeds) as CropId[])
      next.inventory.seeds[id].bound = 0;
    // 2. 再开章。
    const idx = d.chapter_index;
    next.clock.chapter_index = idx;
    next.chapters[idx].status = 'active';
    next.chapters[idx].activated_day = d.player_day_id;
    // 3. 最后发本章 Grant——顺序颠倒会把它清掉。
    const ch = ctx.content.chapters.chapters[idx];
    if (!next.chapters[idx].grants_issued) {
      for (const [crop, n] of Object.entries(ch.grants))
        if (!crop.startsWith('_')) next.inventory.seeds[crop as CropId].bound += n ?? 0;
      next.chapters[idx].grants_issued = true;
    }
    if (ch.nursery_stage) next.nursery.stage = ch.nursery_stage as FarmState['nursery']['stage'];
  }
  return ok(next);
}

/** 首次建场时发第 0 章 Grant（create_farm 走这条，不经过换日）。 */
export function issueChapterZeroGrants(s: FarmState, ctx: Ctx): FarmState {
  if (s.chapters[0].grants_issued) return s;
  const next: FarmState = structuredClone(s);
  const ch = ctx.content.chapters.chapters[0];
  for (const [crop, n] of Object.entries(ch.grants))
    if (!crop.startsWith('_')) next.inventory.seeds[crop as CropId].bound += n ?? 0;
  next.chapters[0].grants_issued = true;
  return next;
}
