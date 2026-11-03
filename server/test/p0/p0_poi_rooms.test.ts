/** Enterable POIs (SGODOT-313, plan poi-enter-plan-2026-11-03): the template table, POI room ids, a room's spec. */
import { describe, expect, it } from 'vitest';
import { loadPoiTemplates, parsePoiRoom, poiRoomSpec, templateFor } from '../../src/p0/online/poi.js';

const table = loadPoiTemplates();

describe('enterable POI rooms (SGODOT-313)', () => {
  it('the table: 16 to a room, each template walled and seated, every maki / class row a template there', () => {
    expect(table.capacity).toBe(16);
    expect(Object.keys(table.templates).sort()).toEqual(['city_park', 'hotel_lobby', 'service_hall']);
    expect(table.templates.hotel_lobby.seats).toHaveLength(8);
    expect(table.templates.city_park.bounds).toEqual([-4, 4, -4, 4]);
  });
  it('picks by maki, else class, else none', () => {
    expect(templateFor(table, 'lodging', '')).toBe('hotel_lobby');
    expect(templateFor(table, 'bank', 'commercial_services')).toBe('service_hall');
    expect(templateFor(table, 'picnic-site', 'park_like')).toBe('city_park');   // no maki row: its class's
    expect(templateFor(table, 'restaurant', 'food_and_drink')).toBe('');        // no Go in
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
});
