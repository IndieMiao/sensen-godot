import type { FishingCast, FishingSite } from '../domain/fishing.js';
import type { PondRoom } from '../ponds/catalog.js';
import { randomUUID } from 'node:crypto';
import type { Content } from '../domain/content.js';
import type { FarmRow } from '../http/dto.js';
import type { Store } from '../http/store.js';
import { defaultAppearance, type Appearance } from './appearance.js';
import { ACTIONS, CAPACITY, STEP, distance, initialExpedition, lootRoll, mineNavigation, move, profile, segment,
  type Checkpoint, type Effect, type Expedition, type Navigation, type Point } from './model.js';

export interface Transport { send(data: string | Buffer): void; buffered(): number; close(code: number, reason: string): void; resume?(floor: number): string }
export interface Member {
  player: string; id: number; wire: Transport; stats: ReturnType<typeof profile>;
  x: number; z: number; yaw: number; target: Point; floor: number; epoch: number;
  seq: number; commandSeq: number; inputAt: number; action: number; actionSerial: number;
  attackAt: number; hurtAt: number; grace: number;
  appearance: Appearance;
  fishingVersion?: number; invalidFishingSequence?: number;
  fishing?: { sequence: number; cast: FishingCast; held: boolean; fish: number; hintAt: number; resultAt?: number; fishId?: string };
  pending?: { seq: number; action: string; node: string; time: number; waiting: number };
}

/** One serialized actor owns a space. No await can interleave a join with a commit. */
export class Room {
  readonly members = new Map<string, Member>();
  checkpoint: Checkpoint | null = null;
  mine: Expedition;
  tickNumber = 0;
  now = 0;
  lastActive = Date.now();
  failed = false;
  private tail: Promise<unknown> = Promise.resolve();
  private ticking = false;
  private settling = false;
  private navs = new Map<number, Navigation>();
  private interests = new Map<number, Set<number>>();
  readonly metrics = { ticks: 0, maxTickMs: 0, skipped: 0, bytes: 0, snapshots: 0, slowCloses: 0 };

