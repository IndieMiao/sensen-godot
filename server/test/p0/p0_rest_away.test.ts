import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 8, 1, 0, 0); // 09:00 Shanghai
const H = 3_600_000, MIN = 60_000;

function run(s: P0State, cmd: P0Command, now: number): P0State {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code}`);
  return r.state;
}
const tired = () => { const s = freshState(c, 'player-rest-01', T0, 4); s.energy = { value: 100, tick_ms: T0 }; return s; };
const rest = (s: P0State, now: number) => applyP0(c, s, { type: 'rest', space: 'home' }, now);
const ping = (space: string): P0Command => ({ type: 'equip', item: 'rod_starter', space });   // any accepted command

describe('Rest: 2 h since leaving the homestead (§3.4.3, q(41))', () => {
  it('a player who has not left yet cannot rest; the view says so with a null countdown', () => {
    let s = tired();
    s = run(s, ping('home'), T0);
    expect(rest(s, T0 + 10 * MIN)).toMatchObject({ ok: false, code: 'away_short', detail: { ready_in: null, away_h: 2 } });
    expect(viewOf(c, s, T0).rest).toMatchObject({ away_h: 2, away_ready_in: null });
  });

  it('leaving = the first command from the pond / an outpost / the mine; Rest opens 2 h later, at home only', () => {
    let s = tired();
    s = run(s, ping('home'), T0);
    s = run(s, ping('pond'), T0 + 30 * MIN);          // left at 09:30
    s = run(s, ping('outpost'), T0 + 60 * MIN);       // still away: the departure time stays
    s = run(s, ping('home'), T0 + 90 * MIN);          // back home
    expect(rest(s, T0 + 100 * MIN)).toMatchObject({ ok: false, code: 'away_short', detail: { ready_in: 50 * MIN } });
    expect(viewOf(c, s, T0 + 100 * MIN).rest.away_ready_in).toBe(50 * MIN);
    expect(applyP0(c, s, { type: 'rest', space: 'pond' }, T0 + 160 * MIN)).toMatchObject({ ok: false, code: 'not_home' });
    const r = rest(s, T0 + 150 * MIN);
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.state.day.rest).toBe(1);
  });

  it('two commands ≥ 2 h apart count as leaving at the earlier one (the session ended)', () => {
    let s = tired();
    s = run(s, ping('home'), T0);
    expect(rest(s, T0 + 2 * H + MIN).ok).toBe(true);   // came back to the farm after a 2 h break
    s = run(s, ping('home'), T0 + H);
    expect(rest(s, T0 + 2 * H).ok).toBe(false);          // only 1 h since the last command at home
  });

  it('the map and commands without a space change nothing; older clients keep the old rule', () => {
    let s = tired();
    s = run(s, ping('home'), T0);
    s = run(s, ping('map'), T0 + 10 * MIN);
    s = run(s, { type: 'equip', item: 'rod_starter' }, T0 + 20 * MIN);
    expect(s.presence).toMatchObject({ left_at: null, space: 'home' });
    expect(applyP0(c, s, { type: 'rest' }, T0 + 30 * MIN).ok).toBe(true);   // no space: no away check
  });
});

describe('arriving home (hook for SGODOT-231)', () => {
  it('trackPresence reports the first command back at home', async () => {
    const { trackPresence } = await import('../../src/p0/presence.js');
    const s = tired();
    expect(trackPresence(c, s, 'home', T0)).toBe(true);
    expect(trackPresence(c, s, 'home', T0 + MIN)).toBe(false);
    expect(trackPresence(c, s, 'map', T0 + 2 * MIN)).toBe(false);
    expect(trackPresence(c, s, 'pond', T0 + 3 * MIN)).toBe(false);
    expect(trackPresence(c, s, 'home', T0 + 4 * MIN)).toBe(true);
  });
});
