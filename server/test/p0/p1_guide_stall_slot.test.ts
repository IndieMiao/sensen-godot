/** q(215) ④⑦ (SGODOT-341 / 344): a guided save without Pond Catch holds the Stall Board's first slot until Nadia's
 * first request is delivered — then it refills 4 h later, as after Pond Catch — and the guide ending before that
 * (the fallback, a changed table) refills it at once. */
import { describe, expect, it } from 'vitest';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { heldSlot, settleBoards } from '../../src/p0/boards.js';
import { validateGuide, type GuideContent } from '../../src/p0/guide.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';

const T0 = Date.UTC(2026, 9, 27, 2);
const H = 3_600_000;
const ONE = 'req_res_nadia_radish', SIX = 'req_res_nadia_six_radishes';

const TABLE: GuideContent = {
  steps: [
    { id: 't_nadia_1', phase: 'C', done_on: { key: `deliver:${ONE}` } },
    { id: 't_nadia_2', phase: 'G', done_on: { key: `accept:${SIX}` } },
  ],
  recover: [], tips: {}, pond_catch: false, stall_refill_on: `deliver:${ONE}`,
};
function content(guide: GuideContent = TABLE): P0Content {
  const c = loadP0Content();
  c.guide = structuredClone(guide);
  return c;
}
const c = content();
function run(s: P0State, cmd: P0Command, now: number, cc = c): P0State {
  const r = applyP0(cc, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code}`);
  return r.state;
}
/** The Stall Board as the next command or the view would find it at `now`. */
function stall(s: P0State, now: number, cc = c) {
  const t = structuredClone(s);
  settleBoards(cc, t, now);
  return t.boards.stall.map(sl => ({ req: sl.req?.id ?? null, held: heldSlot(cc, t, 'stall', sl), refill_at: sl.refill_at }));
}
const guided = (cc = c) => freshState(cc, 'guide-stall-01', T0, 42, { guide: true });
/** Take and hand in A Fresh Radish at `at`. */
function deliverOne(s: P0State, at: number, cc = c): P0State {
  s = run(s, { type: 'accept', request: ONE }, at - 60_000, cc);
  s.bag.push({ id: 'crop_radish', qty: 1 });
  return run(s, { type: 'deliver', request: ONE }, at, cc);
}

describe('the Stall Board\'s first slot in the guide (q(215) ④⑦)', () => {
  it('starts held, both slots, with no countdown, while the guide waits for Nadia', () => {
    const s = guided();
    expect(s.guide?.step).toBe('t_nadia_1');
    expect(stall(s, T0)).toEqual([
      { req: null, held: true, refill_at: T0 + 72 * H }, { req: null, held: true, refill_at: T0 + 72 * H }]);
    expect(stall(s, T0 + 40 * H).map(x => x.req)).toEqual([null, null]);
  });

  it('refills 4 h after A Fresh Radish is delivered; slot 2 keeps its 72 h', () => {
    const at = T0 + H;
    const s = deliverOne(guided(), at);
    expect(s.guide?.step).toBe('t_nadia_2');
    expect(stall(s, at)).toEqual([
      { req: null, held: false, refill_at: at + 4 * H }, { req: null, held: true, refill_at: T0 + 72 * H }]);
    expect(stall(s, at + 4 * H - 1)[0].req).toBeNull();
    expect(stall(s, at + 4 * H)[0].req).toMatch(/-stall0-/);
    expect(stall(s, at + 4 * H)[1].req).toBeNull();
    // the guide ending (Six Radishes taken) inside those 4 h does not bring it forward
    s.residents.res_nadia.affinity = 17;
    const ended = run(s, { type: 'accept', request: SIX }, at + 2 * H);
    expect(ended.guide).toMatchObject({ step: null, end: 'done' });
    expect(stall(ended, at + 2 * H)[0]).toEqual({ req: null, held: false, refill_at: at + 4 * H });
  });

  it('refills at once when the guide ends before the delivery (a table without its step; 341\'s fallback ends the same way)', () => {
    const s = guided();
    const changed = content({ ...TABLE, steps: [{ id: 't_other', phase: 'C', done_on: { key: 'ack:t_other' } }] });
    const later = T0 + 5 * H;
    const plot = s.plots.find(p => p.state === 'tilled')!.id;
    const after = run(s, { type: 'sow', plot, seed: 'seed_radish', space: 'home' } as P0Command, later, changed);
    expect(after.guide).toMatchObject({ step: null, end: 'done' });
    expect(stall(after, later, changed)[0]).toMatchObject({ held: false, refill_at: later });
    expect(stall(after, later, changed)[0].req).toMatch(/-stall0-/);
    expect(stall(after, later, changed)[1]).toMatchObject({ req: null, held: true });
  });

  it('leaves a save outside the guide on Pond Catch, and a drawn first slot where it is', () => {
    const plain = freshState(c, 'guide-stall-02', T0, 42);
    expect(plain.guide?.step).toBeNull();
    expect(stall(plain, T0)[0].req).toBe('req_pond_catch');
    const delivered = plain.boards.stall[0];
    const s = guided();
    s.boards.stall = [{ ...delivered }];   // a first slot that is not the held one
    s.guide = { step: null, n: {}, end: 'done', at: T0 };
    s.residents.res_nadia = { affinity: 0, chat_day: '', gift_day: '', next: 0, req: { id: ONE, at: T0, progress: 0 }, done_day: '' };
    s.bag.push({ id: 'crop_radish', qty: 1 });
    const after = run(s, { type: 'deliver', request: ONE }, T0 + H);
    expect(stall(after, T0 + H)[0].req).toBe('req_pond_catch');
  });

  it('a table naming an unknown key for the refill is reported', () => {
    expect(validateGuide(content())).toEqual([]);
    expect(validateGuide(content({ ...TABLE, stall_refill_on: 'handover:req_res_nadia_radish' })))
      .toContain('stall_refill_on: unknown key handover:req_res_nadia_radish');
  });
});
