/** q(219) (SGODOT-338 / 345): an account's first two bites always land — the client keeps the hook window open and the
 * reel from failing, and the server settles an `escaped` on those bites as landed (not before the bite, not when the bag
 * can't take the fish); `cancel` after the bite and a stale line stay got away. Pin 1 holds at a pond without Pond
 * Crucian: its first three bites are the pond's Common global fish. */
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { pickFish } from '../../src/p0/fishing.js';
import { pondAt, type Pond } from '../../src/p0/fishing_world.js';
import { applyP0, count, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { HOME_ALIAS } from '../../src/p0/travel.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content();
const SF = HOME_ALIAS['san francisco'];
const FERN = 'pond_san_francisco_03', CLOVER = 'pond_san_francisco_02';   // Fern = Pond template, Clover = Coast (q(109))
const T0 = Date.UTC(2026, 9, 10, 20);   // 13:00 in San Francisco
const S = 1000;

function step(s: P0State, cmd: P0Command, now: number): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return { s: r.state, ev: r.events };
}
const fresh = (place = FERN): P0State => { const s = freshState(c, 'player-q219', T0, 7); s.presence.place = place; return s; };
const catchOf = (ev: P0Event[]) => ev.find(e => e.kind === 'catch') as Extract<P0Event, { kind: 'catch' }>;
const fishIn = (s: P0State) => s.bag.filter(b => b.id.startsWith('fish_')).reduce((n, b) => n + b.qty, 0);

/** Cast, then report `outcome` `after` ms past the bite (negative: before it). */
function fishOnce(s: P0State, outcome: 'landed' | 'escaped' | 'cancel', at: number, after = 5 * S) {
  const cast = step(s, { type: 'cast' }, at);
  const reel = step(cast.s, { type: 'reel', outcome }, at + cast.s.cast!.bite_ms + after);
  return { cast: cast.s, s: reel.s, ev: reel.ev };
}

describe('first-catch guarantee (q(219))', () => {
  it('an escaped report on the first two bites lands the fish; the third escapes as before', () => {
    let s = fresh();
    for (let i = 0; i < 2; i++) {
      const r = fishOnce(s, 'escaped', T0 + i * 60 * S);
      expect(catchOf(r.ev)).toMatchObject({ fish: 'fish_crucian', result: 'landed', refund: 0 });
      expect(r.s.fishing.bites).toBe(i + 1);
      s = r.s;
    }
    expect(count(s.bag, 'fish_crucian')).toBe(2);
    const third = fishOnce(s, 'escaped', T0 + 120 * S);
    expect(catchOf(third.ev)).toMatchObject({ fish: '', result: 'escaped', refund: 5 });   // newbie protection refunds in full
    expect(count(third.s.bag, 'fish_crucian')).toBe(2);
    expect(third.s.fishing.bites).toBe(3);
  });

  it('a landed report on the first two bites is unchanged (the client that never fails them)', () => {
    const r = fishOnce(fresh(), 'landed', T0);
    expect(catchOf(r.ev)).toMatchObject({ fish: 'fish_crucian', result: 'landed' });
    expect(r.s.skills.fishing).toBe(fishOnce(fresh(), 'escaped', T0).s.skills.fishing);   // same XP either way
  });

  it('cancel after the bite still counts as got away and uses up one of the two', () => {
    const r = fishOnce(fresh(), 'cancel', T0);
    expect(catchOf(r.ev)).toMatchObject({ result: 'escaped', refund: 5 });
    expect(fishIn(r.s)).toBe(0);
    expect(r.s.fishing.bites).toBe(1);
    const next = fishOnce(r.s, 'escaped', T0 + 60 * S);   // the second bite is still sure
    expect(catchOf(next.ev).result).toBe('landed');
    expect(fishOnce(next.s, 'escaped', T0 + 120 * S).ev.find(e => e.kind === 'catch')).toMatchObject({ result: 'escaped' });
  });

  it('an escaped report before the bite does not land the fish', () => {
    const r = fishOnce(fresh(), 'escaped', T0, -100);
    expect(catchOf(r.ev)).toMatchObject({ fish: '', result: 'escaped' });
    expect(fishIn(r.s)).toBe(0);
  });

  it('a line left in past the 90 s grace settles as got away when the next cast goes out', () => {
    const cast = step(fresh(), { type: 'cast' }, T0).s;
    const again = step(cast, { type: 'cast' }, T0 + c.fishing.stale_ms + S);
    expect(catchOf(again.ev)).toMatchObject({ fish: '', result: 'escaped' });
    expect(fishIn(again.s)).toBe(0);
    expect(again.s.fishing.bites).toBe(1);
  });

  it('a bag that cannot take the fish: landed is refused, escaped settles as got away (no bag_full loop)', () => {
    const cast = step(fresh(), { type: 'cast' }, T0).s;
    while (cast.bag.length < c.bag.capacity) cast.bag.push({ id: `crop_radish`, qty: 1 });
    for (const b of cast.bag) if (b.id === 'crop_radish') b.qty = 99;   // full stacks: no room for a crucian anywhere
    const at = T0 + cast.cast!.bite_ms + 5 * S;
    expect(applyP0(c, cast, { type: 'reel', outcome: 'landed' }, at)).toMatchObject({ ok: false, code: 'bag_full' });
    const r = step(cast, { type: 'reel', outcome: 'escaped' }, at);
    expect(catchOf(r.ev)).toMatchObject({ fish: '', result: 'escaped' });
    expect(count(r.s.bag, 'fish_crucian')).toBe(0);
  });

  it('the view marks only the first two bites sure', () => {
    let s = fresh();
    for (const sure of [true, true, false]) {
      const cast = step(s, { type: 'cast' }, T0 + s.fishing.bites * 60 * S).s;
      expect(viewOf(c, cast, T0 + s.fishing.bites * 60 * S).fishing.cast).toMatchObject({ sure });
      s = step(cast, { type: 'reel', outcome: 'landed' }, T0 + s.fishing.bites * 60 * S + cast.cast!.bite_ms + S).s;
    }
  });
});

