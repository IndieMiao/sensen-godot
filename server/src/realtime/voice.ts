import { randomUUID } from 'node:crypto';
import { AccessToken, RoomServiceClient, TrackSource } from 'livekit-server-sdk';
import type { Store } from '../http/store.js';

export interface VoiceConfig {
  url: string; apiKey: string; apiSecret: string; namespace: string;
  mode: 'cloud' | 'self-hosted'; maxParticipants: number;
  maxTotalParticipants?: number;
  adminUrl?: string;
}
export interface VoiceMedia {
  listRooms(): Promise<{ name: string }[]>;
  createRoom(options: { name: string; maxParticipants: number; emptyTimeout: number; departureTimeout: number }): Promise<unknown>;
  deleteRoom(name: string): Promise<void>;
}
interface Lease { id: string; request: string; player: string; tokenHash: string; expires: number }
interface VoiceRoom { party: string; name: string; ready: boolean; leases: Map<string, Lease>; retiring: Set<string> }
export const VOICE_LEASE_MS = 20000;

export function voiceConfig(env: NodeJS.ProcessEnv): VoiceConfig | undefined {
  const values = [env.LIVEKIT_URL, env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET];
  if (values.every(v => !v)) return undefined;
  if (values.some(v => !v)) throw new Error('Incomplete LiveKit configuration');
  const url = new URL(values[0]!);
  const mode = env.LIVEKIT_MODE ?? 'cloud';
  if (!['cloud', 'self-hosted'].includes(mode) || !['ws:', 'wss:'].includes(url.protocol) ||
      (mode === 'cloud' && url.protocol !== 'wss:') || url.username || url.password || url.search || url.hash)
    throw new Error('Invalid LiveKit URL or mode');
  const namespace = env.VOICE_NAMESPACE;
  let adminUrl: string | undefined;
  if (env.LIVEKIT_ADMIN_URL) {
    const admin = new URL(env.LIVEKIT_ADMIN_URL);
    if (!['http:', 'https:'].includes(admin.protocol) || admin.username || admin.password || admin.search || admin.hash ||
      (mode === 'cloud' && admin.protocol !== 'https:')) throw new Error('Invalid LiveKit admin URL');
    adminUrl = admin.toString().replace(/\/$/, '');
  }
  if (!namespace || !/^[a-z0-9-]{3,40}$/.test(namespace)) throw new Error('Set an isolated VOICE_NAMESPACE');
  const maxParticipants = Number(env.VOICE_MAX_PARTICIPANTS ?? 8);
  if (!Number.isInteger(maxParticipants) || maxParticipants < 2 || maxParticipants > 8) throw new Error('Voice capacity must be 2–8');
  const maxTotalParticipants = Number(env.VOICE_MAX_TOTAL_PARTICIPANTS ?? 32);
  if (!Number.isInteger(maxTotalParticipants) || maxTotalParticipants < maxParticipants || maxTotalParticipants > 300)
    throw new Error('Voice total capacity must be between room capacity and 300');
  return { url: url.toString().replace(/\/$/, ''), apiKey: values[1]!, apiSecret: values[2]!, namespace,
    mode: mode as VoiceConfig['mode'], maxParticipants, maxTotalParticipants, adminUrl };
}

/** Ephemeral voice authority. The existing realtime writer owns this service too.
 * Room generations make cached SFU tokens harmless after membership/lease removal,
 * including self-hosted LiveKit, where RemoveParticipant alone does not revoke JWTs.
 */
