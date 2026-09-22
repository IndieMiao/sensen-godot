import { plotForFarm } from '../geography/farm_terrain.js';
import { relocateFarmState, relocationAvailable, relocationBlocked, relocationCommandMatches, relocationConfirmError, relocationEnvelope,
  RelocationError, type RelocationConfirm, type RelocationDraft, type RelocationOutcome } from '../domain/farm_relocation.js';
import type { FishingPresenceReader } from '../domain/fishing.js';
/**
 * 内存 Store：HTTP 层测试用。事务语义在单进程里天然满足，所以它只需要如实实现
 * **顺序**（幂等查表先于版本门控等）——这些顺序本身就是被测对象。
 */
import type { PlotLayout } from '../domain/plot.js';
import { randomUUID } from 'node:crypto';
import { changeDirectory } from '../realtime/directory.js';
import { applyEffects } from '../realtime/model.js';
import type { Command, CommandEnvelope } from '../domain/commands.js';
import type { Content } from '../domain/content.js';
import { apply, makeCtx, type Ctx } from '../domain/reducer.js';
import { effectiveNow as qaNow } from '../domain/qa.js';
import { DOMAIN_VERSION, STATE_SCHEMA_VERSION } from '../domain/version.js';
import { currentOwnerFarmView, type FarmRow } from './dto.js';
import { MAX_ACTIVE_TOKENS, TOKEN_IDLE_MS, newToken, tokenHash } from './auth.js';
import type { ApplyOutcome, CommandRecord, PlayerRow, Store, TokenRow } from './store.js';
import { canonicalJson, commandRecordResult, payloadHash } from './hash.js';

export interface MemoryStoreDeps {
  content: Content;
  timezone: string;
  plot: PlotLayout;
  now: () => number;
  contentVersion: string;
}

export class MemoryStore implements Store {
  private realtimeRooms = new Map<string, import('../realtime/model.js').Checkpoint>();
  private realtimePlayers = new Map<string, import('../realtime/model.js').DirectoryPlayer>();
  private realtimeParties = new Map<string, import('../realtime/model.js').Party>();

  async realtimeLoad(key: string) { return structuredClone(this.realtimeRooms.get(key) ?? null); }

  async realtimeDirectory(player: string, action: import('../realtime/model.js').DirectoryAction = 'get', value = '') {
    if (action === 'get') {
      const entry = this.realtimePlayers.get(player), party = this.realtimeParties.get(entry?.party ?? '') ?? null;
      return structuredClone({ instance: entry?.instance ?? '', party, farm_access: Boolean(party && entry?.farm_access === party.id) });
    }
    const players = structuredClone(this.realtimePlayers), parties = structuredClone(this.realtimeParties);
    const result = changeDirectory(players, parties, player, action, value);
    this.realtimePlayers = players;
    this.realtimeParties = parties;
    return result;
  }

  async realtimeHomes(players: string[]) {
    const requested = new Set(players);
    return [...this.farms.values()].filter(f => requested.has(f.owner_id)).map(f => ({ id: f.id, owner_id: f.owner_id,
      region_id: f.region_id, layout_patch_id: f.layout_patch_id, blueprint_revision: f.blueprint_revision,
      visit_access: f.visit_access, party_farm_access: this.realtimePlayers.get(f.owner_id)?.farm_access ?? '' }));
  }

  async realtimeCommit(key: string, expected: number, commit: string,
    mine: import('../realtime/model.js').Expedition, effects: import('../realtime/model.js').Effect[]) {
    const prior = this.realtimeRooms.get(key);
    const owners = new Set(effects.map(e => e.player));
    const farms = [...this.farms.values()].filter(f => owners.has(f.owner_id));
    if (prior?.commit === commit) return structuredClone({ checkpoint: prior, farms });
    if ((prior?.revision ?? 0) !== expected) throw new Error('ROOM_CONFLICT');
    if (farms.length !== owners.size) throw new Error('NO_FARM');
    if (farms.some(f => f.domain_version !== DOMAIN_VERSION || f.content_version !== this.deps.contentVersion)) throw new Error('VERSION_MISMATCH');
    const rescued: string[] = [];
    const changed = farms.map(f => ({ ...f, ...applyEffects(f, effects, this.deps.content, rescued) }));
    const checkpoint = { revision: expected + 1, commit, mine: structuredClone(mine), rescued };
    for (const farm of changed) this.farms.set(farm.id, farm);
    this.realtimeRooms.set(key, checkpoint);
    return structuredClone({ checkpoint, farms: changed });
  }
  private players = new Map<string, PlayerRow>();
  private tokens: TokenRow[] = [];
  private farms = new Map<string, FarmRow & { content_version: string; domain_version: string; state_schema_version: number; created_at: number }>();
  private creations = new Map<string, { key: string; hash: string; farmId: string }>();
  private commands = new Map<string, Map<string, CommandRecord>>();
  private snapshots = new Map<string, { revision: number; taken_at: number; body: object }>();

