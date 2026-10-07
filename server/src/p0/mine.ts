/**
 * Mine floors 1–2 (plan §13.3, LOCK-21; SGODOT-231). A run starts by paying floor 1 (2 Energy); stairs or the elevator pay
 * a floor the first time the run reaches it (2), once the floor above is cleared; every rock is 2. Two runs a player day;
 * a new run needs this run's floor 2 cleared; the 04:00 rollover ends an unfinished run. Each rock gives Stone by the
 * pickaxe plus one weighted extra drop derived from the run seed, floor and rock, so a retry or a torch never re-rolls.
 * The server has no position: commands from another space (cmd.space) are refused, otherwise the client keeps the player
 * in the mine. Ported from the 2026-10-05 recovery (production.ts), on the v3 save and the expect_seq dedupe.
 */
import { createHash } from 'node:crypto';
import { add, count, room, take, type BagHolder } from './bag.js';
import type { P0Content } from './content.js';
import type { Refusal } from './fishing.js';
import { energyDetail, spendEnergy, type P0Event } from './progress.js';
import { dayKey, untilRollover } from './rules.js';
import type { MineRun, P0State } from './state.js';

export type MineCommand =
  | { type: 'mine_enter' }                         // Continue run · Free, or Enter mine · 2 Energy (a new run)
  | { type: 'mine_new_run' }                       // New run · 2 Energy: ends the current run (needs its floor 2 cleared)
  | { type: 'mine_floor'; floor: number }          // stairs / elevator: pays an unpaid floor, free otherwise
  | { type: 'mine_rock'; floor: number; rock: number }
  | { type: 'mine_torch'; floor: number };

const TYPES = new Set(['mine_enter', 'mine_new_run', 'mine_floor', 'mine_rock', 'mine_torch']);
export function isMineCommand(cmd: { type: string }): cmd is MineCommand { return TYPES.has(cmd.type); }

/**
 * The 04:00 rollover ends an unfinished run (same lazy settle as energy and boards, for commands and the view). `at` is
 * the rollover itself, not the moment it was noticed, so every view of it is the same and the client floats it once.
 */
export function settleMine(c: P0Content, s: P0State, now: number): void {
  const run = s.mine.run;
  if (run && run.day !== dayKey(c, now)) {
    s.mine.run = null;
    s.mine.ended = { reason: 'reset', at: rolloverAfter(c, run.day) };
  }
}

/** The 04:00 home-time moment that ends player day `day` (YYYY-MM-DD). */
function rolloverAfter(c: P0Content, day: string): number {
  return Date.parse(`${day}T00:00:00Z`) + 86_400_000 - (c.day.utc_offset_hours - c.day.rollover_hour) * 3_600_000;
}

