import { createHash } from 'node:crypto';
import type { Command } from './commands.js';
import { mineRocks, type JourneyMaterial } from './content.js';
import { err, ok, type Result } from './errors.js';
import type { Ctx } from './reducer.js';
import type { FarmState, MineState } from './state.js';
import { characterStats, grantStarterWeapon, spendCharacterBuff, gatherSeconds, gatheringReady } from './character.js';
import { ensureMineCombat, updateMineClearance } from './combat.js';

const COMMANDS = ['enter_mine', 'leave_mine', 'mine_rock', 'descend_mine', 'ascend_mine',
  'use_mine_elevator', 'restart_mine'];
type MineCommand = Exclude<Extract<Command, { run: number }>, { type: 'mine_combat' }>;
const isMineCommand = (cmd: Command): cmd is MineCommand => COMMANDS.includes(cmd.type);

export function initialMineState(): MineState {
  return { version: 1, run: 0, floor: 0, deepest_floor: 1, cleared_floors: [], broken: {}, elevator_unlocked: false };
}

export function applyMining(s: FarmState, cmd: Command, ctx: Ctx): Result<FarmState> | null {
  if (!isMineCommand(cmd)) return null;
  if (!s.journey) return err('NOT_AVAILABLE', 'Start your neighbourhood journey first');
  const current = s.mine ?? initialMineState();
  if (!Number.isSafeInteger(cmd.run) || cmd.run < 0 || cmd.run !== current.run)
    return err('NOT_AVAILABLE', 'This mine expedition has changed');
  const next = structuredClone(s);
  const mine = next.mine ??= initialMineState();
  const config = ctx.content.mining;
  ensureMineCombat(mine, ctx.content);
  if (cmd.type === 'enter_mine') {
    if (mine.floor !== 0) return err('NOT_AVAILABLE', 'You are already inside the mine');
    mine.floor = 1;
    grantStarterWeapon(next, ctx.content);
  } else if (cmd.type === 'restart_mine') {
    if (mine.floor !== 0 || !mine.cleared_floors.includes(config.floors))
      return err('NOT_AVAILABLE', 'Finish the fifth floor and return to the farm first');
    if (mine.run === Number.MAX_SAFE_INTEGER) return err('NOT_AVAILABLE');
    next.mine = { ...initialMineState(), run: mine.run + 1, elevator_unlocked: mine.elevator_unlocked };
    return ok(next, [{ type: 'mine_restarted', run: next.mine.run }]);
  } else {
    if (!Number.isSafeInteger(cmd.floor) || cmd.floor < 1 || cmd.floor > config.floors || cmd.floor !== mine.floor)
      return err('NOT_AVAILABLE', 'This mine floor has changed');
    switch (cmd.type) {
      case 'leave_mine':
        mine.floor = 0;
        break;
      case 'ascend_mine':
        if (mine.floor === 1) return err('NOT_AVAILABLE', 'Use the mine exit to return to the farm');
        mine.floor -= 1;
        break;
      case 'descend_mine':
        if (mine.floor >= config.floors || !mine.cleared_floors.includes(mine.floor))
          return err('NOT_AVAILABLE', 'Clear the rocks or monsters on this floor to open the ladder');
        mine.floor += 1;
        break;
      case 'use_mine_elevator':
        if (!mine.elevator_unlocked || (mine.floor !== 1 && mine.floor !== config.floors))
          return err('NOT_AVAILABLE', 'Clear the fifth floor to unlock the elevator');
        mine.floor = mine.floor === 1 ? config.floors : 1;
        break;
      case 'mine_rock': {
        if (typeof cmd.node_id !== 'string' || !mineRocks(config, mine.floor).some(rock => rock.id === cmd.node_id))
          return err('NOT_AVAILABLE', 'Unknown mine rock');
        const broken = mine.broken[String(mine.floor)] ??= [];
        if (broken.includes(cmd.node_id)) return err('ALREADY_CLAIMED', 'This rock has already been mined');
        if (!gatheringReady(s, next, ctx, gatherSeconds(s, ctx.content, 'ore', 1))) return err('WORK_COOLDOWN');
        // Stable farm/run/floor/node draws prevent retries, re-entry, or mining order from rerolling rewards.
        const digest = createHash('sha256').update(JSON.stringify([
          ctx.farmId ?? 'domain-test', mine.run, mine.floor, cmd.node_id,
        ])).digest();
        const totalWeight = config.bonus_drops.reduce((sum, drop) => sum + drop.weight, 0);
        let roll = digest.readUInt32BE(0) / 0x100000000 * totalWeight;
        const bonus = characterStats(s, ctx.content).mining_bonus;
        const rewards: Partial<Record<JourneyMaterial, number>> = { stone: config.stone_per_rock + bonus };
        for (const drop of config.bonus_drops) {
          if (roll < drop.weight) {
            if (drop.material) rewards[drop.material] = drop.quantity;
            break;
          }
          roll -= drop.weight;
        }
        const materials = next.journey!.materials ??= { stone: 0, fiber: 0 };
        for (const [id, quantity] of Object.entries(rewards)) {
          const material = id as Exclude<JourneyMaterial, 'wood'>;
          materials[material] = (materials[material] ?? 0) + quantity!;
        }
        broken.push(cmd.node_id);
        updateMineClearance(mine, ctx.content);
        mine.last_drop = { floor: mine.floor, node_id: cmd.node_id, materials: rewards };
        if (bonus > 0) spendCharacterBuff(next, 'mining_bonus', ctx.content);
        return ok(next, [{ type: 'rock_mined', ...mine.last_drop, elevator_unlocked: mine.elevator_unlocked }]);
      }
    }
  }
  mine.deepest_floor = Math.max(mine.deepest_floor, mine.floor);
  delete mine.last_drop;
  return ok(next, [{ type: 'mine_floor_changed', floor: mine.floor }]);
}
