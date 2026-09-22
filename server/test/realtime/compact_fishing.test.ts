import { describe, expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { buildApp } from '../../src/http/app.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { DEFAULT_CONTENT_DIR } from '../../src/domain/content.js';
import { initialFishingSimulation, stepFishing } from '../../src/domain/fishing.js';
import { farmPondSite } from '../../src/geography/farm_terrain.js';
import { onlineGateways } from '../../src/realtime/gateway.js';
import { Client, content, cv, sets, blueprintDir } from './helpers.js';
import { CENTER, fixtureGeography, rectangle } from '../geography/fixtures.js';

describe('mixed-generation host pond authority', () => {
  it.each([[2, 1], [1, 2]])('uses generation %i host geometry for a generation %i visitor, with independent caught-fish ownership', async (hostGeneration, visitorGeneration) => {
    let now = Date.now();
    const store = new MemoryStore({ content, contentVersion: cv, plot: sets, timezone: 'Asia/Shanghai', now: () => now });
    const app = await buildApp({ store, content, contentVersion: cv, blueprintDir,
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
      const hostSite = farmPondSite(accounts[0].farm.farm_terrain, content.fishing.sites.farm_pond);
      const visitorHomeSite = farmPondSite(accounts[1].farm.farm_terrain, content.fishing.sites.farm_pond);
      expect(room.farmFishingSite).toEqual(hostSite); expect(hostSite.center).not.toEqual(visitorHomeSite.center);
      expect(room.navigation.cell).toBe(hostGeneration === 2 ? .8 : .75);
      for (const [index, account] of accounts.entries()) {
        const member = room.members.get(account.player)!;
        member.x = hostSite.stand[0] + index * .2; member.z = hostSite.stand[1]; member.target = [member.x, member.z];
        const presence = gateway.fishingPresence(account.player)!;
        expect(presence.home).toBe(accounts[0].farm.farm_id); expect(presence.farm_site).toEqual(hostSite);
      }
      // A visitor cannot replace host geometry by putting their own pond into command JSON.
      const forged = await command(1, 'cast_fishing', { sequence: 0, site_id: 'farm_pond', target: visitorHomeSite.center, farm_site: visitorHomeSite });
      expect(forged.status).toBe(422); expect(forged.body.code).toBe('FISHING_LOCATION');
      const casts = await Promise.all([0, 1].map(i => command(i, 'cast_fishing', { sequence: 0, site_id: 'farm_pond', target: hostSite.center })));
      expect(casts.map(cast => cast.status)).toEqual([200, 200]);
      for (const cast of casts) expect(cast.body.state.fishing.active.home).toBe(accounts[0].farm.farm_id);
      const visitorMember = room.members.get(accounts[1].player)!;
      const visible = await clients[0].next('fishing', frame => frame.members.some((member: any) => member.id === visitorMember.id));
      expect(visible.members.find((member: any) => member.id === visitorMember.id).target).toEqual(hostSite.center);
      expect(JSON.stringify(visible)).not.toMatch(/seed|nonce|wallet|bag|hook_until/);
      const hookTimes: number[] = [];
      for (const index of [0, 1].sort((a, b) => casts[a].body.state.fishing.active.bite_at - casts[b].body.state.fishing.active.bite_at)) {
        now = Math.max(now, casts[index].body.state.fishing.active.bite_at);
        const hook = await command(index, 'hook_fishing', { sequence: 1 }); expect(hook.status).toBe(200);
        hookTimes[index] = hook.body.state.fishing.active.hooked_at;
      }
      const traces = casts.map(cast => {
        const active = cast.body.state.fishing.active, simulation = initialFishingSimulation(active.seed, content.fishing); let inputs = '';
        while (simulation.outcome === 'playing') {
          const held = simulation.fish > simulation.bar + simulation.velocity * .15; inputs += held ? '1' : '0';
          stepFishing(simulation, held, content.fishing.tiers[String(content.fishing.fish[active.fish_id].tier)], content.fishing);
        }
        expect(simulation.outcome).toBe('caught'); return inputs;
      });
      now = Math.max(...traces.map((trace, index) => hookTimes[index] + trace.length * content.fishing.step_ms));
      const hostCatch = await command(0, 'finish_fishing', { sequence: 1, inputs: traces[0] });
      expect(hostCatch.status).toBe(200); expect(hostCatch.body.state.fishing.last.outcome).toBe('caught');
      const hostSaved = structuredClone((await store.farmByOwner(accounts[0].player))!);
      const visitorCatch = await command(1, 'finish_fishing', { sequence: 1, inputs: traces[1] });
      expect(visitorCatch.status).toBe(200); expect(visitorCatch.body.state.fishing.last.outcome).toBe('caught');
      expect(await store.farmByOwner(accounts[0].player)).toEqual(hostSaved);
      for (const [index, caught] of [hostCatch, visitorCatch].entries()) {
        expect(caught.body.state.bag.slots.some((stack: any) => stack.item_id === casts[index].body.state.fishing.active.fish_id && stack.quantity === 1)).toBe(true);
        expect(caught.body.farm_terrain.source.generator_version).toBe(index === 0 ? hostGeneration : visitorGeneration);
      }
    } finally { clients.forEach(client => client.close()); await app.close(); }
  });
});
