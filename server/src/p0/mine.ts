/**
 * Mine floors 1–5 (plan §13.3, LOCK-21; SGODOT-231 floors 1–2, SGODOT-275 floors 3–5). A run starts by paying floor 1
 * (2 Energy); stairs or the elevator pay a floor the first time the run reaches it (2), once the floor above is cleared;
 * every rock is 2. Two runs a player day; a new run needs this run's floor 2 cleared (an Express run counts as having
 * it); the 04:00 rollover ends an unfinished run. Each rock gives Stone by the pickaxe plus one weighted extra drop
 * derived from the run seed, floor and rock, so a retry or a torch never re-rolls.
 * Floors 3–4 have slimes, floor 5 only its elite (§13.3.4): fighting is 0 Energy. The client owns movement, the slimes'
 * moves and the swing arc (as the old mining combat did); the server settles the swing cooldown, damage, hits, HP and
 * loot. Floors 1–4 clear when their rocks are broken (monsters may be left); floor 5 clears when its elite is beaten,
 * which ends the run (Run complete). The first clear of floor 4 opens Floor 5 · Express for the account: 0 Energy, no
 * floor 5 fee, from the mouth it starts a run. The elite's quartz drops once a player day. HP counts only in the mine:
 * 0 knocks the player back to the mine mouth with the run kept; entering refills it.
 * The server has no position: commands from another space (cmd.space) are refused, otherwise the client keeps the player
 * in the mine. Ported from the 2026-10-05 recovery (production.ts) and the old domain mining / combat.
 */
import { createHash } from 'node:crypto';
import { add, count, room, take, type BagHolder } from './bag.js';
import type { P0Content } from './content.js';
import type { Refusal } from './fishing.js';
import { energyDetail, spendEnergy, type P0Event } from './progress.js';
import { dayKey, rolloverAfter, untilRollover } from './rules.js';
import type { MineRun, P0State } from './state.js';
import { putInStorage } from './storage.js';

export type MineCommand =
  | { type: 'mine_enter' }                         // Continue run · Free, or Enter mine · 2 Energy (a new run)
  | { type: 'mine_new_run' }                       // New run · 2 Energy: ends the current run (needs its floor 2 cleared)
  | { type: 'mine_express' }                       // Floor 5 · Express · Free: from the mouth a new run, inside a ride
  | { type: 'mine_floor'; floor: number }          // stairs / elevator: pays an unpaid floor, free otherwise
  | { type: 'mine_rock'; floor: number; rock: number }
  | { type: 'mine_torch'; floor: number }
  | { type: 'mine_attack'; floor: number; targets?: number[]; hurt_by?: number };   // a swing's hits and/or a monster's hit

const TYPES = new Set(['mine_enter', 'mine_new_run', 'mine_express', 'mine_floor', 'mine_rock', 'mine_torch', 'mine_attack']);
export function isMineCommand(cmd: { type: string }): cmd is MineCommand { return TYPES.has(cmd.type); }
const FROM_OUTSIDE = new Set(['mine_enter', 'mine_new_run', 'mine_express']);

/**
 * The 04:00 rollover ends an unfinished run (same lazy settle as energy and boards, for commands and the view). `at` is
 * the rollover itself, not the moment it was noticed, so every view of it is the same and the client floats it once.
 */
export function settleMine(c: P0Content, s: P0State, now: number): void {
  const run = s.mine.run;
  if (run && run.day !== dayKey(c, s, now)) {
    s.mine.run = null;
    s.mine.ended = { reason: 'reset', at: rolloverAfter(c, s, run.day) };
  }
}

/** Rocks on a floor (§13.3.2: 6 on floors 1–4, none on floor 5). */
export function floorRocks(c: P0Content, floor: number): number {
  return c.mine.floors[floor - 1]?.rocks ?? c.mine.rocks;
}

