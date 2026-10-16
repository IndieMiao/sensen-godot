/**
 * The pick-your-farm-spot page's still maps (SGODOT-303 HOME-PICK-3; 不知火舞 on 303 28883acf): one picture per open
 * city, north up, framed round its beginner pond and its three base spots with room for any player's scatter, as the
 * client lays its pins (modules/p0/p0_home_spot_maps.gd: Web Mercator, the 328 × 268 card, every pin 24 clear of the
 * edge). The client uses a picture only while its points fit it; the spot table changed, bake again.
 *   npx tsx tools/bake_home_spot_maps.ts --style <owner>/<style id> [--out ../assets/p0/home_spots] [--cities gn-1,gn-2]
 * The style must be the game map's (its colours, no POI icons); the token is mapbox_token.txt's, never printed.
 */
import { execFile } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { loadP0Content } from '../src/p0/content.js';
import { citySet, citySpots, cityPonds, homeRules } from '../src/p0/home_city.js';
import { offset, worldOf } from '../src/p0/world.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const run = promisify(execFile);
const arg = (name: string, fallback = '') => { const i = process.argv.indexOf(name); return i > 0 ? process.argv[i + 1] : fallback; };

// The client's card and reach (p0_home_spot_maps.gd): keep in step.
const CARD = { w: 328, h: 268 }, CLEAR = 24, TILE = 512;
const REACH = { l: 30, t: 40, r: 30, b: 20 };   // the widest of a spot pin's and the pond's (its disc over, its name under)

const merc = (lat: number, lng: number) => ({ x: (lng + 180) / 360, y: 0.5 - Math.log(Math.tan(Math.PI / 4 + (lat * Math.PI) / 360)) / (2 * Math.PI) });
const unmerc = (x: number, y: number) => ({ lat: (Math.atan(Math.sinh(Math.PI * (1 - 2 * y))) * 180) / Math.PI, lng: x * 360 - 180 });

/** The picture's centre and zoom round the points, as the client's fit (its zoom floored a little: never tighter). */
export function frameOf(points: { lat: number; lng: number }[]): { lat: number; lng: number; zoom: number } {
  const m = points.map(p => merc(p.lat, p.lng));
  const lo = { x: Math.min(...m.map(p => p.x)), y: Math.min(...m.map(p => p.y)) };
  const hi = { x: Math.max(...m.map(p => p.x)), y: Math.max(...m.map(p => p.y)) };
  const inner = { w: CARD.w - REACH.l - REACH.r - 2 * CLEAR, h: CARD.h - REACH.t - REACH.b - 2 * CLEAR };
  const zoom = Math.floor(Math.log2(Math.min(inner.w / Math.max(hi.x - lo.x, 1e-9), inner.h / Math.max(hi.y - lo.y, 1e-9)) / TILE) * 100) / 100;
  const scale = TILE * 2 ** zoom;
  const centre = unmerc((lo.x + hi.x) / 2 - (REACH.l - REACH.r) / 2 / scale, (lo.y + hi.y) / 2 - (REACH.t - REACH.b) / 2 / scale);
  return { lat: Math.round(centre.lat * 1e6) / 1e6, lng: Math.round(centre.lng * 1e6) / 1e6, zoom };
}

async function main() {
  const style = arg('--style');
  if (!/^[\w-]+\/[\w-]+$/.test(style)) { console.log('usage: npx tsx tools/bake_home_spot_maps.ts --style <owner>/<style id> [--out dir] [--cities gn-1,gn-2]'); process.exit(2); }
  const out = path.resolve(arg('--out', path.join(ROOT, 'assets/p0/home_spots')));
  mkdirSync(out, { recursive: true });
  const c = loadP0Content(), w = worldOf(c)!, scatter = homeRules(c).spot.scatter_m[1] / 1000;
  const only = arg('--cities').split(',').filter(Boolean);
  const cities = only.length ? only : homeRules(c).cities;
  const token = readFileSync(path.join(ROOT, 'mapbox_token.txt'), 'utf8').trim();
  const manifest: Record<string, { file: string; lat: number; lng: number; zoom: number }> = {};
  for (const id of cities) {
    const set = citySet(c, id), spots = citySpots(c, id), pond = set && cityPonds(c, id).find(p => p.id === set.pond);
    if (!spots || !pond?.at) { console.log(id, '— no spots'); continue; }
    // a player's spot stands up to the scatter from its base: the frame holds all of them
    const points = [pond.at, ...spots.flatMap(s => [0, 90, 180, 270].map(b => offset(s.at.lat, s.at.lng, scatter, b)))];
    const f = frameOf(points), file = `${id}.png`;
    const url = `https://api.mapbox.com/styles/v1/${style}/static/${f.lng},${f.lat},${f.zoom},0/${CARD.w}x${CARD.h}@2x?attribution=false&logo=false&access_token=${token}`;
    try { await run('curl', ['-sS', '-f', '-m', '60', '-o', path.join(out, file), url]); }
    catch (e) { console.log(id, `request failed (${(e as { code?: number }).code ?? '?'})`); continue; }   // the URL carries the token: never print it
    manifest[id] = { file, ...f };
    console.log(id, f);
  }
  writeFileSync(path.join(out, 'maps.json'), JSON.stringify({ _note: 'tools/bake_home_spot_maps.ts: the spot page\'s still maps (SGODOT-303)',
    style, seed: w.seed, revision: w.revision, cities: manifest }, null, 1) + '\n');
}
if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) main().catch(e => { console.error(String(e)); process.exit(1); });
