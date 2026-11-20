// TEMP (not committed): gathering points and stands of some ponds (410 / 422 checks).
import { loadP0Content } from '../src/p0/content.js';
import { pondPoints, pondShape } from '../src/p0/pond_gather.js';
const c = loadP0Content();
for (let i = 1; i <= 6; i++) {
  const id = `pond_san_francisco_0${i}`;
  console.log(id, pondShape(c, id), JSON.stringify(pondPoints(c, id).filter((p: any) => p.kind === 'reed').map((p: any) => [p.slot, p.x, p.z, p.stand])));
}