/** A floor's monsters' HP left; a run saved before SGODOT-275 meets its monsters at full HP. */
export function floorMobs(c: P0Content, run: MineRun, floor: number): number[] {
  const f = run.floors[floor - 1];
  const kinds = c.mine.floors[floor - 1]?.mobs ?? [];
  if (!f) return [];
  if (!f.mobs || f.mobs.length !== kinds.length) f.mobs = kinds.map(k => c.mine.monsters[k].hp);
  return f.mobs;
}

/** §13.3.9: floors with rocks clear when every rock is broken (monsters may be left); a floor of monsters only (floor 5)
 * when they are all beaten. */
export function floorCleared(c: P0Content, run: MineRun, floor: number): boolean {
  if (!run.floors[floor - 1]) return false;
  const rocks = floorRocks(c, floor);
  if (rocks > 0) return run.floors[floor - 1].broken.length >= rocks;
  const mobs = floorMobs(c, run, floor);
  return mobs.length > 0 && mobs.every(hp => hp <= 0);
}

/** New run's condition (§13.3.1): this run's floor 2 cleared, or an Express run (it skipped floors 1–4). */
function restartOpen(c: P0Content, run: MineRun): boolean {
  return !!run.express || floorCleared(c, run, c.mine.restart_floor);
}

/** Deepest floor this run has paid: Continue run lands here (§13.3.1). */
export function deepestPaid(run: MineRun): number {
  let deepest = 0;
  run.floors.forEach((f, i) => { if (f.paid) deepest = i + 1; });
  return deepest;
}

export function stonePerRock(c: P0Content, s: P0State): number {
  return c.mine.picks[s.gear.pick]?.stone ?? 1;
}

/** The Combat slot's weapon (§13.3.8): the Wooden Sword until weapons drop (P1 has no other). */
export function weapon(c: P0Content): { attack: number; speed: number } {
  return c.mine.combat.weapons[c.tools.combat] ?? { attack: 1, speed: 1 };
}

/** The player's HP in this run; a run saved before SGODOT-275 starts full. */
export function runHp(c: P0Content, run: MineRun): number {
  return run.hp ?? c.mine.combat.hp;
}

/** The weighted extra drop of one rock: sha256(player:seed:floor:rock), never the save's rng. */
export function rockDrop(c: P0Content, s: P0State, run: MineRun, floor: number, rock: number): string | null {
  const weights = c.mine.floors[floor - 1].drops;
  const total = weights.reduce((n, [, w]) => n + w, 0);
  const hash = createHash('sha256').update(`${s.player}:${run.seed}:${floor}:${rock}`).digest().readUInt32BE(0);
  let pick = hash / 0x1_0000_0000 * total;
  for (const [id, w] of weights) { if (pick < w) return id; pick -= w; }
  return null;
}

/** Elite kills so far this player day (its quartz drops on the first, §13.3.4). */
function eliteKillsToday(c: P0Content, s: P0State, now: number): number {
  return s.mine.elite?.day === dayKey(c, s, now) ? s.mine.elite.kills : 0;
}

/**
 * One monster's loot, from sha256(player:seed:floor:mob:index), never the save's rng. A once-a-day item already given
 * today drops out and its weight is shared out over the rest in proportion (§13.3.4: the elite's second kill a day).
 */
export function mobLoot(c: P0Content, s: P0State, run: MineRun, floor: number, index: number, now: number): [string, number] | null {
  const kind = c.mine.floors[floor - 1].mobs![index];
  const m = c.mine.monsters[kind];
  const spent = m.once_a_day && eliteKillsToday(c, s, now) > 0 ? m.once_a_day : null;
  const loot = m.loot.filter(([id]) => id !== spent);
  const total = loot.reduce((n, [, , w]) => n + w, 0);
  const hash = createHash('sha256').update(`${s.player}:${run.seed}:${floor}:mob:${index}`).digest().readUInt32BE(0);
  let pick = hash / 0x1_0000_0000 * total;
  for (const [id, qty, w] of loot) { if (pick < w) return [id, qty]; pick -= w; }
  return null;
}

