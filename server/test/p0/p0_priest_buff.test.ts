/** The priest's buffs (the user 11-07; plan zhuge-355/priest-buff, all 8 points as recommended): taken from Gabriel in
 * Grace Cathedral, each 20 minutes of real time; the farm one halves the ripening of what is sown under it, the fish one
 * lands two of what is cast under it; takes unlimited in the demo week, 2 a player day from 11-15. */
import { describe, expect, it } from 'vitest';
import { count } from '../../src/p0/bag.js';
import { room, stackLimit } from '../../src/p0/bag.js';
import { loadP0Content } from '../../src/p0/content.js';
import { growMs } from '../../src/p0/garden.js';
import { applyP0, type P0Command, type P0Result } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content();
const CHURCH = { space: 'outpost', place: 'sf_church_1' };
const FERN = 'pond_san_francisco_03', M = 60_000, H = 3_600_000;
const DEMO = Date.parse('2026-11-09T18:00:00Z');   // San Francisco 10:00, player day 11-09
const LATER = Date.parse('2026-11-16T18:00:00Z');  // player day 11-16, the limit on
const at = (s: P0State) => (cmd: Record<string, unknown>, now: number): P0Result => applyP0(c, s, cmd as unknown as P0Command, now);
function save(now = DEMO): P0State { const s = freshState(c, `p0-buff-${now}`, now); s.energy.value = 200; return s; }
const ok = (r: P0Result) => { if (!r.ok) throw new Error(`${r.code} ${JSON.stringify(r.detail ?? {})}`); return r; };

describe('taking a buff (the cathedral, 20 minutes, renew, both at once)', () => {
  it('in the cathedral: 20 minutes on, running on while away; again starts it over; both kinds at once', () => {
    let s = save();
    const r = ok(at(s)({ type: 'buff', buff: 'farm', ...CHURCH }, DEMO));
    expect(r.events).toContainEqual({ kind: 'buff', id: 'farm', left: 20 * M, renewed: false });
    s = r.state;
    expect(viewOf(c, s, DEMO + 19 * M)).toMatchObject({ buffs: [{ id: 'farm', left: M }] });   // offline, the clock runs
    expect((viewOf(c, s, DEMO + 20 * M) as { buffs: unknown[] }).buffs).toEqual([]);           // over: not sent
    s = ok(at(s)({ type: 'buff', buff: 'fish', ...CHURCH }, DEMO + 10 * M)).state;
    expect((viewOf(c, s, DEMO + 10 * M) as { buffs: unknown[] }).buffs).toEqual([{ id: 'farm', left: 10 * M }, { id: 'fish', left: 20 * M }]);
    const again = ok(at(s)({ type: 'buff', buff: 'farm', ...CHURCH }, DEMO + 15 * M));
    expect(again.events).toContainEqual({ kind: 'buff', id: 'farm', left: 20 * M, renewed: true });
    expect((viewOf(c, again.state, DEMO + 15 * M) as { buffs: { id: string; left: number }[] }).buffs.find(b => b.id === 'farm')!.left).toBe(20 * M);   // not 25
  });

  it('only in the cathedral; only farm or fish', () => {
    const s = save();
    expect(at(s)({ type: 'buff', buff: 'farm', space: 'outpost', place: 'sh_tea_1' }, DEMO)).toMatchObject({ ok: false, code: 'not_here', detail: { place: 'sf_church_1' } });
    expect(at(s)({ type: 'buff', buff: 'farm', space: 'home' }, DEMO)).toMatchObject({ ok: false, code: 'not_here' });
    expect(at(s)({ type: 'buff', buff: 'luck', ...CHURCH }, DEMO)).toMatchObject({ ok: false, code: 'bad_buff' });
  });

  it('the demo week takes as often as wanted (limit null); from player day 11-15, 2 a day, both kinds together, back after the rollover', () => {
    let s = save();
    for (let i = 0; i < 4; i++) s = ok(at(s)({ type: 'buff', buff: i % 2 ? 'fish' : 'farm', ...CHURCH }, DEMO + i * M)).state;
    expect(viewOf(c, s, DEMO + 5 * M)).toMatchObject({ buff_takes: { used: 4, limit: null } });
    let t = save(LATER);
    t = ok(at(t)({ type: 'buff', buff: 'farm', ...CHURCH }, LATER)).state;
    t = ok(at(t)({ type: 'buff', buff: 'fish', ...CHURCH }, LATER + M)).state;
    expect(viewOf(c, t, LATER + 2 * M)).toMatchObject({ buff_takes: { used: 2, limit: 2 } });
    const third = at(t)({ type: 'buff', buff: 'farm', ...CHURCH }, LATER + 2 * M);
    expect(third).toMatchObject({ ok: false, code: 'buff_limit', detail: { limit: 2 } });
    const resets = (third as unknown as { detail: { resets_in: number } }).detail.resets_in;
    expect(resets).toBeGreaterThan(0);
    expect(ok(at(t)({ type: 'buff', buff: 'farm', ...CHURCH }, LATER + 2 * M + resets + M)).events).toContainEqual(expect.objectContaining({ kind: 'buff', id: 'farm' }));
  });
});

