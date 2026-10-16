import path from 'node:path';
import { AppearanceCatalog as AvatarCatalog } from '../p0/online/appearance.js';

// P0 owns the avatar catalog (SGODOT-304: the Journey server is retired around it); Journey's rooms find assets/avatar
// from their regions file as before.
export { DEFAULT_SLOTS, defaultAppearance, type Appearance } from '../p0/online/appearance.js';

/** Cosmetic IDs only: no paths, transforms, ownership grants or combat attributes. */
export class AppearanceCatalog extends AvatarCatalog {
  constructor(regionsFile: string) {
    super(path.resolve(path.dirname(regionsFile), '../../avatar'));
  }
}