/**
 * q(44): a floor is minable when one rock's worst case fits — the pickaxe's Stone plus any one of the floor's ores —
 * judged for the whole floor, so a grey rock never tells which one holds copper. A floor without rocks always fits
 * (its monsters' loot that does not fit goes to Farm Storage, like a gathering spot's).
 */
export function bagFitsFloor(c: P0Content, s: P0State, floor: number): boolean {
  if (floorRocks(c, floor) === 0) return true;
  const stone = stonePerRock(c, s);
  if (room(c, s, 'stone') < stone) return false;
  for (const [id] of c.mine.floors[floor - 1].drops) {
    if (!id) continue;
    const trial: BagHolder = { bag: structuredClone(s.bag), bag_cap: s.bag_cap };
    add(c, trial, 'stone', stone);
    if (room(c, trial, id) < 1) return false;
  }
  return true;
}

function newRun(c: P0Content, s: P0State, now: number, express: boolean): MineRun {
  const id = ++s.mine.count;
  const seed = createHash('sha256').update(`${s.player}:run:${id}`).digest().readUInt32BE(0);
  const last = c.mine.floors.length;
  const run: MineRun = {
    id, seed, day: dayKey(c, s, now), hp: c.mine.combat.hp, ...(express ? { express: true } : {}),
    floors: c.mine.floors.map((def, i) => ({
      paid: express ? i + 1 === last : i === 0, broken: [], lit: false,
      mobs: (def.mobs ?? []).map(k => c.mine.monsters[k].hp),
    })),
  };
  s.mine.run = run;
  s.mine.ended = null;
  s.day.mine_runs += 1;
  return run;
}

function noRunsLeft(c: P0Content, s: P0State, now: number): Refusal | null {
  return s.day.mine_runs >= c.mine.runs_per_day
    ? { code: 'no_runs', detail: { used: s.day.mine_runs, limit: c.mine.runs_per_day, resets_in: untilRollover(c, s, now) } } : null;
}

function startRun(c: P0Content, s: P0State, now: number, events: P0Event[]): Refusal | null {
  const none = noRunsLeft(c, s, now);
  if (none) return none;
  // q(48): a floor fee is never paid into a floor whose first rock wouldn't fit (Enter mine · Bag full).
  if (!bagFitsFloor(c, s, 1)) return { code: 'bag_full', detail: { floor: 1 } };
  if (s.energy.value < c.mine.floor_energy) return { code: 'need_energy', detail: energyDetail(c, s, now, c.mine.floor_energy) };
  spendEnergy(c, s, now, c.mine.floor_energy, events, 'mine_floor');
  const run = newRun(c, s, now, false);
  events.push({ kind: 'mine', action: 'enter', run: run.id, floor: 1, cost: c.mine.floor_energy });
  return null;
}

/** Floor 5 · Express · Free (§13.3.1, §13.3.9): 0 Energy, no floor 5 fee. From the mouth it is a new run (a run a day);
 * with an unfinished run it goes as New run does (needs that run's floor 2 cleared); inside a run it is a free ride. */
function express(c: P0Content, s: P0State, cmd: { space?: string }, now: number, events: P0Event[]): Refusal | null {
  if (!s.mine.express) return { code: 'express_locked', detail: { floor: c.mine.express_unlock_floor } };
  const last = c.mine.floors.length;
  const run = s.mine.run;
  if (run && cmd.space === 'mine') {
    run.floors[last - 1].paid = true;   // the ride never pays floor 5's fee, even into an unpaid floor 5
    events.push({ kind: 'mine', action: 'express', run: run.id, floor: last, cost: 0 });
    return null;
  }
  if (run && !restartOpen(c, run)) return { code: 'clear_floor_first', detail: { floor: c.mine.restart_floor } };
  const none = noRunsLeft(c, s, now);
  if (none) return none;
  const fresh = newRun(c, s, now, true);
  fresh.hp = c.mine.combat.hp;
  events.push({ kind: 'mine', action: 'express', run: fresh.id, floor: last, cost: 0 });
  return null;
}

