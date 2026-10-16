/**
 * Water check for a few generated cities (SGODOT-280, q(114) ⑤ / q(126)), offline: the places on water or too near it
 * and the nearest land that keeps the placement rules (tools/world_water_lib.ts), with world.overrides and the water
 * table already laid over (so a city that is clean comes back with nothing wet).
 *   npx tsx tools/world_water_check.ts gn-5128581 [gn-…]   → JSON on stdout (wet, moved, failed, still_bad)
 *   --raw   checks the generated points, before the water table
 */
import { CityClusters, type CityCluster } from '../src/p0/clusters.js';
import { loadP0Content, type P0Content } from '../src/p0/content.js';
import { generateCity } from '../src/p0/world.js';
import { fixCity, placesOf, type Place } from './world_water_lib.js';

const c = loadP0Content();
const clusters = CityClusters.load();   // every cluster, a closed country's too (q(189))
const raw = process.argv.includes('--raw');
const out = [];
for (const id of process.argv.slice(2).filter(a => !a.startsWith('--'))) {
  const cl = clusters.get(id);
  if (!cl) { out.push({ cluster: id, error: 'no such cluster' }); continue; }
  try {
    const city = generateCity(c, cl, { water: !raw });
    const places: Place[] = placesOf(city);
    out.push({ name: cl.name, tier: city.tier, ...(await fixCity(cl, places)) });
  } catch (e) { out.push({ cluster: id, error: String(e) }); }
}
console.log(JSON.stringify(out, null, 1));
