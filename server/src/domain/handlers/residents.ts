/**
 * 居民、请求、生活选择、共同事件、工程篮、成长选择。
 *
 * 生活选择槽（Codex 三审 N-I11）：出售命令**不再隐式**写槽——普通批量出售可能在玩家
 * 表达意图之前就把分支锁死。改为唯一入口 `resolve_life_choice`，且三种选择各自校验
 * 对应事实已成立：gift 看该章赠礼记录、keep 看库存、sold 看 sales_facts。
 */
import type { Command } from '../commands.js';
import type { CropId, DishId, ResidentId } from '../content.js';
import { err, ok, type DomainEvent, type Result } from '../errors.js';
import type { Ctx } from '../reducer.js';
import type { FarmState, ResidentState } from '../state.js';
import { availableProduce, unlockChapter } from './economy.js';

/** 阶段由点数 + 门槛条件共同决定：赠礼刷满点数也不能独立解锁「熟悉」（PRD §8.2 L621）。 */
export function stageOf(r: ResidentState, ctx: Ctx): string {
  const stages = ctx.content.relationships.stages;
  let cur = stages[0].id;
  for (const st of stages) {
    if (r.points < st.min) continue;
    if (st.requires === 'first_met' && r.first_met_day === null) continue;
    if (st.requires === 'shared_event' && !r.shared_event_done) continue;
    cur = st.id;
  }
  return cur;
}

const gainPoints = (r: ResidentState, n: number, events: DomainEvent[], reason: string): void => {
  r.points += n;
  events.push({ type: 'relationship', amount: n, reason });
};