export function mineCommand(c: P0Content, s: P0State, cmd: MineCommand & { space?: string }, now: number, events: P0Event[]): Refusal | null {
  // Entering is from the farm's mine mouth; everything else happens inside (Express both). Older clients send no space.
  if (cmd.space !== undefined && !FROM_OUTSIDE.has(cmd.type) && cmd.space !== 'mine') return { code: 'not_in_mine' };
  switch (cmd.type) {
    case 'mine_enter': {
      const run = s.mine.run;
      if (!run) return startRun(c, s, now, events);
      run.hp = c.mine.combat.hp;   // HP counts only in the mine: back in, it is full again
      events.push({ kind: 'mine', action: 'continue', run: run.id, floor: deepestPaid(run), cost: 0 });
      return null;
    }
    case 'mine_new_run': {
      const run = s.mine.run;
      if (run && !restartOpen(c, run)) return { code: 'clear_floor_first', detail: { floor: c.mine.restart_floor } };
      return startRun(c, s, now, events);
    }
    case 'mine_express': return express(c, s, cmd, now, events);
    case 'mine_floor': case 'mine_rock': case 'mine_torch': case 'mine_attack': {
      const run = s.mine.run;
      if (!run) return { code: 'no_run' };
      const n = Number(cmd.floor);
      if (!Number.isInteger(n) || n < 1 || n > run.floors.length) return { code: 'bad_floor' };
      const floor = run.floors[n - 1];
      if (cmd.type === 'mine_floor') {
        if (!floor.paid) {
          if (!floorCleared(c, run, n - 1)) return { code: 'clear_floor_first', detail: { floor: n - 1 } };
          if (!bagFitsFloor(c, s, n)) return { code: 'bag_full', detail: { floor: n } };   // q(48): Floor 2 · Bag full
          if (s.energy.value < c.mine.floor_energy) return { code: 'need_energy', detail: energyDetail(c, s, now, c.mine.floor_energy) };
          spendEnergy(c, s, now, c.mine.floor_energy, events, 'mine_floor');
          floor.paid = true;
          events.push({ kind: 'mine', action: 'floor', run: run.id, floor: n, cost: c.mine.floor_energy });
        } else events.push({ kind: 'mine', action: 'floor', run: run.id, floor: n, cost: 0 });
        return null;
      }
      if (!floor.paid) return { code: 'floor_not_paid', detail: { floor: n } };
      if (cmd.type === 'mine_attack') return attack(c, s, run, n, cmd, now, events);
      const rocks = floorRocks(c, n);
      if (rocks === 0) return { code: 'no_rocks' };   // floor 5: No rocks here
      if (cmd.type === 'mine_torch') {
        if (floor.lit) return { code: 'lit' };
        if (count(s.bag, 'torch') < 1) return { code: 'no_item', detail: { item: 'torch' } };
        take(s.bag, 'torch', 1);
        floor.lit = true;
        events.push({ kind: 'item', id: 'torch', delta: -1 }, { kind: 'mine', action: 'torch', run: run.id, floor: n, cost: 0 });
        return null;
      }
      const rock = Number(cmd.rock);
      if (!Number.isInteger(rock) || rock < 0 || rock >= rocks) return { code: 'bad_rock' };
      if (floor.broken.includes(rock)) return { code: 'rock_gone' };
      if (now - s.mine.swing_at < c.mine.tempo_ms) return { code: 'tempo', detail: { ready_in: c.mine.tempo_ms - (now - s.mine.swing_at) } };
      if (!bagFitsFloor(c, s, n)) return { code: 'bag_full', detail: { floor: n } };
      if (s.energy.value < c.mine.rock_energy) return { code: 'need_energy', detail: energyDetail(c, s, now, c.mine.rock_energy) };
      spendEnergy(c, s, now, c.mine.rock_energy, events, 'mine_rock');
      const stone = stonePerRock(c, s), drop = rockDrop(c, s, run, n, rock);
      add(c, s, 'stone', stone);
      events.push({ kind: 'item', id: 'stone', delta: stone });
      if (drop) { add(c, s, drop, 1); events.push({ kind: 'item', id: drop, delta: 1 }); }
      floor.broken.push(rock);
      s.mine.swing_at = now;
      events.push({ kind: 'mine', action: 'rock', run: run.id, floor: n, rock, drop, cost: c.mine.rock_energy });
      if (floor.broken.length === rocks) {
        events.push({ kind: 'mine', action: 'cleared', run: run.id, floor: n, cost: 0 });
        if (n === c.mine.express_unlock_floor && !s.mine.express) {
          s.mine.express = true;   // §13.3.1: the account has cleared floor 4 once
          events.push({ kind: 'mine', action: 'express_unlocked', run: run.id, floor: n, cost: 0 });
        }
      }
      return null;
    }
  }
}

