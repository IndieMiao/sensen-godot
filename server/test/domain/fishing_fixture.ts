import type { Content } from '../../src/domain/content.js';
import type { FishingPresence } from '../../src/domain/fishing.js';

// A server-admitted pond fixture retains the compact geometry used by the
// timing/equipment tests; farm-room admission is tested as a rejection now.
export function fishingPondPresence(content: Content): FishingPresence {
  return { space: 'pond', home: 'test-pond', nonce: 'connection-1', x: 9.375, z: -27.375,
    pond: { id: 'test_pond', site: { ...content.fishing.sites.farm_pond, space: 'pond' } } };
}