export function applyResidents(s: FarmState, cmd: Command, ctx: Ctx): Result<FarmState> | null {
  const c = ctx.content;
  const rel = c.relationships;

  switch (cmd.type) {
    case 'talk_to_resident': {
      const meta = rel.residents[cmd.resident_id];
      if (!meta) return err('NOT_AVAILABLE', cmd.resident_id);
      if (s.clock.chapter_index < meta.available_from_chapter)
        return err('NOT_AVAILABLE', `${cmd.resident_id} 尚未登场`);
      const next = structuredClone(s);
      const r = next.residents[cmd.resident_id];
      const events: DomainEvent[] = [];
      r.first_met_day ??= next.clock.player_day_id;
      if (r.talked_day !== next.clock.player_day_id) {
        r.talked_day = next.clock.player_day_id;
        gainPoints(r, rel.points.daily_first_talk.points, events, 'daily_first_talk');
      }
      return ok(next, events);
    }

    case 'give_gift': {
      const meta = rel.residents[cmd.resident_id];
      if (!meta) return err('NOT_AVAILABLE', cmd.resident_id);
      if (s.clock.chapter_index < unlockChapter(ctx, 'gifts'))
        return err('CHAPTER_LOCKED', '赠礼尚未开放');
      if (s.clock.chapter_index < meta.available_from_chapter)
        return err('NOT_AVAILABLE', `${cmd.resident_id} 尚未登场`);
      if (!(rel.gift_clues[cmd.resident_id] ?? []).includes(cmd.crop))
        return err('NOT_AVAILABLE', `${cmd.resident_id} 的线索里没有 ${cmd.crop}`);
      const cap = rel.points.clued_gift.week_cap ?? Infinity;
      if (s.residents[cmd.resident_id].gifts_given >= cap) return err('ALREADY_CLAIMED', '赠礼次数已满');
      if (availableProduce(s, cmd.crop) < 1) return err('INSUFFICIENT_ITEMS', cmd.crop);
      const next = structuredClone(s);
      const r = next.residents[cmd.resident_id];
      const events: DomainEvent[] = [];
      next.inventory.produce[cmd.crop] -= 1;
      r.gifts_given += 1;
      r.first_met_day ??= next.clock.player_day_id;
      gainPoints(r, rel.points.clued_gift.points, events, 'clued_gift');
      // 记下本章赠礼的作物，供 resolve_life_choice(gift) 校验。
      next.sales_facts[-next.clock.chapter_index - 1] ??= {};
      next.sales_facts[-next.clock.chapter_index - 1][cmd.crop] =
        (next.sales_facts[-next.clock.chapter_index - 1][cmd.crop] ?? 0) + 1;
      return ok(next, events);
    }

    case 'resolve_life_choice': {
      const ch = c.chapters.chapters[cmd.chapter];
      if (!ch?.life_choice_crop) return err('NOT_AVAILABLE', `第 ${cmd.chapter} 章没有用途选择`);
      if (s.clock.chapter_index !== cmd.chapter) return err('CHAPTER_LOCKED', '只能选当前章节');
      if (s.life_choices[cmd.chapter] !== undefined) return err('SLOT_TAKEN', '本章已选过');
      const crop = ch.life_choice_crop;
      const next = structuredClone(s);
      if (cmd.choice === 'gift') {
        if ((next.sales_facts[-cmd.chapter - 1]?.[crop] ?? 0) < 1)
          return err('REQUEST_MISMATCH', `本章尚未赠出 ${crop}`);
      } else if (cmd.choice === 'keep') {
        if (availableProduce(next, crop) < 1) return err('INSUFFICIENT_ITEMS', crop);
        next.inventory.produce[crop] -= 1; // 留作下周，不再进入本周流通
      } else {
        if ((next.sales_facts[cmd.chapter]?.[crop] ?? 0) < 1)
          return err('REQUEST_MISMATCH', `本章尚未在摊位售出 ${crop}`);
      }
      next.life_choices[cmd.chapter] = cmd.choice;
      return ok(next, [{ type: 'life_choice', chapter: cmd.chapter, choice: cmd.choice }]);
    }

    case 'submit_request': {
      const req = c.requests.requests[cmd.request_id];
      if (!req) return err('NOT_AVAILABLE', cmd.request_id);
      if (s.requests_done.includes(cmd.request_id)) return err('REQUEST_DONE', cmd.request_id);
      if (s.clock.chapter_index < req.chapter) return err('CHAPTER_LOCKED', cmd.request_id);
      // 物品必须精确匹配请求定义；提交原子（PRD §7.6 L588）。
      for (const [crop, n] of Object.entries(req.items ?? {}))
        if (availableProduce(s, crop as CropId) < (n ?? 0)) return err('INSUFFICIENT_ITEMS', crop);
      for (const [dish, n] of Object.entries(req.dishes ?? {}))
        if (s.inventory.dishes[dish as DishId] < (n ?? 0)) return err('INSUFFICIENT_ITEMS', dish);
      const next = structuredClone(s);
      const events: DomainEvent[] = [];
      for (const [crop, n] of Object.entries(req.items ?? {}))
        next.inventory.produce[crop as CropId] -= n ?? 0;
      for (const [dish, n] of Object.entries(req.dishes ?? {}))
        next.inventory.dishes[dish as DishId] -= n ?? 0;
      next.wallet += req.coins;
      next.requests_done.push(cmd.request_id);
      // 只有首个标记 personal_story 的请求给 15 点；教学/生活/施工回购不刷关系（L550）。
      if (req.personal_story) {
        const r = next.residents[req.resident];
        if (!r.request_done) {
          r.request_done = true;
          r.first_met_day ??= next.clock.player_day_id;
          gainPoints(r, rel.points.personal_request.points, events, 'personal_request');
        }
      }
      events.push({ type: 'request_done', id: cmd.request_id, coins: req.coins });
      return ok(next, events);
    }

    case 'attend_shared_event': {
      const ch = c.chapters.chapters.find(x => x.shared_events?.some(e => e.id === cmd.event_id));
      const ev = ch?.shared_events?.find(e => e.id === cmd.event_id);
      if (!ch || !ev) return err('NOT_AVAILABLE', cmd.event_id);
      // 只靠章节前置门控，不发一次性 capability（spec §11 假设 3，明确接受的风险）：
      // 居民场景在客户端播放，服务端本就无法验证「真的参与过」；MVP 无排行与跨玩家奖励，
      // 伪造收益仅是自己提前解锁。
      if (s.clock.chapter_index < ch.index) return err('CHAPTER_LOCKED', cmd.event_id);
      const r0 = s.residents[ev.resident];
      if (r0.shared_event_done) return err('ALREADY_CLAIMED', cmd.event_id);
      const next = structuredClone(s);
      const events: DomainEvent[] = [];
      const r = next.residents[ev.resident];
      r.shared_event_done = true;
      r.first_met_day ??= next.clock.player_day_id;
      gainPoints(r, rel.points.shared_event.points, events, 'shared_event');
      return ok(next, events);
    }

    case 'reserve_engineering':
    case 'withdraw_engineering':
    case 'submit_engineering':
      return applyEngineering(s, cmd, ctx);

    case 'set_growth_intent': {
      if (s.clock.chapter_index < unlockChapter(ctx, 'growth_choice'))
        return err('CHAPTER_LOCKED', '成长选择尚未开放');
      if (s.growth_choice.purchase) return err('LOCKED_CHOICE', '已付款，不可改');
      const next = structuredClone(s);
      next.growth_choice.intent = cmd.choice; // 付款前可改选（PRD §7.5 L556）
      return ok(next);
    }

    case 'purchase_growth_choice': {
      if (s.clock.chapter_index < unlockChapter(ctx, 'growth_choice'))
        return err('CHAPTER_LOCKED', '成长选择尚未开放');
      if (s.growth_choice.purchase) return err('LOCKED_CHOICE', '首周永久二选一');
      const gc = c.economy.growth_choice;
      const next = structuredClone(s);
      if (cmd.choice === 'tool') {
        if (next.wallet < gc.tool.price) return err('INSUFFICIENT_FUNDS', `需要 ${gc.tool.price}`);
        next.wallet -= gc.tool.price;
        next.tools.row_tool = true;
      } else {
        // 扩地是一次原子事务：400 + 固定篮 12 枚种子。篮子固定而不是玩家任选——任选时
        // 12R 只要 48、12H 要 120，都推不出账本里的 84（Codex 二审 Critical 1）。
        const basket = gc.field.seed_basket;
        const seedCost = Object.entries(basket)
          .reduce((sum, [crop, n]) => sum + c.crops.crops[crop as CropId].seed_price * (n ?? 0), 0);
        const total = gc.field.price + seedCost;
        if (next.wallet < total) return err('INSUFFICIENT_FUNDS', `需要 ${total}`);
        next.wallet -= total;
        next.beds_unlocked = 4;
        for (const [crop, n] of Object.entries(basket))
          next.inventory.seeds[crop as CropId].bought += n ?? 0;
        // 预留畦到手即已清理已翻土，不计首次清理 XP（决策⑥）——否则 D5/D6 累计会变成
        // 271/304，与 PRD L567/L570 的 268/301 矛盾。
        for (const id of ctx.blueprint.reserved) next.cells[id].state = 'tilled';
      }
      next.growth_choice.purchase = cmd.choice;
      next.growth_choice.intent ??= cmd.choice;
      next.growth_choice.locked_at = ctx.now;
      next.growth_choice.transaction_id = cmd.transaction_id;
      return ok(next, [{ type: 'growth_purchased', choice: cmd.choice }]);
    }

    case 'choose_nursery_appearance': {
      if (s.clock.chapter_index < unlockChapter(ctx, 'nursery_appearance'))
        return err('CHAPTER_LOCKED', '外观选择尚未开放');
      const next = structuredClone(s);
      next.nursery.appearance = cmd.appearance; // 两种等价值外观（PRD §9.2 L682）
      return ok(next);
    }

    case 'record_visit_return': {
      if (s.clock.chapter_index < unlockChapter(ctx, 'visit'))
        return err('CHAPTER_LOCKED', '访问尚未开放');
      const next = structuredClone(s);
      // 只写教学事实，零资源：访问不产生金币、XP、关系、任务进度或每日奖励（PRD §8.4 L655）。
      next.chapters[unlockChapter(ctx, 'visit')].step_flags.visit_tutorial_completed = true;
      return ok(next, [{ type: 'visit_recorded' }]);
    }

    default:
      return null;
  }
}

