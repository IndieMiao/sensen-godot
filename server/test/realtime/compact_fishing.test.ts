import { describe, expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { buildApp } from '../../src/http/app.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { DEFAULT_CONTENT_DIR } from '../../src/domain/content.js';
import { onlineGateways } from '../../src/realtime/gateway.js';
import { Client, content, cv, sets, blueprintDir } from './helpers.js';
import { CENTER, fixtureGeography, rectangle } from '../geography/fixtures.js';

describe('retired farm ponds across host generations', () => {
  it.each([[2, 1], [1, 2]])('rejects farm fishing for a generation %i host and generation %i visitor without altering holdings', async (hostGeneration, visitorGeneration) => {
    let now = Date.now();
    const store = new MemoryStore({ content, contentVersion: cv, plot: sets, timezone: 'Asia/Shanghai', now: () => now });
    const app = await buildApp({ guestWrites: true, store, content, contentVersion: cv, blueprintDir,
      regionsFile: path.join(DEFAULT_CONTENT_DIR, 'regions.json'), pepper: 'mixed-pond-test', now: () => now,
      geographyProvider: async () => fixtureGeography([{ id: 'fixture/dry-land', kind: 'land', surface: 'soil', polygon: rectangle(-1, -1, 66, 66) }]) });
    const address = await app.listen({ host: '127.0.0.1', port: 0 }), clients: Client[] = [];
    const create = async (generation: number) => {
      const auth = (await app.inject({ method: 'POST', url: '/v1/auth/anonymous', payload: { install_key: randomUUID().replaceAll('-', '') } })).json();
      const response = await app.inject({ method: 'POST', url: '/v1/farms', headers: { authorization: 'Bearer ' + auth.token },
        payload: { generation_version: generation, region_id: 'shanghai', location: CENTER, idempotency_key: randomUUID() } });
      expect(response.statusCode).toBe(201);
      return { player: auth.player_id as string, token: auth.token as string, farm: response.json() };
    };
    try {
      const accounts = [await create(hostGeneration), await create(visitorGeneration)];
      const command = async (index: number, type: string, payload: object) => {
        const account = accounts[index], farm = (await store.farmByOwner(account.player))!;
        const response = await fetch(address + '/v1/farms/me/commands', { method: 'POST', headers: {
          authorization: 'Bearer ' + account.token, 'content-type': 'application/json' },
          body: JSON.stringify({ type, payload, base_version: farm.version, idempotency_key: randomUUID() }) });
        return { status: response.status, body: await response.json() as any };
      };
      expect((await command(0, 'set_visit_access', { access: 'anyone' })).status).toBe(200);
      for (const account of accounts) {
        const client = new Client(address.replace('http:', 'ws:') + '/v1/online'); clients.push(client);
        await client.connect(account.token); await client.join('farm', { farm_id: accounts[0].farm.farm_id });
      }
      const gateway = onlineGateways.get(app)!, room = gateway.rooms.get(clients[0].joined.room)!;
      expect(room.farmFishingSite).toBeUndefined();
      expect(room.navigation.cell).toBe(hostGeneration === 2 ? .8 : .75);
      for (const [index, account] of accounts.entries()) {
        const before = structuredClone((await store.farmByOwner(account.player))!);
        expect(before.farm_terrain!.plot.regions.some(r => r.id === 'pond' && r.kind === 'water')).toBe(false);
        const member = room.members.get(account.player)!;
        member.x = 9.375; member.z = -27.375; member.target = [member.x, member.z];
        expect(gateway.fishingPresence(account.player)!.farm_site).toBeUndefined();
        const cast = await command(index, 'cast_fishing', { sequence: 0, site_id: 'farm_pond', target: [9,-29], farm_site: content.fishing.sites.farm_pond });
        expect(cast.status).toBe(422); expect(cast.body.code).toBe('FISHING_LOCATION');
        expect((await store.farmByOwner(account.player))!.state).toEqual(before.state);
      }
    } finally { clients.forEach(client => client.close()); await app.close(); }
  });
});
