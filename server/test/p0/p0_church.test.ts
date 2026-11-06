/** Grace Cathedral (the user 11-06: in with v7, a place to see): an outpost of role church in San Francisco — a room of
 * its own (poi_church), no keeper, no counter, and never a place a board, a request or a notice sends anyone to (0.3.0
 * clients, whose outpost table lacks it, would show its raw id: 哪吒 / 亚瑟). */
import { describe, expect, it } from 'vitest';
import { crossTarget, visitPlaces } from '../../src/p0/boards.js';
import { loadP0Content } from '../../src/p0/content.js';
import { loadOutposts } from '../../src/p0/online/outposts.js';
import { OutpostRooms } from '../../src/p0/online/rooms.js';
import { freshState } from '../../src/p0/state.js';
import { cityInfo } from '../../src/p0/travel.js';

const c = loadP0Content();
const SF = 'gn-5391959', CHURCH = 'sf_church_1', T = Date.parse('2026-11-07T18:00:00Z');

describe('Grace Cathedral (role church)', () => {
  it("is in the outpost table as 不知火舞 named it: no keeper, its room's walls and 8 pews", () => {
    const o = loadOutposts().find(x => x.id === CHURCH)!;
    expect(o).toMatchObject({ role: 'church', name: 'Grace Cathedral', category: 'Church · Stained glass', cluster: SF, capacity: 12,
      art: 'poi_church', keeper: {}, residents: [] });
    expect(o.seats).toHaveLength(8);
    expect(c.outposts?.find(x => x.id === CHURCH)).toMatchObject({ role: 'church', residents: [] });
    expect(c.outposts?.find(x => x.id === CHURCH)).not.toHaveProperty('keeper');
  });

  it('has a room of 12 with its seats, as any outpost', () => {
    const rooms = new OutpostRooms(loadOutposts());
    expect(rooms.join('p0-church-0001', CHURCH)).toMatchObject({ outpost: CHURCH, room: 1, capacity: 12 });
    expect(rooms.spec(CHURCH)?.seats).toContain('seat_left_1');
  });

  it("is not of the city's set and never a request's place: Stamp Run, the cross-city visits, the city's counts", () => {
    const s = freshState(c, 'p0-church-0002', T);
    expect(cityInfo(c, SF).outposts).not.toContain(CHURCH);
    for (const board of ['stall', 'market'] as const) expect(visitPlaces(c, board, s)).not.toContain(CHURCH);
    for (const role of ['market', 'tea', 'post', 'tackle', 'church']) expect(crossTarget(c, SF, role)).not.toBe(CHURCH);
  });
});
