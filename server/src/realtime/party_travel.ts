import { createHmac, timingSafeEqual } from 'node:crypto';
import { readFileSync } from 'node:fs';
import type { AppDeps } from '../http/app.js';
import type { FarmRow } from '../http/dto.js';
import { visitorSnapshot } from '../http/dto.js';
import { avatarRef } from '../http/avatar_ref.js';
import { derive } from '../domain/derive.js';
import { effectiveNow } from '../domain/qa.js';

export interface SpacePresence {
  kind: 'street' | 'farm' | 'mine' | 'pond'; key: string; home: string; channel: number; floor: number;
  region: string; layout: string; revision: number; nonce: string; epoch: number;
  terrain?: string;
}
export interface TravelGrant {
  purpose: 'party-travel'; player: string; target: string; party: string;
  mode: 'leader' | 'follow' | 'farm'; destination: SpacePresence; expires: number;
}
const fail = (code: string): never => { throw new Error(code); };

/** Discovery grants no authority. A signed destination is checked again at admission. */
export class PartyTravel {
  private zones: Map<string, string>;
  private zone: (id: string) => string;
  constructor(private deps: AppDeps, private presence: (player: string) => SpacePresence | null,
    private hasSeat: (key: string, player: string) => boolean) {
    const regions = JSON.parse(readFileSync(deps.regionsFile, 'utf8')).regions as { id: string; timezone: string }[];
    this.zones = new Map(regions.map(r => [r.id, r.timezone]));
    // Global cities are resolved at runtime; curated regions stay in the static table above.
    this.zone = (id: string) => this.zones.get(id) ?? deps.cities?.timezone(id) ?? 'UTC';
  }

  async sameParty(player: string, target: string) {
    const entry = await this.deps.store.realtimeDirectory(player);
    if (!entry.party || !entry.party.members.includes(target)) fail('PARTY_CHANGED');
    return entry;
  }

  async canVisitFarm(player: string, farm: FarmRow): Promise<boolean> {
    if (farm.owner_id === player || farm.visit_access === 'anyone') return true;
    const [caller, owner] = await Promise.all([
      this.deps.store.realtimeDirectory(player), this.deps.store.realtimeDirectory(farm.owner_id),
    ]);
    return Boolean(caller.party && owner.party?.id === caller.party.id && owner.farm_access && caller.party.members.includes(farm.owner_id));
  }

  async canVisitStreet(player: string, farm: FarmRow): Promise<boolean> {
    return this.canVisitFarm(player, farm);
  }

  async status(player: string) {
    const entry = await this.deps.store.realtimeDirectory(player);
    const homes = await this.deps.store.realtimeHomes(entry.party?.members ?? []);
    const byPlayer = new Map(homes.map(h => [h.owner_id, h]));
    return { ...entry, travel_version: 1, roster: (entry.party?.members ?? []).map(id => {
      const home = byPlayer.get(id), scene = this.presence(id);
      // Connection nonce is an admission fence, not part of the player's public position summary.
      const visible = scene ? { kind: scene.kind, room: scene.key, region_id: scene.region,
        layout_patch_id: scene.layout, blueprint_revision: scene.revision, channel: scene.channel, floor: scene.floor } : null;
      return { player: id, leader: id === entry.party!.leader, online: Boolean(scene), scene: visible,
        can_visit_farm: Boolean(home && (id === player || home.visit_access === 'anyone' || home.party_farm_access === entry.party!.id)) };
    }) };
  }

