/**
 * 经济命令：摊位出售、门口回购箱、料理、买卖之外的领取。
 *
 * 摊位规则（PRD §6.4 L431）：每个 `player_day_id` 最多按固定价收购 100 金币，达到预算后
 * 产物**留在库存且不降价**——不是拒绝交易、也不是折价收购。所以这条命令按 `items` 顺序
 * 逐项成交，装不下的原样退回，只有一件都没成交时才报 STALL_BUDGET。
 *
 * 门口回购箱**不占**摊位预算：PRD L544-547 自己把茶回购算在「居民请求」224 那一栏
 * （30+45+55+70+24），不在摊位 381 里；且账本 D4 当天摊位 79 + 回购 24 = 103 会超 100
 * 预算——计入预算既违背 PRD 口径又让目标账本跑不通。堵高频漏洞改用另外两个闸门：
 * 回购**周上限 1 次**（PRD 全周恰好用一次）与种苗包周上限 2，实测宽松上界 972 ≤ 981。
 */
import type { Command } from '../commands.js';
import type { CropId, DishId } from '../content.js';
import { err, ok, type DomainEvent, type Result } from '../errors.js';
import type { Ctx } from '../reducer.js';
import type { FarmState } from '../state.js';

/** 工程篮预留物不进入出售、赠礼、料理候选（PRD §7.5 L574）。 */
export function availableProduce(s: FarmState, crop: CropId): number {
  return s.inventory.produce[crop] - (s.engineering.reserved[crop] ?? 0);
}