/** Loot into the bag as far as it fits, the rest to Farm Storage (fighting is never refused for a full bag). */
function giveLoot(c: P0Content, s: P0State, id: string, qty: number, events: P0Event[]): void {
  const toBag = Math.min(qty, room(c, s, id));
  if (toBag > 0) { add(c, s, id, toBag); events.push({ kind: 'item', id, delta: toBag }); }
  if (qty - toBag > 0) putInStorage(s, id, qty - toBag);
}

/**
 * One swing's hits and/or one monster's hit (§13.3.4, §13.3.8), the old mining combat's split: the client says which
 * monsters the swing reached (targets) and which one reached the player (hurt_by); the server checks they are alive,
 * the swing cooldown (weapon speed) and the hit cooldown (invulnerability), then settles damage, HP and loot. A lethal
 * swing wins a simultaneous clash with that monster. All 0 Energy.
 */
function attack(c: P0Content, s: P0State, run: MineRun, n: number, cmd: { targets?: unknown; hurt_by?: unknown },
  now: number, events: P0Event[]): Refusal | null {
  const kinds = c.mine.floors[n - 1].mobs ?? [];
  const hp = floorMobs(c, run, n);
  const isIndex = (x: unknown): x is number => Number.isInteger(x) && (x as number) >= 0 && (x as number) < kinds.length;
  const targets = cmd.targets === undefined ? [] : cmd.targets;
  if (!Array.isArray(targets) || targets.length > kinds.length || new Set(targets).size !== targets.length
    || !targets.every(isIndex)) return { code: 'bad_target' };
  const hurtBy = cmd.hurt_by;
  if (hurtBy !== undefined && !isIndex(hurtBy)) return { code: 'bad_target' };
  if (!targets.length && hurtBy === undefined) return { code: 'bad_target' };
  if (targets.some(i => hp[i] <= 0) || (hurtBy !== undefined && hp[hurtBy] <= 0)) return { code: 'mob_gone' };
  const w = weapon(c);
  if (targets.length && now - (run.attack_at ?? -Infinity) < 1000 / w.speed)
    return { code: 'tempo', detail: { ready_in: Math.ceil(1000 / w.speed - (now - (run.attack_at ?? -Infinity))) } };
  const hurtOk = hurtBy !== undefined && now - (run.hurt_at ?? -Infinity) >= c.mine.combat.invulnerability_ms;
  if (targets.length) run.attack_at = now;
  const defeated: number[] = [];
  for (const i of targets) {
    hp[i] = Math.max(0, hp[i] - w.attack);
    events.push({ kind: 'mine', action: 'hit', run: run.id, floor: n, mob: i, hp: hp[i], damage: w.attack, cost: 0 });
    if (hp[i] > 0) continue;
    defeated.push(i);
    const elite = !!c.mine.monsters[kinds[i]].once_a_day;
    const loot = mobLoot(c, s, run, n, i, now);   // judged before this kill counts toward the day
    if (elite) {
      const day = dayKey(c, s, now);
      s.mine.elite = { day, kills: eliteKillsToday(c, s, now) + 1 };
    }
    if (loot) giveLoot(c, s, loot[0], loot[1], events);
    events.push({ kind: 'mine', action: 'defeat', run: run.id, floor: n, mob: i, mob_kind: kinds[i], loot, cost: 0,
      ...(elite && eliteKillsToday(c, s, now) > 1 ? { quartz_spent: true } : {}) });
  }
  // A lethal swing wins the clash with the monster it killed; a hit inside the invulnerability window does nothing.
  if (hurtBy !== undefined && hurtOk && hp[hurtBy] > 0) {
    run.hurt_at = now;
    const damage = c.mine.monsters[kinds[hurtBy]].damage;
    run.hp = Math.max(0, runHp(c, run) - damage);
    events.push({ kind: 'mine', action: 'hurt', run: run.id, floor: n, mob: hurtBy, hp: run.hp, damage, cost: 0 });
    if (run.hp <= 0) {
      run.hp = c.mine.combat.hp;   // Knocked out · back at the entrance: the run is kept, HP full outside
      events.push({ kind: 'mine', action: 'knocked_out', run: run.id, floor: n, cost: 0 });
    }
  }
  if (floorRocks(c, n) === 0 && floorCleared(c, run, n)) {   // floor 5: its elite beaten ends the run
    events.push({ kind: 'mine', action: 'cleared', run: run.id, floor: n, cost: 0 }, { kind: 'mine', action: 'complete', run: run.id, floor: n, cost: 0 });
    s.mine.completed = { run: run.id, at: now };
    s.mine.run = null;
  }
  return null;
}