  constructor(private deps: MemoryStoreDeps) {}

  async authAnonymous(hmac: string) {
    let player = [...this.players.values()].find(p => p.install_key_hmac === hmac);
    if (!player) {
      player = { id: randomUUID(), install_key_hmac: hmac };
      this.players.set(player.id, player);
    }
    const token = newToken();
    this.tokens.push({
      id: randomUUID(), player_id: player.id, token_hash: tokenHash(token), last_used_at: this.deps.now(),
    });
    // 超出上限时淘汰最久未用的（Codex 三审 N-I5：不限量会让 token 表无限增长）。
    const mine = this.tokens.filter(t => t.player_id === player!.id)
      .sort((a, b) => a.last_used_at - b.last_used_at);
    for (const t of mine.slice(0, Math.max(0, mine.length - MAX_ACTIVE_TOKENS)))
      this.tokens = this.tokens.filter(x => x.id !== t.id);
    return { player, token };
  }

  async revokeToken(hash: string) { this.tokens = this.tokens.filter(t => t.token_hash !== hash); }
  async revokeAllTokens(playerId: string) { this.tokens = this.tokens.filter(t => t.player_id !== playerId); }
  async rotateInstallKey(playerId: string, newHmac: string) {
    const p = this.players.get(playerId);
    if (p) p.install_key_hmac = newHmac;
  }
  async playerHmac(playerId: string) { return this.players.get(playerId)?.install_key_hmac ?? null; }

  async playerByToken(hash: string, now: number) {
    const t = this.tokens.find(x => x.token_hash === hash);
    if (!t) return null;
    if (now - t.last_used_at > TOKEN_IDLE_MS) { // 90 天闲置过期
      this.tokens = this.tokens.filter(x => x.id !== t.id);
      return null;
    }
    t.last_used_at = now;
    return this.players.get(t.player_id) ?? null;
  }

  async farmByOwner(ownerId: string) {
    return [...this.farms.values()].find(f => f.owner_id === ownerId) ?? null;
  }

  async farmById(farmId: string) {
    return this.farms.get(farmId) ?? null;
  }

  async saveRelocationPreview(ownerId: string, draft: RelocationDraft) {
    const farm = [...this.farms.values()].find(f => f.owner_id === ownerId);
    if (!farm) return { code: 'NO_FARM' };
    if (farm.domain_version !== DOMAIN_VERSION || farm.content_version !== this.deps.contentVersion
      || farm.state_schema_version !== STATE_SCHEMA_VERSION) return { code: 'VERSION_MISMATCH' };
    if (!relocationAvailable(farm)) return { code: 'RELOCATION_UNAVAILABLE' };
    if (relocationBlocked(farm, this.deps.now(), this.deps.content)) return { code: 'RELOCATION_BUSY' };
    if (farm.version !== draft.base_version || farm.region_id !== draft.region_id) return { code: 'RELOCATION_CONFLICT' };
    farm.relocation_draft = structuredClone(draft);
    return {};
  }