describe('the farm buff: a snapshot as the seed goes in', () => {
  const sow = (s: P0State, plot: number, now: number) => ok(at(s)({ type: 'sow', plot, seed: 'seed_radish', space: 'home' }, now)).state;
  const water = (s: P0State, plot: number, now: number) => ok(at(s)({ type: 'water', plot, space: 'home' }, now)).state;

  it('sown under it ripens in half the time, watered after it ended too; sown before it and watered during it, not', () => {
    let s = save();
    s = sow(s, 1, DEMO);                                                   // before the buff
    s = ok(at(s)({ type: 'buff', buff: 'farm', ...CHURCH }, DEMO + M)).state;
    s = sow(s, 0, DEMO + 2 * M);                                           // under it
    s = water(s, 1, DEMO + 3 * M);                                         // the one sown before, watered during: no
    s = water(s, 0, DEMO + 30 * M);                                        // the buff has ended: still yes
    const p0 = s.plots.find(p => p.id === 0)!, p1 = s.plots.find(p => p.id === 1)!;
    expect(p0.boost).toBe(0.5);
    expect(p1.boost).toBeUndefined();
    expect(p0.ready_at! - (DEMO + 30 * M)).toBe((p1.ready_at! - (DEMO + 3 * M)) / 2);
    const v = viewOf(c, s, DEMO + 30 * M) as { plots: { id: number; boost?: boolean }[] };
    expect(v.plots.find(p => p.id === 0)!.boost).toBe(true);
    expect(v.plots.find(p => p.id === 1)!.boost).toBeUndefined();
    s = ok(at(s)({ type: 'harvest', plot: 0, space: 'home' }, p0.ready_at! + 1)).state;
    expect(s.plots.find(p => p.id === 0)!.boost).toBeUndefined();         // gone with the crop
  });

  it('after the 45% cap, a layer of its own', () => {
    const s = save();
    const base = growMs(c, s, { id: 0, state: 'sown', fert: true }, 4);
    expect(growMs(c, s, { id: 0, state: 'sown', fert: true, boost: 0.5 }, 4)).toBe(base / 2);
    expect(base).toBe(Math.round(4 * H * (1 - (1 - (c.goods.fert_compost.grow_mult ?? 1)))));
  });

  it('a Quick Radish keeps its fixed time', () => {
    let s = save();
    s = ok(at(s)({ type: 'buff', buff: 'farm', ...CHURCH }, DEMO)).state;
    const quick = c.quick_seeds?.[0];
    if (!quick) return;
    if (!s.bag.some(b => b.id === quick.seed)) s.bag.push({ id: quick.seed, qty: 1 } as never);
    s = ok(at(s)({ type: 'sow', plot: 2, seed: quick.seed, space: 'home' }, DEMO + M)).state;
    expect(s.plots.find(p => p.id === 2)!.crop).toBe(quick.id);
    expect(s.plots.find(p => p.id === 2)!.boost).toBeUndefined();
  });
});

