/** 355 E: per-mine progress, deterministic daily floors, and content-driven combat. */
import { createHash } from 'node:crypto';
import { add, count, room, take, type BagHolder } from './bag.js';
import { seededRand } from './boards.js';
import type { MineSite, P0Content } from './content.js';
import type { Refusal } from './fishing.js';
import { energyDetail, spendEnergy, type P0Event } from './progress.js';
import { dayKey, rolloverAfter } from './rules.js';
import type { MineB1Day, MineB1FloorState, MineB1Record, P0State } from './state.js';
import { wildById } from './wild.js';

export type MineCommand =
  | { type: 'mine_enter'; mine: string; floor?: number }
  | { type: 'mine_floor'; day: string; to: number; via?: 'ladder' | 'elevator' }
  | { type: 'mine_rock'; day: string; floor: number; rock: number }
  | { type: 'mine_torch'; day: string; floor: number }
  | { type: 'mine_pick'; day: string; floor: number; ground: number }
  | { type: 'mine_attack'; day: string; floor: number; targets?: number[]; hurt_by?: number; stunned?: number[] };
const TYPES = new Set(['mine_enter', 'mine_floor', 'mine_rock', 'mine_torch', 'mine_attack', 'mine_pick']);
export const isMineCommand = (cmd: { type: string }): cmd is MineCommand => TYPES.has(cmd.type);

// Catalogue first; development fixtures never replace an authored wild site.
export function mineSite(c: P0Content, id: string): MineSite | undefined {
  const site = wildById(c, id);
  return site?.mine ? { ...site, mine: site.mine } : c.mine.dev_sites?.find(dev => dev.id === id);
}
const cap = (site: MineSite) => Math.min(site.mine.floors, site.mine.open_to ?? site.mine.floors);
const floorKey = (mine: string, floor: number) => `${mine}:${floor}`;
/** The deepest floor of any mine: the view's rank, and Pip's First Dig's count (contract-efg §9.2). */
export const mineRank = (s: P0State): number => Math.max(0, ...Object.values(s.mine.records).map(r => r.deepest));
export const stations = (record?: MineB1Record): number[] =>
  Array.from({ length: Math.floor((record?.deepest ?? 0) / 10) }, (_, i) => (i + 1) * 10);

export function floorSpec(c: P0Content, site: MineSite, floor: number, player: string, key: string) {
  if (!Number.isInteger(floor) || floor < 1 || floor > cap(site)) throw new RangeError('bad_floor');
  const type = c.mine.types[site.type];
  if (!type) throw new Error('not_open');
  const special = type.floors[String(floor)] ?? {};
  if (special.guard) return { mobs: [special.guard], rocks: 0, drops: [] as [string | null, number][], deck: [] as (string | null)[], guard: special.guard, hpMult: special.hp_mult ?? 1 };
  const band = type.bands.find(b => b.from <= floor && floor <= b.to)
    ?? [...type.bands].filter(b => b.to < floor).sort((a, b) => b.to - a.to)[0];
  if (!band) throw new Error(`No mine band for ${site.type}:${floor}`);
  const draw = seededRand(`${player}:mine@${site.id}:${floor}:${key}`), mobs: string[] = [];
  const append = (rows: [string, number, number][]) => {
    for (const [kind, min, max] of rows) {
      const n = min + Math.floor(draw() * (max - min + 1));
      for (let i = 0; i < n; i++) mobs.push(kind);
    }
  };
  if (special.only) mobs.push(...special.only);
  else { append(band.mobs); append(special.add ?? []); if (special.elite) mobs.push(special.elite); }
  const rocks = band.rocks[0] + Math.floor(draw() * (band.rocks[1] - band.rocks[0] + 1));
  const drops: [string | null, number][] = band.drops.map(([id, weight]) => [id, weight]);
  if (site.mine.main && type.main_weight?.length) {
    let weight = type.main_weight[0][1];
    // The second band shares the catalogue threshold shown on the mine entrance card (#625).
    for (const [i, [from, w]] of type.main_weight.entries()) if (floor >= (i === 1 ? site.mine.main_from : from)) weight = w;
    const existing = drops.find(([id]) => id === site.mine.main);
    if (existing) existing[1] += weight; else drops.push([site.mine.main, weight]);
  }
  const total = drops.reduce((n, [, weight]) => n + weight, 0);
  const deck = Array.from({ length: rocks }, () => {
    let pick = draw() * total;
    for (const [id, weight] of drops) { if (pick < weight) return id; pick -= weight; }
    return null;
  });
  return { mobs, rocks, drops, deck, guard: null as string | null, hpMult: 1 };
}
const maxHp = (c: P0Content, kind: string, multiplier: number) => Math.ceil(c.mine.monsters[kind].hp * multiplier);
function currentSpec(c: P0Content, s: P0State, site: MineSite, floor: number) {
  const spec = floorSpec(c, site, floor, s.player, s.mine.day!.key);
  if (spec.guard && s.mine.records[site.id]?.guards.includes(floor)
    && !s.mine.day!.floors[floorKey(site.id, floor)]?.mobs.length) return { ...spec, mobs: [], guard: null };
  return spec;
}
function floorState(c: P0Content, s: P0State, site: MineSite, floor: number): MineB1FloorState {
  const day = s.mine.day!, key = floorKey(site.id, floor);
  if (!day.floors[key]) {
    const spec = currentSpec(c, s, site, floor);
    day.floors[key] = { paid: false, broken: [], lit: false, mobs: spec.mobs.map(kind => maxHp(c, kind, spec.hpMult)), ground: [], ground_seq: 0 };
  }
  return day.floors[key];
}
const emptyDay = (key: string, hp: number): MineB1Day => ({ key, at: null, hp, floors: {}, picked: [] });