  async confirmFarmRelocation(ownerId: string, input: RelocationConfirm): Promise<RelocationOutcome> {
    // No await between lookup and commit: mirrors PostgreSQL's single locked transaction.
    const farm = [...this.farms.values()].find(f => f.owner_id === ownerId);
    if (!farm) return { kind: 'rejected', code: 'NO_FARM' };
    const log = this.commands.get(farm.id) ?? new Map<string, CommandRecord>();
    const env = relocationEnvelope(input), hash = payloadHash(env), prior = log.get(input.idempotency_key);
    if (prior) {
      if (prior.payload_hash !== hash) return { kind: 'rejected', code: 'IDEMPOTENCY_MISMATCH' };
      return prior.outcome === 'applied' ? { kind: 'replayed', farm: structuredClone(farm) }
        : { kind: 'rejected', code: (prior.result as { code: string }).code };
    }
    if (farm.domain_version !== DOMAIN_VERSION || farm.content_version !== this.deps.contentVersion
      || farm.state_schema_version !== STATE_SCHEMA_VERSION) return { kind: 'rejected', code: 'VERSION_MISMATCH' };
    const reject = (code: string): RelocationOutcome => {
      log.set(input.idempotency_key, { idempotency_key: input.idempotency_key, payload_hash: hash, outcome: 'rejected', result: { code } });
      this.commands.set(farm.id, log);
      return { kind: 'rejected', code };
    };
    const code = relocationConfirmError(farm, input, this.deps.now(), this.deps.content);
    if (code) return reject(code);
    const draft = farm.relocation_draft!;
    try {
      const moved = relocateFarmState(farm.state, plotForFarm({ farm_terrain: draft.farm_terrain }, this.deps.plot), this.deps.content);
      Object.assign(farm, { state: moved.state, location: structuredClone(draft.location), farm_terrain: structuredClone(draft.farm_terrain),
        layout_patch_id: draft.farm_terrain.layout_id, blueprint_revision: draft.farm_terrain.plot.revision,
        version: farm.version + 1, relocation_available: false, relocation_used: true, relocation_draft: null });
      this.snapshots.delete(farm.id);
      log.set(input.idempotency_key, { idempotency_key: input.idempotency_key, payload_hash: hash, outcome: 'applied',
        result: { version: farm.version, events: [{ type: 'farm_relocated' }] } });
      this.commands.set(farm.id, log);
      return { kind: 'applied', farm: structuredClone(farm) };
    } catch (error) { if (error instanceof RelocationError) return reject(error.code); throw error; }
  }

