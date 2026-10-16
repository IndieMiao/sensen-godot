/**
 * q(188) ① (SGODOT-303): the home pick's `Near you` row — the open city nearest the player's address, from an address
 * table made out of DB-IP City Lite at image build (tools/ip_near_table.ts → src/p0/ip_city.ts). No guess without the
 * table, for a private or reserved address, or an address the data does not place.
 */
import Fastify from 'fastify';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { gzipSync } from 'node:zlib';
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { nearestOpen } from '../../src/p0/home_city.js';
import { openIpNear, type IpNear } from '../../src/p0/ip_city.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { P0Store } from '../../src/p0/store.js';

const c = loadP0Content();
const SF = 'gn-5391959', TOKYO = 'gn-1850147', LONDON = 'gn-2643743';
const SERVER = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const hd = { 'x-p0-player': 'player-near-01' };
const app = async (ipNear?: IpNear) => {
  const a = Fastify();
  registerP0Routes(a, { content: c, store: new P0Store(c), now: () => Date.now(), dev: false, ipNear });
  return a;
};

/** A DB-IP City Lite CSV in miniature (start,end,continent,country,region,city,lat,lng), with gaps and an unknown range. */
const CSV = [
  '1.0.0.0,1.0.0.255,AS,JP,Tokyo,Shinjuku,35.69,139.70',
  '1.0.1.0,1.0.1.255,AS,JP,Chiba,Chiba,35.60,140.12',      // also Tokyo's: merged with the range before
  '1.0.4.0,1.0.4.255,NA,US,California,San Jose,37.33,-121.89',   // a gap before it (1.0.2.0–1.0.3.255): nobody
  '1.0.5.0,1.0.5.255,EU,GB,England,Reading,51.45,-0.97',
  '1.0.6.0,1.0.6.255,OC,AU,New South Wales,Sydney,-33.87,151.21',   // over 1,500 km from any open city: no guess
  '100.64.0.0,100.127.255.255,ZZ,ZZ,,,0,0',                // reserved: no city, not the one nearest 0, 0
  '2400:4000::,2400:4000:ffff:ffff:ffff:ffff:ffff:ffff,AS,JP,Tokyo,Tokyo,35.68,139.76',
  '2600:1700::,2600:1700:ffff:ffff:ffff:ffff:ffff:ffff,NA,US,California,Oakland,37.80,-122.27',
  // a range ending inside a /64 and the next one starting in that same /64 and running on over several (周瑜 on #447)
  '2a01:402:3300::,2a01:402:3300::1,EU,BG,Sofia,Sofia,42.70,23.32',
  '2a01:402:3300::2,2a01:404:1603:ffff:ffff:ffff:ffff:ffff,EU,NL,North Holland,Amsterdam,52.37,4.90',
].join('\n') + '\n';

describe('Near you (q(188) ①)', () => {
  it('is the open city nearest the point', () => {
    expect(nearestOpen(c, { lat: 35.6, lng: 139.8 })?.id).toBe(TOKYO);
    expect(nearestOpen(c, { lat: 37.33, lng: -121.89 })?.id).toBe(SF);   // San Jose: San Francisco
    // q(205) ②: farther than 1,500 km from every open city, no guess (Sydney is 6,300 km from Singapore)
    expect(nearestOpen(c, { lat: -33.87, lng: 151.21 })).toBeNull();
  });

  it('the address table names each range its nearest open city', () => {
    const dir = mkdtempSync(path.join(tmpdir(), 'ip-near-'));
    writeFileSync(path.join(dir, 'mini.csv.gz'), gzipSync(CSV));
    execFileSync(path.join(SERVER, 'node_modules/.bin/tsx'), ['tools/ip_near_table.ts', path.join(dir, 'mini.csv.gz'), path.join(dir, 'near.bin')], { cwd: SERVER });
    const near = openIpNear(path.join(dir, 'near.bin'));
    expect(['1.0.0.7', '1.0.1.200', '1.0.4.1', '1.0.5.9'].map(near)).toEqual([TOKYO, TOKYO, SF, LONDON]);
    expect(near('1.0.2.1')).toBeNull();            // the gap
    expect(near('1.0.6.9')).toBeNull();            // Sydney: too far from any open city (q(205) ②)
    expect(near('0.255.255.255')).toBeNull();      // before the first
    expect(near('2400:4000:12:34::1')).toBe(TOKYO);
    expect(near('2600:1700:abcd::9')).toBe(SF);
    // the /64 they share goes to the first (Sofia: nearest open city by the content), the /64s after it to Amsterdam's
    for (const ip of ['2a01:402:3301::1', '2a01:403::1', '2a01:404:1603::1']) expect(near(ip)).toBe(LONDON);
    expect(near('200.1.2.3')).toBeNull();          // past the last v4 range
    expect(near('2a02::1')).toBeNull();            // past the last v6 range
    for (const ip of ['10.1.2.3', '192.168.0.4', '127.0.0.1', '100.70.1.1', '::1', 'fe80::1', 'not-an-ip']) expect(near(ip)).toBeNull();
  });

  it('the city list carries it for the request\'s address, only a city open today, and null without a table', async () => {
    const seen: string[] = [];
    const a = await app(ip => { seen.push(ip); return TOKYO; });
    const r = (await a.inject({ method: 'GET', url: '/v1/p0/home/cities', headers: hd })).json();
    expect(r.near?.id).toBe(TOKYO);
    expect(r.near?.status).toBe('open');
    expect(seen).toEqual(['127.0.0.1']);   // the request's own address (behind Caddy: X-Forwarded-For, P0_TRUST_PROXY)
    await a.close();
    const closed = await app(() => 'gn-2988507');   // Paris: not open, no row
    expect((await closed.inject({ method: 'GET', url: '/v1/p0/home/cities', headers: hd })).json().near).toBeNull();
    await closed.close();
    const none = await app();
    expect((await none.inject({ method: 'GET', url: '/v1/p0/home/cities', headers: hd })).json().near).toBeNull();
    await none.close();
  });
});
