import { farmPondSite, terrainNavigation } from '../geography/farm_terrain.js';
import { createHmac, randomUUID, timingSafeEqual } from 'node:crypto';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { WebSocket, WebSocketServer } from 'ws';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { AppDeps } from '../http/app.js';
import { tokenHash } from '../http/auth.js';
import type { FarmRow } from '../http/dto.js';
import { CAPACITY, walkable, type DirectoryAction, type Navigation } from './model.js';
import { Room, type Member, type Transport } from './room.js';
import { PartyTravel, type SpacePresence } from './party_travel.js';
import { AppearanceCatalog, defaultAppearance } from './appearance.js';
import { PartyVoice } from './voice.js';
import { PondCatalog, type PondRoom } from '../ponds/catalog.js';

interface Connection { ws: WebSocket; player: string; hash: string; room?: Room; member?: Member; openedAt: number; resumeNonce: string;
  space?: Pick<SpacePresence, 'home' | 'channel' | 'region' | 'layout' | 'revision' | 'terrain'>;
  lastSeen: number; lastAuth: number; tokens: number; tokenAt: number; busy: boolean; dressedAt?: number; pendingFarm?: string }
export const onlineGateways = new WeakMap<FastifyInstance, OnlineGateway>();

export class OnlineGateway {
  readonly rooms = new Map<string, Room>();
  readonly connections = new Set<Connection>();
  readonly travel: PartyTravel;
  readonly ponds: PondCatalog;
  readonly voice?: PartyVoice;
  private voiceSweep?: ReturnType<typeof setInterval>;
  private voiceSweeping = false;
  private byPlayer = new Map<string, Connection>();
  private loading = new Map<string, Promise<Room>>();
  private maps: Record<string, Navigation>;
  private appearances: AppearanceCatalog;
  private transitions: Promise<unknown> = Promise.resolve();
  private timer?: ReturnType<typeof setInterval>;
  private wss: WebSocketServer;
  private revokedResumes = new Map<string, number>();
  private relocationRefresh = new Map<string, Set<string>>();

