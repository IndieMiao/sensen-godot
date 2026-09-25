import type { Content } from '../../src/domain/content.js';
import { PondCatalog } from '../../src/ponds/catalog.js';
import { defaultFishingTarget, validFishingCast, type FishingPoint } from '../../src/domain/fishing.js';
import { walkable } from '../../src/realtime/model.js';

export function registeredPondFixture(content: Content) {
  const catalog = new PondCatalog(), entry = catalog.list('shanghai')[0];
  const {site, template} = catalog.room(entry.id, catalog.revision, content);
  const nav = template.navigation;
  for (let y=0; y<nav.rows.length; y++) for (let x=0; x<nav.rows[y].length; x++) {
    const origin: FishingPoint = [(x+.5)*nav.cell,-(y+.5)*nav.cell];
    const target = defaultFishingTarget(site, origin);
    if (validFishingCast(site,origin,target,content.fishing,p=>walkable(nav,p)))
      return {id:entry.id, revision:catalog.revision, origin, target, site, nav};
  }
  throw new Error('Registered pond has no reachable shore');
}
