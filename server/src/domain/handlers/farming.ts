/**
 * 农事命令：开垦、播种、浇水、收割、铲平、买种子。
 *
 * 自由格子种田（SGODOT-128）：地面属性决定哪些格能开垦，玩家自己决定田的形状。
 * **未开垦的格不进状态** —— `cells` 里没有这个 key 就是未开垦，几千格的农场只存玩家真正
 * 动过的那几十上百格。开垦有软上限，防止状态无界增长。
 *
 * 服务端不限每条命令处理几格（上限只防滥用）：一次刷一片是客户端的手势便利，
 * 不改产量也不缩短时长。
 */
import { gatherSeconds, gatheringReady } from '../character.js';
import { checkCellIds } from '../commands.js';
import type { Command } from '../commands.js';
import { canUse } from '../journey.js';
import type { CropId } from '../content.js';
import { err, ok, type DomainEvent, type Result } from '../errors.js';
import type { Ctx } from '../reducer.js';
import type { FarmState } from '../state.js';
import { isTillable } from '../plot.js';

/** 一座农场最多同时持有这么多已开垦格。稀疏存储下这是状态体积的唯一上界。 */
export const MAX_TILLED_CELLS = 600;

/** 校验格 ID 本身合法且地面可开垦；不检查格子当前处于什么状态。 */
function gateCells(ctx: Ctx, ids: string[]): Result<string[]> {
  const bad = checkCellIds(ids);
  if (bad) return err('DUPLICATE_CELL', bad);
  for (const id of ids)
    if (!isTillable(ctx.plot, id)) return err('CELL_NOT_CULTIVABLE', id);
  return ok(ids);
}

/** 已开垦的格才有状态；未开垦的格在 `cells` 里根本不存在。 */
function requireTracked(s: FarmState, id: string) {
  return s.cells[id];
}

const addXp = (s: FarmState, n: number, events: DomainEvent[], reason: string): void => {
  if (n <= 0) return;
  s.xp.total += n;
  events.push({ type: 'xp', amount: n, reason });
};