  async prepare(player: string, target: string, mode: 'leader' | 'follow' | 'farm') {
    if (mode === 'leader') target = (await this.deps.store.realtimeDirectory(player)).party?.leader ?? fail('PARTY_NOT_FOUND');
    if (target === player) fail('ALREADY_THERE');
    const entry = await this.sameParty(player, target);
    let destination: SpacePresence;
    if (mode !== 'farm') {
      const current = this.presence(target);
      if (!current) fail('TARGET_OFFLINE');
      destination = { ...current! };
      if (destination.kind === 'mine' && entry.party!.leader !== target) fail('FOLLOW_LEADER_MINE');
    } else {
      const farm = await this.deps.store.farmByOwner(target);
      if (!farm) fail('NOT_FOUND');
      const current = this.presence(target);
      const channel = current?.kind === 'farm' && current.home === farm!.id ? current.channel : 1;
      destination = { kind: 'farm', key: 'farm:' + farm!.id + ':' + channel, home: farm!.id, channel, floor: 0,
        region: farm!.region_id, layout: farm!.layout_patch_id, revision: farm!.blueprint_revision,
        terrain: farm!.farm_terrain?.plot.checksum ?? '', nonce: '', epoch: 0 };
    }
    const grant: TravelGrant = { purpose: 'party-travel', player, target, party: entry.party!.id, mode, destination, expires: Date.now() + 60000 };
    await this.validate(grant, player);
    let snapshot: ReturnType<typeof visitorSnapshot> | Record<string, unknown> | undefined;
    if (destination.kind !== 'mine' && destination.kind !== 'pond') {
      const farm = await this.deps.store.farmById(destination.home);
      if (!farm) fail('NOT_FOUND');
      const now = Math.max(effectiveNow(farm!.state.qa, this.deps.now()), farm!.state.clock.last_effective_now);
      const view = visitorSnapshot(farm!, derive(farm!.state, now, this.zone(farm!.region_id), this.deps.content), farm!.version, now, undefined, avatarRef(farm!));
      snapshot = destination.kind === 'farm' ? view : {
        farm_id: view.farm_id, avatar_ref: view.avatar_ref, layout_patch_id: view.layout_patch_id,
        blueprint_revision: view.blueprint_revision, nursery: view.nursery, street_snapshot: view.street_snapshot,
      };
    }
    const payload = Buffer.from(JSON.stringify(grant)).toString('base64url');
    const ticket = payload + '.' + this.sign(payload).toString('hex');
    return { travel_version: 1, kind: destination.kind, room: destination.key, floor: destination.floor,
      farm_id: destination.home, channel: destination.channel, layout_patch_id: destination.layout,
      blueprint_revision: destination.revision, expires_at: grant.expires, ticket,
      ...(destination.kind === 'pond' ? { pond_id: destination.home, catalog_revision: destination.terrain } : {}),
      replaces_instance: destination.kind === 'mine' && Boolean(entry.instance && 'mine:' + entry.instance !== destination.key),
      ...(snapshot ? { snapshot } : {}) };
  }

  read(ticket: unknown, player: string): TravelGrant {
    if (typeof ticket !== 'string' || ticket.length > 2048) fail('TRAVEL_EXPIRED');
    const [payload, signature, extra] = (ticket as string).split('.');
    if (!payload || extra || !/^[a-f0-9]{64}$/.test(signature ?? '') || !timingSafeEqual(this.sign(payload), Buffer.from(signature, 'hex'))) fail('TRAVEL_EXPIRED');
    let grant: TravelGrant;
    try { grant = JSON.parse(Buffer.from(payload, 'base64url').toString()); }
    catch { return fail('TRAVEL_EXPIRED'); }
    if (grant.purpose !== 'party-travel' || grant.player !== player || !Number.isFinite(grant.expires) || grant.expires < Date.now()) fail('TRAVEL_EXPIRED');
    return grant;
  }

  async validate(grant: TravelGrant, player: string): Promise<void> {
    if (grant.player !== player || grant.expires < Date.now()) fail('TRAVEL_EXPIRED');
    const entry = await this.sameParty(player, grant.target);
    if (entry.party!.id !== grant.party) fail('PARTY_CHANGED');
    if (grant.mode === 'leader' && entry.party!.leader !== grant.target) fail('DESTINATION_CHANGED');
    const destination = grant.destination;
    if (grant.mode !== 'farm') {
      const current = this.presence(grant.target);
      if (!current) fail('TARGET_OFFLINE');
      if (current!.key !== destination.key || current!.home !== destination.home || current!.nonce !== destination.nonce ||
        current!.epoch !== destination.epoch || current!.floor !== destination.floor) fail('DESTINATION_CHANGED');
    }
    if (destination.kind === 'mine') {
      if (entry.party!.leader !== grant.target) fail('FOLLOW_LEADER_MINE');
    } else if (destination.kind !== 'pond') {
      const farm = await this.deps.store.farmById(destination.home);
      if (!farm) fail('NOT_FOUND');
      if (farm!.layout_patch_id !== destination.layout || farm!.blueprint_revision !== destination.revision || farm!.region_id !== destination.region) fail('DESTINATION_CHANGED');
      if ((farm!.farm_terrain?.plot.checksum ?? '') !== (destination.terrain ?? '')) fail('DESTINATION_CHANGED');
      const permitted = destination.kind === 'farm' ? await this.canVisitFarm(player, farm!) : await this.canVisitStreet(player, farm!);
      if (!permitted) fail('PARTY_ACCESS_REQUIRED');
    }
    if (!this.hasSeat(destination.key, player)) fail('ROOM_FULL');
    if (grant.mode !== 'farm') {
      const current = this.presence(grant.target);
      if (!current || current.key !== destination.key || current.nonce !== destination.nonce || current.epoch !== destination.epoch) fail('DESTINATION_CHANGED');
    }
  }
  private sign(payload: string) { return createHmac('sha256', this.deps.pepper).update('party-travel:' + payload).digest(); }
}