/** Reads settle a copy; commands persist the same reset. Staying on the floor pays no second fee. */
export function settleMine(c: P0Content, s: P0State, now: number): void {
  const old = s.mine.day, key = dayKey(c, s, now);
  if (!old || old.key === key) return;
  s.mine.day = null;
  if (!old.at) return;
  const site = mineSite(c, old.at.mine);
  if (!site || !c.mine.types[site.type] || old.at.floor > cap(site)) return;
  const day = emptyDay(key, old.hp);
  day.at = { ...old.at }; s.mine.day = day;
  floorState(c, s, site, day.at.floor).paid = true;
  s.mine.notice = { kind: 'reset', at: rolloverAfter(c, s, old.key), floor: day.at.floor };
}

/** Restore only living guards/elites. Dead and damaged ordinary monsters remain unchanged. */
export function restoreBosses(c: P0Content, s: P0State): void {
  const day = s.mine.day, at = day?.at;
  if (!day || !at) return;
  const site = mineSite(c, at.mine), saved = day.floors[floorKey(at.mine, at.floor)];
  if (!site || !saved) return;
  const spec = currentSpec(c, s, site, at.floor);
  spec.mobs.forEach((kind, i) => {
    const def = c.mine.monsters[kind];
    if (saved.mobs[i] > 0 && (def.guard || def.elite)) saved.mobs[i] = maxHp(c, kind, spec.hpMult);
  });
  delete saved.guard_hit_at;
  saved.ground = [];
}
export function leaveMine(c: P0Content, s: P0State, now: number): void {
  settleMine(c, s, now);
  if (!s.mine.day?.at) return;
  restoreBosses(c, s);
  s.mine.day.at = null; s.mine.day.hp = c.mine.combat.hp; s.mine.day.picked = [];
}
export const stonePerRock = (c: P0Content, s: P0State) => c.mine.picks[s.gear.pick]?.stone ?? 1;
export function weapon(c: P0Content, s: P0State) { return c.mine.combat.weapons[s.gear.weapon]; }
/** Card number is the count already broken, never the selected rock's identity. */
export function rockDrop(c: P0Content, s: P0State, site: MineSite, floor: number, card: number): string | null {
  return floorSpec(c, site, floor, s.player, s.mine.day!.key).deck[card] ?? null;
}
export function bagFitsFloor(c: P0Content, s: P0State, site: MineSite, floor: number, key: string): boolean {
  const spec = floorSpec(c, site, floor, s.player, key);
  const dealt = s.mine.day?.floors[floorKey(site.id, floor)]?.broken.length ?? 0;
  if (dealt >= spec.rocks) return true;
  const extra = spec.deck[dealt], trial: BagHolder = { bag: structuredClone(s.bag), bag_cap: s.bag_cap, skills: s.skills };
  const stone = stonePerRock(c, s);
  if (room(c, trial, 'stone') < stone) return false;
  add(c, trial, 'stone', stone);
  if (extra && room(c, trial, extra) < 1) return false;
  return true;
}
function canPay(c: P0Content, s: P0State, site: MineSite, floor: number, now: number): Refusal | null {
  if (s.mine.day?.floors[floorKey(site.id, floor)]?.paid) return null;
  if (s.energy.value < c.mine.floor_energy) return { code: 'need_energy', detail: energyDetail(c, s, now, c.mine.floor_energy) };
  return null;
}
function arrive(c: P0Content, s: P0State, site: MineSite, floor: number, now: number, events: P0Event[]): void {
  const day = s.mine.day!, state = floorState(c, s, site, floor);
  if (s.mine.records[site.id]?.guards.includes(floor)) state.mobs = [];
  if (!state.paid) { spendEnergy(c, s, now, c.mine.floor_energy, events, 'mine_floor'); state.paid = true; }
  day.at = { mine: site.id, floor }; day.picked = [];
  const record = s.mine.records[site.id] ??= { deepest: 0, guards: [], first_at: now };
  if (floor > record.deepest) { record.deepest = floor; events.push({ kind: 'mine_record', mine: site.id, deepest: floor }); }
  events.push({ kind: 'mine_floor', mine: site.id, floor, cleared: state.mobs.every(hp => hp <= 0), station: stations(record).includes(floor) });
}
const badFloor = (site: MineSite, n?: number): Refusal => ({ code: 'bad_floor', detail: { max: cap(site),
  ...(n !== undefined && n > cap(site) && n <= site.mine.floors ? { not_open: true } : {}) } });