export function applyEconomy(s: FarmState, cmd: Command, ctx: Ctx): Result<FarmState> | null {
  const c = ctx.content;
  switch (cmd.type) {
    case 'sell_at_stall': {
      if (!Array.isArray(cmd.items) || cmd.items.length === 0 || cmd.items.length > 12)
        return err('INSUFFICIENT_ITEMS', 'items 需 1..12 项');
      const next = structuredClone(s);
      const budget = c.economy.stall_budget_per_day;
      const sold: { kind: string; id: string; qty: number; coins: number }[] = [];
      const unsold: { kind: string; id: string; qty: number }[] = [];
      for (const item of cmd.items) {
        if (!Number.isInteger(item.qty) || item.qty < 1) return err('INSUFFICIENT_ITEMS', 'qty 非法');
        const price = item.kind === 'produce'
          ? c.crops.crops[item.id as CropId]?.unit_price
          : c.recipes.recipes[item.id as DishId]?.stall_price;
        if (price === undefined) return err('INSUFFICIENT_ITEMS', `未知物品 ${item.id}`);
        const have = item.kind === 'produce'
          ? availableProduce(next, item.id as CropId)
          : next.inventory.dishes[item.id as DishId];
        if (have < item.qty) return err('INSUFFICIENT_ITEMS', `${item.id} 不足`);
        // 按顺序成交到预算为止；装不下的原样留库存、不降价。
        const room = Math.max(0, budget - next.stall.settled);
        const canSell = Math.min(item.qty, Math.floor(room / price));
        if (canSell === 0) { unsold.push({ ...item }); continue; }
        const coins = canSell * price;
        next.stall.settled += coins;
        next.wallet += coins;
        if (item.kind === 'produce') {
          next.inventory.produce[item.id as CropId] -= canSell;
          // 按当前章节累加成交事实：resolve_life_choice(sold) 的唯一校验依据
          //（Codex 三审 N-I11：出售不再隐式写生活槽）。
          const chap = next.clock.chapter_index;
          next.sales_facts[chap] ??= {};
          next.sales_facts[chap][item.id as CropId] =
            (next.sales_facts[chap][item.id as CropId] ?? 0) + canSell;
        } else {
          next.inventory.dishes[item.id as DishId] -= canSell;
        }
        sold.push({ ...item, qty: canSell, coins });
        if (canSell < item.qty) unsold.push({ ...item, qty: item.qty - canSell });
      }
      if (sold.length === 0) return err('STALL_BUDGET', `当日已结算 ${next.stall.settled}`);
      return ok(next, [{ type: 'stall_sold', settled: next.stall.settled, sold, unsold }]);
    }

    case 'sell_to_buyback_box': {
      const bb = c.recipes.buyback;
      if (cmd.qty !== 1) return err('BUYBACK_LIMIT', '每次一份');
      if (s.buyback.day === s.clock.player_day_id && s.buyback.sold >= bb.per_player_day)
        return err('BUYBACK_LIMIT', `每玩家日 ${bb.per_player_day} 份`);
      if (s.buyback.week_total >= bb.per_week) return err('BUYBACK_LIMIT', `首周 ${bb.per_week} 份`);
      if (s.inventory.dishes[bb.dish] < 1) return err('INSUFFICIENT_ITEMS', bb.dish);
      const next = structuredClone(s);
      next.inventory.dishes[bb.dish] -= 1;
      next.wallet += bb.coins;
      next.buyback = {
        day: next.clock.player_day_id,
        sold: next.buyback.day === next.clock.player_day_id ? next.buyback.sold + 1 : 1,
        week_total: next.buyback.week_total + 1,
      };
      return ok(next, [{ type: 'buyback', coins: bb.coins }]);
    }

    case 'cook_dish': {
      const recipe = c.recipes.recipes[cmd.recipe];
      if (!recipe) return err('INSUFFICIENT_ITEMS', `未知配方 ${cmd.recipe}`);
      const kitchenChapter = unlockChapter(ctx, 'kitchen');
      if (s.clock.chapter_index < kitchenChapter)
        return err('CHAPTER_LOCKED', `厨房需第 ${kitchenChapter} 章开放`);
      for (const [crop, n] of Object.entries(recipe.inputs))
        if (availableProduce(s, crop as CropId) < (n ?? 0))
          return err('INSUFFICIENT_ITEMS', `${crop} 不足`);
      const next = structuredClone(s);
      const events: DomainEvent[] = [];
      for (const [crop, n] of Object.entries(recipe.inputs))
        next.inventory.produce[crop as CropId] -= n ?? 0;
      next.inventory.dishes[cmd.recipe] += 1;
      if (!next.xp.first_recipes.includes(cmd.recipe)) {
        next.xp.first_recipes.push(cmd.recipe);
        next.xp.total += c.xp.sources.first_recipe.xp;
        events.push({ type: 'xp', amount: c.xp.sources.first_recipe.xp, reason: 'first_recipe' });
        next.handbook.push({ kind: 'first_recipe', key: cmd.recipe, day: next.clock.player_day_id });
      }
      return ok(next, events);
    }

    case 'claim_subsidy': {
      const sub = c.economy.subsidies[cmd.subsidy_id];
      if (!sub) return err('NOT_AVAILABLE', `未知补贴 ${cmd.subsidy_id}`);
      if (s.subsidies_claimed.includes(cmd.subsidy_id)) return err('ALREADY_CLAIMED', cmd.subsidy_id);
      if (s.clock.chapter_index < sub.chapter) return err('CHAPTER_LOCKED', cmd.subsidy_id);
      // 竣工补贴要苗圃真的竣工，不能只靠到了第 6 章（PRD §7.3 L536）。
      if (cmd.subsidy_id === 'nursery_built' && s.nursery.stage !== 'built')
        return err('NOT_AVAILABLE', '苗圃尚未竣工');
      const next = structuredClone(s);
      next.wallet += sub.coins;
      next.subsidies_claimed.push(cmd.subsidy_id);
      return ok(next, [{ type: 'subsidy', id: cmd.subsidy_id, coins: sub.coins }]);
    }

    case 'claim_seedling_pack': {
      const pack = c.economy.seedling_pack;
      if (s.seedling_packs.days.length >= pack.week_cap) return err('PACK_LIMIT', '首周上限');
      if (s.seedling_packs.days.includes(s.clock.player_day_id)) return err('PACK_LIMIT', '今日已领');
      // 空仓判定收紧（Codex 三审 N-I1）：只有真的一无所有才发，否则高频玩家可以靠反复
      // 领免费种子把账户价值上界推过 981。
      const cheapest = Math.min(...Object.values(c.crops.crops).map(x => x.seed_price));
      if (s.wallet >= cheapest) return err('NOT_AVAILABLE', '钱包足以买种子');
      const hasSeeds = Object.values(s.inventory.seeds).some(l => l.bought + l.bound > 0);
      const hasProduce = Object.values(s.inventory.produce).some(n => n > 0);
      const hasDishes = Object.values(s.inventory.dishes).some(n => n > 0);
      const hasReserved = Object.values(s.engineering.reserved).some(n => (n ?? 0) > 0);
      const growing = Object.values(s.cells).some(x => x.state === 'sown' || x.state === 'growing');
      if (hasSeeds || hasProduce || hasDishes || hasReserved || growing)
        return err('NOT_AVAILABLE', '仍有可回收资产');
      const next = structuredClone(s);
      for (const [crop, n] of Object.entries(pack.contents))
        next.inventory.seeds[crop as CropId].bound += n ?? 0;
      next.seedling_packs.days.push(next.clock.player_day_id);
      return ok(next, [{ type: 'seedling_pack' }]);
    }

    default:
      return null;
  }
}

export function unlockChapter(ctx: Ctx, unlock: string): number {
  for (const ch of ctx.content.chapters.chapters) if (ch.unlocks.includes(unlock)) return ch.index;
  return 0;
}
