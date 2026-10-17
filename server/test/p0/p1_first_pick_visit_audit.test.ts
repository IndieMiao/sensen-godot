/** SGODOT-286 ad0c1580: the read-only audit of saves the first-pick bug left San Francisco visited in. */
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { auditFirstPickVisits } from '../../src/p0/first_pick_visit.js';
import { freshState, type P0State } from '../../src/p0/state.js';

const c = loadP0Content();
const SF = 'gn-5391959', TOKYO = 'gn-1850147', NYC = 'gn-5128581';
const T0 = Date.parse('2026-10-14T10:00:00Z'), MIN = 60_000, DAY = 86_400_000;
const v = (n: number, first_at: number, last_at: number, deliveries = 0) => ({ n, first_at, last_at, deliveries, delivered_day: '' });
/** A save as the old choose_home left it: home Tokyo picked at T0 + 5 min, San Francisco written visited. */
const bitten = (player: string): P0State => {
  const s = freshState(c, player, T0, 7);
  Object.assign(s.travel, { home: TOKYO, here: TOKYO, home_chosen_at: T0 + 5 * MIN, visits: { [SF]: v(1, T0, T0 + 5 * MIN) } });
  return s;
};

describe('first-pick San Francisco visits (SGODOT-286)', () => {
  it('sorts the saves: never been, went later, changed home since; real visits and San Francisco homes are left out', () => {
    const went = bitten('p-went');
    went.travel.visits[SF] = v(2, T0, T0 + DAY, 1);   // travel there later: n 2, still no stamp
    const changed = bitten('p-changed');
    Object.assign(changed.travel, { home: NYC, home_changes: 1, home_chosen_at: T0 + DAY });
    changed.travel.visits[TOKYO] = v(1, T0 + 5 * MIN, T0 + DAY);
    const legacy = freshState(c, 'p-legacy', T0, 3);   // played San Francisco, changed to Tokyo: its visit is real
    Object.assign(legacy.travel, { home: TOKYO, home_changes: 1, home_chosen_at: T0 + DAY, visits: { [SF]: v(1, T0, T0 + DAY) } });
    const real = freshState(c, 'p-real', T0, 7);   // went by travel: stamped
    Object.assign(real.travel, { home: TOKYO, home_chosen_at: T0 + MIN, visits: { [SF]: v(1, T0 + DAY, T0 + DAY) },
      stamps: [{ cluster: SF, kind: 'landmark', at: T0 + DAY, counted_on: '2026-10-15' }] });
    const home = freshState(c, 'p-home', T0, 3);   // San Francisco's own
    const a = auditFirstPickVisits(c, { 'p-never': bitten('p-never'), 'p-went': went, 'p-changed': changed, 'p-legacy': legacy,
      'p-real': real, 'p-home': home });
    expect(a).toEqual({ never: ['p-never'], went: ['p-went'],
      changed: [{ player: 'p-changed', looks: 'first_pick' }, { player: 'p-legacy', looks: 'played_san_francisco' }] });
  });
});