export function mineCommand(c: P0Content, s: P0State, cmd: MineCommand & { space?: string }, now: number, events: P0Event[]): Refusal | null {
  settleMine(c, s, now);
  if (cmd.type === 'mine_enter') {
    const site = typeof cmd.mine === 'string' ? mineSite(c, cmd.mine) : undefined;
    if (!site) return { code: typeof cmd.mine === 'string' && wildById(c, cmd.mine) ? 'not_open' : 'unknown_place' };
    if (site.open === false || !c.mine.types[site.type] || cap(site) < 1) return { code: 'not_open' };
    if (!c.mine.dev_sites?.includes(site) && s.travel.here !== site.id) return { code: 'not_here' };
    const gate = c.mine.types[site.type].gate;
    if (gate && s.homestead.level < gate.homestead) return { code: 'not_open', detail: { homestead: gate.homestead } };
    const n = cmd.floor ?? 1;
    if (!Number.isInteger(n) || n < 1 || n > cap(site)) return badFloor(site, n);
    if (n !== 1 && !stations(s.mine.records[site.id]).includes(n)) return badFloor(site);
    if (s.mine.day?.at) return { code: 'not_here' };
    const refusal = canPay(c, s, site, n, now); if (refusal) return refusal;
    s.mine.day ??= emptyDay(dayKey(c, s, now), c.mine.combat.hp);
    s.mine.day.hp = c.mine.combat.hp; s.mine.notice = null;
    arrive(c, s, site, n, now, events); return null;
  }
  if (cmd.day !== dayKey(c, s, now)) return { code: 'new_day' };
  const day = s.mine.day, at = day?.at;
  if (!day || !at || (cmd.space !== undefined && cmd.space !== 'mine')) return { code: 'not_in_mine' };
  const site = mineSite(c, at.mine);
  if (!site) return { code: 'unknown_place' };
  const state = floorState(c, s, site, at.floor);
  if (cmd.type === 'mine_floor') {
    const n = cmd.to, stops = stations(s.mine.records[site.id]);
    if (!Number.isInteger(n) || n < 1 || n > cap(site)) return badFloor(site, n);
    if (cmd.via === 'elevator') {
      if ((at.floor !== 1 && !stops.includes(at.floor)) || !stops.includes(n) || n === at.floor) return badFloor(site);
    } else {
      if (cmd.via !== undefined && cmd.via !== 'ladder') return badFloor(site);
      if (Math.abs(n - at.floor) !== 1) return badFloor(site);
      const left = state.mobs.filter(hp => hp > 0).length;
      if (n > at.floor && left) return { code: 'floor_locked', detail: { left } };
    }
    const refusal = canPay(c, s, site, n, now); if (refusal) return refusal;
    restoreBosses(c, s); arrive(c, s, site, n, now, events); return null;
  }
  if (cmd.floor !== at.floor) return badFloor(site);
  const spec = currentSpec(c, s, site, at.floor);
  if (cmd.type === 'mine_attack') return attack(c, s, site, state, spec, cmd, now, events);
  if (cmd.type === 'mine_pick') {
    const ground = Number.isInteger(cmd.ground) ? state.ground.find(g => g.id === cmd.ground) : undefined;
    if (!ground) return { code: 'no_item', detail: { ground: cmd.ground } };
    if (room(c, s, ground.item) < ground.qty) return { code: 'bag_full' };
    giveLoot(c, s, ground.item, ground.qty, events);
    state.ground = state.ground.filter(g => g.id !== ground.id);
    return null;
  }
  if (!spec.rocks) return { code: 'no_rocks' };
  if (cmd.type === 'mine_torch') {
    if (state.lit) return { code: 'lit' };
    if (count(s.bag, 'torch') < 1) return { code: 'no_item', detail: { item: 'torch' } };
    take(s.bag, 'torch', 1); state.lit = true;
    events.push({ kind: 'item', id: 'torch', delta: -1 }, { kind: 'mine', action: 'torch', mine: site.id, floor: at.floor, cost: 0 });
    return null;
  }
  const rock = cmd.rock;
  if (!Number.isInteger(rock) || rock < 0 || rock >= spec.rocks) return { code: 'bad_rock' };
  if (state.broken.includes(rock)) return { code: 'rock_gone' };
  const ready = c.mine.rules.rock_tempo_ms - (now - (day.swing_at ?? -Infinity));
  if (ready > 0) return { code: 'tempo', detail: { ready_in: ready } };
  if (!bagFitsFloor(c, s, site, at.floor, day.key)) return { code: 'bag_full', detail: { floor: at.floor } };
  if (s.energy.value < c.mine.rock_energy) return { code: 'need_energy', detail: energyDetail(c, s, now, c.mine.rock_energy) };
  const drop = rockDrop(c, s, site, at.floor, state.broken.length);
  spendEnergy(c, s, now, c.mine.rock_energy, events, 'mine_rock');
  giveLoot(c, s, 'stone', stonePerRock(c, s), events); if (drop) giveLoot(c, s, drop, 1, events);
  state.broken.push(rock); day.swing_at = now;
  events.push({ kind: 'mine', action: 'rock', mine: site.id, floor: at.floor, rock, drop, cost: c.mine.rock_energy });
  return null;
}

