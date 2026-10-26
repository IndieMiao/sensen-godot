/** SGODOT-341 (338·L1): the new-player guide's steps — saved on the player, passed by what they do, healed when they stray. */
import Fastify from 'fastify';
import { describe, expect, it } from 'vitest';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { guideKeys, guideRecover, setGuide, validateGuide, type GuideContent } from '../../src/p0/guide.js';
import { mapMarkers } from '../../src/p0/markers.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { freshState, upgradeState, type P0State } from '../../src/p0/state.js';
import { P0Store } from '../../src/p0/store.js';
import { viewOf } from '../../src/p0/view.js';
import type { P0Event } from '../../src/p0/progress.js';

const T0 = Date.UTC(2026, 9, 26, 2);
const H = 3_600_000;

/** A test-only table shaped like 338's first stretch (the real one waits for 339's §14 v3). */
const SAMPLE: GuideContent = {
  steps: [
    { id: 'sow_two', phase: 'B', done_on: { key: 'sow:crop_radish', count: 2 }, marks: [{ place: 'home', kind: 'request' }], tip: 'sow' },
    { id: 'water_two', phase: 'B', done_on: { key: 'water:crop_radish', count: 2 } },
    { id: 'harvest_two', phase: 'B', done_on: { key: 'harvest:crop_radish', count: 2 } },
    { id: 'to_market', phase: 'C', done_on: { key: 'enter:sh_market_1' }, marks: [{ place: 'sh_market_1', kind: 'request' }] },
    { id: 'sell_one', phase: 'C', done_on: { key: 'sell:crop_radish' },
      needs: [{ if: { have: { crop_radish: 1 } }, else: ['rec_wait', 'rec_sow', 'rec_buy'] }] },
    { id: 'read_line', phase: 'D', done_on: { key: 'ack:read_line' } },
    { id: 'make_soup', phase: 'F', done_if: { have: { dish_grilled_crucian: 1 } },
      needs: [{ if: { any: [{ have: { fish_crucian: 1 } }, { pot: 'dish_grilled_crucian' }] }, else: ['rec_fish'] }] },
    { id: 'sow_more', phase: 'H', done_on: { key: 'sow:crop_radish', count: 3, from_step: true } },
  ],
  recover: [
    { id: 'rec_wait', when: { planted: { crop_radish: 1 } }, marks: [{ place: 'home' }] },
    { id: 'rec_sow', when: { have: { seed_radish: 1 } } },
    { id: 'rec_buy' },
    { id: 'rec_fish', marks: [{ place: 'pond_san_francisco_03' }] },
  ],
  tips: {},
};

function content(guide: GuideContent = SAMPLE): P0Content {
  const c = loadP0Content();
  c.guide = structuredClone(guide);
  return c;
}