describe('pin 1 at a pond without Pond Crucian (q(219) ③)', () => {
  it('a Coast pond\'s first three bites are its Common global fish (Grey Mullet), then the usual weights', () => {
    const pond: Pond = { ...pondAt(c, CLOVER, T0), cluster: SF };
    const s = fresh(CLOVER);
    for (let i = 0; i < 3; i++, s.fishing.bites++) {
      for (let k = 0; k < 50; k++) expect(pickFish(c, s, null, c.fishing.sites.coast, pond).id).toBe('fish_mullet');
    }
    s.skills.fishing = 480;   // past pin 2
    const later = new Set<string>();
    for (let k = 0; k < 400; k++) later.add(pickFish(c, s, null, c.fishing.sites.coast, pond).id);
    expect(later.size).toBeGreaterThan(1);
  });

  it('the first two bites at a Coast pond land through the real commands, even reported escaped', () => {
    let s = fresh(CLOVER);
    for (let i = 0; i < 2; i++) {
      const r = fishOnce(s, 'escaped', T0 + i * 60 * S);
      expect(r.cast.cast!.breaks).toBeNull();
      expect(catchOf(r.ev)).toMatchObject({ fish: 'fish_mullet', result: 'landed' });
      s = r.s;
    }
  });

  it('a pond with no Common global fish at all falls back to any Common global fish', () => {
    const s = fresh(CLOVER);
    const noRegional: Pond = { ...pondAt(c, CLOVER, T0), regional: [] };
    const k = { ...c, fish: c.fish.map(f => f.id === 'fish_mullet' ? { ...f, where: [] } : f) };   // the Coast loses its Common fish
    expect(k.fish.some(f => f.rarity === 1 && !f.regional && f.where.includes('coast'))).toBe(false);
    const f = pickFish(k, s, null, k.fishing.sites.coast, noRegional);
    expect(f.rarity).toBe(1);
    expect(f.regional).not.toBe(true);
    expect(f.level).toBe(1);
  });
});
