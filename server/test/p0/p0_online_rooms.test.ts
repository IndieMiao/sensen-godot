import { existsSync, readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { MAX_ROOMS, OutpostRooms, REJOIN_MS, SEAT_REACH_M, SIT_SETTLE_MS, SPAWN_CANDIDATES_MAX, SPAWN_FREE_M, type OutpostSpec } from '../../src/p0/online/rooms.js';

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
    clock.t += SIT_SETTLE_MS + 100;   // settled on it (SGODOT-478)
    r.move('a', 3, -1, 0, 'run');
    expect(r.occupant('a')!.seat).toBe('');
    expect(r.sit('b', 'seat_table1_1')).toBe('ok');
    r.leave('b');
    expect(r.sit('a', 'seat_table1_1')).toBe('ok');
  });

  // SGODOT-478 (the user 11-11: sitting did not show in the church, nor anywhere): every sit stood up one input later,
  // the glide onto the seat (0.3 s, a pew's 1.9 m) reported as walking away. A sit puts the player on its spot at once
  // (within SEAT_REACH_M) and the inputs of the next SIT_SETTLE_MS leave it there.
  it('a sit puts the player on the seat at once, and the glide onto it does not stand them up', () => {
    const { r, clock } = rooms();
    r.join('a', TEA.id, [1, -1]);
    expect(r.sitAt('a', 'seat_table1_1', [2.9, -1])).toBe('ok');   // a pew's 1.9 m: past walking speed at dt 0
    expect(r.occupant('a')).toMatchObject({ x: 2.9, z: -1, seat: 'seat_table1_1', action: 'sit' });
    for (const x of [1.2, 1.6, 2.1, 2.6, 2.9]) {   // the glide, a frame every 0.1 s from the aisle end
      clock.t += 100;
      r.move('a', x, -1, 0.5, 'idle');
      expect(r.occupant('a')).toMatchObject({ x: 2.9, seat: 'seat_table1_1', action: 'sit', yaw: 0.5 });
    }
    clock.t += SIT_SETTLE_MS;
    r.move('a', 2.9, -1, 0.5, 'idle');   // settled where it sat
    expect(r.occupant('a')!.seat).toBe('seat_table1_1');
    clock.t += 100;
    r.move('a', 3.5, -1, 0.5, 'walk');   // then walking off stands up, as ever
    expect(r.occupant('a')).toMatchObject({ seat: '', action: 'walk' });
  });

  it('a seat further than SEAT_REACH_M is refused and nobody moves; one player per seat as before', () => {
    const { r } = rooms();
    r.join('a', TEA.id, [1, -1]);
    r.join('b', TEA.id, [1, -2]);
    expect(r.sitAt('a', 'seat_table1_1', [1 + SEAT_REACH_M + 0.5, -1])).toBe('TOO_FAR');
    expect(r.occupant('a')).toMatchObject({ x: 1, z: -1, seat: '' });
    expect(r.sitAt('a', 'seat_table1_1', [1 + SEAT_REACH_M - 0.5, -1])).toBe('ok');
    expect(r.sitAt('b', 'seat_table1_1', [1 + SEAT_REACH_M - 0.5, -1])).toBe('SEAT_TAKEN');
    expect(r.sitAt('b', 'seat_nowhere', [2, -2])).toBe('NO_SEAT');
    expect(r.occupant('b')).toMatchObject({ x: 1, z: -2, seat: '' });
    expect(r.sitAt('b', 'seat_table1_2', [99, -2])).toBe('TOO_FAR');   // clamped to the wall (10, -2) first: still 9 m
    r.stand('a');
    expect(r.occupant('a')!.seat).toBe('');
    r.move('a', 3, -1, 0, 'walk');   // standing up ends the settle at once: its inputs are its own
    expect(r.occupant('a')!.x).not.toBeCloseTo(1 + SEAT_REACH_M - 0.5);
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

// The fixture is the client's (tests/fixtures), in the repo but not in the server image (server/deploy/p0/Dockerfile copies
// server/ and the content tables, never tests/): skipped where the client's tests are not there at all (蒙恬, each
// rehearsal's one known failure), failed in the repo when the fixture alone is gone — it is the only file in its folder,
// so the whole tests/ is what tells the image apart (哪吒 on #984).
const CLIENT_TESTS = new URL('../../../tests/', import.meta.url);
const FRAME_V1 = new URL('fixtures/p0/frame_v1.hex', CLIENT_TESTS);
describe('P0 snapshot frame v1 fixture (shared with tests/p0/test_p0_online.gd)', () => {
  it.skipIf(!existsSync(CLIENT_TESTS))('encodes exactly the bytes the Godot client test decodes', async () => {
    const { snapshotFrame } = await import('../../src/p0/online/frame.js');
    const m = (id: number, x: number, z: number, yaw: number, action: string, seq: number) =>
      ({ player: 'p' + id, outpost: 'o', layout: '', room: 1, id, x, z, yaw, action, seat: '', seq, at: 0 });
    const frame = snapshotFrame(42, 3, [m(1, 1.25, -2.5, 0.75, 'walk', 7), m(4, -1, 2, 3.0, 'sit', 9)]);
    expect(frame.toString('hex')).toBe(readFileSync(FRAME_V1, 'utf8').trim());
  });
});

describe('the tea house on its own kit (SGODOT-216)', () => {
  // 上官婉儿's tea house (#598): three tea tables of three and the window bench, a landing out to the exit. Positions
  // past it are clamped onto the room; every seat of the kit is one, none other.
  it('has the kit\'s twelve seats and walls out to the landing', async () => {
    const { loadOutposts } = await import('../../src/p0/online/outposts.js');
    const tea = loadOutposts().find(o => o.id === 'sh_tea_1')!;
    expect(tea.art).toBe('tea_house');
    expect(tea.seats).toEqual(['seat_table1_1', 'seat_table1_2', 'seat_table1_3', 'seat_table2_1', 'seat_table2_2', 'seat_table2_3',
      'seat_table3_1', 'seat_table3_2', 'seat_table3_3', 'seat_bench_1', 'seat_bench_2', 'seat_bench_3']);
    const clock = { t: 1_000_000 };
    const r = new OutpostRooms(loadOutposts(), () => clock.t);
    r.join('tea-client-001', 'sh_tea_1', [0.3, 4.6]);   // past the landing's end
    const [x0, x1, , z1] = tea.bounds;
    expect(r.occupant('tea-client-001')).toMatchObject({ x: 0.3, z: z1 });
    expect(z1).toBeGreaterThanOrEqual(3.8);             // the exit (0.3, 3.8) is inside
    clock.t += 1000;
    r.move('tea-client-001', -4, 3.5, 0, 'walk');
    expect(r.occupant('tea-client-001')!.x).toBeGreaterThanOrEqual(x0);
    expect(r.sit('tea-client-001', 'seat_bench_1')).toBe('ok');
    expect(r.occupant('tea-client-001')).toMatchObject({ seat: 'seat_bench_1' });
    expect(r.sit('tea-client-001', 'seat_table4_1')).toBe('NO_SEAT');
    expect(x1).toBeGreaterThan(0);
  });
});

/** q(311): a newer client sends its places in order (the spawn, then the rings round it) on its first join of a visit; the
 * server puts it on the first nobody in the room stands within SPAWN_FREE_M of. */
describe('P0 room places for newcomers (q(311), SGODOT-470)', () => {
  const SPAWN: [number, number] = [5, -5];
  const RING: [number, number][] = [SPAWN, [5.75, -5], [4.25, -5], [5.5, -4.35], [4.5, -4.35], [5.5, -5.65], [4.5, -5.65]];
  const at = (r: OutpostRooms, p: string) => { const o = r.occupant(p)!; return [o.x, o.z]; };

  it('one after another, each on the first free place: nobody on another', () => {
    const { r } = rooms();
    for (let i = 0; i < RING.length; i++) {
      r.join(`p${i}`, TEA.id, SPAWN, '', RING);
      expect(at(r, `p${i}`)).toEqual(RING[i]);
    }
    for (let i = 0; i < RING.length; i++) for (let j = 0; j < i; j++) {
      const [a, b] = [at(r, `p${i}`), at(r, `p${j}`)];
      expect(Math.hypot(a[0] - b[0], a[1] - b[1])).toBeGreaterThanOrEqual(SPAWN_FREE_M);
    }
  });

  it('a place someone stands near is taken by them, whoever they are; a place left is free again', () => {
    const { r, clock } = rooms();
    r.join('first', TEA.id, SPAWN, '', RING);
    clock.t += 1000;
    r.move('first', 5.6, -5, 0, 'walk');   // walked over to the right one's place (within 0.45 m of it)
    r.join('second', TEA.id, SPAWN, '', RING);
    expect(at(r, 'second')).toEqual(SPAWN);   // the spawn is free again
    r.join('third', TEA.id, SPAWN, '', RING);
    expect(at(r, 'third')).toEqual(RING[2]);   // the right is taken by 'first' standing near it: the left
    r.leave('second');
    r.join('fourth', TEA.id, SPAWN, '', RING);
    expect(at(r, 'fourth')).toEqual(SPAWN);
  });

  it('no place free: at the spawn as before; places outside the room are clamped into it', () => {
    const { r } = rooms();
    r.join('a', TEA.id, SPAWN, '', [SPAWN]);
    r.join('b', TEA.id, SPAWN, '', [SPAWN]);
    expect(at(r, 'b')).toEqual(SPAWN);
    r.join('c', TEA.id, SPAWN, '', [SPAWN, [99, -5]]);
    expect(at(r, 'c')).toEqual([10, -5]);   // TEA's box ends at x 10
  });

  it('only the first SPAWN_CANDIDATES_MAX places are read', () => {
    const { r } = rooms();
    const many: [number, number][] = Array.from({ length: SPAWN_CANDIDATES_MAX }, () => SPAWN);
    r.join('a', TEA.id, SPAWN);
    r.join('b', TEA.id, SPAWN, '', [...many, [1, -1]]);
    expect(at(r, 'b')).toEqual(SPAWN);   // the 14th, free, is not looked at
  });

  it('without places (an older client, a reconnect) the join stands where it says, as ever', () => {
    const { r } = rooms();
    r.join('a', TEA.id, SPAWN, '', RING);
    r.join('old', TEA.id, SPAWN);
    expect(at(r, 'old')).toEqual(SPAWN);
    r.join('empty', TEA.id, SPAWN, '', []);
    expect(at(r, 'empty')).toEqual(SPAWN);
  });

  it('places are per instance: Room 2 starts again at its spawn', () => {
    const { r } = rooms();
    fill(r, TEA.id, TEA.capacity);
    r.join('next', TEA.id, SPAWN, '', RING);
    expect(r.occupant('next')!.room).toBe(2);
    expect(at(r, 'next')).toEqual(SPAWN);
  });
});
