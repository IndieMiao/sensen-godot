/**
 * 农事命令：清理、翻土、播种、照料、精心、收获、买种子。G1 客户端直接用的就是这几条。
 *
 * 服务端**不限每条命令处理几格**：`row_tool` 是客户端一次手势覆盖整畦 3 格的便利，
 * 不改产量也不缩短时长（PRD §6.3 L408），所以它不是服务端的权限概念。
 */
import { checkCellIds } from '../commands.js';
import type { Command } from '../commands.js';
import { canUse } from '../journey.js';
import { advanceFieldGrowth, fieldCellUnlocked } from '../field_growth.js';
import type { CropId } from '../content.js';
import { err, ok, type DomainEvent, type Result } from '../errors.js';
import type { Ctx } from '../reducer.js';
import type { CellSlot, FarmState } from '../state.js';

/** 第四畦要买下才能动（PRD §6.1）；mask 表达「这格能不能是田」，解锁与否看 beds_unlocked。 */
function unlocked(s: FarmState, ctx: Ctx, id: string): boolean {
  if (!ctx.blueprint.cultivable.has(id)) return false;
  if (ctx.blueprint.reserved.has(id)) return s.beds_unlocked === 4;
  return fieldCellUnlocked(s, id);
}

function gateCells(s: FarmState, ctx: Ctx, ids: string[]): Result<string[]> {
  const bad = checkCellIds(ids);
  if (bad) return err('DUPLICATE_CELL', bad);
  for (const id of ids) {
    if (!ctx.blueprint.cultivable.has(id)) return err('CELL_NOT_CULTIVABLE', id);
    if (!unlocked(s, ctx, id)) return err('CELL_LOCKED', `${id} 尚未解锁`);
  }
  return ok(ids);
}

const addXp = (s: FarmState, n: number, events: DomainEvent[], reason: string): void => {
  if (n <= 0) return;
  s.xp.total += n;
  events.push({ type: 'xp', amount: n, reason });
};

/** 当前所有已播种格都完成本轮天气动作 → 当日一次的 15 XP（PRD §7.2 L480）。 */
function maybeDailyCareBonus(s: FarmState, ctx: Ctx, events: DomainEvent[]): void {
  if (s.xp.care_bonus_day === s.clock.player_day_id) return;
  const sown = Object.values(s.cells).filter(c => c.state === 'sown' || c.state === 'growing');
  if (sown.length === 0 || sown.some(c => c.state === 'sown')) return;
  s.xp.care_bonus_day = s.clock.player_day_id;
  addXp(s, ctx.content.xp.sources.daily_care_complete.xp, events, 'daily_care_complete');
}

