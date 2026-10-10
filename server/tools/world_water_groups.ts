/**
 * Hand fixes for the places the water table could not move (SGODOT-280, q(126) → world.overrides, 0.2.2): a pond and
 * what hangs on it (its tackle shop; for the beginner pond also Market Square 1) searched together, so a group that is
 * stuck one place at a time finds a spot where every one of them is off the water and every placement rule holds. It
 * may move a dry anchor (a beginner pond on land whose square stands in the river): that is a hand fix, proposed here,
 * checked on the map, then written into world.overrides by hand.
 *   npx tsx tools/world_water_groups.ts gn-4641239 [gn-…]   → JSON: per city the proposed moves and what is still bad
 */
import type { CityCluster } from '../src/p0/clusters.js';
import { loadP0Content, type P0Content } from '../src/p0/content.js';
import { generateCity, km } from '../src/p0/world.js';
import { MIN_POND_M, around, dryM, need, ruleOk, waterMap, type Place, type WaterMap } from './world_water_lib.js';

const c = loadP0Content();
const clusters = (c as P0Content & { clusters: { get(id: string): CityCluster | undefined } }).clusters;

const bad = (cl: CityCluster, map: WaterMap, places: Place[], p: Place) => dryM(map, p) < need(p) || !ruleOk(cl, places, p, p);

/** The first spot near `around` (within `reach` m) where `o` is off the water and keeps every rule, the others as they stand. */
function spotFor(cl: CityCluster, map: WaterMap, places: Place[], o: Place, from: { lat: number; lng: number }, reach: number) {
  for (const s of around(from, reach)) if (dryM(map, s) >= need(o) && ruleOk(cl, places, o, s)) return s;
  return null;
}

async function fixGroups(cl: CityCluster, searchM: number) {
  const city = generateCity(c, cl);   // as served: water table and hand fixes laid over
  const places: Place[] = [...city.detail.ponds.map(p => ({ ...p, kind: 'pond' as const })), ...city.detail.outposts.map(o => ({ ...o, kind: 'outpost' as const }))];
  const lats = places.map(p => p.lat), lngs = places.map(p => p.lng), pad = (searchM + 1500) / 111_320;
  const padLng = pad / Math.cos((cl.lat * Math.PI) / 180);
  const map = await waterMap(Math.min(...lats) - pad, Math.min(...lngs) - padLng, Math.max(...lats) + pad, Math.max(...lngs) + padLng);
  const moves: { id: string; name: string; from: [number, number]; to: [number, number]; moved_m: number; water_m: number }[] = [];
  const beginner = places.find(p => p.kind === 'pond' && p.beginner)!;
  const anchorOf = (p: Place): Place => {
    if (p.kind === 'pond') return p;
    if (p.role === 'tackle') return places.find(q => q.kind === 'pond' && q.name === p.nearest?.name) ?? p;
    if (p.id.endsWith('~market0')) return beginner;
    return p;
  };
  const anchors = [...new Set(places.filter(p => bad(cl, map, places, p)).map(anchorOf))];
  for (const a of anchors) {
    if (a.kind !== 'pond') {   // an outpost on its own: the nearest spot that keeps the rules
      const s = spotFor(cl, map, places, a, a, searchM);
      if (s) { moves.push({ id: a.id, name: a.name, from: [a.lat, a.lng], to: [s.lat, s.lng], moved_m: Math.round(km(a, s) * 1000), water_m: Math.round(dryM(map, s)) }); a.lat = s.lat; a.lng = s.lng; }
      continue;
    }
    const shop = places.find(o => o.kind === 'outpost' && o.role === 'tackle' && o.nearest?.name === a.name);
    const square = a.beginner ? places.find(o => o.id === `${cl.id}~market0`) : undefined;
    const start = { lat: a.lat, lng: a.lng };
    const saved = [a, shop, square].filter(Boolean).map(p => [p!, p!.lat, p!.lng] as const);
    let done = false;
    for (const q of around(start, searchM)) {
      if (dryM(map, q) < MIN_POND_M || !ruleOk(cl, places, a, q)) continue;
      a.lat = q.lat; a.lng = q.lng;
      // what hangs on the pond goes where it fits with the pond here: kept where it stands if it already does
      const fit = (o: Place | undefined, reach: number) => {
        if (!o || !bad(cl, map, places, o)) return true;
        const s = spotFor(cl, map, places, o, a, reach);
        if (!s) return false;
        o.lat = s.lat; o.lng = s.lng; return true;
      };
      if (fit(shop, 300) && fit(square, 800) && fit(shop, 300) && [a, shop, square].every(p => !p || !bad(cl, map, places, p))) { done = true; break; }
      for (const [p, lat, lng] of saved) { p.lat = lat; p.lng = lng; }
    }
    if (!done) continue;
    for (const [p, lat, lng] of saved) {
      if (p.lat !== lat || p.lng !== lng) moves.push({ id: p.id, name: p.name, from: [lat, lng], to: [p.lat, p.lng], moved_m: Math.round(km({ lat, lng }, p) * 1000), water_m: Math.round(dryM(map, p)) });
    }
  }
  const still = places.filter(p => bad(cl, map, places, p)).map(p => ({ id: p.id, water_m: Math.round(Math.max(0, dryM(map, p))) }));
  return { cluster: cl.id, name: cl.name, moves, still_bad: still };
}

const searchM = Number(process.argv.find(a => a.startsWith('--search='))?.slice(9) ?? 6000);
const out = [];
for (const id of process.argv.slice(2).filter(a => !a.startsWith('--'))) {
  const cl = clusters.get(id);
  if (!cl) { out.push({ cluster: id, error: 'no such cluster' }); continue; }
  try { out.push(await fixGroups(cl, searchM)); } catch (e) { out.push({ cluster: id, error: String(e) }); }
}
console.log(JSON.stringify(out, null, 1));