/** What the mine mouth, the floors and the elevator show (§13.3.1, §13.3.9): facts only; P0MaterialLogic writes the copy. */
export function mineView(c: P0Content, s: P0State, now: number) {
  const run = s.mine.run;
  return {
    runs: { used: s.day.mine_runs, limit: c.mine.runs_per_day, resets_in: untilRollover(c, s, now) },
    ended: s.mine.ended,
    completed: s.mine.completed ?? null,
    floor_energy: c.mine.floor_energy, rock_energy: c.mine.rock_energy, rocks: c.mine.rocks,
    entry_bag_ok: bagFitsFloor(c, s, 1),   // q(48): Enter mine / New run gate (floor 1's worst case)
    stone_per_rock: stonePerRock(c, s),
    floors: c.mine.floors.length,
    express: !!s.mine.express,                                   // Floor 5 · Express · Free is offered
    elite_quartz_today: eliteKillsToday(c, s, now) === 0,        // the elite still drops quartz today
    hp_max: c.mine.combat.hp, weapon: { id: c.tools.combat, ...weapon(c) },
    run: run && {
      id: run.id, deepest: deepestPaid(run), express: !!run.express, hp: runHp(c, run),
      can_new_run: restartOpen(c, run) && s.day.mine_runs < c.mine.runs_per_day,
      new_run_block: !restartOpen(c, run) ? 'clear_floor_2' : s.day.mine_runs >= c.mine.runs_per_day ? 'no_runs' : null,
      floors: run.floors.map((f, i) => {
        const rocks = floorRocks(c, i + 1);
        return {
          floor: i + 1, paid: f.paid, cleared: floorCleared(c, run, i + 1), rocks, left: rocks - f.broken.length,
          broken: Array.from({ length: rocks }, (_, r) => f.broken.includes(r)),
          lit: f.lit,
          preview: f.lit ? Array.from({ length: rocks }, (_, r) => rockDrop(c, s, run, i + 1, r)) : null,   // null = Stone only
          bag_ok: bagFitsFloor(c, s, i + 1),
          mobs: (c.mine.floors[i].mobs ?? []).map((kind, m) => ({ kind, hp: floorMobs(c, run, i + 1)[m], max: c.mine.monsters[kind].hp })),
        };
      }),
    },
  };
}