export function applyFarming(s: FarmState, cmd: Command, ctx: Ctx): Result<FarmState> | null {
  const c = ctx.content;
  switch (cmd.type) {
    case 'clear_cells': {
      const gate = gateCells(s, ctx, cmd.cell_ids);
      if (!gate.ok) return gate;
      const next = structuredClone(s);
      const events: DomainEvent[] = [];
      for (const id of cmd.cell_ids) {
        if (next.cells[id].state !== 'wild') return err('WRONG_STATE', `${id} 不是荒地`);
        next.cells[id].state = 'cleared';
        if (!next.xp.first_clear_cells.includes(id)) {
          next.xp.first_clear_cells.push(id);
          addXp(next, c.xp.sources.first_clear_cell.xp, events, 'first_clear_cell');
        }
      }
      return ok(next, events);
    }

    case 'till_cells': {
      const gate = gateCells(s, ctx, cmd.cell_ids);
      if (!gate.ok) return gate;
      const next = structuredClone(s);
      for (const id of cmd.cell_ids) {
        if (next.cells[id].state !== 'cleared') return err('WRONG_STATE', `${id} 未清理`);
        next.cells[id].state = 'tilled';
      }
      return ok(next);
    }

    case 'sow_cells': {
      if (typeof cmd.crop !== 'string' || !Object.hasOwn(c.crops.crops, cmd.crop)
        || (cmd.lot !== 'bought' && cmd.lot !== 'bound'))
        return err('INSUFFICIENT_ITEMS', '种子或来源非法');
      const gate = gateCells(s, ctx, cmd.cell_ids);
      if (!gate.ok) return gate;
      const unlockedCrop = cropUnlockChapter(ctx, cmd.crop);
      if (!(cmd.crop === 'R' || cmd.crop === 'L' || canUse(s, `crop_${cmd.crop}`, unlockedCrop)))
        return err('CHAPTER_LOCKED', `${cmd.crop} 需第 ${unlockedCrop} 章开放`);
      const next = structuredClone(s);
      const lot = next.inventory.seeds[cmd.crop];
      const need = cmd.cell_ids.length;
      if (lot[cmd.lot] < need) return err('INSUFFICIENT_ITEMS', `${cmd.crop} ${cmd.lot} 种子不足`);
      // D0 教学那 6 株用 3 分钟特例；判定条件是「第 0 章 + 该章的教学作物 + 尚未首次收获」。
      const ch0 = c.chapters.chapters[0];
      const tutorial = next.clock.chapter_index === 0
        && cmd.crop === ch0.tutorial_crop
        && !next.xp.first_harvest_crops.includes(cmd.crop);
      for (const id of cmd.cell_ids) {
        if (next.cells[id].state !== 'tilled') return err('WRONG_STATE', `${id} 未翻土`);
        next.cells[id] = {
          state: 'sown', crop: cmd.crop,
          care_weather: next.clock.field_condition, // 绑定播种时的今日田况（PRD §6.2 L391）
          care_done_at: null, ready_at: null, careful: false, tutorial,
        };
      }
      lot[cmd.lot] -= need;
      advanceFieldGrowth(next, 'planted', need, c);
      return ok(next, [{ type: 'sown', crop: cmd.crop, count: need, tutorial }]);
    }

    case 'apply_care': {
      const gate = gateCells(s, ctx, cmd.cell_ids);
      if (!gate.ok) return gate;
      const next = structuredClone(s);
      const events: DomainEvent[] = [];
      for (const id of cmd.cell_ids) {
        const cell = next.cells[id];
        if (cell.state !== 'sown') return err('WRONG_STATE', `${id} 不在待照料状态`);
        const want = c.weather.care_action[cell.care_weather!];
        if (want !== cmd.kind) return err('WRONG_CARE', `${id} 需要 ${want}，收到 ${cmd.kind}`);
        cell.state = 'growing';
        cell.care_done_at = ctx.now;
        // ready_at 只在本轮必需照料成功时写入（PRD §11.1 L785）——播种但未照料保持 null，
        // 作物停在起点不开始成长，也就不会跨日被误补算。
        cell.ready_at = ctx.now + durationOf(ctx, cell);
        if (!next.xp.first_weather.includes(cell.care_weather!)) {
          next.xp.first_weather.push(cell.care_weather!);
          addXp(next, c.xp.sources.first_weather_care.xp, events, 'first_weather_care');
        }
      }
      maybeDailyCareBonus(next, ctx, events);
      return ok(next, events);
    }

    case 'apply_optional_care': {
      const gate = gateCells(s, ctx, cmd.cell_ids);
      if (!gate.ok) return gate;
      const next = structuredClone(s);
      for (const id of cmd.cell_ids) {
        const cell = next.cells[id];
        if (cell.state !== 'growing') return err('WRONG_STATE', `${id} 不在生长中`);
        if (cell.careful) return err('ALREADY_CLAIMED', `${id} 已做过精心照料`);
        cell.careful = true; // 只影响手账/料理表现/居民反馈，不改售价与产量（PRD §6.2 L396）
      }
      return ok(next);
    }

    case 'harvest_cells': {
      const gate = gateCells(s, ctx, cmd.cell_ids);
      if (!gate.ok) return gate;
      const next = structuredClone(s);
      const events: DomainEvent[] = [];
      const ripe = new Set(ctx.derived.ripe_cells);
      const cap = c.xp.sources.harvest_plant.daily_cap_plants ?? Infinity;
      for (const id of cmd.cell_ids) {
        const cell = next.cells[id];
        if (!ripe.has(id)) return err('NOT_RIPE', id);
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
          next.handbook.push({
            kind: 'first_harvest', key: crop, day: next.clock.player_day_id, careful: cell.careful,
          });
        }
        // 收完回到已翻土：下一轮直接播种，不用重新清理（PRD §6.2 的循环）。
        next.cells[id] = {
          state: 'tilled', crop: null, care_weather: null, care_done_at: null,
          ready_at: null, careful: false, tutorial: false,
        };
      }
      advanceFieldGrowth(next, 'harvested', cmd.cell_ids.length, c);
      return ok(next, events);
    }

    case 'buy_seeds': {
      if (typeof cmd.crop !== 'string' || !Object.hasOwn(c.crops.crops, cmd.crop))
        return err('INSUFFICIENT_ITEMS', '未知种子');
      if (!Number.isInteger(cmd.qty) || cmd.qty < 1 || cmd.qty > 24)
        return err('INSUFFICIENT_ITEMS', 'qty 必须是 1..24');
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

function durationOf(ctx: Ctx, cell: CellSlot): number {
  const t = ctx.content.crops.d0_tutorial;
  if (cell.tutorial && cell.crop === t.crop) return t.duration_ms;
  return ctx.content.crops.crops[cell.crop!].duration_ms;
}
