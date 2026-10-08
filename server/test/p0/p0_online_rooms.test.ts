import { describe, expect, it } from 'vitest';
import { MAX_ROOMS, OutpostRooms, REJOIN_MS, type OutpostSpec } from '../../src/p0/online/rooms.js';

const TEA: OutpostSpec = { id: 'outpost_tea_1', role: 'tea', capacity: 12, bounds: [0, 10, -10, 0], seats: ['seat_table1_1', 'seat_table1_2'] };
const MARKET: OutpostSpec = { id: 'outpost_market_1', role: 'market', capacity: 30, bounds: [0, 20, -20, 0], seats: [] };

function rooms(start = 1_000_000) {
  const clock = { t: start };
  return { r: new OutpostRooms([TEA, MARKET], () => clock.t), clock };
}
const fill = (r: OutpostRooms, outpost: string, n: number, prefix = 'p') =>
  Array.from({ length: n }, (_, i) => r.join(`${prefix}${i}`, outpost));

describe('P0 outpost rooms (SGODOT-227)', () => {
  it('fills Room 1 to capacity, then opens Room 2 (indoor 12, market 30)', () => {
    const { r } = rooms();
    expect(fill(r, TEA.id, 12).every(p => p.room === 1)).toBe(true);
    expect(r.join('late', TEA.id)).toEqual({ outpost: TEA.id, room: 2, capacity: 12, rejoined: false });
    expect(fill(r, MARKET.id, 30, 'm').every(p => p.room === 1)).toBe(true);
    expect(r.join('m30', MARKET.id).room).toBe(2);
    expect(r.presence()).toEqual({ [TEA.id]: { online: 13, rooms: 2 }, [MARKET.id]: { online: 31, rooms: 2 } });
    expect(r.total()).toBe(44);
  });

  it('a newcomer takes the lowest instance with a free place', () => {
    const { r } = rooms();
    fill(r, TEA.id, 13);
    r.leave('p3', false);
    expect(r.join('next', TEA.id).room).toBe(1);
  });

  it('a reconnect within the window returns to the same instance while it has room', () => {
    const { r, clock } = rooms();
    fill(r, TEA.id, 13);
    expect(r.occupant('p12')!.room).toBe(2);
    r.leave('p12');
    r.leave('p0', false);              // Room 1 now has a free place …
    clock.t += REJOIN_MS - 1;
    expect(r.join('p12', TEA.id)).toMatchObject({ room: 2, rejoined: true });   // … but p12 goes back to Room 2
    r.leave('p12');
    clock.t += REJOIN_MS + 1;
    expect(r.join('p12', TEA.id)).toMatchObject({ room: 1, rejoined: false });   // reservation expired
  });

  it('joining another outpost moves the player; leaving empties the instance', () => {
    const { r } = rooms();
    r.join('a', TEA.id);
    r.join('a', MARKET.id);
    expect(r.presence()[TEA.id]).toEqual({ online: 0, rooms: 0 });
    expect(r.occupant('a')).toMatchObject({ outpost: MARKET.id, room: 1 });
    r.leave('a');
    expect(r.presence()[MARKET.id]).toEqual({ online: 0, rooms: 0 });
  });

  it('rejects unknown outposts and caps the number of instances', () => {
    const { r } = rooms();
    expect(() => r.join('a', 'nowhere')).toThrow('UNKNOWN_OUTPOST');
    const tiny = new OutpostRooms([{ ...TEA, capacity: 1 }]);
    for (let i = 0; i < MAX_ROOMS; i++) tiny.join(`p${i}`, TEA.id);
    expect(() => tiny.join('one-more', TEA.id)).toThrow('SERVER_FULL');
  });

  it('clamps positions to the room and to walking speed', () => {
    const { r, clock } = rooms();
    r.join('a', TEA.id, [5, -5]);
    const jump = r.move('a', 50, 50, 0, 'run')!;   // clamped to the corner (10, 0), then to SLACK reach at dt 0
    expect(Math.hypot(jump.x - 5, jump.z + 5)).toBeCloseTo(0.5);
    expect(jump.x - 5).toBeCloseTo(jump.z + 5);
    clock.t += 1000;
    expect(r.move('a', 9, -5, 0, 'run')).toMatchObject({ x: 9, z: -5 });
    clock.t += 1000;
    expect(r.move('a', 99, -99, 0, 'run')).toMatchObject({ x: 10, z: -10 });
    expect(r.move('a', NaN, -5, 0, 'run')!.x).toBeGreaterThanOrEqual(0);
  });

  it('one player per seat; moving away stands up and frees it', () => {
    const { r, clock } = rooms();
    r.join('a', TEA.id, [1, -1]);
    r.join('b', TEA.id, [1, -1]);
    expect(r.sit('a', 'seat_table1_1')).toBe('ok');
    expect(r.sit('b', 'seat_table1_1')).toBe('SEAT_TAKEN');
    expect(r.sit('b', 'seat_nowhere')).toBe('NO_SEAT');
    expect(r.occupant('a')).toMatchObject({ seat: 'seat_table1_1', action: 'sit' });
    clock.t += 1000;
    r.move('a', 3, -1, 0, 'run');
    expect(r.occupant('a')!.seat).toBe('');
    expect(r.sit('b', 'seat_table1_1')).toBe('ok');
    r.leave('b');
    expect(r.sit('a', 'seat_table1_1')).toBe('ok');
  });

  it('member ids are small and reused within an instance', () => {
    const { r } = rooms();
    fill(r, TEA.id, 3);
    expect(['p0', 'p1', 'p2'].map(p => r.occupant(p)!.id)).toEqual([1, 2, 3]);
    r.leave('p1', false);
    r.join('q', TEA.id);
    expect(r.occupant('q')!.id).toBe(2);
    fill(r, TEA.id, 12, 'x');
    expect(r.occupant('x9')).toMatchObject({ room: 2, id: 1 });   // Room 1 full after x8
  });

  it('seats are per instance', () => {
    const { r } = rooms();
    fill(r, TEA.id, 12);
    r.join('room2', TEA.id);
    expect(r.sit('p0', 'seat_table1_1')).toBe('ok');
    expect(r.sit('room2', 'seat_table1_1')).toBe('ok');
  });
});

describe('P0 snapshot frame v1 fixture (shared with tests/p0/test_p0_online.gd)', () => {
  it('encodes exactly the bytes the Godot client test decodes', async () => {
    const { readFileSync } = await import('node:fs');
    const { snapshotFrame } = await import('../../src/p0/online/frame.js');
    const m = (id: number, x: number, z: number, yaw: number, action: string, seq: number) =>
      ({ player: 'p' + id, outpost: 'o', room: 1, id, x, z, yaw, action, seat: '', seq, at: 0 });
    const frame = snapshotFrame(42, 3, [m(1, 1.25, -2.5, 0.75, 'walk', 7), m(4, -1, 2, 3.0, 'sit', 9)]);
    expect(frame.toString('hex')).toBe(readFileSync(new URL('../../../tests/fixtures/p0/frame_v1.hex', import.meta.url), 'utf8').trim());
  });
});
