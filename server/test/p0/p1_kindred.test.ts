import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

// q(171) (SGODOT-284, P1 exit 11): first reaching Kindred gives the resident's postcard into the Passport — `Postcard
// from Pip`, its text their Kindred line — and the title `Pip's Best Friend`, beside a Trusted request's title. Once.
const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 13, 18, 0, 0);
const DAY = 24 * 3_600_000;

function step(s: P0State, cmd: P0Command, now = T0): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return { s: r.state, ev: r.events };
}
const fresh = (pip = 0) => {
  const s = { ...freshState(c, 'player-kindred-01', T0, 3), created_at: T0 - 8 * DAY };
  if (pip) s.residents.res_pip = { affinity: pip, chat_day: '', gift_day: '', next: 0, req: null, done_day: '' };
  return s;
};
const kindred = (ev: P0Event[]) => ev.filter(e => e.kind === 'kindred');

describe('Kindred gives a postcard and a title (q(171))', () => {
  it('the chat that reaches 150 gives both, after its affinity event', () => {
    const r = step(fresh(148), { type: 'talk', resident: 'res_pip' });
    const kinds = r.ev.map(e => e.kind);
    expect(kinds.indexOf('kindred')).toBeGreaterThan(kinds.indexOf('affinity'));
    expect(kindred(r.ev)).toEqual([{ kind: 'kindred', resident: 'res_pip', postcard: 'Postcard from Pip', title: "Pip's Best Friend" }]);
    expect(r.s.residents.res_pip.kindred_at).toBe(T0);
    const v = viewOf(c, r.s, T0);
    expect(v.residents.res_pip.kindred).toEqual({ postcard: 'Postcard from Pip', text: c.residents.res_pip.lines.Kindred,
      title: "Pip's Best Friend", at: T0 });
    expect(v.residents.res_pip.kindred!.text).not.toBe('');
    expect(v.profile.titles).toEqual(["Pip's Best Friend"]);
    expect(r.s.bag.some(b => b.id.includes('postcard'))).toBe(false);   // into the Passport, never the bag
  });

  it('once per resident: later points at Kindred give nothing more', () => {
    const first = step(fresh(148), { type: 'talk', resident: 'res_pip' });
    const next = step(first.s, { type: 'talk', resident: 'res_pip' }, T0 + DAY);
    expect(next.ev.some(e => e.kind === 'affinity')).toBe(true);
    expect(kindred(next.ev)).toEqual([]);
    expect(next.s.residents.res_pip.kindred_at).toBe(T0);
    expect(viewOf(c, next.s, T0 + DAY).profile.titles).toEqual(["Pip's Best Friend"]);
  });

  it('below Kindred nothing is given; the view says null', () => {
    const r = step(fresh(140), { type: 'talk', resident: 'res_pip' });
    expect(kindred(r.ev)).toEqual([]);
    expect(viewOf(c, r.s, T0).residents.res_pip.kindred).toBeNull();
    expect(viewOf(c, r.s, T0).profile.titles).toEqual([]);
  });

  it('a gift that crosses 150 gives them too, at its time', () => {
    const s = fresh(149);
    s.bag.push({ id: 'dish_carrot_cake', qty: 1 });   // Pip likes Dessert: +2
    const r = step(s, { type: 'gift', resident: 'res_pip', item: 'dish_carrot_cake' }, T0 + 5);
    expect(kindred(r.ev)).toHaveLength(1);
    expect(r.s.residents.res_pip.kindred_at).toBe(T0 + 5);
  });

  it('a save already at Kindred gets them with its next affinity change', () => {
    const r = step(fresh(162), { type: 'talk', resident: 'res_pip' });
    expect(kindred(r.ev)).toHaveLength(1);
    expect(viewOf(c, fresh(162), T0).residents.res_pip.kindred).toBeNull();   // nothing before that
  });

  it('every resident has a Kindred line for their postcard, and the title sits beside a request title', () => {
    for (const [id, def] of Object.entries(c.residents)) expect(def.lines.Kindred ?? '', id).not.toBe('');
    const s = fresh(148);
    s.rewards.push('title:Route Buddy');
    const r = step(s, { type: 'talk', resident: 'res_pip' });
    expect(viewOf(c, r.s, T0).profile.titles).toEqual(['Route Buddy', "Pip's Best Friend"]);
  });
});