  constructor(readonly app: FastifyInstance, readonly deps: AppDeps) {
    this.ponds = deps.pondCatalog ?? new PondCatalog();
    this.maps = JSON.parse(readFileSync(path.join(path.dirname(deps.regionsFile), 'online_navigation.json'), 'utf8')).maps;
    this.appearances = new AppearanceCatalog(deps.regionsFile);
    if (deps.voice) {
      this.voice = new PartyVoice(deps.voice, deps.store, deps.now, players => {
        for (const c of this.connections) if (players.includes(c.player) && c.ws.readyState === WebSocket.OPEN)
          c.ws.send(JSON.stringify({ t: 'voice_changed' }));
      }, deps.voiceMedia);
      this.voiceSweep = setInterval(() => {
        if (this.voiceSweeping) return;
        this.voiceSweeping = true;
        void this.voice!.sweep().catch(() => {}).finally(() => this.voiceSweeping = false);
      }, 5000);
      this.voiceSweep.unref();
    }
    this.travel = new PartyTravel(deps, player => this.presence(player), (key, player) => {
      const room = this.rooms.get(key);
      return !room || room.members.has(player) || room.members.size < room.capacity;
    });
    this.wss = new WebSocketServer({ noServer: true, maxPayload: 4096, perMessageDeflate: false });
    app.server.on('upgrade', (req, socket, head) => {
      if (req.url?.split('?')[0] !== '/v1/online' || this.connections.size >= 10000 ||
        [...this.connections].filter(c => !c.player).length >= 64) {
        socket.end('HTTP/1.1 503 Service Unavailable\r\nConnection: close\r\n\r\n'); return;
      }
      this.wss.handleUpgrade(req, socket, head, ws => this.accept(ws));
    });
    this.timer = setInterval(() => {
      for (const [key, room] of this.rooms) {
        void room.tick();
        if (room.failed || (!room.members.size && Date.now() - room.lastActive > 60000)) this.rooms.delete(key);
      }
      const now = Date.now();
      for (const [nonce, until] of this.revokedResumes) if (until < now) this.revokedResumes.delete(nonce);
      for (const c of this.connections) {
        if ((!c.player && now - c.openedAt > 5000) || now - c.lastSeen > 30000) c.ws.terminate();
        if (c.player && now - c.lastAuth > 60000) {
          c.lastAuth = now;
          void this.deps.store.playerByToken(c.hash, this.deps.now()).then(p => {
            if (!p) c.ws.close(4003, 'UNAUTHENTICATED');
          }).catch(() => c.ws.close(1013, 'AUTH_UNAVAILABLE'));
        }
      }
    }, 50);
    this.timer.unref();
    app.addHook('preClose', async () => { this.close(); await this.voice?.close(); });
  }
  close() {
    if (this.timer) clearInterval(this.timer);
    this.timer = undefined;
    if (this.voiceSweep) clearInterval(this.voiceSweep);
    this.voiceSweep = undefined;
    for (const c of this.connections) { c.room?.leave(c.member!); c.ws.terminate(); }
    this.connections.clear();
    this.byPlayer.clear();
    this.wss.close();
  }
  private active(player: string): Connection | undefined {
    const c = this.byPlayer.get(player);
    return c?.member && c.room && !c.room.failed && c.room.members.get(player) === c.member && c.ws.readyState === WebSocket.OPEN ? c : undefined;
  }
  fishingPresence(player: string) {
    const c = this.active(player);
    if (!c?.space || !c.member || !c.room || c.busy) return null;
    const member = c.member, nav = c.room.nav(member.floor);
    return { space: c.room.kind, home: c.space.home, room: c.room.key, nonce: c.resumeNonce, x: member.x, z: member.z,
      ...(c.room.farmFishingSite ? { farm_site: c.room.farmFishingSite } : {}),
      ...(c.room.pond ? { pond: { id: c.room.pond.location.id, site: c.room.pond.site } } : {}),
      walkable: (point: [number, number]) => walkable(nav, point),
      validSequence: (sequence: number) => sequence > (member.invalidFishingSequence ?? -1) };
  }
  syncFishing(farm: FarmRow) {
    const c = this.active(farm.owner_id);
    if (c?.member && c.room && !c.busy) c.room.syncFishing(c.member, farm, c.resumeNonce);
  }
  private presence(player: string): SpacePresence | null {
    const c = this.active(player);
    if (!c?.space) return null;
    return { ...c.space, key: c.room!.key, kind: c.room!.kind, floor: c.member!.floor, epoch: c.member!.epoch, nonce: c.resumeNonce };
  }
  private serialize<T>(fn: () => Promise<T>): Promise<T> {
    const result = this.transitions.then(fn);
    this.transitions = result.catch(() => {});
    return result;
  }
  /** Fishing and relocation share the admission queue, including the durable write and presence sync. */
  withFishingCommand<T>(fn: () => Promise<T>): Promise<T> { return this.serialize(fn); }

  withFarmRelocation<T>(ownerId: string, farmId: string, commit: () => Promise<T>): Promise<T> {
    return this.serialize(async () => {
      const before = await this.deps.store.farmByOwner(ownerId);
      if (!before || before.id !== farmId) throw new Error('NOT_FOUND');
      const fingerprint = farmGeometry(before);
      // A consumed one-time relocation can only replay or reject in the store; recovery
      // must remain possible after the player has already continued into another activity.
      if (!before.farm_terrain && !before.relocation_used) {
        const owner = this.active(ownerId);
        if (owner?.room?.kind === 'mine') throw new Error('RELOCATION_BUSY');
        const players = new Set([ownerId]);
        for (const c of this.connections) if (c.member && c.room?.kind === 'farm' && c.space?.home === farmId)
          players.add(c.player);
        const config = this.deps.content.fishing;
        for (const player of players) {
          const farm = player === ownerId ? before : await this.deps.store.farmByOwner(player);
          const cast = farm?.state.fishing?.active;
          // Match the domain's active-cast window; abandoned casts cannot lock relocation forever.
          if (cast && this.deps.now() <= (cast.hooked_at ?? cast.hook_until) + config.max_steps * config.step_ms + config.settle_grace_ms)
            throw new Error('RELOCATION_BUSY');
        }
      }
      try {
        const result = await commit();
        const after = await this.deps.store.farmByOwner(ownerId);
        if (!after || farmGeometry(after) !== fingerprint) this.farmRelocated(ownerId, farmId);
        return result;
      } catch (error) {
        // A lost COMMIT response may still have saved the new geometry. Close stale
        // actors even when the HTTP caller must recover the result by idempotency key.
        try {
          const after = await this.deps.store.farmByOwner(ownerId);
          if (!after || farmGeometry(after) !== fingerprint) this.farmRelocated(ownerId, farmId);
        } catch { this.farmRelocated(ownerId, farmId); }
        throw error;
      }
    });
  }