function giveLoot(c: P0Content, s: P0State, id: string, qty: number, events: P0Event[], from?: number): void {
  const n = Math.min(qty, room(c, s, id));
  if (n) {
    add(c, s, id, n); events.push({ kind: 'item', id, delta: n });
    const picked = s.mine.day!.picked.find(([item]) => item === id);
    if (picked) picked[1] += n; else s.mine.day!.picked.push([id, n]);
    if (!s.firsts.includes(`loot:${id}`)) s.firsts.push(`loot:${id}`);
  }
  if (n < qty && from !== undefined) {
    const at = s.mine.day!.at!, saved = s.mine.day!.floors[floorKey(at.mine, at.floor)];
    saved.ground.push({ id: ++saved.ground_seq, item: id, qty: qty - n, from });
  }
}
export function mobLoot(c: P0Content, s: P0State, site: MineSite, floor: number, index: number, kind: string): [string, number] | null {
  const def = c.mine.monsters[kind];
  const pool = (def.loot ?? []).filter(([id]) => !def.once_a_day || id !== def.once_a_day || !(s.day.once[kind] > 0));
  const hash = createHash('sha256').update(`${s.player}:mine@${site.id}:${floor}:${s.mine.day!.key}:mob:${index}`).digest().readUInt32BE(0);
  let pick = hash / 0x1_0000_0000 * pool.reduce((n, [, , w]) => n + w, 0);
  for (const [id, qty, w] of pool) { if (pick < w) return id ? [id, qty] : null; pick -= w; }
  return null;
}

