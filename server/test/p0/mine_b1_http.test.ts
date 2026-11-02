import Fastify from 'fastify';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { notePresence } from '../../src/p0/presence.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { freshState } from '../../src/p0/state.js';
import { P0Store } from '../../src/p0/store.js';
import { wildById, wildNear3 } from '../../src/p0/wild.js';

describe('355 E day-token HTTP and persisted mine state', () => {
  it('uses C travel settlement for mine commands and state reads, and preserves here when place is omitted', async () => {
    const c = loadP0Content(), player = 'mine-c-travel', now = Date.UTC(2026, 10, 2, 2);
    const s = freshState(c, player, now);
    s.created_at = now - 30 * 86400000;
    const mine = wildNear3(c, s).find(id => wildById(c, id)?.type === 'quarry')!;
    expect(mine).toBeDefined();
    const arrived = applyP0(c, s, { type: 'travel', to: mine }, now);
    if (!arrived.ok) throw new Error(arrived.code);
    arrived.state.travel.here = arrived.state.travel.home;
    const dir = mkdtempSync(path.join(tmpdir(), 'sulie-mine-c-')), store = new P0Store(c, path.join(dir, 'state.json'));
    const app = Fastify(), headers = { 'x-p0-player': player };
    store.put(arrived.state);
    registerP0Routes(app, { content: c, store, now: () => now, dev: false });
    try {
      await app.ready();
      const rejected = (await app.inject({ method: 'POST', url: '/v1/p0/commands', headers,
        payload: { type: 'mine_enter', mine, space: 'mine', place: mine } })).json();
      expect(rejected).toMatchObject({ ok: false, code: 'travel_required' });
      // C permits refreshes from an already-entered mine; restore here if an older read sent it home.
      const resumed = store.peek(player)!; resumed.presence.entered = mine; store.put(resumed);
      const enter = (await app.inject({ method: 'POST', url: '/v1/p0/commands', headers,
        payload: { type: 'mine_enter', mine, space: 'mine', place: mine } })).json();
      expect(enter).toMatchObject({ ok: true, state: { travel: { here: mine }, mine: { at: { mine, floor: 1 } } } });
      expect(store.peek(player)!.travel.here).toBe(mine);
      const stored = store.peek(player)!; stored.travel.here = stored.travel.home; store.put(stored);
      const read = (await app.inject({ method: 'GET', url: `/v1/p0/state?space=mine&place=${mine}`, headers })).json();
      expect(read).toMatchObject({ ok: true, state: { travel: { here: mine } } });
      expect(store.peek(player)!.travel.here).toBe(mine);
      const bare = (await app.inject({ method: 'GET', url: '/v1/p0/state?space=mine', headers })).json();
      expect(bare).toMatchObject({ ok: true, state: { travel: { here: mine }, mine: { at: { mine } } } });
    } finally { await app.close(); rmSync(dir, { recursive: true, force: true }); }
  });

  it('persists the home at the first guard kill and never rewrites it after moving home or killing that kind again', () => {
    const c = loadP0Content(), player = 'mine-first-home-test', mine = 'wd-dev-quarry';
    const dir = mkdtempSync(path.join(tmpdir(), 'sulie-mine-home-')), file = path.join(dir, 'state.json');
    let now = Date.UTC(2026, 10, 2, 2), s = freshState(c, player, now);
    s.created_at = now - 30 * 86400000;
    s.mine.records[mine] = { deepest: 20, guards: [], first_at: now };
    const home = s.travel.home;
    const send = (cmd: Record<string, unknown>) => {
      now += 1000;
      const r = applyP0(c, s, { space: 'mine', day: s.mine.day?.key, ...cmd } as P0Command, now);
      if (!r.ok) throw new Error(r.code);
      s = r.state;
    };
    const kill = (floor: number) => {
      send({ type: 'mine_enter', mine, floor });
      while (s.mine.day!.floors[`${mine}:${floor}`].mobs[0] > 0) send({ type: 'mine_attack', floor, targets: [0] });
    };
    try {
      kill(10);
      const kind = c.mine.types.quarry.floors['10'].guard!;
      const first = { at: now, mine, floor: 10, home };
      expect(s.guard_firsts[kind]).toEqual(first);
      const store = new P0Store(c, file); store.put(s);
      s = new P0Store(c, file).peek(player)!;
      expect(s.guard_firsts[kind]).toEqual(first);
      notePresence(c, s, 'map', now, null);
      s.travel.home = 'gn-1796236'; s.travel.here = s.travel.home;
      expect(s.travel.home).not.toBe(home);
      kill(20);
      expect(s.kills[kind]).toBe(2);
      expect(s.guard_firsts[kind]).toEqual(first);
      store.put(s);
      expect(new P0Store(c, file).peek(player)!.guard_firsts[kind]).toEqual(first);
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });
  it('refuses an old-day action, persists only the day reset, survives restart and exits without losing records', async () => {
    const c = loadP0Content(); c.profile.timezone = 'Asia/Shanghai';
    const dir = mkdtempSync(path.join(tmpdir(), 'sulie-mine-b1-')), file = path.join(dir, 'state.json');
    const player = 'mine-http-test', mine = 'wd-dev-quarry';
    let now = Date.UTC(2026, 10, 2, 2), store = new P0Store(c, file), app = Fastify();
    const s = freshState(c, player, now); s.created_at = now - 30 * 86400000;
    store.put(s);
    const headers = { 'x-p0-player': player };
    const start = async () => { registerP0Routes(app, { content: c, store, now: () => now, dev: false }); await app.ready(); };
    const send = async (payload: Record<string, unknown>) => (await app.inject({ method: 'POST', url: '/v1/p0/commands', headers, payload })).json();
    const read = async (space?: string) => (await app.inject({ method: 'GET', url: '/v1/p0/state' + (space ? `?space=${space}` : ''), headers })).json();
    try {
      await start();
      const entry = await send({ type: 'mine_enter', mine }); expect(entry.ok).toBe(true);
      const day = entry.state.mine.at.day;
      now += 1000;
      const hit = await send({ type: 'mine_attack', space: 'mine', floor: 1, day, targets: [0], hurt_by: 0, expect_seq: entry.state.seq });
      expect(hit.ok).toBe(true);
      const before = structuredClone(store.peek(player)!);
      now += 86400000;
      const viewed = await read();
      expect(viewed.state.mine.at).toMatchObject({ mine, floor: 1, hp: hit.state.mine.at.hp });
      expect(viewed.state.mine.at.day).not.toBe(day);
      expect(store.peek(player)!.mine).toEqual(before.mine); // lazy view remains a copy
      const refused = await send({ type: 'mine_rock', space: 'mine', floor: 1, rock: 0, day, expect_seq: before.seq });
      expect(refused).toMatchObject({ ok: false, code: 'new_day' });
      expect(refused.state.mine).toEqual(viewed.state.mine);
      expect(store.peek(player)!.seq).toBe(before.seq);
      expect(store.peek(player)!.mine.day!.picked).toEqual([]);
      expect(store.peek(player)!.mine.day!.floors[`${mine}:1`].broken).toEqual([]);
      expect(store.peek(player)!.mine.day!.floors[`${mine}:1`].paid).toBe(true);
      const persisted = structuredClone(store.peek(player)!.mine);
      await app.close(); store = new P0Store(c, file); app = Fastify(); await start();
      expect(store.peek(player)!.mine).toEqual(persisted);
      const moved = await send({ type: 'mine_rock', space: 'mine', floor: 1, rock: 0, day: refused.state.mine.at.day, expect_seq: before.seq });
      expect(moved.ok).toBe(true);
      expect(moved.events.filter((e: { kind: string }) => e.kind === 'energy')).toEqual([{ kind: 'energy', delta: -c.mine.rock_energy, reason: 'mine_rock' }]);
      expect(await send({ type: 'mine_rock', space: 'mine', floor: 1, rock: 0, day: refused.state.mine.at.day, expect_seq: before.seq })).toMatchObject({ ok: false, code: 'stale_state' });
      const exit = await read('map'); expect(exit.state.mine.at).toBeNull();
      expect(store.peek(player)!.mine.day!.at).toBeNull();
      expect(exit.state.mine.records[mine].deepest).toBe(1);
      const again = await send({ type: 'mine_enter', mine });
      expect(again.ok).toBe(true); expect(again.events.some((e: { kind: string }) => e.kind === 'energy')).toBe(false);
    } finally { await app.close(); rmSync(dir, { recursive: true, force: true }); }
  });
});
