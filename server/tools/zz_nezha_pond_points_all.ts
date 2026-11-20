// TEMP (not committed): every gathering point of the three SF ponds, as the view sends them (#906 tree check).
import { loadP0Content } from '../src/p0/content.js';
import { pondPoints } from '../src/p0/pond_gather.js';
const c = loadP0Content();
const out: Record<string, unknown> = {};
for (const id of ['pond_san_francisco_01', 'pond_san_francisco_02', 'pond_san_francisco_03'])
  out[id] = pondPoints(c, id).map((p: any) => ({ id: p.id, x: p.x, z: p.z, stand: p.stand, kind: p.kind }));
console.log(JSON.stringify(out));