  async nearby(regionId: string, excludeOwnerId: string, limit: number) {
    // 与 PgStore 同一排序键 (created_at, id)：同毫秒建的农场靠 id 定序，两套实现才会给出
    // 同样的列表——一致性套件抓过这里只按插入序的漂移。
    const all = [...this.farms.values()]
      .filter(f => f.region_id === regionId && f.visit_access === 'anyone' && f.owner_id !== excludeOwnerId)
      .sort((a, b) => a.created_at - b.created_at || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
    return { count: all.length, farms: all.slice(0, limit).map(({ created_at: _c, ...f }) => f as FarmRow) };
  }

  async snapshotGetOrCreate(farmId: string, slot: number, build: (current: FarmRow) => object) {
    const farm = this.farms.get(farmId);
    if (!farm) throw new Error('NO_FARM');
    const prev = this.snapshots.get(farmId);
    if (prev && prev.taken_at === slot) return { ...prev, farm: structuredClone(farm) };
    const body = build(structuredClone(farm));
    const changed = !prev || canonicalJson(prev.body) !== canonicalJson(body);
    const next = { revision: prev ? (changed ? prev.revision + 1 : prev.revision) : 1, taken_at: slot, body };
    this.snapshots.set(farmId, next);
    return { ...next, farm: structuredClone(farm) };
  }

  async ensureSystemFarm(playerHmac: string, farm: FarmRow) {
    if (this.farms.has(farm.id)) return;
    if (!this.players.has(farm.owner_id))
      this.players.set(farm.owner_id, { id: farm.owner_id, install_key_hmac: playerHmac });
    this.farms.set(farm.id, {
      ...farm, content_version: this.deps.contentVersion,
      domain_version: DOMAIN_VERSION, state_schema_version: STATE_SCHEMA_VERSION,
      created_at: this.deps.now(),
    });
  }

  private creationLocks = new Map<string, Promise<unknown>>();
  async createFarm(args: Parameters<Store['createFarm']>[0]) {
    const prior = this.creationLocks.get(args.ownerId) ?? Promise.resolve();
    const pending = prior.catch(() => {}).then(() => this.createFarmLocked(args));
    this.creationLocks.set(args.ownerId, pending);
    try { return await pending; }
    finally { if (this.creationLocks.get(args.ownerId) === pending) this.creationLocks.delete(args.ownerId); }
  }

  private async createFarmLocked(args: Parameters<Store['createFarm']>[0]) {
    const prior = this.creations.get(args.ownerId);
    if (prior) {
      // 建农场也要比对 payload hash：同 key 换地区不能被当成重试（Codex 二审 Important 2）。
      if (prior.key !== args.idempotencyKey || prior.hash !== args.payloadHash)
        return { kind: 'idempotency_mismatch' as const };
      return { kind: 'replayed' as const, farm: this.farms.get(prior.farmId)! };
    }
    const farm = await args.build();
    this.farms.set(farm.id, {
      ...farm, content_version: this.deps.contentVersion,
      domain_version: DOMAIN_VERSION, state_schema_version: STATE_SCHEMA_VERSION,
      created_at: this.deps.now(),
    });
    this.creations.set(args.ownerId, { key: args.idempotencyKey, hash: args.payloadHash, farmId: farm.id });
    return { kind: 'created' as const, farm };
  }

  async applyCommand(ownerId: string, env: CommandEnvelope, cmd: Command, fishingPresence?: FishingPresenceReader): Promise<ApplyOutcome> {
    const farm = await this.farmByOwner(ownerId);
    if (!farm) return { kind: 'no_farm' };
    const stored = this.farms.get(farm.id)!;

    // 1. 幂等查表**先于**版本门控：部署新版本后，对旧命令的同 key 重试必须能拿回已提交
    //    的结果，而不是先撞 503（Codex 三审 O-I4）。
    const log = this.commands.get(farm.id) ?? new Map();
    const hash = payloadHash(env);
    const prior = log.get(env.idempotency_key);
    if (prior)
      return prior.payload_hash === hash
        ? { kind: 'replayed', record: prior, farm: stored }
        : { kind: 'idempotency_mismatch' };

    // 2. 新命令才做版本门控。
    if (stored.content_version !== this.deps.contentVersion
      || stored.domain_version !== DOMAIN_VERSION
      || stored.state_schema_version !== STATE_SCHEMA_VERSION)
      return { kind: 'version_mismatch' };

    if (!relocationCommandMatches(stored, env)) {
      log.set(env.idempotency_key, { idempotency_key: env.idempotency_key, payload_hash: hash,
        outcome: 'rejected', result: commandRecordResult(env, { code: 'FARM_RELOCATED' }) });
      this.commands.set(farm.id, log);
      return { kind: 'rejected', code: 'FARM_RELOCATED' };
    }

    // 3. 锁后采样，单调 clamp。
    // QA 时间变换必须和 PgStore 走同一条路。只改一处的话，内存实现（测试与本地
    // 开发用）会和线上表现不一致，而线上正是没人天天盯着的那个。
    const realNow = this.deps.now();
    const effectiveNow = Math.max(qaNow(stored.state.qa, realNow), stored.state.clock.last_effective_now);

    if (env.base_version !== stored.version) return { kind: 'version_conflict', farm: stored };

    const ctx = makeCtx(stored.state, effectiveNow, this.deps.timezone, this.deps.content,
      plotForFarm(stored, this.deps.plot), realNow, farm.id);
    ctx.fishingPresence = fishingPresence?.();
    const r = apply(stored.state, cmd, ctx);
    const record: CommandRecord = {
      idempotency_key: env.idempotency_key, payload_hash: hash,
      outcome: r.ok ? 'applied' : 'rejected',
      result: r.ok ? null : commandRecordResult(env, { code: r.code, detail: r.detail }),
    };

    if (!r.ok) {
      // 失败也落日志并可重放（Codex 二审 Important 2：否则同 key 稍后可能从失败变成功）。
      log.set(env.idempotency_key, record);
      this.commands.set(farm.id, log);
      stored.state.clock.last_effective_now = effectiveNow;
      return { kind: 'rejected', code: r.code, detail: r.detail };
    }

    const nextState = { ...r.state, clock: { ...r.state.clock, last_effective_now: effectiveNow } };
    stored.state = nextState;
    stored.version += 1;
    applySettingsSideEffects(stored, cmd);
    const body = { ...currentOwnerFarmView(stored, effectiveNow, this.deps.timezone,
      this.deps.content, this.deps.plot), events: r.events };
    // 与 PgStore 一致：日志只记版本与事件，重放时由调用方用当前农场行重建视图。
    record.result = commandRecordResult(env, { version: stored.version, events: r.events });
    log.set(env.idempotency_key, record);
    this.commands.set(farm.id, log);
    return { kind: 'applied', body };
  }
}

/** 两个设置字段在列上而不是 state 里，由存储层写。 */
function applySettingsSideEffects(farm: FarmRow, cmd: Command): void {
  if (cmd.type === 'set_location_visible') farm.location_visible = cmd.visible;
  if (cmd.type === 'set_visit_access') farm.visit_access = cmd.access;
}