  get capacity() { return this.pond?.capacity ?? CAPACITY; }
  constructor(readonly key: string, readonly kind: 'street' | 'farm' | 'mine' | 'pond',
    readonly navigation: Navigation, readonly store: Store, readonly content: Content, readonly realNow: () => number = Date.now,
    readonly farmFishingSite?: FishingSite, readonly pond?: PondRoom) {
    this.mine = initialExpedition(content);
  }
  async load() {
    if (this.kind !== 'mine') return;
    this.checkpoint = await this.store.realtimeLoad(this.key);
    if (this.checkpoint) this.mine = structuredClone(this.checkpoint.mine);
    // Restart from safe phases without reviving monsters or changing rewards.
    for (const floor of Object.values(this.mine.floors)) for (const m of floor.monsters) {
      m.phase = 'idle'; m.timer = 0;
    }
  }
  exclusive<T>(fn: () => Promise<T>): Promise<T> {
    const result = this.tail.then(fn);
    this.tail = result.catch(() => {});
    return result;
  }
  nav(floor: number) {
    if (this.kind !== 'mine') return this.navigation;
    if (!this.navs.has(floor)) this.navs.set(floor, mineNavigation(this.mine.floors[String(floor)]));
    return this.navs.get(floor)!;
  }
  async join(farm: FarmRow, wire: Transport, beforeJoin?: () => Promise<void>, partyId = '', resumeFloor = 1, appearance = defaultAppearance()): Promise<Member> {
    return this.exclusive(async () => {
      if (this.failed) throw new Error('ROOM_UNAVAILABLE');
      if (this.members.size >= this.capacity && !this.members.has(farm.owner_id)) throw new Error('ROOM_FULL');
      if (this.kind === 'mine') {
        this.mine.owner ??= farm.owner_id;
        if (partyId) this.mine.party = partyId;
        const changed = await this.persist(this.mine, [{ player: farm.owner_id, starter: true }]);
        farm = changed.find(f => f.owner_id === farm.owner_id) ?? farm;
      }
      if (beforeJoin) await beforeJoin();
      const old = this.members.get(farm.owner_id);
      if (old) { old.wire.close(4001, 'SESSION_REPLACED'); this.leave(old); }
      const floor = this.kind === 'mine' ? resumeFloor : 0;
      const [x, z] = this.spawnPosition(floor);
      const occupied = new Set([...this.members.values()].map(m => m.id));
      let id = 1;
      while (occupied.has(id)) id++;
      const m: Member = { player: farm.owner_id, id, wire, stats: profile(farm, this.content), appearance: structuredClone(appearance),
        x, z, yaw: 0, target: [x, z], floor, epoch: 1, seq: -1, commandSeq: -1, inputAt: this.now,
        action: 0, actionSerial: 0, attackAt: -100, hurtAt: -100, grace: this.now + 1.5 };
      this.members.set(m.player, m);
      this.interests.clear();
      this.send(m, { t: 'joined', protocol: 1, room: this.key, kind: this.kind, capacity: this.capacity,
        self: m.id, floor, epoch: m.epoch, spawn: [x, z], tick_hz: 20, snapshot_hz: 10, resume: wire.resume?.(floor) });
      this.sendWorld(m);
      this.roster(m);
      for (const other of this.members.values()) if (other !== m) this.send(other, {
        t: 'peer', count: this.members.size, member: other.floor === m.floor ? this.memberView(m) : null });
      return m;
    });
  }
  private spawnPosition(floor: number): Point {
    const nav = this.nav(floor), origin = nav.spawn;
    const occupied = [...this.members.values()].filter(m => m.floor === floor);
    for (let radius = 0; radius <= 4; radius++) for (let dz = -radius; dz <= radius; dz++) for (let dx = -radius; dx <= radius; dx++) {
      if (Math.max(Math.abs(dx), Math.abs(dz)) !== radius) continue;
      const point: Point = [origin[0] + dx * nav.cell, origin[1] + dz * nav.cell];
      if (occupied.every(m => distance(point, [m.x, m.z]) >= .6) && segment(nav, origin, point)) return point;
    }
    return [...origin];
  }
  leave(m: Member) {
    if (this.members.get(m.player) !== m) return;
    this.members.delete(m.player);
    this.interests.clear();
    this.lastActive = Date.now();
    for (const other of this.members.values()) this.send(other, { t: 'left', id: m.id, count: this.members.size });
  }
  reload(farm: FarmRow) {
    const m = this.members.get(farm.owner_id);
    if (m && farm.version >= m.stats.version) {
      const weapon = m.stats.weapon;
      m.stats = profile(farm, this.content);
      if (weapon !== m.stats.weapon && m.pending?.action === "dig") m.pending.time = 0;
      if (weapon !== m.stats.weapon) for (const other of this.members.values()) if (other.floor === m.floor)
        this.send(other, { t: 'peer', count: this.members.size, member: this.memberView(m) });
    }
  }
  syncFishing(m: Member, farm: FarmRow, nonce: string) {
    if (farm.version <= (m.fishingVersion ?? -1)) return;
    m.fishingVersion = farm.version;
    const f = farm.state.fishing, cast = f?.active;
    if (cast && cast.nonce === nonce && (!cast.room || cast.room === this.key) && cast.origin && cast.target
      && f!.sequence > (m.invalidFishingSequence ?? -1)
      && distance(cast.origin, [m.x, m.z]) <= this.content.fishing.anchor_tolerance) {
      const same = m.fishing?.sequence === f!.sequence;
      m.fishing = { sequence: f!.sequence, cast: structuredClone(cast), held: same ? m.fishing!.held : false,
        fish: same ? m.fishing!.fish : .5, hintAt: same ? m.fishing!.hintAt : this.realNow() };
    } else if (!cast && f?.last?.outcome === 'caught' && m.fishing?.sequence === f.last.sequence && !m.fishing.resultAt) {
      m.fishing.resultAt = this.realNow(); m.fishing.fishId = f.last.fish_id; m.fishing.held = false;
    } else m.fishing = undefined;
  }
  private fishingView(m: Member) {
    const f = m.fishing;
    if (!f) return null;
    const now = this.realNow(), cast = f.cast;
    return { id: m.id, sequence: f.sequence, site: cast.site, origin: cast.origin, target: cast.target,
      phase: f.resultAt !== undefined ? 'result' : cast.hooked_at !== undefined ? 'playing'
        : now < (cast.cast_at ?? 0) + 950 ? 'casting' : now >= cast.bite_at ? 'hook' : 'waiting',
      age: Math.max(0, now - (f.resultAt ?? cast.hooked_at ?? (now >= cast.bite_at ? cast.bite_at : cast.cast_at ?? now))) / 1000,
      cast_age: Math.max(0, now - (cast.cast_at ?? now)) / 1000,
      held: f.held && now - f.hintAt < 500, fish: f.fish,
      ...(f.fishId ? { outcome: 'caught', fish_id: f.fishId } : {}) };
  }
  dress(m: Member, appearance: Appearance) {
    if (this.failed || this.members.get(m.player) !== m) return;
    if (JSON.stringify(m.appearance) === JSON.stringify(appearance)) return;
    m.appearance = structuredClone(appearance);
    for (const other of this.members.values()) if (other.floor === m.floor)
      this.send(other, { t: 'peer', count: this.members.size, member: this.memberView(m) });
  }
  input(m: Member, b: Record<string, unknown>) {
    if (this.failed || this.members.get(m.player) !== m || b.epoch !== m.epoch) return;
    if (!Number.isSafeInteger(b.seq) || Number(b.seq) < 0 || Number(b.seq) > 0xffffffff) throw new Error('SCHEMA');
    if (b.t === 'input') {
      if (Number(b.seq) <= m.seq) return;
      if (![b.x, b.z, b.yaw].every(v => typeof v === 'number' && Number.isFinite(v) && Math.abs(v) < 10000)) throw new Error('SCHEMA');
      m.seq = Number(b.seq);
      m.target = [Number(b.x), Number(b.z)];
      m.yaw = Number(b.yaw) % (Math.PI * 2);
      m.inputAt = this.now;
      const action = typeof b.action === 'string' ? ACTIONS.indexOf(b.action as typeof ACTIONS[number]) : 0;
      if (m.action !== 9 && m.action !== 10) m.action = action >= 0 && action < 13 && action !== 9 && action !== 10 ? action : 0;
      const hint = b.fishing as { sequence?: number; held?: boolean; fish?: number } | undefined;
      if (hint && m.fishing && hint.sequence === m.fishing.sequence && m.fishing.cast.hooked_at !== undefined
        && typeof hint.held === 'boolean' && typeof hint.fish === 'number' && Number.isFinite(hint.fish)) {
        m.fishing.held = hint.held; m.fishing.fish = Math.min(1, Math.max(0, hint.fish)); m.fishing.hintAt = this.realNow();
      }
    } else if (b.t === 'act') {
      if (Number(b.seq) <= m.commandSeq) return;
      m.commandSeq = Number(b.seq);
      if (this.kind !== 'mine' || !['attack', 'dig', 'up', 'down', 'elevator'].includes(String(b.action))) throw new Error('SCHEMA');
      if (m.pending) { this.result(m, Number(b.seq), false, 'BUSY'); return; }
      m.pending = { seq: Number(b.seq), action: String(b.action), node: String(b.node ?? '').slice(0, 32), time: 0, waiting: 0 };
    }
  }
  async tick(): Promise<void> {
    if (this.failed || !this.members.size) return;
    if (this.ticking) {
      this.metrics.skipped++;
      // Durable combat is serialized, but slow database commits must not stop movement fanout.
      if (this.settling) { this.movePlayers(); if (this.tickNumber % 2 === 0) this.snapshots(); }
      return;
    }
    this.ticking = true;
    const started = performance.now();
    try { await this.exclusive(() => this.step()); }
    catch {
      // Freeze a failed actor. A new connection reloads the last committed checkpoint.
      this.failed = true;
      for (const m of this.members.values()) m.wire.close(1013, 'ROOM_RECOVERING');
    } finally {
      this.metrics.ticks++;
      this.metrics.maxTickMs = Math.max(this.metrics.maxTickMs, performance.now() - started);
      this.ticking = false;
    }
  }
  private async step() {
    this.movePlayers();
    if (this.kind === 'mine') await this.stepMine();
    if (this.tickNumber % 2 === 0) this.snapshots();
  }
  private movePlayers() {
    this.now += STEP;
    this.tickNumber++;
    for (const m of this.members.values()) {
      const before: Point = [m.x, m.z];
      if (this.now - m.inputAt > .35) m.target = before;
      [m.x, m.z] = move(this.nav(m.floor), before, m.target, m.stats.speed * STEP);
      if (!m.pending && (m.action === 9 || m.action === 10) && this.now > m.attackAt + .35) m.action = 0;
      if (!m.pending && distance(before, [m.x, m.z]) > .001) m.action = 1;
      const f = m.fishing;
      if (f) {
        const now = this.realNow(), cast = f.cast;
        if (distance(cast.origin!, [m.x, m.z]) > this.content.fishing.anchor_tolerance
          || (f.resultAt !== undefined ? now > f.resultAt + 1600 : cast.hooked_at !== undefined
            ? now > cast.hooked_at + this.content.fishing.max_steps * this.content.fishing.step_ms + this.content.fishing.settle_grace_ms
            : now > cast.hook_until)) {
          m.invalidFishingSequence = Math.max(m.invalidFishingSequence ?? -1, f.sequence);
          m.fishing = undefined; m.action = 0;
        } else {
          m.action = cast.hooked_at !== undefined ? 14 : 13;
          m.yaw = Math.atan2(cast.target![0] - m.x, cast.target![1] - m.z);
        }
      }
    }
  }
  private async stepMine() {
    const draft = structuredClone(this.mine);
    const effects: Effect[] = [];
    const replies: { m: Member; seq: number; ok: boolean; code: string }[] = [];
    const rescued = new Set<string>();
    let dirty = false;
    const done = (m: Member, ok: boolean, code = '') => {
      if (m.pending) replies.push({ m, seq: m.pending.seq, ok, code });
      m.pending = undefined;
    };
    for (const m of this.members.values()) {
      const pending = m.pending;
      if (!pending) continue;
      const floor = draft.floors[String(m.floor)], nav = this.nav(m.floor);
      const point: Point = [m.x, m.z];
      if (pending.action === 'attack') {
        if (!m.stats.damage || this.now < m.attackAt + 1 / m.stats.attack_speed) { done(m, false, 'COOLDOWN'); continue; }
        m.attackAt = this.now; m.action = 9; m.actionSerial = (m.actionSerial + 1) % 65536;
        for (const monster of floor.monsters) {
          const target: Point = [monster.x, monster.z], d = distance(point, target);
          const dot = d < .05 ? 1 : (Math.sin(m.yaw) * (target[0] - m.x) + Math.cos(m.yaw) * (target[1] - m.z)) / d;
          if (!monster.hp || d > m.stats.reach || dot < Math.cos(this.content.mining.combat.attack_arc_degrees * Math.PI / 360) || !segment(nav, point, target)) continue;
          const spec = this.content.mining.combat.monsters[monster.kind];
          monster.hp = Math.max(0, monster.hp - Math.max(1, m.stats.damage - spec.defense));
          if (!monster.contributors.includes(m.player)) monster.contributors.push(m.player);
          if (!spec.stun_resistant) { monster.phase = 'stunned'; monster.timer = this.content.mining.combat.hit_stun_seconds; }
          if (d > .001) [monster.x, monster.z] = move(nav, target,
            [target[0] + (target[0] - m.x) / d, target[1] + (target[1] - m.z) / d], m.stats.knockback * (1 - spec.knockback_resistance));
          dirty = true;
          if (!monster.hp) for (const player of monster.contributors) effects.push({ player,
            loot: lootRoll(JSON.stringify([this.key, draft.run, m.floor, monster.id, player]), spec.loot),
            ...(m.floor === 5 ? { elevator: true } : {}) });
        }
        done(m, true);
      } else if (pending.action === 'dig') {
        const rock = floor.rocks.find(r => r.id === pending.node);
        if (!rock || rock.broken) { done(m, false, 'ALREADY_CLAIMED'); continue; }
        if (distance(point, rock.position) > 1.65 || distance(point, m.target) > .15) {
          // A predicted arrival can precede the authoritative position by a few frames.
          pending.waiting += STEP; pending.time = 0;
          if (distance(m.target, rock.position) > 1.7 || pending.waiting > 2) done(m, false, 'OUT_OF_RANGE');
          continue;
        }
        m.action = 10;
        pending.time += STEP;
        if (pending.time + 1e-6 < 1 / m.stats.ore_power) continue;
        rock.broken = true;
        dirty = true;
        const participants = [...this.members.values()].filter(p => p.floor === m.floor && p.pending?.action === 'dig' &&
          p.pending.node === rock.id && p.pending.time >= .1 && distance([p.x, p.z], rock.position) <= 1.65);
        for (const participant of participants) {
          const loot = lootRoll(JSON.stringify([this.key, draft.run, m.floor, rock.id, participant.player]),
            this.content.mining.bonus_drops.map(d => ({ item_id: d.material, quantity: d.quantity, weight: d.weight })));
          loot.stone = (loot.stone ?? 0) + this.content.mining.stone_per_rock;
          effects.push({ player: participant.player, loot, mining: true });
          done(participant, true);
        }
      } else {
        const anchor: Point = pending.action === 'down' ? [8.25, -6.75] : pending.action === 'elevator' ? [1.25, -6.75] : [1, -.75];
        if (distance(point, anchor) > 1.7) {
          pending.waiting += STEP;
          if (distance(m.target, anchor) > 1.7 || pending.waiting > 2) done(m, false, 'OUT_OF_RANGE');
          continue;
        }
        let next = m.floor;
        if (pending.action === 'down' && floor.cleared && m.floor < 5) next++;
        else if (pending.action === 'up' && m.floor > 1) next--;
        else if (pending.action === 'elevator' && (draft.elevator || (await this.store.farmByOwner(m.player))?.state.mine?.elevator_unlocked) && [1, 5].includes(m.floor)) next = m.floor === 1 ? 5 : 1;
        if (next === m.floor) { done(m, false, 'NOT_AVAILABLE'); continue; }
        m.floor = next; m.epoch++; m.grace = this.now + 1.5;
        [m.x, m.z] = this.nav(next).spawn; m.target = [m.x, m.z];
        m.action = 0;
        done(m, true);
        this.send(m, { t: 'floor', floor: next, epoch: m.epoch, spawn: [m.x, m.z], resume: m.wire.resume?.(next) });
        this.sendWorld(m);
        this.interests.clear();
        this.roster(m);
        for (const other of this.members.values()) if (other !== m) {
          this.send(other, { t: 'left', id: m.id, count: this.members.size });
          if (other.floor === m.floor) this.send(other, { t: 'peer', count: this.members.size, member: this.memberView(m) });
        }
      }
    }
    for (const [floorId, floor] of Object.entries(draft.floors)) {
      const nav = this.nav(Number(floorId));
      const targets = [...this.members.values()].filter(m => m.floor === Number(floorId) && this.now >= m.grace);
      for (const monster of floor.monsters) {
        if (!monster.hp) continue;
        const spec = this.content.mining.combat.monsters[monster.kind];
        let nearest: Member | undefined, d = Infinity;
        for (const m of targets) {
          if (rescued.has(m.player)) continue;
          const range = distance([monster.x, monster.z], [m.x, m.z]);
          if (range < d) { d = range; nearest = m; }
        }
        monster.timer = Math.max(0, monster.timer - STEP);
        if (!nearest) { monster.phase = 'idle'; continue; }
        const point: Point = [monster.x, monster.z], target: Point = [nearest.x, nearest.z];
        if (['idle', 'chase'].includes(monster.phase)) {
          if (d <= spec.attack_range && segment(nav, point, target)) {
            monster.phase = 'windup'; monster.timer = spec.windup_seconds;
            monster.direction = d > .001 ? [(target[0] - point[0]) / d, (target[1] - point[1]) / d] : [0, 1];
          } else if (d <= spec.aggro_range) {
            monster.phase = 'chase';
            [monster.x, monster.z] = move(nav, point, chaseWaypoint(nav, point, target), spec.move_speed * STEP);
          } else monster.phase = 'idle';
        } else if (monster.phase === 'windup' && !monster.timer) {
          monster.phase = 'dash'; monster.timer = spec.dash_seconds;
        } else if (monster.phase === 'dash') {
          [monster.x, monster.z] = move(nav, point, [point[0] + monster.direction[0], point[1] + monster.direction[1]], spec.dash_speed * STEP);
          for (const m of targets) {
            if (rescued.has(m.player) || this.now < m.hurtAt + this.content.mining.combat.invulnerability_ms / 1000) continue;
            if (distance([monster.x, monster.z], [m.x, m.z]) > spec.radius + .35 || !segment(nav, [monster.x, monster.z], [m.x, m.z])) continue;
            const damage = Math.min(m.stats.hp, Math.max(1, spec.damage - m.stats.defense));
            effects.push({ player: m.player, raw_damage: spec.damage });
            m.hurtAt = this.now;
            if (damage >= m.stats.hp) rescued.add(m.player);
            dirty = true;
          }
          if (!monster.timer) { monster.phase = 'recover'; monster.timer = spec.recovery_seconds; }
        } else if (['recover', 'stunned'].includes(monster.phase) && !monster.timer) monster.phase = 'chase';
      }
      if (!floor.cleared && ((floor.rocks.length > 0 && floor.rocks.every(r => r.broken)) ||
        (floor.monsters.length > 0 && floor.monsters.every(m => !m.hp)))) {
        floor.cleared = true; dirty = true;
        if (floorId === '5') draft.elevator = true;
      }
    }
    if (dirty) {
      const farms = await this.persist(draft, effects);
      rescued.clear();
      for (const id of this.checkpoint?.rescued ?? []) rescued.add(id);
      this.mine = draft;
      this.navs.clear();
      for (const farm of farms) {
        this.reload(farm);
        const m = this.members.get(farm.owner_id);
        if (m) this.send(m, { t: 'farm_changed', version: farm.version, loot: effects.filter(e => e.player === m.player).map(e => e.loot ?? {}) });
      }
      for (const m of this.members.values()) this.sendWorld(m);
    } else this.mine = draft;
    for (const reply of replies) this.result(reply.m, reply.seq, reply.ok, reply.code);
    for (const player of rescued) {
      const m = this.members.get(player);
      if (m) { this.send(m, { t: 'rescued' }); this.leave(m); }
    }
  }
  private async persist(mine: Expedition, effects: Effect[]) {
    const commit = randomUUID(), expected = this.checkpoint?.revision ?? 0;
    let last: unknown;
    this.settling = true;
    try {
      for (let attempt = 0; attempt < 3; attempt++) {
        try {
          const result = await this.store.realtimeCommit(this.key, expected, commit, mine, effects);
          this.checkpoint = result.checkpoint;
          return result.farms;
        } catch (error) { last = error; if (String(error).includes('ROOM_CONFLICT')) break; }
      }
      throw last;
    } finally { this.settling = false; }
  }
  send(m: Member, payload: object) {
    const text = JSON.stringify(payload);
    if (m.wire.buffered() > 256 * 1024) { this.metrics.slowCloses++; m.wire.close(1013, 'SLOW_CLIENT'); return; }
    this.metrics.bytes += Buffer.byteLength(text);
    m.wire.send(text);
  }
  private result(m: Member, seq: number, ok: boolean, code = '') { this.send(m, { t: 'result', seq, ok, code }); }
  private memberView(m: Member) { return { id: m.id, player: m.player, floor: m.floor, weapon: m.stats.weapon, appearance: m.appearance }; }
  roster(m: Member) {
    this.send(m, { t: 'roster', count: this.members.size,
      members: [...this.members.values()].filter(p => p.floor === m.floor).map(p => this.memberView(p)) });
  }
  sendWorld(m: Member) {
    this.send(m, { t: 'world', epoch: m.epoch, navigation: this.nav(m.floor),
      ...(this.pond ? { pond_id: this.pond.location.id, catalog_revision: this.pond.revision,
        template_id: this.pond.template.id, site: this.pond.site } : {}),
      ...(this.kind === 'mine' ? { instance: this.key.slice(5), run: this.mine.run, floor: m.floor,
        cleared: Object.entries(this.mine.floors).filter(([, f]) => f.cleared).map(([id]) => Number(id)),
        elevator: this.mine.elevator, floors: Object.fromEntries(Object.entries(this.mine.floors).map(([id, f]) =>
          [id, { broken: f.rocks.filter(r => r.broken).map(r => r.id), hp: f.monsters.map(m => m.hp) }])),
        rocks: this.mine.floors[String(m.floor)].rocks } : {}) });
  }
  private snapshots() {
    const all = [...this.members.values()];
    const farTick = this.tickNumber % 10 === 0;
    const enemies = new Map<number, string>();
    for (const m of all) {
      if (m.wire.buffered() > 256 * 1024) { this.metrics.slowCloses++; m.wire.close(1013, 'SLOW_CLIENT'); continue; }
      if (m.wire.buffered() > 64 * 1024) continue;
      if (farTick || !this.interests.has(m.id)) this.interests.set(m.id, new Set([m.id, ...all.filter(p => p.floor === m.floor && p !== m)
        .sort((a, b) => distance([m.x, m.z], [a.x, a.z]) - distance([m.x, m.z], [b.x, b.z])).slice(0, 64).map(p => p.id)]));
      const near = this.interests.get(m.id)!;
      const visible = all.filter(p => p.floor === m.floor && (farTick || near.has(p.id)));
      const buffer = Buffer.allocUnsafe(12 + visible.length * 26);
      buffer.writeUInt16LE(1, 0); buffer.writeUInt32LE(this.tickNumber >>> 0, 2);
      buffer.writeUInt32LE(m.epoch, 6); buffer.writeUInt16LE(visible.length, 10);
      visible.forEach((p, i) => {
        const offset = 12 + i * 26;
        buffer.writeUInt16LE(p.id, offset); buffer.writeFloatLE(p.x, offset + 2); buffer.writeFloatLE(p.z, offset + 6);
        buffer.writeFloatLE(p.yaw, offset + 10); buffer.writeUInt16LE(p.stats.hp, offset + 14);
        buffer.writeUInt16LE(p.stats.max_hp, offset + 16); buffer.writeUInt8(p.action, offset + 18);
        buffer.writeUInt8(p.floor, offset + 19); buffer.writeUInt32LE(Math.max(0, p.seq), offset + 20);
        buffer.writeUInt16LE(p.actionSerial, offset + 24);
      });
      m.wire.send(buffer); this.metrics.bytes += buffer.length; this.metrics.snapshots++;
      if (this.kind !== 'mine' && this.tickNumber % 4 === 0) {
        const ids = [...near].filter(id => id !== m.id).slice(0, 8);
        const nearby = ids.map(id => all.find(p => p.id === id)!).filter(Boolean);
        this.send(m, { t: 'fishing', epoch: m.epoch, members: nearby.map(p => this.fishingView(p)).filter(Boolean) });
      }
      if (this.kind === 'mine') {
        if (!enemies.has(m.floor)) enemies.set(m.floor, JSON.stringify({ t: 'enemies', floor: m.floor,
          monsters: this.mine.floors[String(m.floor)].monsters.map(({ contributors, ...monster }) => monster) }));
        const frame = enemies.get(m.floor)!;
        m.wire.send(frame); this.metrics.bytes += Buffer.byteLength(frame);
      }
    }
  }
}

// The authoritative grid uses the same cell centres as BlueprintGrid. Only chase needs pathfinding.
function chaseWaypoint(nav: Navigation, a: Point, b: Point): Point {
  if (segment(nav, a, b)) return b;
  const width = nav.rows[0].length;
  const start = Math.floor(-a[1] / nav.cell) * width + Math.floor(a[0] / nav.cell);
  const end = Math.floor(-b[1] / nav.cell) * width + Math.floor(b[0] / nav.cell);
  const queue = [start], previous = new Map<number, number>([[start, -1]]);
  for (let i = 0; i < queue.length; i++) {
    const cell = queue[i], x = cell % width, y = Math.floor(cell / width);
    if (cell === end) break;
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const nx = x + dx, ny = y + dy, next = ny * width + nx;
      if (nx < 0 || nx >= width || nav.rows[ny]?.[nx] !== '1' || previous.has(next)) continue;
      previous.set(next, cell); queue.push(next);
    }
  }
  if (!previous.has(end)) return a;
  let cell = end;
  while (previous.get(cell) !== start && previous.get(cell)! >= 0) cell = previous.get(cell)!;
  return [(cell % width + .5) * nav.cell, -(Math.floor(cell / width) + .5) * nav.cell];
}