export function applyFarming(s: FarmState, cmd: Command, ctx: Ctx): Result<FarmState> | null {
  const c = ctx.content;
  switch (cmd.type) {
    // 开垦：未开垦 → 已开垦。合并了旧的「清理 + 翻土」两步。
    case 'till_cells': {
      const gate = gateCells(ctx, cmd.cell_ids);
      if (!gate.ok) return gate;
      const next = structuredClone(s);
      let added = 0;
      for (const id of cmd.cell_ids) {
        if (requireTracked(next, id)) return err('WRONG_STATE', `${id} 已经开垦过`);
        added += 1;
      }
      if (Object.keys(next.cells).length + added > MAX_TILLED_CELLS)
        return err('PLOT_LIMIT_REACHED', `最多同时持有 ${MAX_TILLED_CELLS} 块已开垦的地`);
      for (const id of cmd.cell_ids)
        next.cells[id] = { state: 'tilled', crop: null, watered_at: null, ready_at: null };
      return ok(next, [{ type: 'tilled', count: added }]);
    }

    // 铲平：已开垦且空着 → 回到未开垦（把格子从状态里摘掉）。
    case 'clear_plot': {
      const gate = gateCells(ctx, cmd.cell_ids);
      if (!gate.ok) return gate;
      const next = structuredClone(s);
      for (const id of cmd.cell_ids) {
        const cell = requireTracked(next, id);
        if (!cell) return err('WRONG_STATE', `${id} 还没有开垦`);
        if (cell.state !== 'tilled') return err('WRONG_STATE', `${id} 上还有作物`);
        delete next.cells[id];
      }
      return ok(next);
    }

    case 'sow_cells': {
      if (typeof cmd.crop !== 'string' || !Object.hasOwn(c.crops.crops, cmd.crop)
        || (cmd.lot !== 'bought' && cmd.lot !== 'bound'))
        return err('INSUFFICIENT_ITEMS', '种子或来源非法');
      const gate = gateCells(ctx, cmd.cell_ids);
      if (!gate.ok) return gate;
      const unlockedCrop = cropUnlockChapter(ctx, cmd.crop);
      if (!(cmd.crop === 'R' || cmd.crop === 'L' || canUse(s, `crop_${cmd.crop}`, unlockedCrop)))
        return err('CHAPTER_LOCKED', `${cmd.crop} 需第 ${unlockedCrop} 章开放`);
      const next = structuredClone(s);
      const lot = next.inventory.seeds[cmd.crop];
      const need = cmd.cell_ids.length;
      if (lot[cmd.lot] < need) return err('INSUFFICIENT_ITEMS', `${cmd.crop} ${cmd.lot} 种子不足`);
      for (const id of cmd.cell_ids) {
        const cell = requireTracked(next, id);
        if (!cell) return err('WRONG_STATE', `${id} 还没有开垦`);
        if (cell.state !== 'tilled') return err('WRONG_STATE', `${id} 上还有作物`);
        next.cells[id] = { state: 'sown', crop: cmd.crop, watered_at: null, ready_at: null };
      }
      lot[cmd.lot] -= need;
      return ok(next, [{ type: 'sown', crop: cmd.crop, count: need }]);
    }

    // 浇水：播下 → 生长。这是唯一写 ready_at 的地方，没浇水的作物永远停在起点。
    case 'water_cells': {
      const gate = gateCells(ctx, cmd.cell_ids);
      if (!gate.ok) return gate;
      const next = structuredClone(s);
      for (const id of cmd.cell_ids) {
        const cell = requireTracked(next, id);
        if (!cell) return err('WRONG_STATE', `${id} 还没有开垦`);
        if (cell.state !== 'sown') return err('WRONG_STATE', `${id} 不在待浇水状态`);
        cell.state = 'growing';
        cell.watered_at = ctx.now;
        cell.ready_at = ctx.now + c.crops.crops[cell.crop!].duration_ms;
      }
      return ok(next);
    }

    case 'harvest_cells': {
      const gate = gateCells(ctx, cmd.cell_ids);
      if (!gate.ok) return gate;
      const next = structuredClone(s);
      const events: DomainEvent[] = [];
      const ripe = new Set(ctx.derived.ripe_cells);
      const cap = c.xp.sources.harvest_plant.daily_cap_plants ?? Infinity;
      for (const id of cmd.cell_ids) {
        const cell = requireTracked(next, id);
        if (!cell || !ripe.has(id)) return err('NOT_RIPE', id);
        const crop = cell.crop!;
        next.inventory.produce[crop] += c.crops.crops[crop].yield;
        if (next.xp.harvest_counted.day !== next.clock.player_day_id)
          next.xp.harvest_counted = { day: next.clock.player_day_id, plants: 0 };
        if (next.xp.harvest_counted.plants < cap) {
          next.xp.harvest_counted.plants += 1;
          addXp(next, c.xp.sources.harvest_plant.xp, events, 'harvest_plant');
        }
        if (!next.xp.first_harvest_crops.includes(crop)) {
          next.xp.first_harvest_crops.push(crop);
          addXp(next, c.xp.sources.first_harvest_crop.xp, events, 'first_harvest_crop');
          next.handbook.push({ kind: 'first_harvest', key: crop, day: next.clock.player_day_id });
        }
        // 收完回到已开垦：下一轮直接播种，不用重新开垦。
        next.cells[id] = { state: 'tilled', crop: null, watered_at: null, ready_at: null };
      }
      const seconds = cmd.cell_ids.reduce((sum, id) => sum + gatherSeconds(s, c,
        c.crops.crops[s.cells[id]!.crop!].woody ? 'wood' : 'crop', .45), 0);
      if (!gatheringReady(s, next, ctx, seconds)) return err('WORK_COOLDOWN');
      return ok(next, events);
    }

    case 'buy_seeds': {
      if (typeof cmd.crop !== 'string' || !Object.hasOwn(c.crops.crops, cmd.crop))
        return err('INSUFFICIENT_ITEMS', '未知种子');
      if (!Number.isInteger(cmd.qty) || cmd.qty < 1 || cmd.qty > 99)
        return err('INSUFFICIENT_ITEMS', 'qty 必须是 1..99');
      const unlockChapter = cropUnlockChapter(ctx, cmd.crop);
      if (!(cmd.crop === 'R' || cmd.crop === 'L' || canUse(s, `crop_${cmd.crop}`, unlockChapter)))
        return err('CHAPTER_LOCKED', `${cmd.crop} 需第 ${unlockChapter} 章开放`);
      const cost = c.crops.crops[cmd.crop].seed_price * cmd.qty;
      if (s.wallet < cost) return err('INSUFFICIENT_FUNDS', `需要 ${cost}`);
      const next = structuredClone(s);
      next.wallet -= cost;
      next.inventory.seeds[cmd.crop].bought += cmd.qty;
      return ok(next, [{ type: 'bought_seeds', crop: cmd.crop, qty: cmd.qty, cost }]);
    }

    default:
      return null;
  }
}

/** 作物按章节解锁（PRD §7.2 L505：C 由 D2、H 由 D3；R/L 自 D0 起可用）。 */
function cropUnlockChapter(ctx: Ctx, crop: CropId): number {
  const want = `crop_${crop}`;
  for (const ch of ctx.content.chapters.chapters)
    if (ch.unlocks.includes(want)) return ch.index;
  return 0;
}
