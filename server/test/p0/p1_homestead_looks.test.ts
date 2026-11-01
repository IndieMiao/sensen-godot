/** SGODOT-282 LOOK-PICK (§8.3.1, q(24) / q(112)): Homestead looks at Lv3 / 5 / 8 / 10, a (timber) or b (stone). */
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, upgradeState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 10, 2);
const H = 3_600_000;
const at = (level: number): P0State => {
  const s = { ...freshState(c, 'looks', T0, 7), created_at: T0 - 8 * 24 * H, fires: 1 };
  s.homestead.level = level;
  return s;
};
function step(s: P0State, cmd: P0Command): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, cmd, T0);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return { s: r.state, ev: r.events };
}
const refusal = (s: P0State, cmd: P0Command) => {
  const r = applyP0(c, s, cmd, T0);
  return r.ok ? null : { code: r.code, detail: r.detail };
};
const looks = (s: P0State) => viewOf(c, s, T0).homestead.looks;

describe('Homestead looks (LOOK-PICK, q(112))', () => {
  it('four stages: Fence & Mailbox Lv3, Porch Lv5, Kitchen Wing Lv8, Master Farmhouse Lv15 (v4q(1)), each on its level', () => {
    expect(c.homestead.looks!.map(l => [l.id, l.level, l.name, l.a, l.b])).toEqual([
      ['fence', 3, 'Fence & Mailbox', 'Timber Fence', 'Stone Wall'],
      ['porch', 5, 'Porch', 'Timber Porch', 'Stone Porch'],
      ['kitchen_extension', 8, 'Kitchen Wing', 'Timber Kitchen Wing', 'Stone Kitchen Wing'],
      ['master_farmhouse', 15, 'Master Farmhouse', 'Timber Lodge', 'Stone Manor'],
    ]);
    for (const l of c.homestead.looks!) expect(c.homestead.levels.find(x => x.level === l.level)!.unlocks).toContain(l.id);
  });

  it('the view lists every stage; a reached one reads a until picked, one not reached reads null', () => {
    expect(looks(at(5)).map(l => [l.id, l.look])).toEqual([['fence', 'a'], ['porch', 'a'], ['kitchen_extension', null], ['master_farmhouse', null]]);
    expect(looks(at(1)).every(l => l.look === null)).toBe(true);
  });

  it('set_look picks b, back to a, free of Energy and coins; the view and an event say so', () => {
    let s = at(5);
    const before = { energy: s.energy.value, coins: s.coins };
    const r = step(s, { type: 'set_look', stage: 'porch', look: 'b' });
    s = r.s;
    expect(r.ev).toEqual([{ kind: 'look', stage: 'porch', look: 'b' }]);
    expect(looks(s).find(l => l.id === 'porch')!.look).toBe('b');
    expect(looks(s).find(l => l.id === 'fence')!.look).toBe('a');   // each stage on its own
    expect({ energy: s.energy.value, coins: s.coins }).toEqual(before);
    s = step(s, { type: 'set_look', stage: 'porch', look: 'a' }).s;
    expect(looks(s).find(l => l.id === 'porch')!.look).toBe('a');
  });

  it('refuses a stage not reached, an unknown stage or look, and away from home', () => {
    expect(refusal(at(4), { type: 'set_look', stage: 'porch', look: 'b' })).toMatchObject({ code: 'homestead_level', detail: { need: 5 } });
    expect(refusal(at(10), { type: 'set_look', stage: 'roof', look: 'b' })?.code).toBe('bad_stage');
    expect(refusal(at(10), { type: 'set_look', stage: 'porch', look: 'c' } as unknown as P0Command)?.code).toBe('bad_look');
    const away = at(10);
    away.presence.space = 'away';
    expect(refusal(away, { type: 'set_look', stage: 'porch', look: 'b' })?.code).toBe('not_home');
  });

  it('the upgrade to a look level names its stage in the homestead event; others do not', () => {
    const ready = (s: P0State) => {
      const next = c.homestead.levels.find(l => l.level === s.homestead.level + 1)!;
      s.skills = { farming: 99_999, fishing: 99_999, cooking: 99_999 };
      for (const [id, n] of next.materials) s.storage[id] = (s.storage[id] ?? 0) + n;
      s.coins = next.coins + 40;
      return s;
    };
    const ev = (lv: number) => step(ready(at(lv - 1)), { type: 'homestead_upgrade' }).ev.find(e => e.kind === 'homestead');
    expect(ev(5)).toMatchObject({ level: 5, look: 'porch' });
    expect(ev(15)).toMatchObject({ level: 15, look: 'master_farmhouse' });
    expect(ev(4)).not.toHaveProperty('look');
  });

  it('a save without looks (P0, or P1 before LOOK-PICK) reads every reached stage as a', () => {
    const { looks: _none, ...home } = at(15).homestead;
    const up = upgradeState(c, { ...at(15), homestead: home } as P0State, T0);
    expect(looks(up).map(l => l.look)).toEqual(['a', 'a', 'a', 'a']);
  });
});