  /** Only an actual new owner/visitor DTO clears the fence, never a prior cached response. */
  acknowledgeFarmRead(player: string, view: Record<string, unknown>): Promise<void> {
    return this.serialize(async () => {
      const farmId = typeof view.farm_id === 'string' ? view.farm_id : '';
      const pending = this.relocationRefresh.get(player);
      if (!pending?.has(farmId)) return;
      const farm = await this.deps.store.farmById(farmId);
      if (!farm || view.layout_patch_id !== farm.layout_patch_id || view.blueprint_revision !== farm.blueprint_revision) return;
      const terrain = view.farm_terrain as { plot?: { checksum?: unknown } } | undefined;
      if (terrain?.plot?.checksum !== farm.farm_terrain?.plot.checksum) return;
      pending.delete(farmId);
      if (!pending.size) this.relocationRefresh.delete(player);
    });
  }

  private farmRelocated(ownerId: string, farmId: string) {
    for (const c of this.connections) {
      if (c.player !== ownerId && c.pendingFarm !== farmId && !(c.room?.kind === 'farm' && c.space?.home === farmId)) continue;
      const pending = this.relocationRefresh.get(c.player) ?? new Set<string>();
      pending.add(farmId); this.relocationRefresh.set(c.player, pending);
      this.revokedResumes.set(c.resumeNonce, Date.now() + 120000);
      c.resumeNonce = randomUUID();
      if (c.member) { c.member.epoch++; c.room?.leave(c.member); }
      c.member = undefined; c.room = undefined; c.space = undefined;
      if (c.ws.readyState === WebSocket.OPEN) {
        c.ws.send(JSON.stringify({ t: 'error', code: 'FARM_RELOCATED', farm_id: farmId }));
        c.ws.close(4005, 'FARM_RELOCATED');
      }
    }
    // An empty channel also owns immutable navigation and must not survive this change.
    for (const [key, room] of this.rooms) if (room.kind === 'farm' && key.startsWith('farm:' + farmId + ':')) {
      room.failed = true; this.rooms.delete(key);
    }
  }
  private accept(ws: WebSocket) {
    const now = Date.now();
    const c: Connection = { ws, player: '', hash: '', openedAt: now, resumeNonce: randomUUID(), lastSeen: now, lastAuth: now, tokens: 60, tokenAt: now, busy: false };
    this.connections.add(c);
    ws.on('error', () => {});
    ws.on('close', (_code, reason) => {
      if (reason.toString() === 'LEAVING') this.revokedResumes.set(c.resumeNonce, Date.now() + 120000);
      if (c.member) c.room?.leave(c.member);
      this.connections.delete(c);
      if (this.byPlayer.get(c.player) === c) this.byPlayer.delete(c.player);
    });
    ws.on('pong', () => c.lastSeen = Date.now());
    ws.on('message', (raw, binary) => {
      const now = Date.now();
      c.tokens = Math.min(60, c.tokens + (now - c.tokenAt) * .03); c.tokenAt = now;
      if (--c.tokens < 0 || binary) { ws.close(4002, 'RATE_OR_SCHEMA'); return; }
      c.lastSeen = now;
      let b: Record<string, unknown>;
      try {
        const parsed: unknown = JSON.parse(raw.toString());
        if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error();
        b = parsed as Record<string, unknown>;
      } catch { ws.close(4002, 'SCHEMA'); return; }
      if (b.t === 'ping') {
        ws.send(JSON.stringify({ t: 'pong', at: b.at, time: this.deps.now(),
          resume: c.member && c.room?.kind === 'mine' ? this.resumeTicket(c, c.room.key, c.member.floor) : undefined }));
        return;
      }
      if (c.busy) return;
      if (!c.player || b.t === 'join' || b.t === 'leave') {
        c.busy = true;
        if (b.t === 'join') {
          c.pendingFarm = b.kind !== 'mine' && typeof b.farm_id === 'string' ? b.farm_id : undefined;
          if (b.travel_ticket && c.player) {
            try {
              const grant = this.travel.read(b.travel_ticket, c.player);
              if (grant.destination.kind !== 'mine') c.pendingFarm = grant.destination.home;
            } catch { /* The serialized admission returns the protocol error. */ }
          }
        }
        void this.serialize(() => this.control(c, b)).catch(error => {
          if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ t: 'error', code: safeCode(error) }));
        }).finally(() => { c.busy = false; c.pendingFarm = undefined; });
      } else {
        if (b.t === 'appearance') {
          try {
            if (!c.member || !c.room) throw new Error('NOT_IN_SPACE');
            const appearance = this.appearances.parse(b.appearance);
            if (now - (c.dressedAt ?? 0) < 500) throw new Error('APPEARANCE_RATE_LIMIT');
            c.dressedAt = now;
            c.room.dress(c.member, appearance);
            ws.send(JSON.stringify({ t: 'appearance_result', ok: true }));
          } catch (error) { ws.send(JSON.stringify({ t: 'appearance_result', ok: false, code: safeCode(error) })); }
          return;
        }
        try { if (c.member) c.room?.input(c.member, b); }
        catch { ws.close(4002, 'SCHEMA'); }
      }
    });
  }
  private async control(c: Connection, b: Record<string, unknown>) {
    if (c.ws.readyState !== WebSocket.OPEN) return;
    if (!c.player) {
      if (b.t !== 'auth' || typeof b.token !== 'string' || b.token.length !== 64) throw new Error('UNAUTHENTICATED');
      c.hash = tokenHash(b.token);
      const player = await this.deps.store.playerByToken(c.hash, this.deps.now());
      if (!player) throw new Error('UNAUTHENTICATED');
      if (c.ws.readyState !== WebSocket.OPEN) return;
      // One active spatial presence per account, across all device tokens and scene types.
      for (const old of this.connections) if (old !== c && old.player === player.id) {
        if (old.member) old.room?.leave(old.member);
        old.ws.close(4001, 'SESSION_REPLACED');
      }
      c.player = player.id;
      this.byPlayer.set(c.player, c);
      c.ws.send(JSON.stringify({ t: 'authenticated', player: c.player, appearance_version: 1 }));
      return;
    }
    if (b.t === 'leave') {
      this.revokedResumes.set(c.resumeNonce, Date.now() + 120000);
      c.resumeNonce = randomUUID();
      if (c.member && c.room) await c.room.exclusive(async () => c.room!.leave(c.member!));
      c.member = undefined; c.room = undefined;
      c.ws.send(JSON.stringify({ t: 'departed' }));
      return;
    }
    if (b.t !== 'join' || c.member) throw new Error('ALREADY_IN_SPACE');
    const appearance = b.appearance === undefined ? defaultAppearance() : this.appearances.parse(b.appearance);
    const grant = b.travel_ticket ? this.travel.read(b.travel_ticket, c.player) : null;
    if (grant) {
      if (b.resume) throw new Error('SCHEMA');
      await this.travel.validate(grant, c.player);
      b = { ...b, kind: grant.destination.kind, farm_id: grant.destination.home, channel: grant.destination.channel,
        ...(grant.destination.kind === 'pond' ? { pond_id: grant.destination.home, catalog_revision: grant.destination.terrain } : {}) };
    }
    if (!['street', 'farm', 'mine', 'pond'].includes(String(b.kind))) throw new Error('SCHEMA');
    // Legacy clients naming their home street enter the same private farm.
    const kind = b.kind === 'street' ? 'farm' : b.kind;
    const farm = await this.deps.store.farmByOwner(c.player);
    if (!farm?.state.journey) throw new Error('NO_FARM');
    let key = '', nav: Navigation, partyId = '', resumeFloor = 1, host = farm;
    let pond: PondRoom | undefined;
    if (kind === 'pond') {
      if (b.resume) throw new Error('SCHEMA');
      const channel = b.channel ?? 1;
      if (!Number.isInteger(channel) || Number(channel) < 1 || Number(channel) > 100) throw new Error('SCHEMA');
      pond = this.ponds.room(b.pond_id, b.catalog_revision, this.deps.content);
      key = 'pond:' + pond.location.id + ':' + channel;
      nav = pond.template.navigation;
    } else if (kind === 'mine') {
      const directory = await this.deps.store.realtimeDirectory(c.player);
      partyId = directory.party?.id ?? '';
      const recovery = b.resume ? this.readResume(String(b.resume), c.player) : null;
      if (b.resume && (!recovery || recovery.key !== 'mine:' + directory.instance)) throw new Error('RESUME_EXPIRED');
      // Explicit user rule: only the leader's CURRENT in-mine presence supplies a binding.
      const leader = directory.party?.leader;
      const leaderConnection = leader && leader !== c.player ? this.active(leader) : undefined;
      const active = leaderConnection?.room?.kind === 'mine' ? leaderConnection : undefined;
      let instance = recovery?.key.slice(5) ?? grant?.destination.key.slice(5) ?? active?.room?.key.slice(5) ?? directory.instance;
      if (!recovery && active) resumeFloor = active.member!.floor;
      if ((!active || recovery) && instance) {
        const prior = await this.deps.store.realtimeLoad('mine:' + instance);
        if (recovery && prior?.mine.retired) throw new Error('RESUME_EXPIRED');
        // A former member cannot enter another leader's private instance without that party.
        if (!recovery && (prior?.mine.retired || (prior?.mine.party && prior.mine.party !== partyId) ||
          (prior?.mine.owner && prior.mine.owner !== c.player && !directory.party?.members.includes(prior.mine.owner)))) instance = '';
      }
      if (recovery) { resumeFloor = recovery.floor; c.resumeNonce = recovery.nonce; partyId = ''; }
      if (grant) resumeFloor = grant.destination.floor;
      if (!instance) instance = randomUUID();
      key = 'mine:' + instance;
      nav = { cell: .5, rows: [], spawn: [4.75, -.75] };
    } else {
      const channel = b.channel ?? 1;
      if (!Number.isInteger(channel) || Number(channel) < 1 || Number(channel) > 100) throw new Error('SCHEMA');
      if (kind === 'farm' || b.farm_id) {
        host = await this.deps.store.farmById(String(b.farm_id ?? farm.id)) ?? farm;
        const permitted = kind === 'farm' ? await this.travel.canVisitFarm(c.player, host) : await this.travel.canVisitStreet(c.player, host);
        if (String(b.farm_id ?? farm.id) !== host.id || !permitted) throw new Error('NOT_FOUND');
      }
      if (kind === 'farm' && this.relocationRefresh.get(c.player)?.has(host.id)) throw new Error('FARM_RELOCATED');
      // Reading a new DTO on another device cannot authorize an old rendered scene.
      // Bind this join's geometry only after relocation; original clients retain access
      // to farms whose layout has never changed.
      if (kind === 'farm' && host.relocation_used && (!host.farm_terrain || b.terrain_checksum !== host.farm_terrain.plot.checksum))
        throw new Error('FARM_RELOCATED');
      nav = kind === 'farm' && host.farm_terrain ? terrainNavigation(host.farm_terrain)
        : this.maps[String(kind) + ':' + host.layout_patch_id + ':' + host.blueprint_revision];
      if (!nav) throw new Error('MAP_UNAVAILABLE');
      key = kind === 'farm' ? 'farm:' + host.id + ':' + channel :
        'street:' + host.region_id + ':' + host.layout_patch_id + ':' + host.blueprint_revision + ':' + channel;
    }
    const room = await this.getRoom(key, kind as Room['kind'], nav, kind === 'farm' ? host : undefined, pond);
    if (grant && key !== grant.destination.key) throw new Error('DESTINATION_CHANGED');
    if (room.members.size >= room.capacity) throw new Error('ROOM_FULL');
    if (c.ws.readyState !== WebSocket.OPEN) return;
    const wire: Transport = { buffered: () => c.ws.bufferedAmount,
      send: data => { if (c.ws.readyState === WebSocket.OPEN) c.ws.send(data); },
      close: (code, reason) => c.ws.close(code, reason),
      resume: floor => kind === 'mine' ? this.resumeTicket(c, key, floor) : '' };
    c.room = room;
    c.space = { home: pond?.location.id ?? host.id, channel: kind === 'mine' ? 0 : Number(b.channel ?? 1), region: pond?.location.region_id ?? host.region_id,
      layout: pond?.template.id ?? host.layout_patch_id, revision: pond?.template.revision ?? host.blueprint_revision,
      terrain: pond?.revision ?? host.farm_terrain?.plot.checksum ?? '' };
    c.member = await room.join(farm, wire, async () => {
      if (c.ws.readyState !== WebSocket.OPEN) throw new Error('CONNECTION_CLOSED');
      if (grant) await this.travel.validate(grant, c.player);
      // Replace the saved entry only after both capacity and durable room startup succeeded.
      if (kind === 'mine') await this.deps.store.realtimeDirectory(c.player, 'bind', key.slice(5));
    }, partyId, resumeFloor, appearance);
    if (c.ws.readyState !== WebSocket.OPEN) { room.leave(c.member); c.member = undefined; c.room = undefined; }
  }
  private resumeTicket(c: Connection, key: string, floor: number): string {
    const payload = Buffer.from(JSON.stringify({ player: c.player, key, floor, nonce: c.resumeNonce, expires: Date.now() + 120000 })).toString('base64url');
    return payload + '.' + createHmac('sha256', this.deps.pepper).update(payload).digest('hex');
  }
  private readResume(ticket: string, player: string): { key: string; floor: number; nonce: string } | null {
    if (ticket.length > 1024) return null;
    const [payload, signature] = ticket.split('.');
    if (!payload || !/^[a-f0-9]{64}$/.test(signature ?? '')) return null;
    const expected = createHmac('sha256', this.deps.pepper).update(payload).digest();
    if (!timingSafeEqual(expected, Buffer.from(signature, 'hex'))) return null;
    try {
      const value = JSON.parse(Buffer.from(payload, 'base64url').toString());
      if (value.player !== player || value.expires < Date.now() || !/^mine:[0-9a-f-]{36}$/.test(value.key) ||
        !Number.isInteger(value.floor) || value.floor < 1 || value.floor > 5 || this.revokedResumes.has(value.nonce)) return null;
      return value;
    } catch { return null; }
  }
  private async getRoom(key: string, kind: Room['kind'], nav: Navigation, host?: FarmRow, pond?: PondRoom): Promise<Room> {
    const existing = this.rooms.get(key);
    if (existing && !existing.failed) return existing;
    if (this.loading.has(key)) return this.loading.get(key)!;
    if (this.rooms.size >= 256) throw new Error('SERVER_FULL');
    const loading = (async () => {
      const site = kind === 'farm' ? farmPondSite(host?.farm_terrain, this.deps.content.fishing.sites.farm_pond) : undefined;
      const room = new Room(key, kind, nav, this.deps.store, this.deps.content, this.deps.now, site, pond);
      await room.load();
      this.rooms.set(key, room);
      return room;
    })();
    this.loading.set(key, loading);
    try { return await loading; } finally { this.loading.delete(key); }
  }
  async refresh(player: string) {
    const farm = await this.deps.store.farmByOwner(player);
    if (farm) for (const room of this.rooms.values()) room.reload(farm);
    if (farm) await this.revokeVisitors(farm.id);
  }
  prepareTravel(player: string, target: string, mode: 'leader' | 'follow' | 'farm') {
    return this.serialize(() => this.travel.prepare(player, target, mode));
  }
  private async revokeVisitors(farmId?: string) {
    const homes = new Map<string, Awaited<ReturnType<AppDeps['store']['farmById']>>>();
    for (const c of this.connections) {
      if (!c.member || c.room?.kind !== 'farm' || !c.space || (farmId && c.space.home !== farmId)) continue;
      if (!homes.has(c.space.home)) homes.set(c.space.home, await this.deps.store.farmById(c.space.home));
      const farm = homes.get(c.space.home);
      if (!farm || !await this.travel.canVisitFarm(c.player, farm)) {
        c.room.leave(c.member);
        c.ws.close(4004, 'ACCESS_REVOKED');
      }
    }
  }
  async party(player: string, action: DirectoryAction, value = '') {
    return this.serialize(async () => {
      const before = await this.deps.store.realtimeDirectory(player);
      const result = await this.deps.store.realtimeDirectory(player, action, value);
      await this.revokeVisitors();
      const affected = new Set([player, ...(before.party?.members ?? []), ...(result.party?.members ?? [])]);
      // A voice outage cannot roll back a committed party action. The voice
      // authority retains failed retirements, refuses new grants, and retries.
      await this.voice?.membershipChanged([...affected]).catch(() => {});
      for (const c of this.connections) if (affected.has(c.player) && c.ws.readyState === WebSocket.OPEN)
        c.ws.send(JSON.stringify({ t: 'party_changed' }));
      return result;
    });
  }
  async reset(player: string) {
    return this.serialize(async () => {
      const entry = await this.deps.store.realtimeDirectory(player);
      if (entry.party && entry.party.leader !== player) throw new Error('NOT_LEADER');
      const room = this.rooms.get('mine:' + entry.instance);
      if (room) await room.exclusive(async () => {});
      if (room?.members.size) throw new Error('INSTANCE_OCCUPIED');
      if (entry.party && [...this.connections].some(c => entry.party!.members.includes(c.player) && c.room?.kind === 'mine' && c.member && c.room.members.has(c.player))) throw new Error('INSTANCE_OCCUPIED');
      if (!entry.instance) return entry;
      const saved = await this.deps.store.realtimeLoad('mine:' + entry.instance);
      if (saved) {
        await this.deps.store.realtimeCommit('mine:' + entry.instance, saved.revision, randomUUID(), { ...saved.mine, retired: true }, []);
        this.rooms.delete('mine:' + entry.instance);
      }
      return this.deps.store.realtimeDirectory(player, 'bind', randomUUID());
    });
  }
}

