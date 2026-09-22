import { addBagItem, allBagStacks, projectBagAggregates, reconcileBagChanges } from './bag.js';
import type { Command } from './commands.js';
import type { CharacterBonusStat, CharacterStat, Content, JourneyMaterial, HandStats } from './content.js';
import { err, ok, type Result } from './errors.js';
import type { Ctx } from './reducer.js';
import type { FarmState } from './state.js';

const BASIC_MATERIALS = ['wood', 'stone', 'fiber'] as const;

export function ensureCharacter(state: FarmState, content: Content): void {
  state.character ??= { version: 1, buffs: [] };
  const maximum = equipmentStats(state, content).max_hp;
  state.character.hp = Math.min(maximum, Math.max(1, state.character.hp ?? maximum));
  if (state.mine?.floor && state.bag) grantStarterWeapon(state, content);
}

export function grantStarterWeapon(state: FarmState, content: Content): void {
  if (state.character!.starter_weapon_granted) return;
  const id = content.mining.combat.starter_weapon;
  if (!allBagStacks(state.bag!).some(stack => stack.item_id === id)) {
    addBagItem(state.bag!, { item_id: id, quantity: 1 }, content, true);
    if (!state.bag!.equipped.main_hand) {
      const stack = [...state.bag!.slots, ...state.bag!.overflow].find(value => value.item_id === id)!;
      state.bag!.slots = state.bag!.slots.filter(value => value.id !== stack.id);
      state.bag!.overflow = state.bag!.overflow.filter(value => value.id !== stack.id);
      state.bag!.equipped.main_hand = stack;
    }
    state.bag!.sequence += 1;
  }
  state.character!.starter_weapon_granted = true;
}

function activeBuff(state: FarmState, stat: CharacterBonusStat, content: Content) {
  return state.character?.buffs.find(buff => buff.remaining_uses > 0
    && content.character.consumables[buff.source_item_id]?.buff_id === buff.id
    && content.character.consumables[buff.source_item_id]?.stat === stat);
}

export function equipmentStats(state: FarmState, content: Content): Record<CharacterStat, number> {
  const stats = { ...content.character.base };
  const tool = state.bag?.equipped.main_hand;
  // Legacy row ownership only supplies scope before the unified bag exists.
  stats.tool_scope = tool ? Number(content.items.items[tool.item_id]?.properties.tool_scope ?? stats.tool_scope)
    : !state.bag && state.tools.row_tool ? Number(content.items.items.row_tool.properties.tool_scope) : stats.tool_scope;
  for (const stack of Object.values(state.bag?.equipped ?? {})) {
    if (!stack) continue;
    const modifiers = content.character.equipment[stack.item_id]?.modifiers ?? {};
    for (const [stat, amount] of Object.entries(modifiers)) stats[stat as CharacterBonusStat] += amount!;
  }
  return stats;
}

export function mainHandStats(state: FarmState, content: Content): HandStats {
  const id = state.bag?.equipped.main_hand?.item_id;
  const properties = id ? content.items.items[id]?.properties : undefined;
  return Object.fromEntries(Object.entries(content.character.main_hand_base).map(([key, value]) =>
    [key, typeof properties?.[key] === 'number' ? properties[key] : value])) as HandStats;
}
export type ResourceKind = 'crop' | 'ore' | 'wood';
export function resourceKind(materials: Partial<Record<JourneyMaterial, number>>): ResourceKind {
  if ((materials.wood ?? 0) > 0) return 'wood';
  if (['stone', 'copper_ore', 'rock_salt'].some(key => Number(materials[key as JourneyMaterial] ?? 0) > 0)) return 'ore';
  return 'crop';
}
export function gatherSeconds(state: FarmState, content: Content, kind: ResourceKind, work = .9): number {
  return work / mainHandStats(state, content)[`${kind}_power`];
}
/** Rate-limit confirmed collections using authoritative real time; rejected commands spend nothing. */
export function gatheringReady(before: FarmState, after: FarmState, ctx: Ctx, seconds: number): boolean {
  const now = ctx.realNow ?? ctx.now;
  if (now + 50 < (before.character?.last_gather_at ?? -Infinity) + seconds * 1000) return false;
  after.character ??= { version: 1, buffs: [] };
  after.character.last_gather_at = now;
  return true;
}

export function characterStats(state: FarmState, content: Content): Record<CharacterStat, number> {
  const stats = equipmentStats(state, content);
  for (const stat of ['gather_bonus', 'mining_bonus', 'craft_savings'] as const) {
    const buff = activeBuff(state, stat, content);
    if (buff) stats[stat] += content.character.consumables[buff.source_item_id].amount;
  }
  return stats;
}

/** Call only on an action's draft, after proving that this effect contributed to the result. */
export function spendCharacterBuff(state: FarmState, stat: CharacterBonusStat, content: Content): void {
  const buff = activeBuff(state, stat, content);
  if (!buff) return;
  buff.remaining_uses -= 1;
  state.character!.buffs = state.character!.buffs.filter(value => value.remaining_uses > 0);
}

export function gatheringMaterials(state: FarmState, materials: Partial<Record<JourneyMaterial, number>>, content: Content) {
  const result = { ...materials };
  const primary = BASIC_MATERIALS.reduce<(typeof BASIC_MATERIALS)[number] | undefined>((best, id) =>
    (materials[id] ?? 0) > (best ? materials[best] ?? 0 : 0) ? id : best, undefined);
  const bonus = characterStats(state, content).gather_bonus;
  if (primary && bonus > 0) result[primary] = (result[primary] ?? 0) + bonus;
  return { materials: result, bonus: primary ? bonus : 0 };
}

