/**
 * Quick Recast (Fishing Lv9, §4.6.2; 不知火舞 on 283: no toast, no mark): after a landed rod catch, the next cast at the
 * same pond bites sooner (×0.7). Every cast clears it, so a fish lost, a line in, another pond or the cast after that
 * waits as usual. P0 casts where the player stands, so the plan's "no walking back" holds already.
 */
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 13, 20);
const S = 1000, H = 3_600_000;
const FERN = 'pond_san_francisco_03', BLOSSOM = 'pond_san_francisco_06';
const LV = (n: number) => c.skills.fishing[n - 1];

function step(s: P0State, cmd: P0Command, now = T0): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return { s: r.state, ev: r.events };
}
function player(level: number, place = FERN): P0State {
  const s = { ...freshState(c, 'p1-quick-01', T0, 7), created_at: T0 - 8 * 24 * H };
  s.skills.fishing = LV(level);
  s.presence.place = place;
  return s;
}
/** Cast, wait out the bite, reel with this outcome; the state after and when it ended. */
function fishOnce(s: P0State, outcome: 'landed' | 'escaped' | 'cancel', at = T0): { s: P0State; end: number } {
  const cast = step(s, { type: 'cast' }, at);
  const end = outcome === 'cancel' ? at + 100 : at + cast.s.cast!.bite_ms + 5 * S;
  return { s: step(cast.s, { type: 'reel', outcome }, end).s, end };
}
/** The next cast's bite wait, and the same cast's had Quick Recast not been there (same draw). */
function nextBite(s: P0State, at: number): { got: number; usual: number; after: P0State } {
  const plain = structuredClone(s);
  delete plain.fishing.quick;
  const a = step(s, { type: 'cast' }, at), b = step(plain, { type: 'cast' }, at);
  return { got: a.s.cast!.bite_ms, usual: b.s.cast!.bite_ms, after: a.s };
}

describe('Quick Recast (Fishing Lv9, §4.6.2)', () => {
  it('the rule is content: Lv9, ×0.7', () => {
    expect(c.fishing.quick_recast).toEqual({ level: 9, wait: 0.7 });
    const conv = (c.fishing as { conveniences?: Record<string, number> }).conveniences;
    if (conv?.quick_recast !== undefined) expect(conv.quick_recast).toBe(c.fishing.quick_recast!.level);   // the Skills page's level (#366)
  });

  it('from Lv9 a landed fish makes the next cast at that pond bite ×0.7 sooner, once', () => {
    const landed = fishOnce(player(9), 'landed');
    expect(landed.s.fishing.quick).toBe(FERN);
    const next = nextBite(landed.s, landed.end + S);
    expect(Math.abs(next.got - next.usual * 0.7)).toBeLessThanOrEqual(1);   // both rounded to the ms
    expect(next.after.fishing.quick).toBeUndefined();   // used up by that cast
    const after = step(next.after, { type: 'reel', outcome: 'escaped' }, landed.end + S + next.got + 5 * S).s;
    const third = nextBite(after, landed.end + 60 * S);
    expect(third.got).toBe(third.usual);   // the cast after a lost fish waits as usual
  });

  it('below Lv9 nothing changes', () => {
    const landed = fishOnce(player(8), 'landed');
    expect(landed.s.fishing.quick).toBeUndefined();
    const next = nextBite(landed.s, landed.end + S);
    expect(next.got).toBe(next.usual);
  });

  it('another pond, a lost fish or a line in waits as usual', () => {
    const landed = fishOnce(player(9), 'landed');
    const moved = structuredClone(landed.s);
    moved.presence.place = BLOSSOM;
    const there = nextBite(moved, landed.end + S);
    expect(there.got).toBe(there.usual);
    for (const outcome of ['escaped', 'cancel'] as const) {
      const lost = fishOnce(player(9), outcome);
      expect(lost.s.fishing.quick).toBeUndefined();
    }
  });
});