function applyEngineering(s: FarmState, cmd: Command, ctx: Ctx): Result<FarmState> {
  const c = ctx.content;
  if (s.clock.chapter_index < unlockChapter(ctx, 'engineering_basket'))
    return err('CHAPTER_LOCKED', '工程篮尚未开放');
  const items = (cmd as { items: Partial<Record<CropId, number>> }).items;
  if (!items || Object.keys(items).length === 0) return err('INSUFFICIENT_ITEMS', 'items 为空');
  const next = structuredClone(s);

  if (cmd.type === 'reserve_engineering') {
    for (const [crop, n] of Object.entries(items)) {
      if ((n ?? 0) < 1) return err('INSUFFICIENT_ITEMS', crop);
      if (availableProduce(next, crop as CropId) < (n ?? 0)) return err('INSUFFICIENT_ITEMS', crop);
      next.engineering.reserved[crop as CropId] = (next.engineering.reserved[crop as CropId] ?? 0) + (n ?? 0);
    }
    return ok(next);
  }

  if (cmd.type === 'withdraw_engineering') {
    for (const [crop, n] of Object.entries(items)) {
      const have = next.engineering.reserved[crop as CropId] ?? 0;
      if (have < (n ?? 0)) return err('INSUFFICIENT_ITEMS', crop);
      next.engineering.reserved[crop as CropId] = have - (n ?? 0);
    }
    return ok(next); // 可主动取回（PRD §7.5 L574），只是竣工延后
  }

  // submit：从预留里扣，累计达配额即竣工。提交必须原子。
  for (const [crop, n] of Object.entries(items)) {
    const have = next.engineering.reserved[crop as CropId] ?? 0;
    if (have < (n ?? 0)) return err('INSUFFICIENT_ITEMS', `${crop} 预留不足`);
  }
  const events: DomainEvent[] = [];
  for (const [crop, n] of Object.entries(items)) {
    next.engineering.reserved[crop as CropId]! -= n ?? 0;
    next.inventory.produce[crop as CropId] -= n ?? 0;
    next.engineering.submitted[crop as CropId] =
      (next.engineering.submitted[crop as CropId] ?? 0) + (n ?? 0);
  }
  const quota = c.economy.engineering_quota;
  const complete = Object.entries(quota).every(
    ([crop, need]) => (next.engineering.submitted[crop as CropId] ?? 0) >= (need ?? 0));
  if (complete && next.nursery.stage !== 'built') {
    next.nursery.stage = 'built';
    events.push({ type: 'nursery_built' });
  }
  return ok(next, events);
}
