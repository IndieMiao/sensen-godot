/** Enterable POIs (SGODOT-313, plan poi-enter-plan-2026-11-03): the template table, POI room ids, a room's spec. */
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { loadPoiTemplates, parsePoiRoom, poiName, poiPassPlace, poiRoomKey, poiRoomSpec, templateFor } from '../../src/p0/online/poi.js';
import { freshState } from '../../src/p0/state.js';
import { requirePass } from '../../src/p0/travel.js';

const table = loadPoiTemplates();
const SF = 'gn-5391959', TOKYO = 'gn-1850147';

describe('enterable POI rooms (SGODOT-313)', () => {
  it('the table: 16 to a room, each template walled and seated, every maki / class row a template there', () => {
    expect(table.capacity).toBe(16);
    expect(Object.keys(table.templates).sort()).toEqual(['city_park', 'classroom', 'hotel_lobby', 'service_hall']);
    expect(table.templates.hotel_lobby.seats).toHaveLength(8);
    expect(table.templates.classroom.seats).toHaveLength(6);
    expect(table.templates.classroom.sign).toBe('sign_door');   // N4's door sign; the others' is sign_name
    expect(table.templates.service_hall.sign).toBe('sign_name');
    expect(table.templates.city_park.bounds).toEqual([-4, 4, -4, 4]);
  });
  it('picks by maki (any -JP cut off), else class, else none (q(279) ③)', () => {
    expect(templateFor(table, 'lodging', '')).toBe('hotel_lobby');
    expect(templateFor(table, 'bank', 'commercial_services')).toBe('service_hall');
    expect(templateFor(table, 'library', 'education')).toBe('classroom');
    expect(templateFor(table, 'dog-park', '')).toBe('city_park');
    expect(templateFor(table, 'hospital-JP', 'medical')).toBe('service_hall');   // Japan's tiles
    expect(templateFor(table, 'school-JP', '')).toBe('classroom');
    expect(templateFor(table, 'picnic-site', 'park_like')).toBe('city_park');   // no maki row: its class's
    expect(templateFor(table, '', 'public_facilities')).toBe('service_hall');   // a community centre, a courthouse
    expect(templateFor(table, '', 'education')).toBe('classroom');
    expect(templateFor(table, 'dentist', 'medical')).toBe('');                  // medical is no class row: doctor / hospital only
    expect(templateFor(table, 'post', 'public_facilities')).toBe('');            // post offices wait for E9, whatever their class
    expect(templateFor(table, 'religious-christian', 'public_facilities')).toBe('');
    expect(templateFor(table, 'place-of-worship', '')).toBe('');
    expect(templateFor(table, 'prison', 'public_facilities')).toBe('');          // would fall to Service Hall
    expect(templateFor(table, 'cemetery', 'park_like')).toBe('');                // would fall to Park
    expect(templateFor(table, 'restaurant', 'food_and_drink')).toBe('');        // no Go in
  });
  it("one class name for card, door and chip: by maki, else the template's (q(279) ⑥)", () => {
    const all = new Set([...Object.values(table.names), ...Object.values(table.templates).map(t => t.door)]);
    expect(all.size).toBe(16);   // q(279) ⑥: 16 new English words
    expect(poiName(table, 'doctor', 'medical')).toBe('Clinic');
    expect(poiName(table, 'hospital-JP', 'medical')).toBe('Hospital');
    expect(poiName(table, 'pitch', 'park_like')).toBe('Sports Field');
    expect(poiName(table, 'dog-park', 'park_like')).toBe('Dog Park');           // its own, not Park
    expect(poiName(table, '', 'public_facilities')).toBe('Service Hall');
    expect(poiName(table, '', 'education')).toBe('School');
    expect(poiName(table, 'cafe', 'food_and_drink')).toBe('');
  });
  it("a POI's room key: the first 12 hex of the SHA-256 of its id, as every phone works it out (亚瑟, D)", () => {
    expect(poiRoomKey('tile:1086226316')).toBe('3c0834443165');                       // a tile feature id
    expect(poiRoomKey('tile:Fern Pond Café:-122.41940:37.77490')).toBe('8cec1cad8318');   // none: name and %.5f place, UTF-8
    expect(parsePoiRoom(`poi:hotel_lobby@${SF}:${poiRoomKey('tile:1086226316')}`)?.key).toBe('3c0834443165');
  });
  it('a room id names a template, a city and 12 hex of the tile id; anything else is no POI room', () => {
    expect(parsePoiRoom('poi:hotel_lobby@gn-5391959:0123456789ab')).toEqual({ template: 'hotel_lobby', cluster: 'gn-5391959', key: '0123456789ab' });
    for (const bad of ['poi:hotel_lobby@gn-5391959:tile:123', 'poi:Hotel@gn-5391959:0123456789ab', 'poi:hotel_lobby@sf:0123456789ab',
      'pond:pond_fern', 'sh_tea_1', 'poi:hotel_lobby@gn-5391959:0123456789abc']) expect(parsePoiRoom(bad)).toBeNull();
  });
  it('a known template in a known city gets its room: 16, its walls and seats; an unknown template or city none', () => {
    const spec = poiRoomSpec(table, c => c === 'gn-5391959');
    expect(spec('poi:city_park@gn-5391959:0123456789ab')).toEqual({ id: 'poi:city_park@gn-5391959:0123456789ab', role: 'poi', capacity: 16,
      bounds: table.templates.city_park.bounds, seats: table.templates.city_park.seats });
    expect(spec('poi:museum@gn-5391959:0123456789ab')).toBeUndefined();
    expect(spec('poi:city_park@gn-1850147:0123456789ab')).toBeUndefined();
  });
  it("joining one is judged by its city's pass, as that city's outposts are: home's free, another's with its pass and there", () => {
    const c = loadP0Content(), T = Date.parse('2026-10-10T18:00:00Z');
    const s = freshState(c, 'poi-player', T, 7);
    expect(s.travel.home).toBe(SF);
    expect(poiPassPlace('pond:pond_fern')).toBe('');
    expect(requirePass(c, s, 'outpost', poiPassPlace(`poi:hotel_lobby@${SF}:0123456789ab`), T)).toBeNull();
    expect(requirePass(c, s, 'outpost', poiPassPlace(`poi:hotel_lobby@${TOKYO}:0123456789ab`), T)?.code).toBe('pass_required');
    s.travel.passes[TOKYO] = { kind: 'day', from: T, until: T + 86_400_000 };
    expect(requirePass(c, s, 'outpost', poiPassPlace(`poi:hotel_lobby@${TOKYO}:0123456789ab`), T)?.code).toBe('travel_required');   // a pass, not there
    s.travel.here = TOKYO;
    expect(requirePass(c, s, 'outpost', poiPassPlace(`poi:hotel_lobby@${TOKYO}:0123456789ab`), T)).toBeNull();
    expect(requirePass(c, s, 'outpost', poiPassPlace(`poi:hotel_lobby@${TOKYO}:0123456789ab`), T + 86_400_001)?.code).toBe('trip_expired');
  });
});