describe('the farm buff skips the fixed-time seeds (周瑜 on #865)', () => {
  it('a fast crop (Cress) keeps its fixed time and no boost', () => {
    let s = save();
    s = ok(at(s)({ type: 'buff', buff: 'farm', ...CHURCH }, DEMO)).state;
    const fast = c.fast_crops?.find(f => f.id === 'crop_cress');
    expect(fast).toBeDefined();
    if (!fast) return;
    if (!s.bag.some(b => b.id === fast.seed)) s.bag.push({ id: fast.seed, qty: 1 } as never);
    s = ok(at(s)({ type: 'sow', plot: 3, seed: fast.seed, space: 'home' }, DEMO + M)).state;
    s = ok(at(s)({ type: 'water', plot: 3, space: 'home' }, DEMO + 2 * M)).state;
    const p = s.plots.find(x => x.id === 3)!;
    expect(p.crop).toBe('crop_cress');
    expect(p.boost).toBeUndefined();
    expect(p.ready_at! - (DEMO + 2 * M)).toBe(fast.grow_s * 1000);
  });
});

describe('the fish buff: a cast under it lands two', () => {
  /** Cast at Fern Pond until a fish that comes in (no gate), then land it; returns the result. */
  function landOne(s: P0State, now: number): { r: P0Result; at: number } {
    for (let t = now; t < now + 40 * M; t += M) {
      const cast = ok(at(s)({ type: 'cast', space: 'pond', place: FERN }, t));
      if (cast.state.cast!.breaks) { s = ok(at(cast.state)({ type: 'reel', outcome: 'cancel', space: 'pond', place: FERN }, t + 100)).state; continue; }
      const when = t + cast.state.cast!.bite_ms + 1000;
      return { r: ok(at(cast.state)({ type: 'reel', outcome: 'landed', space: 'pond', place: FERN }, when)), at: when };
    }
    throw new Error('no fish came in');
  }

  it('two of the fish into the bag and the dex count, the XP and the firsts once; a cast before it, one', () => {
    const plain = landOne(save(), DEMO);
    const one = ok(plain.r).events.find(e => e.kind === 'catch') as unknown as { fish: string; qty?: number };
    expect(one.qty).toBeUndefined();
    let s = save();
    s = ok(at(s)({ type: 'buff', buff: 'fish', ...CHURCH }, DEMO)).state;
    const { r } = landOne(s, DEMO + M);
    const caught = ok(r).events.find(e => e.kind === 'catch') as unknown as { fish: string; qty: number };
    expect(caught.qty).toBe(2);
    expect(ok(r).events).toContainEqual({ kind: 'item', id: caught.fish, delta: 2 });
    expect(count(ok(r).state.bag, caught.fish)).toBe(2);
    expect(ok(r).state.fishing.caught[caught.fish]).toBe(2);
    const xp = (res: P0Result) => ok(res).events.filter(e => e.kind === 'xp').map(e => JSON.stringify(e));
    if (caught.fish === one.fish) expect(xp(r)).toEqual(xp(plain.r));   // the same fish: the same XP
  });

  /** Cast, then make the line's fish a set one that comes in (so two runs compare like for like). */
  function castFixed(s: P0State, now: number, fish = 'fish_crucian'): P0State {
    const cast = ok(at(s)({ type: 'cast', space: 'pond', place: FERN }, now)).state;
    cast.cast = { ...cast.cast!, fish, breaks: null };
    return cast;
  }

  it('the same fish twice gives the same XP and firsts, buff or not: the fish counts once (周瑜 on #865)', () => {
    const plain = castFixed(save(), DEMO);
    const one = ok(at(plain)({ type: 'reel', outcome: 'landed', space: 'pond', place: FERN }, DEMO + plain.cast!.bite_ms + 1000));
    let s = save();
    s = ok(at(s)({ type: 'buff', buff: 'fish', ...CHURCH }, DEMO - M)).state;
    s = castFixed(s, DEMO);
    const two = ok(at(s)({ type: 'reel', outcome: 'landed', space: 'pond', place: FERN }, DEMO + s.cast!.bite_ms + 1000));
    const rest = (r: P0Result) => ok(r).events.filter(e => e.kind !== 'item' && e.kind !== 'catch').map(e => JSON.stringify(e));
    expect(rest(two)).toEqual(rest(one));   // XP, first catch, dex: the very same events
    expect(count(two.state.bag, 'fish_crucian')).toBe(2);
    expect(count(one.state.bag, 'fish_crucian')).toBe(1);
  });

  it('room for one only (the bag filled while it bit): one landed, qty 1, the second not given (周瑜 on #865)', () => {
    let s = save();
    s = ok(at(s)({ type: 'buff', buff: 'fish', ...CHURCH }, DEMO - M)).state;
    s = castFixed(s, DEMO);
    // fill the bag so the crucian has room for one: a stack one short of full, every other slot taken
    const stack = stackLimit(c, 'fish_crucian', s);
    s.bag = [{ id: 'fish_crucian', qty: stack - 1 } as never];
    const fillers = Object.keys(c.materials).filter(id => id !== 'fish_crucian');
    for (let i = 0; s.bag.length < s.bag_cap; i++) s.bag.push({ id: fillers[i % fillers.length], qty: stackLimit(c, fillers[i % fillers.length], s) } as never);
    expect(room(c, s, 'fish_crucian')).toBe(1);
    const r = ok(at(s)({ type: 'reel', outcome: 'landed', space: 'pond', place: FERN }, DEMO + s.cast!.bite_ms + 1000));
    expect((r.events.find(e => e.kind === 'catch') as unknown as { qty: number }).qty).toBe(1);
    expect(r.events).toContainEqual({ kind: 'item', id: 'fish_crucian', delta: 1 });
    expect(count(r.state.bag, 'fish_crucian')).toBe(stack);
    expect(r.state.fishing.caught.fish_crucian).toBe(1);
  });

  // q(305) (the user, bot 613): from player day 11-15 (content.buffs.limit_from) a Legendary under the buff lands one; the
  // day the line went in decides (cast.at, as q(300)'s cast does)
  describe('q(305): a Legendary lands one from 11-15', () => {
    const LIMIT = Date.parse('2026-11-15T12:01:00Z');      // San Francisco 04:01, player day 11-15
    const EVE = Date.parse('2026-11-15T11:58:00Z');        // 03:58, still player day 11-14
    const land = (now: number, fish: string, castAt = now) => {
      let s = save(DEMO);
      s = ok(at(s)({ type: 'buff', buff: 'fish', ...CHURCH }, castAt - M)).state;
      s = castFixed(s, castAt, fish);
      const r = ok(at(s)({ type: 'reel', outcome: 'landed', space: 'pond', place: FERN }, Math.max(now, castAt + s.cast!.bite_ms + 1000)));
      return (r.events.find(e => e.kind === 'catch') as unknown as { qty: number }).qty;
    };
    it('the demo week: a Legendary lands two', () => expect(land(DEMO, 'fish_sturgeon')).toBe(2));
    it('from 11-15: a Legendary lands one', () => expect(land(LIMIT, 'fish_sturgeon')).toBe(1));
    it('from 11-15: any other fish still lands two', () => expect(land(LIMIT, 'fish_crucian')).toBe(2));
    it('cast on 11-14 and landed after 04:00 on 11-15: two, the cast decides', () =>
      expect(land(LIMIT + 5 * M, 'fish_sturgeon', EVE)).toBe(2));
  });

  it('the cast decides: thrown under it, two even if it ended before the bite; the view marks the cast', () => {
    let s = save();
    s = ok(at(s)({ type: 'buff', buff: 'fish', ...CHURCH }, DEMO)).state;
    for (let t = DEMO + 19 * M; ; t += 1000) {
      const cast = ok(at(s)({ type: 'cast', space: 'pond', place: FERN }, t));
      if (cast.state.cast!.breaks) { s = ok(at(cast.state)({ type: 'reel', outcome: 'cancel', space: 'pond', place: FERN }, t + 100)).state; continue; }
      expect(cast.state.cast!.twin).toBe(true);
      expect((viewOf(c, cast.state, t) as { fishing: { cast: { twin?: boolean } } }).fishing.cast.twin).toBe(true);
      const land = ok(at(cast.state)({ type: 'reel', outcome: 'landed', space: 'pond', place: FERN }, DEMO + 21 * M));   // the buff is over
      expect((land.events.find(e => e.kind === 'catch') as unknown as { qty: number }).qty).toBe(2);
      break;
    }
  });
});