export function floorCleared(c: P0Content, run: MineRun, floor: number): boolean {
  return (run.floors[floor - 1]?.broken.length ?? 0) >= c.mine.rocks;
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

/** The weighted extra drop of one rock: sha256(player:seed:floor:rock), never the save's rng. */
export function rockDrop(c: P0Content, s: P0State, run: MineRun, floor: number, rock: number): string | null {
  const weights = c.mine.floors[floor - 1].drops;
  const total = weights.reduce((n, [, w]) => n + w, 0);
  const hash = createHash('sha256').update(`${s.player}:${run.seed}:${floor}:${rock}`).digest().readUInt32BE(0);
  let pick = hash / 0x1_0000_0000 * total;
  for (const [id, w] of weights) { if (pick < w) return id; pick -= w; }
  return null;
}

/**
 * q(44): a floor is minable when one rock's worst case fits — the pickaxe's Stone plus any one of the floor's ores —
 * judged for the whole floor, so a grey rock never tells which one holds copper.
 */
export function bagFitsFloor(c: P0Content, s: P0State, floor: number): boolean {
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

function startRun(c: P0Content, s: P0State, now: number, events: P0Event[]): Refusal | null {
  if (s.day.mine_runs >= c.mine.runs_per_day)
    return { code: 'no_runs', detail: { used: s.day.mine_runs, limit: c.mine.runs_per_day, resets_in: untilRollover(c, now) } };
  if (s.energy.value < c.mine.floor_energy) return { code: 'need_energy', detail: energyDetail(c, s, now, c.mine.floor_energy) };
  spendEnergy(c, s, now, c.mine.floor_energy, events, 'mine_floor');
  const id = ++s.mine.count;
  const seed = createHash('sha256').update(`${s.player}:run:${id}`).digest().readUInt32BE(0);
  s.mine.run = { id, seed, day: dayKey(c, now), floors: c.mine.floors.map((_, i) => ({ paid: i === 0, broken: [], lit: false })) };
  s.mine.ended = null;
  s.day.mine_runs += 1;
  events.push({ kind: 'mine', action: 'enter', run: id, floor: 1, cost: c.mine.floor_energy });
  return null;
}

export function mineCommand(c: P0Content, s: P0State, cmd: MineCommand & { space?: string }, now: number, events: P0Event[]): Refusal | null {
  // Entering is from the farm's mine mouth; everything else happens inside. Older clients send no space.
  if (cmd.space !== undefined && cmd.type !== 'mine_enter' && cmd.type !== 'mine_new_run' && cmd.space !== 'mine') return { code: 'not_in_mine' };
  switch (cmd.type) {
    case 'mine_enter': {
      const run = s.mine.run;
      if (!run) return startRun(c, s, now, events);
      events.push({ kind: 'mine', action: 'continue', run: run.id, floor: deepestPaid(run), cost: 0 });
      return null;
    }
    case 'mine_new_run': {
      const run = s.mine.run;
      if (run && !floorCleared(c, run, c.mine.restart_floor)) return { code: 'clear_floor_first', detail: { floor: c.mine.restart_floor } };
      return startRun(c, s, now, events);
    }
    case 'mine_floor': case 'mine_rock': case 'mine_torch': {
      const run = s.mine.run;
      if (!run) return { code: 'no_run' };
      const n = Number(cmd.floor);
      if (!Number.isInteger(n) || n < 1 || n > run.floors.length) return { code: 'bad_floor' };
      const floor = run.floors[n - 1];
      if (cmd.type === 'mine_floor') {
        if (!floor.paid) {
          if (!floorCleared(c, run, n - 1)) return { code: 'clear_floor_first', detail: { floor: n - 1 } };
          if (s.energy.value < c.mine.floor_energy) return { code: 'need_energy', detail: energyDetail(c, s, now, c.mine.floor_energy) };
          spendEnergy(c, s, now, c.mine.floor_energy, events, 'mine_floor');
          floor.paid = true;
          events.push({ kind: 'mine', action: 'floor', run: run.id, floor: n, cost: c.mine.floor_energy });
        } else events.push({ kind: 'mine', action: 'floor', run: run.id, floor: n, cost: 0 });
        return null;
      }
      if (!floor.paid) return { code: 'floor_not_paid', detail: { floor: n } };
      if (cmd.type === 'mine_torch') {
        if (floor.lit) return { code: 'lit' };
        if (count(s.bag, 'torch') < 1) return { code: 'no_item', detail: { item: 'torch' } };
        take(s.bag, 'torch', 1);
        floor.lit = true;
        events.push({ kind: 'item', id: 'torch', delta: -1 }, { kind: 'mine', action: 'torch', run: run.id, floor: n, cost: 0 });
        return null;
      }
      const rock = Number(cmd.rock);
      if (!Number.isInteger(rock) || rock < 0 || rock >= c.mine.rocks) return { code: 'bad_rock' };
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
      if (floor.broken.length === c.mine.rocks) events.push({ kind: 'mine', action: 'cleared', run: run.id, floor: n, cost: 0 });
      return null;
    }
  }
}

/** What the mine mouth, the floors and the elevator show (§13.3.1, §13.3.9): facts only; P0MaterialLogic writes the copy. */
export function mineView(c: P0Content, s: P0State, now: number) {
  const run = s.mine.run;
  return {
    runs: { used: s.day.mine_runs, limit: c.mine.runs_per_day, resets_in: untilRollover(c, now) },
    ended: s.mine.ended,
    floor_energy: c.mine.floor_energy, rock_energy: c.mine.rock_energy, rocks: c.mine.rocks,
    stone_per_rock: stonePerRock(c, s),
    run: run && {
      id: run.id, deepest: deepestPaid(run),
      can_new_run: floorCleared(c, run, c.mine.restart_floor) && s.day.mine_runs < c.mine.runs_per_day,
      new_run_block: !floorCleared(c, run, c.mine.restart_floor) ? 'clear_floor_2' : s.day.mine_runs >= c.mine.runs_per_day ? 'no_runs' : null,
      floors: run.floors.map((f, i) => ({
        floor: i + 1, paid: f.paid, cleared: f.broken.length >= c.mine.rocks, left: c.mine.rocks - f.broken.length,
        broken: Array.from({ length: c.mine.rocks }, (_, r) => f.broken.includes(r)),
        lit: f.lit,
        preview: f.lit ? Array.from({ length: c.mine.rocks }, (_, r) => rockDrop(c, s, run, i + 1, r)) : null,   // null = Stone only
        bag_ok: bagFitsFloor(c, s, i + 1),
      })),
    },
  };
}