function attack(c: P0Content, s: P0State, site: MineSite, saved: MineB1FloorState, spec: ReturnType<typeof floorSpec>,
  cmd: Extract<MineCommand, { type: 'mine_attack' }>, now: number, events: P0Event[]): Refusal | null {
  const day = s.mine.day!, at = day.at!, w = weapon(c, s);
  if (!w) return { code: 'not_owned' };
  const valid = (i: unknown): i is number => Number.isInteger(i) && (i as number) >= 0 && (i as number) < spec.mobs.length;
  const raw = cmd.targets ?? [];
  if (!Array.isArray(raw) || !raw.every(valid) || new Set(raw).size !== raw.length
    || (cmd.hurt_by !== undefined && !valid(cmd.hurt_by))) return { code: 'bad_target' };
  const targets = raw.slice(0, c.mine.rules.max_targets), hurt = cmd.hurt_by;
  if (!targets.length && hurt === undefined) return { code: 'bad_target' };
  if (targets.some(i => saved.mobs[i] <= 0) || (hurt !== undefined && saved.mobs[hurt] <= 0)) return { code: 'mob_gone' };
  const wait = 1000 / w.speed * c.mine.rules.attack_tempo_factor - (now - (day.attack_at ?? -Infinity));
  if (targets.length && wait > 0) return { code: 'tempo', detail: { ready_in: Math.ceil(wait) } };
  if (targets.length) day.attack_at = now;
  for (const i of targets) {
    const kind = spec.mobs[i], def = c.mine.monsters[kind];
    let damage = w.attack;
    if (def.guard && w.tier < (def.tier ?? 0)) damage = Math.max(1, Math.ceil(damage * c.mine.combat.under_tier));
    if (Array.isArray(cmd.stunned) && cmd.stunned.includes(i) && def.stun_mult) damage *= def.stun_mult;
    if (def.guard) saved.guard_hit_at ??= now;
    saved.mobs[i] = Math.max(0, saved.mobs[i] - damage);
    events.push({ kind: 'mine', action: 'hit', mine: site.id, floor: at.floor, mob: i, hp: saved.mobs[i], damage, cost: 0 });
    if (saved.mobs[i] > 0) continue;
    s.kills[kind] = (s.kills[kind] ?? 0) + 1;
    const loot = mobLoot(c, s, site, at.floor, i, kind);
    if (loot) { giveLoot(c, s, loot[0], loot[1], events, i); if (loot[0] === def.once_a_day) s.day.once[kind] = (s.day.once[kind] ?? 0) + 1; }
    events.push({ kind: 'mob_down', index: i, mob: kind });
    if (def.guard) {
      const first = !s.guard_firsts[kind];
      if (first) {
        s.guard_firsts[kind] = { at: now, mine: site.id, floor: at.floor, home: s.travel.home };
        for (const [id, qty] of def.first ?? []) giveLoot(c, s, id, qty, events, i);
      }
      if (def.pack) {
        const id = def.pack[0] === 'main' ? site.mine.main : def.pack[0];
        if (id) giveLoot(c, s, id, def.pack[1], events, i);
      }
      const record = s.mine.records[site.id];
      if (!record.guards.includes(at.floor)) record.guards.push(at.floor);
      events.push({ kind: 'guard_down', mob: kind, floor: at.floor, first });
      const threshold = maxHp(c, kind, spec.hpMult) / (w.attack * w.speed) * 1000 * c.mine.rules.guard_fast_factor;
      if (now - saved.guard_hit_at! < threshold) console.warn(JSON.stringify({ kind: 'guard_fast', mine: site.id, floor: at.floor, mob: kind, elapsed_ms: now - saved.guard_hit_at!, threshold_ms: threshold }));
    }
  }
  if (hurt !== undefined && saved.mobs[hurt] > 0 && now - (day.hurt_at ?? -Infinity) >= c.mine.combat.invulnerability_ms) {
    day.hurt_at = now;
    const damage = c.mine.monsters[spec.mobs[hurt]].damage;
    day.hp = Math.max(0, day.hp - damage);
    events.push({ kind: 'mine', action: 'hurt', mine: site.id, floor: at.floor, mob: hurt, hp: day.hp, damage, cost: 0 });
    if (day.hp === 0) {
      const lost: [string, number][] = [];
      if (at.floor >= c.mine.combat.ko_keep_from) for (const [id, qty] of day.picked) {
        const n = Math.min(count(s.bag, id), Math.floor(qty * c.mine.combat.ko_lose));
        if (n) { take(s.bag, id, n); lost.push([id, n]); events.push({ kind: 'item', id, delta: -n }); }
      }
      restoreBosses(c, s); day.at = null; day.hp = c.mine.combat.hp; day.picked = [];
      s.mine.notice = { kind: 'ko', at: now, floor: at.floor, lost };
      events.push({ kind: 'mine_ko', floor: at.floor, lost });
    }
  }
  return null;
}

