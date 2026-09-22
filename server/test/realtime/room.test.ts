import { describe, expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';
import { Room, type Member, type Transport } from '../../src/realtime/room.js';
import { initialExpedition, mineNavigation, move, segment } from '../../src/realtime/model.js';
import { memory, seed, content } from './helpers.js';

function wire() {
  const messages: any[] = [];
  const result: Transport = { send: data => { if (typeof data === 'string') messages.push(JSON.parse(data)); }, buffered: () => 0, close: () => {} };
  return { result, messages };
}
const nav = { cell: .5, rows: ['1111111111', '1111111111', '1111111111'], spawn: [.75, -.75] as [number, number] };
function position(m: Member, x: number, z: number, floor = 3) { m.x = x; m.z = z; m.target = [x, z]; m.floor = floor; }
function act(room: Room, m: Member, action: string, seq: number, node = '') { room.input(m, { t: 'act', seq, epoch: m.epoch, action, node }); }

describe('authoritative room simulation', () => {
  it('has exactly 300 seats and does not let the 301st displace anyone', async () => {
    const store = memory(), room = new Room('street:test', 'street', nav, store, content);
    const farm = (await seed(store)).farm;
    for (let i = 0; i < 300; i++) await room.join({ ...farm, owner_id: randomUUID() }, wire().result);
    await expect(room.join({ ...farm, owner_id: randomUUID() }, wire().result)).rejects.toThrow('ROOM_FULL');
    expect(room.members.size).toBe(300);
    await room.tick();
    expect(room.failed).toBe(false);
  });
  it('moves at the equipped server speed and refuses old sequences, epochs and non-finite coordinates', async () => {
    const store = memory(), farm = (await seed(store)).farm, room = new Room('farm:test', 'farm', nav, store, content);
    const m = await room.join(farm, wire().result);
    room.input(m, { t: 'input', epoch: 1, seq: 2, x: 100, z: -.75, yaw: 1 });
    const start = m.x;
    await room.tick();
    expect(m.x - start).toBeCloseTo(m.stats.speed * .05);
    room.input(m, { t: 'input', epoch: 1, seq: 1, x: 0, z: 0, yaw: 0 });
    expect(m.target[0]).toBe(100);
    room.input(m, { t: 'input', epoch: 0, seq: 3, x: 0, z: 0, yaw: 0 });
    expect(m.seq).toBe(2);
    expect(() => room.input(m, { t: 'input', epoch: 1, seq: 4, x: NaN, z: 0, yaw: 0 })).toThrow('SCHEMA');
    expect(() => room.input(m, { t: 'input', epoch: 1, seq: Number.MAX_SAFE_INTEGER, x: 0, z: 0, yaw: 0 })).toThrow('SCHEMA');
    for (let i = 0; i < 30; i++) await room.tick();
    const stopped = m.x;
    await room.tick();
    expect(m.x).toBe(stopped);
    room.input(m, { t: 'input', epoch: 1, seq: 5, x: m.x, z: m.z, yaw: 0, action: 'labour_till' });
    await room.tick();
    expect(m.action).toBe(11);
  });
  it('shares monster HP, checks range/cooldown, pays each contributor once and survives lost commit responses', async () => {
    const store = memory(), a = await seed(store), b = await seed(store);
    const room = new Room('mine:' + randomUUID(), 'mine', nav, store, content);
    const ma = await room.join(a.farm, wire().result), mb = await room.join(b.farm, wire().result);
    const monster = room.mine.floors['3'].monsters[0];
    monster.x = 4.75; monster.z = -3.75;
    position(ma, 4.75, -3.25); position(mb, 5.1, -3.25);
    ma.yaw = Math.PI; mb.yaw = Math.PI;
    ma.stats.damage = 20; mb.stats.damage = 20;
    const beforeA = (await store.farmByOwner(a.player))!.state.bag!.sequence;
    const beforeB = (await store.farmByOwner(b.player))!.state.bag!.sequence;
    const original = store.realtimeCommit.bind(store);
    let lost = false;
    store.realtimeCommit = async (...args) => {
      const result = await original(...args);
      if (!lost) { lost = true; throw new Error('simulated lost COMMIT response'); }
      return result;
    };
    act(room, ma, 'attack', 1); act(room, mb, 'attack', 1);
    await room.tick();
    expect(room.failed).toBe(false);
    expect(room.mine.floors['3'].monsters[0].hp).toBe(0);
    expect(room.mine.floors['3'].cleared).toBe(true);
    expect((await store.farmByOwner(a.player))!.state.bag!.sequence).toBe(beforeA + 1);
    expect((await store.farmByOwner(b.player))!.state.bag!.sequence).toBe(beforeB + 1);
    act(room, ma, 'attack', 1); await room.tick();
    expect((await store.farmByOwner(a.player))!.state.bag!.sequence).toBe(beforeA + 1);
    const restored = new Room(room.key, 'mine', nav, store, content);
    await restored.load();
    expect(restored.mine.floors['3'].monsters[0].hp).toBe(0);
    expect(restored.mine.floors['3'].rocks.every(r => !r.broken)).toBe(true);
  });
  it('requires the current main-hand mining duration and rewards concurrent diggers independently', async () => {
    const store = memory(), a = await seed(store), b = await seed(store);
    const room = new Room('mine:' + randomUUID(), 'mine', nav, store, content);
    const ma = await room.join(a.farm, wire().result), mb = await room.join(b.farm, wire().result);
    position(ma, 2, -1, 1); position(mb, 2.25, -1, 1);
    act(room, ma, 'dig', 1, 'rock_1'); act(room, mb, 'dig', 1, 'rock_1');
    for (let i = 0; i < 39; i++) await room.tick();
    expect(room.mine.floors['1'].rocks[0].broken).toBe(false);
    await room.tick();
    expect(room.mine.floors['1'].rocks[0].broken).toBe(true);
    for (const player of [a, b]) expect((await store.farmByOwner(player.player))!.state.bag!.slots.some(s => s.item_id === 'stone')).toBe(true);
  });
  it('validates stairs spatially and fences inputs from the previous floor', async () => {
    const store = memory(), a = await seed(store), events = wire();
    const room = new Room('mine:' + randomUUID(), 'mine', nav, store, content);
    const m = await room.join(a.farm, events.result);
    room.mine.floors['1'].cleared = true;
    act(room, m, 'down', 1); await room.tick();
    expect(m.floor).toBe(1);
    position(m, 8.25, -6, 1);
    act(room, m, 'down', 2); await room.tick();
    expect(m.floor).toBe(2); expect(m.epoch).toBe(2);
    room.input(m, { t: 'input', seq: 999, epoch: 1, x: 8.25, z: -6, yaw: 0 });
    expect(m.seq).toBe(-1);
  });
  it('resolves elite damage in the server, rescues one player and lets the other continue', async () => {
    const store = memory(), a = await seed(store), b = await seed(store), events = wire();
    const room = new Room('mine:' + randomUUID(), 'mine', nav, store, content);
    (await store.farmByOwner(a.player))!.state.character!.hp = 1;
    a.farm.state.character!.hp = 1;
    const ma = await room.join(a.farm, events.result), mb = await room.join(b.farm, wire().result);
    position(ma, 4.75, -4, 5); position(mb, 8, -.75, 5);
    ma.stats.hp = 1; ma.grace = -1;
    const monster = room.mine.floors['5'].monsters[0];
    monster.x = 4.75; monster.z = -4.2; monster.phase = 'dash'; monster.timer = .4; monster.direction = [0, 1];
    await room.tick();
    expect(room.members.has(a.player)).toBe(false);
    expect(room.members.has(b.player)).toBe(true);
    expect(events.messages.some(m => m.t === 'rescued')).toBe(true);
  });
  it('does not cross rocks and preserves axis sliding', () => {
    const nav = mineNavigation(initialExpedition(content).floors['1']);
    expect(segment(nav, [2, -1], [2, -3])).toBe(false);
    const moved = move(nav, [2, -1], [2, -3], 8);
    expect(moved[1]).toBeGreaterThan(-2);
    const corner = { cell: 1, rows: ['10', '01'], spawn: [.5, -.5] as [number, number] };
    expect(segment(corner, [.5, -.5], [1.5, -1.5])).toBe(false);
  });

  it('waits for a predicted mining arrival without accepting a remote rock claim', async () => {
    const store = memory(), a = await seed(store), events = wire();
    const room = new Room('mine:' + randomUUID(), 'mine', nav, store, content);
    const m = await room.join(a.farm, events.result);
    position(m, 2, -.5, 1);
    room.input(m, { t: 'input', seq: 1, epoch: 1, x: 2, z: -1.1, yaw: 0 });
    act(room, m, 'dig', 1, 'rock_1');
    for (let i = 0; i < 48; i++) await room.tick();
    expect(room.mine.floors['1'].rocks[0].broken).toBe(true);
    act(room, m, 'dig', 2, 'rock_6'); await room.tick();
    expect(events.messages.find(e => e.t === 'result' && e.seq === 2)?.code).toBe('OUT_OF_RANGE');
  });

  it('keeps moving and broadcasting while a durable combat transaction is pending', async () => {
    const store = memory(), a = await seed(store), room = new Room('mine:' + randomUUID(), 'mine', nav, store, content);
    const m = await room.join(a.farm, wire().result);
    position(m, 4.75, -3.25, 3); m.yaw = Math.PI;
    Object.assign(room.mine.floors['3'].monsters[0], { x: 4.75, z: -3.75 });
    const original = store.realtimeCommit.bind(store);
    let release: (() => void) | undefined;
    store.realtimeCommit = async (...args) => { await new Promise<void>(resolve => release = resolve); return original(...args); };
    act(room, m, 'attack', 1);
    const settlement = room.tick();
    while (!release) await new Promise(resolve => setTimeout(resolve, 1));
    const oldX = m.x, frames = room.metrics.snapshots;
    room.input(m, { t: 'input', seq: 1, epoch: 1, x: 6, z: -3.25, yaw: 1.5 });
    await room.tick(); await room.tick();
    expect(m.x).toBeGreaterThan(oldX);
    expect(room.metrics.snapshots).toBeGreaterThan(frames);
    release(); await settlement;
    expect(room.failed).toBe(false);
  });
});