function farmGeometry(farm: FarmRow): string {
  return JSON.stringify([farm.region_id, farm.layout_patch_id, farm.blueprint_revision, farm.farm_terrain?.plot.checksum ?? '']);
}

function safeCode(error: unknown): string {
  const code = error instanceof Error ? error.message : '';
  return /^[A-Z_]{3,40}$/.test(code) ? code : 'ONLINE_UNAVAILABLE';
}

export function registerOnline(app: FastifyInstance, deps: AppDeps,
  auth: (req: FastifyRequest) => Promise<{ id: string } | null>): OnlineGateway {
  const gateway = new OnlineGateway(app, deps);
  onlineGateways.set(app, gateway);
  const partyLimit = app.createRateLimit({ max: 20, timeWindow: '1 minute',
    keyGenerator: req => 'party:' + tokenHash(String(req.headers.authorization ?? '')) });
  const revocations = new WeakMap<FastifyRequest, string>();
  app.addHook('preHandler', async req => {
    if ((req.method === 'DELETE' && ['/v1/auth/token', '/v1/auth/tokens'].includes(req.url)) ||
      (req.method === 'POST' && req.url === '/v1/auth/rotate-install-key')) {
      const player = await auth(req);
      if (player) revocations.set(req, player.id);
    }
  });
  app.get('/v1/online/status', async (req, reply) => {
    const player = await auth(req);
    if (!player) return reply.code(401).send({ code: 'UNAUTHENTICATED' });
    return { protocol: 1, capacity: CAPACITY, template: 'starter_mine',
      voice: { available: !!gateway.voice, capacity: deps.voice?.maxParticipants ?? 8 },
      ...await gateway.travel.status(player.id) };
  });
  const voiceLimit = app.createRateLimit({ max: 60, timeWindow: '1 minute',
    keyGenerator: req => 'voice:' + tokenHash(String(req.headers.authorization ?? '')) });
  for (const action of ['join', 'heartbeat', 'leave'] as const) app.post('/v1/online/voice/' + action, async (req, reply) => {
    reply.header('cache-control', 'no-store');
    const player = await auth(req);
    if (!player) return reply.code(401).send({ code: 'UNAUTHENTICATED' });
    if (!gateway.voice) return reply.code(503).send({ code: 'VOICE_UNAVAILABLE' });
    const quota = await voiceLimit(req);
    if (!quota.isAllowed && quota.isExceeded) return reply.code(429).send({ code: 'RATE_LIMITED' });
    const body = req.body as Record<string, unknown>;
    const key = action === 'join' ? 'request_id' : 'lease_id';
    if (!body || Object.keys(body).some(k => k !== key) || typeof body[key] !== 'string' ||
        !/^[a-zA-Z0-9_-]{8,64}$/.test(body[key] as string)) return reply.code(400).send({ code: 'SCHEMA' });
    const hash = tokenHash(String(req.headers.authorization).slice(7));
    try {
      if (action === 'join') return await gateway.voice.join(player.id, hash, body[key] as string);
      if (action === 'heartbeat') return await gateway.voice.heartbeat(player.id, hash, body[key] as string);
      return await gateway.voice.leave(player.id, body[key] as string);
    } catch (error) {
      const code = safeCode(error);
      return reply.code(code === 'VOICE_UNAVAILABLE' || code === 'ONLINE_UNAVAILABLE' ? 503 : 409)
        .send({ code: code === 'ONLINE_UNAVAILABLE' ? 'VOICE_UNAVAILABLE' : code });
    }
  });
  app.post('/v1/online/party', { config: { rateLimit: { max: 600, timeWindow: '1 minute' } } }, async (req, reply) => {
    const player = await auth(req);
    if (!player) return reply.code(401).send({ code: 'UNAUTHENTICATED' });
    const quota = await partyLimit(req);
    if (!quota.isAllowed && quota.isExceeded) return reply.code(429).header('retry-after', quota.ttlInSeconds).send({ code: 'RATE_LIMITED' });
    const body = req.body as { action?: string; value?: string };
    if (!body || !['create', 'join', 'leave', 'kick', 'leader', 'disband', 'farm_access'].includes(body.action ?? '') ||
      (body.value !== undefined && (typeof body.value !== 'string' || body.value.length > 64))) return reply.code(400).send({ code: 'SCHEMA' });
    try { return await gateway.party(player.id, body.action as DirectoryAction, body.value); }
    catch (e) { return reply.code(409).send({ code: safeCode(e) }); }
  });
  app.post('/v1/online/travel', { config: { rateLimit: { max: 600, timeWindow: '1 minute' } } }, async (req, reply) => {
    const player = await auth(req);
    if (!player) return reply.code(401).send({ code: 'UNAUTHENTICATED' });
    const quota = await partyLimit(req);
    if (!quota.isAllowed && quota.isExceeded) return reply.code(429).header('retry-after', quota.ttlInSeconds).send({ code: 'RATE_LIMITED' });
    const body = req.body as { target?: unknown; mode?: unknown };
    if (!body || typeof body.mode !== 'string' || !['leader', 'follow', 'farm'].includes(body.mode) || (body.mode !== 'leader' && (typeof body.target !== 'string' || !/^[0-9a-f-]{36}$/.test(body.target))))
      return reply.code(400).send({ code: 'SCHEMA' });
    try { return await gateway.prepareTravel(player.id, String(body.target ?? ''), body.mode as 'leader' | 'follow' | 'farm'); }
    catch (e) { return reply.code(409).send({ code: safeCode(e) }); }
  });
  app.post('/v1/online/reset', async (req, reply) => {
    const player = await auth(req);
    if (!player) return reply.code(401).send({ code: 'UNAUTHENTICATED' });
    if ((req.body as { confirm?: boolean })?.confirm !== true) return reply.code(400).send({ code: 'CONFIRM_RESET' });
    try { return await gateway.reset(player.id); }
    catch (e) { return reply.code(409).send({ code: safeCode(e) }); }
  });
  app.addHook('onResponse', async (req, reply) => {
    const revoked = revocations.get(req);
    if (revoked && reply.statusCode < 300) {
      const hash = tokenHash(String(req.headers.authorization).slice(7));
      await gateway.voice?.revoke(revoked, req.url === '/v1/auth/token' ? hash : undefined).catch(() => {});
      for (const c of gateway.connections) if (c.player === revoked && (req.url !== '/v1/auth/token' || c.hash === hash)) {
        if (c.member) c.room?.leave(c.member);
        c.ws.close(4003, 'UNAUTHENTICATED');
      }
    }
    if (req.method === 'POST' && req.url === '/v1/farms/me/commands' && reply.statusCode < 300) {
      const player = await auth(req);
      if (player) await gateway.refresh(player.id);
    }
  });
  app.addHook('onSend', async (req, reply, payload) => {
    const route = req.url.split('?')[0];
    if (reply.statusCode >= 300 || typeof payload !== 'string' || !(
      req.method === 'GET' && (route === '/v1/farms/me' || /^\/v1\/farms\/[0-9a-f-]{36}\/snapshot$/.test(route)) ||
      req.method === 'POST' && (route === '/v1/online/travel' || route === '/v1/farms/me/relocation/confirm'))) return payload;
    const player = await auth(req);
    if (!player) return payload;
    const body = JSON.parse(payload) as Record<string, unknown>;
    const view = route === '/v1/online/travel' ? body.snapshot : body;
    if (view && typeof view === 'object') await gateway.acknowledgeFarmRead(player.id, view as Record<string, unknown>);
    return payload;
  });
  return gateway;
}
