import type { Command } from './commands.js';
import { mainHandStats } from './character.js';
import { createHash } from 'node:crypto';
import { mineRocks, type Content, type CropId } from './content.js';
import { characterStats } from './character.js';
import { err, ok, type Result } from './errors.js';
import type { Ctx } from './reducer.js';
import type { FarmState, MineState } from './state.js';

export function ensureMineCombat(mine: MineState, content: Content): void {
  if (mine.combat?.version === 2) return;
  if (!mine.combat) {
    mine.combat = { version: 2, sequence: 0, defeats: 0, monsters: {} };
    for (const [floor, kinds] of Object.entries(content.mining.combat.floors)) {
      // Completed legacy floors keep their clearance and never receive retroactive rewards.
      mine.combat.monsters[floor] = kinds.map(kind => mine.cleared_floors.includes(Number(floor))
        ? 0 : content.mining.combat.monsters[kind].hp);
    }
  } else {
    // Domain 19 elites had 150 HP. Preserve the remaining fraction and never revive a kill.
    const elite = mine.combat.monsters['5'];
    if (elite?.[0] > 0) elite[0] = Math.ceil(Math.min(1, elite[0] / 150) * content.mining.combat.monsters.elite_slime.hp);
    mine.combat.version = 2;
  }
  for (let floor = 1; floor <= content.mining.floors; floor++) recordClearance(mine, content, floor);
}

function recordClearance(mine: MineState, content: Content, floor: number): void {
  const rocks = mineRocks(content.mining, floor);
  const monsters = mine.combat!.monsters[String(floor)] ?? [];
  const rocksDone = rocks.length > 0 && rocks.every(rock => mine.broken[String(floor)]?.includes(rock.id));
  const monstersDone = monsters.length > 0 && monsters.every(hp => hp === 0);
  if (!rocksDone && !monstersDone) return;
  if (!mine.cleared_floors.includes(floor)) mine.cleared_floors.push(floor);
  if (floor === content.mining.floors) mine.elevator_unlocked = true;
}

export function updateMineClearance(mine: MineState, content: Content): void {
  ensureMineCombat(mine, content);
  if (mine.floor > 0 && mine.floor <= content.mining.floors) recordClearance(mine, content, mine.floor);
}

export function applyCombat(state: FarmState, cmd: Command, ctx: Ctx): Result<FarmState> | null {
  if (cmd.type !== 'mine_combat') return null;
  if (!state.journey || !state.mine || !Number.isSafeInteger(cmd.run) || cmd.run !== state.mine.run
    || !Number.isSafeInteger(cmd.floor) || cmd.floor < 1 || cmd.floor !== state.mine.floor) return err('NOT_AVAILABLE');
  const next = structuredClone(state);
  const mine = next.mine!;
  const config = ctx.content.mining.combat;
  ensureMineCombat(mine, ctx.content);
  const fight = mine.combat!;
  if (!Number.isSafeInteger(cmd.sequence) || cmd.sequence !== fight.sequence) return err('NOT_AVAILABLE');
  const kinds = config.floors[String(mine.floor)];
  const hp = fight.monsters[String(mine.floor)];
  const indexOf = (id: unknown) => typeof id === 'string' && /^slime_[1-3]$/.test(id) ? Number(id.slice(6)) - 1 : -1;
  const alive = (id: unknown) => { const i = indexOf(id); return i >= 0 && i < kinds.length && hp[i] > 0; };
  if (!Array.isArray(cmd.targets) || cmd.targets.length > kinds.length || new Set(cmd.targets).size !== cmd.targets.length
    || cmd.targets.some(id => !alive(id)) || (cmd.hurt_by !== undefined && !alive(cmd.hurt_by))
    || (!cmd.targets.length && cmd.hurt_by === undefined)) return err('NOT_AVAILABLE');
  // The single-player scene owns movement, collision and hit arcs. Damage, cooldowns,
  // equipment, defeat rewards and replay protection are settled here from shared content.
  const now = ctx.realNow ?? ctx.now;
  const weapon = mainHandStats(state, ctx.content);
  if (cmd.targets.length && (!weapon || now < (fight.last_attack_at ?? -Infinity) + 1000 / Number(weapon.speed)))
    return err('NOT_AVAILABLE');
  if (cmd.hurt_by !== undefined && now < (fight.last_hurt_at ?? -Infinity) + config.invulnerability_ms)
    return err('NOT_AVAILABLE');
  const result = { damage: 0, hurt: 0, defeated: [] as string[], rescued: false,
    loot: {} as Record<string, number>,
    materials: {} as NonNullable<MineState['last_drop']>['materials'] };
  if (cmd.targets.length) fight.last_attack_at = now;
  for (const id of cmd.targets) {
    const index = indexOf(id);
    const monster = config.monsters[kinds[index]];
    const damage = Math.max(1, Number(weapon!.damage) - monster.defense);
    result.damage += Math.min(hp[index], damage);
    hp[index] = Math.max(0, hp[index] - damage);
    if (hp[index] !== 0) continue;
    result.defeated.push(id);
    const digest = createHash('sha256').update(JSON.stringify([
      'mine-loot', config.version, ctx.farmId ?? 'domain-test', mine.run, mine.floor, id,
    ])).digest();
    let roll = digest.readUInt32BE(0) / 0x100000000 * monster.loot.reduce((sum, drop) => sum + drop.weight, 0);
    for (const drop of monster.loot) {
      if (roll >= drop.weight) { roll -= drop.weight; continue; }
      result.loot[drop.item_id] = (result.loot[drop.item_id] ?? 0) + drop.quantity;
      const source = ctx.content.items.items[drop.item_id].source;
      if (source.kind === 'seed') next.inventory.seeds[source.id as CropId].bound += drop.quantity;
      else {
        const material = source.id as keyof typeof result.materials;
        result.materials[material] = (result.materials[material] ?? 0) + drop.quantity;
      }
      break;
    }
  }
  // A lethal player strike wins a simultaneous clash with that monster.
  if (cmd.hurt_by !== undefined && alive(cmd.hurt_by)) {
    fight.last_hurt_at = now;
    result.hurt = Math.min(next.character!.hp!, Math.max(1,
      config.monsters[kinds[indexOf(cmd.hurt_by)]].damage - characterStats(next, ctx.content).defense));
    next.character!.hp! -= result.hurt;
    if (next.character!.hp! <= 0) {
      next.character!.hp = 1;
      result.rescued = true;
      fight.defeats += 1;
    }
  }
  const materials = next.journey!.materials ??= { stone: 0, fiber: 0 };
  for (const [id, amount] of Object.entries(result.materials)) {
    if (id === 'wood') next.journey!.wood += amount!;
    else { const key = id as keyof typeof materials; materials[key] = (materials[key] ?? 0) + amount!; }
  }
  updateMineClearance(mine, ctx.content);
  if (result.rescued) mine.floor = 0;
  fight.sequence += 1;
  fight.last_result = result;
  return ok(next, [{ type: 'mine_combat_resolved', ...result }]);
}