export function mineView(c: P0Content, s: P0State, now: number) {
  settleMine(c, s, now);
  const day = s.mine.day, at = day?.at, site = at ? mineSite(c, at.mine) : undefined;
  // type / main: the mine's own (catalogue or dev site), so a client tells which vein a record is without having read
  // its site (v4q(9) ①: any iron vein's F10 ends the iron row; 亚瑟 on #711); null for one no longer known
  const records = Object.fromEntries(Object.entries(s.mine.records).map(([id, r]) => {
    const site = mineSite(c, id);
    return [id, { deepest: r.deepest, guards: [...r.guards], type: site?.type ?? null, main: site?.mine.main ?? null }];
  }));
  const rank = mineRank(s);
  let here = null;
  if (day && at && site) {
    const state = floorState(c, s, site, at.floor), spec = currentSpec(c, s, site, at.floor);
    const stops = stations(s.mine.records[site.id]).filter(n => n <= cap(site));
    const cleared = state.mobs.every(hp => hp <= 0), next = at.floor + 1, prev = at.floor - 1;
    here = {
      mine: site.id, type: site.type, name: site.name, max: cap(site), floor: at.floor, hp: day.hp, day: day.key,
      stations: stops.map(floor => ({ floor, paid: day.floors[floorKey(site.id, floor)]?.paid ?? false })),
      floor_state: { floor: at.floor, paid: state.paid, cleared, rocks: spec.rocks, left: spec.rocks - state.broken.length,
        broken: Array.from({ length: spec.rocks }, (_, i) => state.broken.includes(i)), lit: state.lit,
        deck: state.lit ? deckCounts(spec.deck.slice(state.broken.length)) : null,
        ground: state.ground.map(g => ({ ...g })),
        bag_ok: bagFitsFloor(c, s, site, at.floor, day.key), station: stops.includes(at.floor), guard: spec.guard,
        mobs: spec.mobs.map((kind, i) => ({ kind, hp: state.mobs[i], max: maxHp(c, kind, spec.hpMult), elite: !!c.mine.monsters[kind].elite,
          guard: !!c.mine.monsters[kind].guard, tier: c.mine.monsters[kind].tier ?? 0 })) },
      prev: prev < 1 ? null : { floor: prev, paid: day.floors[floorKey(site.id, prev)]?.paid ?? false,
        fee: day.floors[floorKey(site.id, prev)]?.paid ? 0 : c.mine.floor_energy },
      next: next > site.mine.floors ? null : { floor: next, paid: day.floors[floorKey(site.id, next)]?.paid ?? false,
        fee: day.floors[floorKey(site.id, next)]?.paid ? 0 : c.mine.floor_energy, open: cleared, locked: next > cap(site) ? 'not_open' : null },
    };
  }
  return { floor_energy: c.mine.floor_energy, rock_energy: c.mine.rock_energy, hp_max: c.mine.combat.hp,
    rank, weapon: { id: s.gear.weapon, ...weapon(c, s) }, notice: s.mine.notice, at: here, records, paid_today: paidToday(s) };
}

/** The floors paid for today, by mine, lowest first (fee_per_day): kept out of the mine too, so the mine card's key
 * reads `Enter mine · Free` once F1 is paid today (LOCK-21, 亚瑟 for C part 2). Empty after the day rolls over — but
 * for a player in the mine then, whose floor is paid for the new day where they stand (settleMine; 后裔 on #705). */
function paidToday(s: P0State): Record<string, number[]> {
  const out: Record<string, number[]> = {};
  for (const [key, state] of Object.entries(s.mine.day?.floors ?? {})) {
    if (!state.paid) continue;
    const at = key.lastIndexOf(':');
    (out[key.slice(0, at)] ??= []).push(Number(key.slice(at + 1)));
  }
  for (const floors of Object.values(out)) floors.sort((a, b) => a - b);
  return out;
}

function deckCounts(deck: (string | null)[]): [string, number][] {
  const counts = new Map<string, number>();
  for (const id of deck) if (id !== null) counts.set(id, (counts.get(id) ?? 0) + 1);
  return [...counts];
}