function run(c: P0Content, s: P0State, cmd: P0Command, now = T0): P0State {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code}`);
  return r.state;
}
const guided = (c: P0Content, player = 'guide-player-01') => freshState(c, player, T0, 42, { guide: true });
const tilled = (s: P0State) => s.plots.filter(p => p.state === 'tilled').map(p => p.id);
const at = (s: P0State) => s.guide?.step ?? null;

/** Sow and water two radishes, then harvest them once ripe: the first three sample steps. */
function twoRadishes(c: P0Content, s: P0State): P0State {
  const [a, b] = tilled(s);
  for (const plot of [a, b]) s = run(c, s, { type: 'sow', plot, seed: 'seed_radish', space: 'home' });
  for (const plot of [a, b]) s = run(c, s, { type: 'water', plot, space: 'home' });
  const later = T0 + 5 * H;
  for (const plot of [a, b]) s = run(c, s, { type: 'harvest', plot, space: 'home' }, later);
  return s;
}

describe('the guide in the save (SGODOT-341)', () => {
  it('a save from before the guide is legacy: no guide, the rest unchanged, the upgrade idempotent', () => {
    const c = content();
    const old = freshState(c, 'guide-old-01', T0, 42) as P0State;
    delete old.guide;
    const before = JSON.parse(JSON.stringify(old));
    const up = upgradeState(c, structuredClone(old), T0);
    expect(up.guide).toEqual({ step: null, n: {}, end: 'legacy', at: T0 });
    const { guide: _g, ...rest } = up;
    expect(JSON.parse(JSON.stringify(rest))).toEqual(before);
    const again = upgradeState(c, JSON.parse(JSON.stringify(up)), T0 + H);
    expect(again).toEqual(up);
    expect(viewOf(c, up, T0).guide).toEqual({ step: null, end: 'legacy' });
  });

  it('a new save starts the guide only for a client that can show it, and only once the table has steps', () => {
    const c = content();
    expect(freshState(c, 'guide-new-01', T0).guide).toMatchObject({ step: null, end: 'legacy' });
    expect(guided(c).guide).toEqual({ step: 'sow_two', n: {}, at: T0 });
    expect(guided(content({ steps: [] })).guide).toMatchObject({ step: null, end: 'legacy' });
    expect(guided(loadP0Content()).guide?.end).toBe('legacy');   // the shipped table is empty until 339
  });

  it('Pond Catch stays on a guided save unless the table says pond_catch false', () => {
    expect(guided(content()).boards.stall[0].req?.id).toBe('req_pond_catch');
    const s = guided(content({ ...SAMPLE, pond_catch: false }));
    expect(s.boards.stall).toEqual([]);
    expect(s.requests).toEqual([]);
    expect(freshState(content({ ...SAMPLE, pond_catch: false }), 'guide-old-02', T0).boards.stall[0].req?.id).toBe('req_pond_catch');
  });
});

describe('passing steps (SGODOT-341)', () => {
  it('sow, water and harvest pass their steps, the view counting each', () => {
    const c = content();
    let s = guided(c);
    const [a, b] = tilled(s);
    s = run(c, s, { type: 'sow', plot: a, seed: 'seed_radish', space: 'home' });
    expect(viewOf(c, s, T0).guide).toMatchObject({ step: 'sow_two', phase: 'B', recover: null, progress: { have: 1, need: 2 } });
    s = run(c, s, { type: 'sow', plot: b, seed: 'seed_radish', space: 'home' });
    expect(at(s)).toBe('water_two');
    s = twoRadishes(c, guided(c));
    expect(at(s)).toBe('to_market');
    expect(s.guide?.n).toMatchObject({ 'sow:crop_radish': 2, 'water:crop_radish': 2, 'harvest:crop_radish': 2 });
  });

  it('what was done ahead of its step counts: the market walked into early passes that step at once', () => {
    const c = content();
    let s = guided(c);
    s = run(c, s, { type: 'read_inbox', keys: [], space: 'outpost', place: 'sh_market_1' });
    expect(at(s)).toBe('sow_two');
    s = run(c, s, { type: 'read_inbox', keys: [], space: 'home' });
    s = twoRadishes(c, s);
    expect(at(s)).toBe('sell_one');   // harvest_two and to_market passed by the same harvest
  });

  it('walking into a place on the state read counts (GET /v1/p0/state?space=…), as a command there would', async () => {
    const c = content();
    const store = new P0Store(c);
    const app = Fastify();
    registerP0Routes(app, { content: c, store, now: () => T0, dev: true });
    const headers = { 'x-p0-player': 'guide-route-01', 'x-p0-features': 'guide' };
    await app.inject({ method: 'GET', url: '/v1/p0/state', headers });
    const r = (await app.inject({ method: 'GET', url: '/v1/p0/state?space=outpost&place=sh_market_1', headers })).json();
    expect(r.state.guide.step).toBe('sow_two');
    expect(store.peek('guide-route-01')?.guide?.n['enter:sh_market_1']).toBe(1);
    await app.close();
  });

  it('one settle passes every step already done, ack steps take only themselves, from_step counts from the step on', () => {
    const c = content();
    let s = guided(c);
    expect(setGuide(c, s, 'sell_one', T0)).toBeNull();
    s.bag.push({ id: 'crop_radish', qty: 2 });
    s = run(c, s, { type: 'sell', item: 'crop_radish', qty: 2, space: 'home' });
    expect(at(s)).toBe('read_line');
    expect(applyP0(c, s, { type: 'guide', op: 'ack', step: 'make_soup' }, T0)).toMatchObject({ ok: false, code: 'guide_not_now' });
    s = run(c, s, { type: 'guide', op: 'ack', step: 'read_line' });
    expect(at(s)).toBe('make_soup');
    expect(applyP0(c, s, { type: 'guide', op: 'ack', step: 'read_line' }, T0)).toMatchObject({ ok: false, code: 'guide_not_now' });
    s.bag.push({ id: 'dish_grilled_crucian', qty: 1 });   // done_if: the dish in the bag, however it got there
    const [a, b, d, e] = tilled(s);
    s = run(c, s, { type: 'sow', plot: a, seed: 'seed_radish', space: 'home' });
    expect(at(s)).toBe('sow_more');   // that sow came before the step began: it does not count for it
    expect(viewOf(c, s, T0).guide.progress).toEqual({ have: 0, need: 3 });
    for (const plot of [b, d]) s = run(c, s, { type: 'sow', plot, seed: 'seed_radish', space: 'home' });
    expect(at(s)).toBe('sow_more');
    s = run(c, s, { type: 'sow', plot: e, seed: 'seed_radish', space: 'home' });
    expect(s.guide).toMatchObject({ step: null, end: 'done' });
    expect(viewOf(c, s, T0).guide).toEqual({ step: null, end: 'done' });
  });

  it('an optional step passes once the step after it is done, and never holds the player up', () => {
    const c = content({ steps: [
      { id: 'sow_one', done_on: { key: 'sow:crop_radish' } },
      { id: 'sow_rest', optional: true, done_on: { key: 'sow:crop_radish', count: 5 } },
      { id: 'water_one', done_on: { key: 'water:crop_radish' } },
      { id: 'last', done_on: { key: 'ack:last' } },
    ] });
    let s = guided(c);
    const [a] = tilled(s);
    s = run(c, s, { type: 'sow', plot: a, seed: 'seed_radish', space: 'home' });
    expect(at(s)).toBe('sow_rest');
    s = run(c, s, { type: 'water', plot: a, space: 'home' });
    expect(at(s)).toBe('last');
  });

  it('a step the table no longer has ends the guide instead of stranding the player', () => {
    const c = content();
    let s = guided(c);
    s.guide!.step = 'gone_step';
    s = run(c, s, { type: 'read_inbox', keys: [] });
    expect(s.guide).toMatchObject({ step: null, end: 'done' });
  });
});

describe('straying and healing (SGODOT-341)', () => {
  it('both radishes gone at sell_one: wait for the growing one, else sow, else buy seeds — back on the step once there is one', () => {
    const c = content();
    let s = guided(c);
    setGuide(c, s, 'sell_one', T0);
    s.bag = s.bag.filter(b => b.id !== 'crop_radish');
    expect(guideRecover(c, s, T0)).toBe('rec_sow');   // the start kit's seeds
    const [a] = tilled(s);
    s = run(c, s, { type: 'sow', plot: a, seed: 'seed_radish', space: 'home' });
    expect(guideRecover(c, s, T0)).toBe('rec_wait');
    expect(viewOf(c, s, T0).guide).toMatchObject({ step: 'sell_one', recover: 'rec_wait' });
    s = run(c, s, { type: 'water', plot: a, space: 'home' });
    s = run(c, s, { type: 'harvest', plot: a, space: 'home' }, T0 + 5 * H);
    expect(viewOf(c, s, T0 + 5 * H).guide).toMatchObject({ step: 'sell_one', recover: null });
    s.bag = s.bag.filter(b => b.id !== 'crop_radish' && b.id !== 'seed_radish');
    expect(guideRecover(c, s, T0)).toBe('rec_buy');   // nothing growing, no seeds: the last entry, which has no condition
    expect(s.guide?.step).toBe('sell_one');   // a recover entry is never saved
  });

  it('the map shows only the shown entry\'s pins while the guide is on (339 §2)', () => {
    const c = content();
    let s = guided(c);
    s = run(c, s, { type: 'read_inbox', keys: [] });
    expect(mapMarkers(c, s, T0)[0]).toEqual({ place: 'home', kind: 'request', why: { guide: 'sow_two', tracked: true } });
    expect(mapMarkers(c, s, T0).every(m => m.why.guide)).toBe(true);   // Pond Catch's pins wait while the guide is on
    setGuide(c, s, 'make_soup', T0);
    expect(mapMarkers(c, s, T0)[0]).toMatchObject({ place: 'pond_san_francisco_03', why: { guide: 'rec_fish' } });
    setGuide(c, s, 'end', T0);
    expect(mapMarkers(c, s, T0).some(m => m.why.guide)).toBe(false);
  });
});

describe('guide keys (SGODOT-341)', () => {
  const c = content();
  const keysOf = (cmd: { type: string; [k: string]: unknown } | null, events: P0Event[], s = guided(c)) => Object.fromEntries(guideKeys(c, s, s, cmd, events));
  it('names each kind of thing done', () => {
    expect(keysOf({ type: 'cast' }, [{ kind: 'cast', bite_in: 3000, rarity: 1, breaks: null, bait: null }])).toEqual({ cast: 1 });
    expect(keysOf({ type: 'reel' }, [{ kind: 'catch', fish: 'fish_crucian', rarity: 1, result: 'landed', refund: 0 }])).toEqual({ catch: 1, 'catch:fish_crucian': 1 });
    expect(keysOf({ type: 'reel' }, [{ kind: 'catch', fish: 'fish_crucian', rarity: 1, result: 'escaped', refund: 0 }])).toEqual({});
    expect(keysOf({ type: 'cook' }, [{ kind: 'pot', dish: 'dish_fish_soup', rarity: 2, ms: 5000 }])).toEqual({ cook: 1, 'cook:dish_fish_soup': 1 });
    expect(keysOf({ type: 'collect' }, [{ kind: 'dish', dish: 'dish_fish_soup', quality: 1, qty: 2, first: true, mystery: false, hits: 3 }]))
      .toEqual({ dish: 2, 'dish:dish_fish_soup': 2 });
    expect(keysOf({ type: 'eat' }, [{ kind: 'meal', dish: 'dish_fish_soup', nominal: 30, counted: 30, gain: 30, meals: 1, cap: 300 }]))
      .toEqual({ eat: 1, 'eat:dish_fish_soup': 1 });
    expect(keysOf({ type: 'gift', resident: 'res_nadia', item: 'dish_fish_soup' }, [])).toEqual({ 'gift:res_nadia': 1, 'gift:res_nadia:dish_fish_soup': 1 });
    expect(keysOf({ type: 'talk', resident: 'res_nadia' }, [])).toEqual({ 'talk:res_nadia': 1 });
    expect(keysOf({ type: 'sell' }, [{ kind: 'sale', item: 'crop_radish', qty: 1, asked: 1, coins: 9, shop: 'market', quota: null }]))
      .toEqual({ 'sell:crop_radish': 1, 'sell:crop_radish:market': 1 });
    expect(keysOf({ type: 'accept' }, [{ kind: 'request', id: 'req_res_nadia_1', status: 'accepted', coins: 0 }])).toEqual({ 'accept:req_res_nadia_1': 1 });
    expect(keysOf({ type: 'deliver' }, [{ kind: 'request', id: 'req_res_nadia_1', status: 'done', coins: 9 }])).toEqual({ 'deliver:req_res_nadia_1': 1 });
    expect(keysOf({ type: 'buy' }, [{ kind: 'item', id: 'seed_radish', delta: 3 }])).toEqual({ 'buy:seed_radish': 3 });
    expect(keysOf({ type: 'harvest' }, [{ kind: 'item', id: 'crop_radish', delta: 2 }, { kind: 'item', id: 'seed_radish', delta: 1 }]))
      .toEqual({ 'harvest:crop_radish': 2 });
  });
  it('enter counts a new space or place only, not every command made there', () => {
    const s = guided(c);
    const moved = { ...s, presence: { ...s.presence, space: 'outpost', entered: 'sh_market_1' } };
    expect(Object.fromEntries(guideKeys(c, s, moved, null, []))).toEqual({ 'enter:outpost': 1, 'enter:sh_market_1': 1 });
    expect(Object.fromEntries(guideKeys(c, moved, moved, null, []))).toEqual({});
  });
  it('keys no step counts on are not kept in the save', () => {
    let s = guided(c);
    s = run(c, s, { type: 'talk', resident: 'res_pip', space: 'outpost', place: 'sh_post_1' });
    expect(Object.keys(s.guide!.n)).toEqual([]);
  });
});

describe('follow-ups from the review of #472 (SGODOT-341)', () => {
  it('an optional step before a from_step step: the look-ahead counts from the optional step\'s start (苏烈\'s probe)', () => {
    const c = content({ steps: [
      { id: 'sow_one', done_on: { key: 'sow:crop_radish' } },
      { id: 'rest', optional: true, done_on: { key: 'sow:crop_radish', count: 5 } },
      { id: 'more', done_on: { key: 'sow:crop_radish', count: 1, from_step: true } },
      { id: 'last', done_on: { key: 'ack:last' } },
    ] });
    let s = guided(c);
    const [a, b] = tilled(s);
    s = run(c, s, { type: 'sow', plot: a, seed: 'seed_radish', space: 'home' });
    expect(at(s)).toBe('rest');   // the sow that passed sow_one does not also pass `more`: rest shows
    s = run(c, s, { type: 'sow', plot: b, seed: 'seed_radish', space: 'home' });
    expect(at(s)).toBe('last');   // one more sow is `more` done: rest and more pass together
  });

  it('a step gone from the table ends the guide at load, and the view says done meanwhile', () => {
    const c = content();
    const s = guided(c);
    s.guide!.step = 'gone_step';
    expect(viewOf(c, s, T0).guide).toEqual({ step: null, end: 'done' });
    const up = upgradeState(c, JSON.parse(JSON.stringify(s)), T0 + H);
    expect(up.guide).toMatchObject({ step: null, end: 'done', at: T0 + H });
  });

  it('a read-a-line step before the home pick is acked while the pick waits; nothing else goes through', () => {
    const c = content({ steps: [{ id: 't_city', done_on: { key: 'ack:t_city' } }, { id: 't_pin', done_on: { key: 'home_pick' } }] });
    let s = freshState(c, 'guide-pending-01', T0, 42, { guide: true, pending: true });
    expect(applyP0(c, s, { type: 'read_inbox', keys: [] }, T0)).toMatchObject({ ok: false, code: 'home_pending' });
    s = run(c, s, { type: 'guide', op: 'ack', step: 't_city' });
    expect(at(s)).toBe('t_pin');
    expect(s.travel.pending).toBe(true);
  });

  it('an optional step needs a non-optional step after it', () => {
    const c = content({ steps: [{ id: 'a', optional: true, done_on: { key: 'cast' } }, { id: 'b', optional: true, done_on: { key: 'cast' } }] });
    expect(validateGuide(c)).toEqual(['step a: an optional step needs a step after it that is not optional',
      'step b: an optional step needs a step after it that is not optional']);
  });
});

describe('the dev routes and the feature header (SGODOT-341)', () => {
  it('reset starts the guide for a client that says `guide`; dev/guide moves it; an older client\'s new save is legacy', async () => {
    const c = content();
    const app = Fastify();
    registerP0Routes(app, { content: c, store: new P0Store(c), now: () => T0, dev: true });
    const player = 'guide-route-02';
    const old = (await app.inject({ method: 'GET', url: '/v1/p0/state', headers: { 'x-p0-player': player } })).json();
    expect(old.state.guide).toEqual({ step: null, end: 'legacy' });
    const headers = { 'x-p0-player': player, 'x-p0-features': 'choose_home,guide' };
    const reset = (await app.inject({ method: 'POST', url: '/v1/p0/dev/reset', headers })).json();
    expect(reset.state.guide).toMatchObject({ step: 'sow_two' });
    expect(reset.state.home.pending).toBe(true);
    const moved = (await app.inject({ method: 'POST', url: '/v1/p0/dev/guide', headers, payload: { step: 'make_soup' } })).json();
    expect(moved.state.guide).toMatchObject({ step: 'make_soup', recover: 'rec_fish' });
    expect((await app.inject({ method: 'POST', url: '/v1/p0/dev/guide', headers, payload: { step: 'nope' } })).statusCode).toBe(400);
    const ended = (await app.inject({ method: 'POST', url: '/v1/p0/dev/guide', headers, payload: { step: 'end' } })).json();
    expect(ended.state.guide).toEqual({ step: null, end: 'done' });
    await app.close();
  });
  it('without dev mode there is no dev/guide', async () => {
    const c = content();
    const app = Fastify();
    registerP0Routes(app, { content: c, store: new P0Store(c), now: () => T0, dev: false });
    const r = await app.inject({ method: 'POST', url: '/v1/p0/dev/guide', headers: { 'x-p0-player': 'guide-route-03' }, payload: { step: 'first' } });
    expect(r.statusCode).toBe(404);
    await app.close();
  });
});

describe('the step table (SGODOT-341)', () => {
  it('the shipped table and the sample check out', () => {
    expect(validateGuide(loadP0Content())).toEqual([]);
    expect(validateGuide(content())).toEqual([]);
  });
  it('names what is wrong in a broken table', () => {
    const bad = content({
      steps: [
        { id: 'a', done_on: { key: 'jump:x' } },
        { id: 'b', marks: [{ place: 'nowhere', resident: 'res_nobody' }], tip: 'no_tip' },
        { id: 'c', done_on: { key: 'ack:a' }, needs: [{ if: { have: { no_item: 1 } }, else: ['r1', 'missing'] }] },
        { id: 'a', done_if: { coins: 1 }, needs: [{ if: { coins: 1 }, else: ['r1'] }] },
      ],
      recover: [{ id: 'r1', when: { coins: 1 } }],
    });
    expect(validateGuide(bad)).toEqual(expect.arrayContaining([
      'duplicate id a', 'step a: unknown key jump:x', 'step b: neither done_on nor done_if', 'step b: unknown tip no_tip',
      'step b: unknown place nowhere', 'step b: unknown resident res_nobody', 'step c: an ack step acks itself',
      'step c: unknown item no_item', 'step c: unknown recover missing',
      'step a: the last recover entry of a need must have no "when" (r1)',
    ]));
  });
});
