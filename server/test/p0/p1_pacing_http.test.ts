/** SGODOT-354: wire fields, replay and v5 persistence across a real localhost HTTP restart. */
import Fastify from 'fastify';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { freshState } from '../../src/p0/state.js';
import { P0Store } from '../../src/p0/store.js';
const c = loadP0Content(), T = Date.UTC(2026, 9, 28, 2), player = 'pacing-http-354';

describe('q(245)–q(247) HTTP and restart', () => {
  it('runs the farm loop, persists a growing fast plot and pays each harvest/upgrade once', async () => {
    const dir = mkdtempSync(path.join(tmpdir(), 'sulie354-')), file = path.join(dir, 'state.json');
    let now = T, store = new P0Store(c, file), app = Fastify(), address = '';
    const headers = { 'x-p0-player': player, 'content-type': 'application/json' };
    const start = async () => {
      registerP0Routes(app, { content: c, store, now: () => now, dev: false });
      return app.listen({ host: '127.0.0.1', port: 0 });
    };
    const get = async () => (await fetch(address + '/v1/p0/state?space=home', { headers })).json();
    const send = async (cmd: Record<string, unknown>) => (await fetch(address + '/v1/p0/commands', {
      method: 'POST', headers, body: JSON.stringify({ space: 'home', ...cmd }),
    })).json();
    try {
      const initial = freshState(c, player, T, 7);
      initial.created_at = T - 30 * 86400000; initial.skills.farming = 50;
      initial.storage = { wood: 6, stone: 4, fiber: 3 }; store.put(initial);
      address = await start();
      let v = (await get()).state;
      expect(v.fast_crops).toHaveLength(5);
      expect(v.shops.homestead.buy.find((x: { id: string }) => x.id === 'seed_cress')).toMatchObject({ price: 1, gate: 1, daily: null });
      const buy = await send({ type: 'buy', shop: 'stall', item: 'seed_cress', qty: 2, expect_seq: v.seq });
      expect(buy.ok).toBe(true);
      const sow = await send({ type: 'sow', seed: 'seed_cress', plot: 0, expect_seq: buy.state.seq });
      expect(sow.ok).toBe(true);
      const water = await send({ type: 'water', plot: 0, expect_seq: sow.state.seq });
      expect(water.state.plots[0]).toMatchObject({ state: 'growing', crop: 'crop_cress', ready_in: 10000 });
      const raw = store.peek(player)!;
      const beforeRestart = { seq: raw.seq, coins: raw.coins, version: raw.v, plot: structuredClone(raw.plots[0]) };
      await app.close(); store = new P0Store(c, file); app = Fastify(); now += 4000; address = await start();
      expect(store.migrated).toBe(0);
      const loaded = store.peek(player)!;
      expect({ seq: loaded.seq, coins: loaded.coins, version: loaded.v, plot: loaded.plots[0] }).toEqual(beforeRestart);
      v = (await get()).state; expect(v.plots[0].ready_in).toBe(6000);
      now = T + 10000;
      const command = { type: 'harvest', plot: 0, expect_seq: v.seq };
      const harvest = await send(command); expect(harvest.ok).toBe(true);
      expect(harvest.state.items.crop_cress).toMatchObject({ name: 'Cress', kind: 'crop', sell: 1, cook: false });
      const retry = await send(command); expect(retry).toMatchObject({ ok: false, code: 'stale_state' });
      expect(retry.state.bag.slots).toEqual(harvest.state.bag.slots);
      const sold = await send({ type: 'sell', shop: 'stall', item: 'crop_cress', qty: 1, expect_seq: harvest.state.seq });
      expect(sold.state.coins).toBe(initial.coins - 1);
      const beforeEnergy = sold.state.energy.value, upgradeCmd = { type: 'homestead_upgrade', expect_seq: sold.state.seq };
      const up = await send(upgradeCmd); expect(up.ok).toBe(true);
      const gain = Math.min(40, 210 - beforeEnergy);
      expect(up.events.find((e: { kind: string }) => e.kind === 'homestead')).toMatchObject({ level: 2, energy: gain });
      expect(up.state.energy.value).toBe(beforeEnergy + gain);
      const again = await send(upgradeCmd); expect(again).toMatchObject({ ok: false, code: 'stale_state' });
      expect(again.state.energy).toEqual(up.state.energy); expect(again.state.coins).toBe(up.state.coins);
      expect(store.peek(player)!.v).toBe(6);
    } finally {
      await app.close(); rmSync(dir, { recursive: true, force: true });
    }
  });
});