export class PartyVoice {
  private rooms = new Map<string, VoiceRoom>();
  private pending: Promise<unknown> = Promise.resolve();
  private closed = false;
  readonly media: VoiceMedia;
  constructor(readonly config: VoiceConfig, private store: Store, private now: () => number,
    private notify: (players: string[]) => void, media?: VoiceMedia) {
    this.media = media ?? new RoomServiceClient(config.adminUrl ?? config.url.replace(/^ws/, 'http'), config.apiKey, config.apiSecret,
      { requestTimeout: 2, failover: false });
  }
  private serial<T>(fn: () => Promise<T>): Promise<T> {
    const result = this.pending.then(fn);
    this.pending = result.catch(() => {});
    return result;
  }
  private prefix(party: string) { return `${this.config.namespace}-${party}-`; }
  private name(party: string) { return this.prefix(party) + randomUUID(); }
  private async retire(room: VoiceRoom) {
    for (const name of room.retiring) {
      try { await this.media.deleteRoom(name); }
      catch (e) { if ((e as { code?: string }).code !== 'not_found') throw new Error('VOICE_UNAVAILABLE'); }
      room.retiring.delete(name);
    }
  }
  private async rotate(room: VoiceRoom, remove: string[]) {
    const affected = [...room.leases.keys()];
    for (const player of remove) room.leases.delete(player);
    room.retiring.add(room.name);
    room.name = this.name(room.party);
    room.ready = false;
    // Notify first: healthy clients stop using the old media room immediately,
    // even if the SFU admin API is temporarily unavailable. New grants fail closed.
    this.notify(affected);
    await this.retire(room);
  }
  private async reconcile(room: VoiceRoom) {
    const invalid: string[] = [];
    for (const lease of room.leases.values()) {
      const directory = await this.store.realtimeDirectory(lease.player);
      const auth = await this.store.playerByToken(lease.tokenHash, this.now());
      if (lease.expires <= this.now() || !auth || directory.party?.id !== room.party ||
        !directory.party.members.includes(lease.player)) invalid.push(lease.player);
    }
    if (invalid.length) await this.rotate(room, invalid);
    await this.retire(room);
  }
  private async roomFor(party: string): Promise<VoiceRoom> {
    let room = this.rooms.get(party);
    if (!room) {
      room = { party, name: this.name(party), ready: false, leases: new Map(), retiring: new Set() };
      // Reclaim media sessions left by an earlier process before admitting anyone.
      // Only this environment's namespace and this party are eligible for deletion.
      const previous = await this.media.listRooms();
      for (const old of previous) if (old.name.startsWith(this.prefix(party))) room.retiring.add(old.name);
      this.rooms.set(party, room);
    }
    await this.reconcile(room);
    if (!room.ready) {
      await this.media.createRoom({ name: room.name, maxParticipants: this.config.maxParticipants, emptyTimeout: 30, departureTimeout: 10 });
      room.ready = true;
    }
    return room;
  }
  join(player: string, hash: string, request: string) {
    return this.serial(async () => {
      if (this.closed) throw new Error('VOICE_UNAVAILABLE');
      const directory = await this.store.realtimeDirectory(player);
      if (!directory.party?.members.includes(player)) throw new Error('VOICE_NO_PARTY');
      const existing = this.rooms.get(directory.party.id)?.leases.has(player);
      const total = [...this.rooms.values()].reduce((sum, r) => sum + r.leases.size, 0);
      if (!existing && total >= (this.config.maxTotalParticipants ?? 32)) throw new Error('VOICE_BUSY');
      const room = await this.roomFor(directory.party.id);
      const before = room.leases.get(player);
      if (before && (before.request !== request || before.tokenHash !== hash)) await this.rotate(room, [player]);
      if (!room.leases.has(player) && room.leases.size >= this.config.maxParticipants) throw new Error('VOICE_FULL');
      // Membership/auth may change while an external create/delete request is in flight.
      const fresh = await this.store.realtimeDirectory(player);
      const auth = await this.store.playerByToken(hash, this.now());
      if (!auth || fresh.party?.id !== directory.party.id || !fresh.party.members.includes(player)) throw new Error('VOICE_NO_PARTY');
      if (!room.ready) {
        await this.media.createRoom({ name: room.name, maxParticipants: this.config.maxParticipants, emptyTimeout: 30, departureTimeout: 10 });
        room.ready = true;
        const latest = await this.store.realtimeDirectory(player);
        if (latest.party?.id !== room.party || !latest.party.members.includes(player) ||
          !await this.store.playerByToken(hash, this.now())) throw new Error('VOICE_NO_PARTY');
      }
      const lease: Lease = room.leases.get(player) ?? { id: randomUUID(), request, player, tokenHash: hash, expires: 0 };
      lease.expires = this.now() + VOICE_LEASE_MS;
      room.leases.set(player, lease);
      const token = new AccessToken(this.config.apiKey, this.config.apiSecret, { identity: player, ttl: 60, name: player.slice(0, 8) });
      token.addGrant({ roomJoin: true, room: room.name, canPublish: true, canPublishSources: [TrackSource.MICROPHONE],
        canSubscribe: true, canPublishData: false, canUpdateOwnMetadata: false });
      return { ...this.view(room, player), url: this.config.url, token: await token.toJwt(), lease_id: lease.id,
        lease_ms: VOICE_LEASE_MS, heartbeat_ms: 5000 };
    });
  }
  heartbeat(player: string, hash: string, id: string) {
    return this.serial(async () => {
      const directory = await this.store.realtimeDirectory(player);
      const room = directory.party && this.rooms.get(directory.party.id);
      if (!room) throw new Error('VOICE_EXPIRED');
      await this.reconcile(room);
      const lease = room.leases.get(player);
      if (!lease || lease.id !== id || lease.tokenHash !== hash) throw new Error('VOICE_EXPIRED');
      lease.expires = this.now() + VOICE_LEASE_MS;
      return { ...this.view(room, player), lease_id: lease.id, lease_ms: VOICE_LEASE_MS };
    });
  }
  leave(player: string, id: string) {
    return this.serial(async () => {
      for (const room of this.rooms.values()) if (room.leases.get(player)?.id === id) await this.rotate(room, [player]);
      return { ok: true };
    });
  }
  membershipChanged(players: string[]) {
    return this.serial(async () => {
      for (const room of this.rooms.values()) if (players.some(p => room.leases.has(p))) await this.reconcile(room);
    });
  }
  revoke(player: string, hash?: string) {
    return this.serial(async () => {
      for (const room of this.rooms.values()) {
        const lease = room.leases.get(player);
        if (lease && (!hash || hash === lease.tokenHash)) await this.rotate(room, [player]);
      }
    });
  }
  sweep() { return this.serial(async () => {
    for (const room of this.rooms.values()) {
      // A failed SFU operation in one room must not starve all other leases.
      try {
        await this.reconcile(room);
        if (!room.leases.size) {
          if (room.ready) { room.retiring.add(room.name); await this.retire(room); }
          this.rooms.delete(room.party);
        }
      } catch { /* New grants remain blocked until retirement succeeds. */ }
    }
  }); }
  private view(room: VoiceRoom, player: string) {
    return { available: true, party_id: room.party, room: room.name, capacity: this.config.maxParticipants,
      participants: [...room.leases.keys()], joined: room.leases.has(player) };
  }
  async close() {
    this.closed = true;
    await this.serial(async () => {
      for (const room of this.rooms.values()) {
        try { await this.rotate(room, [...room.leases.keys()]); } catch { /* next owner reclaims this namespace on join */ }
      }
      this.rooms.clear();
    });
  }
}