/** Equipment spends its budget first; tea is spent only when its own budget saves material. */
export function craftingMaterials(state: FarmState, materials: Partial<Record<JourneyMaterial, number>>, content: Content) {
  const result = { ...materials };
  const actual_saved: Partial<Record<JourneyMaterial, number>> = {};
  const reduce = (budget: number) => {
    let saved = 0;
    for (const id of BASIC_MATERIALS) {
      const amount = Math.min(budget - saved, Math.max(0, (result[id] ?? 0) - 1));
      if (amount > 0) {
        result[id] = result[id]! - amount;
        actual_saved[id] = (actual_saved[id] ?? 0) + amount;
        saved += amount;
      }
    }
    return saved;
  };
  const equipment_saved = reduce(equipmentStats(state, content).craft_savings);
  const buff = activeBuff(state, 'craft_savings', content);
  const meal_saved = reduce(buff ? content.character.consumables[buff.source_item_id].amount : 0);
  return { materials: result, actual_saved, equipment_saved, meal_saved };
}

export function applyCharacter(state: FarmState, cmd: Command, ctx: Ctx): Result<FarmState> | null {
  if (cmd.type === 'rest_character') {
    if (state.mine?.floor || !state.journey) return err('NOT_AVAILABLE');
    const next = structuredClone(state);
    ensureCharacter(next, ctx.content);
    next.character!.hp = characterStats(next, ctx.content).max_hp;
    return ok(next, [{ type: 'character_rested', hp: next.character!.hp }]);
  }
  if (cmd.type !== 'use_bag_item' && cmd.type !== 'craft_equipment') return null;
  if (!Number.isSafeInteger(cmd.sequence) || cmd.sequence !== state.bag?.sequence) return err('BAG_CHANGED');
  let next = structuredClone(state);
  ensureCharacter(next, ctx.content);
  if (cmd.type === 'use_bag_item') {
    if (typeof cmd.stack_id !== 'string' || !/^bag_[1-9][0-9]*$/.test(cmd.stack_id)) return err('INVALID_BAG_ACTION');
    const stack = [...next.bag!.slots, ...next.bag!.overflow].find(value => value.id === cmd.stack_id);
    const effect = stack && ctx.content.character.consumables[stack.item_id];
    if (!stack || !effect || stack.quantity < 1) return err('INVALID_BAG_ACTION');
    const alreadyActive = next.character!.buffs.some(buff => buff.id === effect.buff_id && buff.remaining_uses > 0);
    const healed = Math.min(effect.heal ?? 0, characterStats(next, ctx.content).max_hp - next.character!.hp!);
    if (alreadyActive && healed <= 0) return err('EFFECT_ACTIVE');
    stack.quantity -= 1;
    next.bag!.slots = next.bag!.slots.filter(value => value.quantity > 0);
    next.bag!.overflow = next.bag!.overflow.filter(value => value.quantity > 0);
    if (!alreadyActive) next.character!.buffs.push({ id: effect.buff_id, source_item_id: stack.item_id, remaining_uses: effect.uses });
    next.character!.hp! += healed;
    next.bag!.sequence += 1;
    projectBagAggregates(next, ctx.content);
    return ok(next, [{ type: 'item_consumed', item_id: stack.item_id, buff_id: effect.buff_id, healed,
      remaining_uses: next.character!.buffs.find(buff => buff.id === effect.buff_id)!.remaining_uses }]);
  }
  if (typeof cmd.item_id !== 'string' || !Object.hasOwn(ctx.content.character.equipment, cmd.item_id))
    return err('INVALID_BAG_ACTION');
  if (!state.journey?.facts.includes('workbench')) return err('NOT_AVAILABLE', 'Repair the workbench first');
  if (allBagStacks(state.bag!).some(stack => stack.item_id === cmd.item_id)) return err('EQUIPMENT_OWNED');
  const recipe = ctx.content.character.equipment[cmd.item_id];
  if (recipe.starter) return err('NOT_AVAILABLE');
  const cost = craftingMaterials(state, recipe.materials, ctx.content);
  for (const [id, amount] of Object.entries(cost.materials)) {
    const have = id === 'wood' ? next.journey!.wood : next.journey!.materials?.[id as Exclude<JourneyMaterial, 'wood'>] ?? 0;
    if (have < amount!) return err('INSUFFICIENT_ITEMS', id);
    if (id === 'wood') next.journey!.wood -= amount!;
    else next.journey!.materials![id as Exclude<JourneyMaterial, 'wood'>] = have - amount!;
  }
  const paid = reconcileBagChanges(state, next, ctx.content);
  if (!paid.ok) return paid;
  next = paid.state;
  if (!addBagItem(next.bag!, { item_id: cmd.item_id, quantity: 1 }, ctx.content)) return err('BAG_FULL');
  if (cost.meal_saved > 0) spendCharacterBuff(next, 'craft_savings', ctx.content);
  next.bag!.sequence = state.bag!.sequence + 1;
  projectBagAggregates(next, ctx.content);
  return ok(next, [{ type: 'equipment_crafted', item_id: cmd.item_id, actual_saved: cost.actual_saved }]);
}
