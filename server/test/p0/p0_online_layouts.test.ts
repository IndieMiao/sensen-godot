/** SGODOT-218: the market plaza takes the fruit shop's place. A client that draws it names its layout on join and gets the
 * plaza's walls and seats in instances of its own; a client that names none (every one before 0.3.3) stays in the fruit
 * shop's, as before — neither sees the other through the other's walls, nor hears it. Once all have updated they meet. */
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { generatedOutpostSpec, loadOutposts } from '../../src/p0/online/outposts.js';
import { OutpostRooms } from '../../src/p0/online/rooms.js';
import { P0Voice } from '../../src/p0/online/voice.js';
import { cityPlaces, roomPlace } from '../../src/p0/world.js';

const c = loadP0Content();
const table = loadOutposts();
const TOKYO = 'gn-1850147';
const resolve = generatedOutpostSpec(table, id => roomPlace(c, id));
const rooms = () => new OutpostRooms(table, Date.now, (id, layout) => resolve(id, layout));
const OLD: [number, number, number, number] = [-3.05, 3.05, -2.8, 2.8];
const PLAZA: [number, number, number, number] = [-8, 8, -8, 8];

describe('the market plaza layout (SGODOT-218)', () => {
  it('p0_outposts.json: Mission Market Square is the plaza, the fruit shop kept for older clients', () => {
    const sq = table.find(o => o.id === 'sh_market_1')!;
    expect(sq).toMatchObject({ art: 'market_plaza', bounds: PLAZA, seats: ['seat_1', 'seat_2'] });
    expect(sq.before).toEqual({ art: 'fruit_shop', bounds: OLD, seats: [] });
    expect(table.filter(o => o.before).map(o => o.id)).toEqual(['sh_market_1']);   // the one room with two layouts
  });

  it('a client naming no layout is where it was: the fruit shop\'s walls, no seats, Room 1 as before', () => {
    const r = rooms();
    expect(r.join('old-client-0001', 'sh_market_1', [5, 5])).toEqual({ outpost: 'sh_market_1', room: 1, capacity: 30, rejoined: false });
    const o = r.occupant('old-client-0001')!;
    expect([o.layout, o.x, o.z]).toEqual(['', 3.05, 2.8]);   // clamped to the fruit shop
    expect(r.spec('sh_market_1')).toMatchObject({ bounds: OLD, seats: [] });
    expect(r.sit('old-client-0001', 'seat_1')).toBe('NO_SEAT');
    r.move('old-client-0001', 7, 7, 0, 'walk');
    expect([r.occupant('old-client-0001')!.x, r.occupant('old-client-0001')!.z]).toEqual([3.05, 2.8]);
  });

  it('a plaza client gets the plaza: ±8 m, its two benches, instances of its own', () => {
    const r = rooms();
    expect(r.join('new-client-0001', 'sh_market_1', [5, 5], 'market_plaza')).toEqual({ outpost: 'sh_market_1', room: 1, capacity: 30, rejoined: false });
    const o = r.occupant('new-client-0001')!;
    expect([o.layout, o.x, o.z]).toEqual(['market_plaza', 5, 5]);
    expect(r.spec('sh_market_1', 'market_plaza')).toMatchObject({ bounds: PLAZA, seats: ['seat_1', 'seat_2'] });
    expect(r.sit('new-client-0001', 'seat_1')).toBe('ok');
    r.join('new-client-0002', 'sh_market_1', [0, 0], 'market_plaza');
    expect(r.sit('new-client-0002', 'seat_1')).toBe('SEAT_TAKEN');
    expect(r.sit('new-client-0002', 'seat_2')).toBe('ok');
  });

  it('the two layouts never share an instance: each sees only its own, both counted on the map pin', () => {
    const r = rooms();
    r.join('old-client-0001', 'sh_market_1');
    r.join('new-client-0001', 'sh_market_1', [0, 0], 'market_plaza');
    r.join('old-client-0002', 'sh_market_1');
    r.join('new-client-0002', 'sh_market_1', [0, 0], 'market_plaza');
    const old = r.members('sh_market_1', 1).map(m => m.player).sort();
    const plaza = r.members('sh_market_1', 1, 'market_plaza').map(m => m.player).sort();
    expect(old).toEqual(['old-client-0001', 'old-client-0002']);
    expect(plaza).toEqual(['new-client-0001', 'new-client-0002']);
    expect(r.presence().sh_market_1).toEqual({ online: 4, rooms: 2 });
    // the plaza's member ids start at 1 of their own: a frame names only its own instance's
    expect(r.members('sh_market_1', 1, 'market_plaza').map(m => m.id).sort()).toEqual([1, 2]);
  });

  it('a reconnect goes back to its own layout\'s instance, never the other\'s', () => {
    const r = rooms();
    for (let i = 0; i < 30; i++) r.join(`plaza-fill-${String(i).padStart(4, '0')}`, 'sh_market_1', [0, 0], 'market_plaza');
    r.join('new-client-0099', 'sh_market_1', [0, 0], 'market_plaza');
    expect(r.occupant('new-client-0099')!.room).toBe(2);
    r.leave('new-client-0099');
    expect(r.join('new-client-0099', 'sh_market_1').room).toBe(1);   // as an old client now: the fruit shop's Room 1
    expect(r.occupant('new-client-0099')!.layout).toBe('');
  });

  it('every other room ignores a layout: a 0.3.3 client and a 0.3.2 client still meet in the tea house and the tackle shops', () => {
    const r = rooms();
    r.join('new-client-0001', 'sh_tea_1', [0, 0], 'tea_house');
    r.join('old-client-0001', 'sh_tea_1');
    expect(r.members('sh_tea_1', 1).map(m => m.player).sort()).toEqual(['new-client-0001', 'old-client-0001']);
    expect(r.occupant('new-client-0001')!.layout).toBe('');
    const tackle = cityPlaces(c, TOKYO)!.detail.outposts.find(o => o.role === 'tackle')!;
    r.join('new-client-0002', tackle.id, [0, 0], 'tackle_shop');   // its client_art (SGODOT-214) is no layout of its own
    r.join('old-client-0002', tackle.id);
    expect(r.members(tackle.id, 1).map(m => m.player).sort()).toEqual(['new-client-0002', 'old-client-0002']);
    r.join('new-client-0003', 'sh_market_1', [0, 0], 'no_such_kit');
    expect(r.occupant('new-client-0003')!.layout).toBe('');
  });

  it('a generated city\'s square: a plaza client gets the plaza\'s walls in its own instances, an older one the fruit shop\'s', () => {
    const square = cityPlaces(c, TOKYO)!.detail.outposts.find(o => o.role === 'market')!;
    expect(square.art).toBe('fruit_shop');   // what the server names: every client can open it
    const r = rooms();
    r.join('old-client-0001', square.id);
    r.join('new-client-0001', square.id, [0, 0], 'market_plaza');
    expect(r.spec(square.id)).toMatchObject({ role: 'market', bounds: OLD, seats: [] });
    expect(r.spec(square.id, 'market_plaza')).toMatchObject({ role: 'market', bounds: PLAZA, seats: ['seat_1', 'seat_2'], layout: 'market_plaza' });
    expect(r.members(square.id, 1).map(m => m.player)).toEqual(['old-client-0001']);
    expect(r.members(square.id, 1, 'market_plaza').map(m => m.player)).toEqual(['new-client-0001']);
    expect(r.presence()[square.id]).toEqual({ online: 2, rooms: 2 });
    r.leave('new-client-0001');
    expect(r.spec(square.id, 'market_plaza')).toBeUndefined();   // empty: let go, as a generated room is
    expect(r.spec(square.id)).toBeDefined();
  });

  it('voice: the plaza\'s Room 1 is another LiveKit room than the fruit shop\'s; the fruit shop\'s name is unchanged', () => {
    const voice = new P0Voice(null, rooms(), { blocks: '/nonexistent/b', ages: '/nonexistent/a', reports: '/nonexistent/r' }, Date.now);
    const old = voice.roomName({ outpost: 'sh_market_1', room: 1, layout: '' });
    const plaza = voice.roomName({ outpost: 'sh_market_1', room: 1, layout: 'market_plaza' });
    expect(plaza).not.toBe(old);
    expect(old).toBe(voice.roomName({ outpost: 'sh_market_1', room: 1 }));   // what a 0.3.2 client's room has been called
  });
});
