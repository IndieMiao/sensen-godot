/** SGODOT-341 PR-C-s2: the director's run of 339's v3 table (§14.3, q(215)) with the real content — the main line and
 * the ways off it; at every point the guide shows a row to do (never "nothing to do"), and it always reaches its end. */
import { describe, expect, it } from 'vitest';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { resendReady, validateGuide } from '../../src/p0/guide.js';
import { homeSetOf } from '../../src/p0/home_city.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { maxEnergy } from '../../src/p0/rules.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';
import type { P0Event } from '../../src/p0/progress.js';

const c: P0Content = loadP0Content();
const T0 = Date.UTC(2026, 9, 26, 17);   // San Francisco 10-26 10:00 PDT
const S = 1000;
const SF = 'gn-5391959', SHANGHAI = 'gn-1796236';
const ONE = 'req_res_nadia_radish', SIX = 'req_res_nadia_six_radishes';

/** One player through the guide: a clock that moves on, the state, every event, and the check after each command. */
class Run {
  s: P0State; now = T0; events: P0Event[] = [];
  constructor(player: string, opts: { pending?: boolean } = { pending: true }) {
    this.s = freshState(c, player, T0, 42, { guide: true, ...opts });
  }
  get step() { return this.s.guide!.step; }
  get view() { return viewOf(c, this.s, this.now).guide as Record<string, any>; }
  get set() { return homeSetOf(c, this.s)!; }
  do(cmd: P0Command, wait = S): this {
    this.now += wait;
    const r = applyP0(c, this.s, cmd, this.now);
    if (!r.ok) throw new Error(`${cmd.type} at ${this.step}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
    this.s = r.state; this.events.push(...r.events);
    this.check();
    return this;
  }
  /** While the guide is on, past the two pick pages, Today always has a row to do and Pip is on the farm. */
  check() {
    const v = this.view;
    if (v.step === null || v.step === 't_city' || v.step === 't_pin') return;
    expect(v.row?.line, `${v.step}/${v.recover}`).toMatch(/\S/);
    expect(v.row.line, v.step).not.toMatch(/\{/);   // every name filled
    expect(v.pip.here).toBe(true);
  }
  tilled(n: number) { return this.s.plots.filter(p => p.state === 'tilled' && !p.crop).slice(0, n).map(p => p.id); }
  qty(prefix: string) { return this.s.bag.filter(x => x.id.startsWith(prefix)).reduce((n, x) => n + x.qty, 0); }
  pick(city = SF) { return this.do({ type: 'guide', op: 'ack', step: 't_city', space: 'home' }).do({ type: 'choose_home', city, spot: 0, space: 'home' }); }
  sowQuick() {
    const plots = this.tilled(2);
    for (const plot of plots) this.do({ type: 'sow', plot, seed: 'seed_quick_radish', space: 'home' });
    for (const plot of plots) this.do({ type: 'water', plot, space: 'home' });
    return plots;
  }
  lettuce() { for (const plot of this.tilled(10)) this.do({ type: 'sow', plot, seed: 'seed_lettuce', space: 'home' }); return this; }
  harvest(plots: number[]) { this.now += 46 * S; for (const plot of plots) this.do({ type: 'harvest', plot, space: 'home' }); return this; }
  market() { return { space: 'outpost', place: this.set.market }; }
  nadia1() { return this.do({ type: 'talk', resident: 'res_nadia', ...this.market() }).do({ type: 'accept', request: ONE, ...this.market() })
    .do({ type: 'deliver', request: ONE, ...this.market() }); }
  fish(n: number) {
    const at = { space: 'pond', place: this.set.pond };
    for (let i = 0; i < n; i++) {
      this.do({ type: 'cast', ...at }, 60 * S);
      this.do({ type: 'reel', outcome: 'landed', ...at }, this.s.cast!.bite_ms + S);
    }
    return this;
  }
  cook(items: string[], eat = false) {
    this.do({ type: 'cook', items, space: 'home' });
    return this.do({ type: 'collect', ...(eat ? { eat: true } : {}), space: 'home' }, this.s.stove!.ms + S);
  }
  gift(prefix: string) {
    const item = this.s.bag.find(x => x.id.startsWith(prefix))!.id;
    return this.do({ type: 'gift', resident: 'res_nadia', item, ...this.market() });
  }
}

describe('the v3 table (339 §14.3)', () => {
  it('is valid, has S0–S11 and no S12, and keeps Pond Catch off a guided save', () => {
    expect(validateGuide(c)).toEqual([]);
    expect(c.guide!.steps.map(s => s.id)).toEqual(['t_city', 't_pin', 't_sow_quick', 't_water', 't_sow_rest', 't_harvest_quick',
      't_nadia_1', 't_fish', 't_meal', 't_soup', 't_gift', 't_nadia_2']);
    const r = new Run('director-pond-catch');
    expect(r.s.requests).toEqual([]);
    expect(r.qty('seed_quick_radish')).toBe(2);
  });
});

describe('the main line (§14.2)', () => {
  it('S0 → S11 in order, every row on the way, and the end: Pip gone, the first stall slot 4 h after Nadia\'s radish', () => {
    const r = new Run('director-main-01');
    const seen: string[] = [];
    const note = () => { if (seen[seen.length - 1] !== r.step) seen.push(r.step ?? 'end'); };
    note();
    r.pick(); note();
    expect(r.view).toMatchObject({ row: { line: 'Sow 2 Quick Radishes' }, pip: { bang: true } });
    r.do({ type: 'talk', resident: 'res_pip', space: 'home' });
    expect(r.view.pip.bang).toBe(false);
    const quick = r.sowQuick(); note();
    expect(r.view.row.line).toBe('Sow 10 Lettuce · 20 Energy');
    r.lettuce(); note();
    expect(r.view).toMatchObject({ step: 't_harvest_quick', recover: 'r_quick_wait',
      row: { line: 'Quick Radishes ready', countdown: 'crop_quick_radish', count: 2, format: 'mss' }, progress: { have: 0, need: 1 } });
    expect(r.view.row.ready_in).toBeGreaterThan(0);
    expect(r.view.row.ready_in).toBeLessThanOrEqual(45_000);
    r.now += 46 * S; r.check();
    expect(r.view.marks).toEqual([{ plot: quick[0] }, { plot: quick[1] }, { button: 'harvest', pulse: true }]);
    r.now -= 46 * S;
    r.harvest(quick); note();
    expect(r.view.marks.map((m: any) => m.button).filter(Boolean)).toEqual(['request', 'location']);
    expect(r.view.row).toEqual({ line: 'Bring Nadia 1 Radish · Mission Market Square', icon: 'crop_radish', go: 'sh_market_1' });
    r.nadia1(); note();
    const delivered = r.now;
    expect(r.s.boards.stall[0].refill_at).toBe(delivered + c.requests.done_refill_h * 3_600_000);
    expect(r.view.marks[0]).toMatchObject({ place: 'pond_san_francisco_03', why: 'Catch 2 fish · 0/2' });
    expect(r.view.marks[1]).toEqual({ button: 'cast', pulse: true });
    r.fish(1);
    expect(r.view.marks[0].why).toBe('Catch 2 fish · 1/2');
    r.fish(1); note();
    expect(r.view.row.line).toBe('Cook it: Grilled Crucian');
    r.cook(['fish_crucian'], true); note();
    expect(r.view.row.line).toBe('Cook: Fresh Fish Soup · new recipe');
    expect(r.view.marks).toEqual([{ place: 'home', object: 'farmhouse', kind: 'request' }, { object: 'stove', pulse: true },
      { page: 'dish_fish_soup', button: 'cook', pulse: true }]);
    r.cook(['fish_crucian', 'crop_radish']); note();
    expect(r.view.marks.find((m: any) => m.resident)).toEqual({ resident: 'res_nadia', kind: 'gift' });
    expect(r.view.marks.find((m: any) => m.button === 'gift')).toEqual({ button: 'gift', pulse: true });
    expect(r.view.marks.find((m: any) => m.item)).toEqual({ item: 'dish_fish_soup', pulse: true });   // the Gift drawer's soup cell
    r.gift('dish_fish_soup'); note();
    expect(r.view.row.line).toBe("See Nadia's new request");
    r.do({ type: 'accept', request: SIX, ...r.market() }); note();
    expect(seen).toEqual(['t_city', 't_sow_quick', 't_sow_rest', 't_harvest_quick', 't_nadia_1', 't_fish', 't_meal',
      't_soup', 't_gift', 't_nadia_2', 'end']);
    // the observation log's view (§14.8.1): every step change, in order, from the commands' events
    const moves = r.events.filter(e => e.kind === 'guide' && e.action !== 'resend').map(e => (e as { to: string | null }).to ?? 'end');
    expect(moves).toEqual(['t_pin', 't_sow_quick', 't_water', 't_sow_rest', 't_harvest_quick', 't_nadia_1', 't_fish', 't_meal', 't_soup',
      't_gift', 't_nadia_2', 'end']);
    expect(r.s.guide).toMatchObject({ step: null, end: 'done' });
    expect(r.view).toMatchObject({ step: null, end: 'done', pip: { here: false } });
    expect(r.events.filter(e => e.kind === 'guide' && e.action === 'end')).toHaveLength(1);
  });
});

describe('off the path', () => {
  it('no lettuce: S4 passes once the Quick Radishes are ripe (it never holds the player up)', () => {
    const r = new Run('director-skip-lettuce').pick();
    const quick = r.sowQuick();
    expect(r.step).toBe('t_sow_rest');
    r.now += 46 * S;
    r.do({ type: 'talk', resident: 'res_pip', space: 'home' }, 0);
    expect(r.step).toBe('t_harvest_quick');
    expect(r.view.recover).toBeNull();
    r.harvest(quick);
    expect(r.step).toBe('t_nadia_1');
  });
  it('fishing first: the two fish count, so S7 passes the moment Nadia has her radish', () => {
    const r = new Run('director-fish-first').pick();
    r.harvest(r.sowQuick());
    r.fish(2);
    expect(r.step).toBe('t_nadia_1');
    r.nadia1();
    expect(r.step).toBe('t_meal');
  });
  it('both radishes gone twice: Pip gives two seeds each time; the third time Today says sow a Radish', () => {
    const r = new Run('director-resend').pick();
    r.harvest(r.sowQuick());
    for (const nth of [1, 2]) {
      r.s.bag = r.s.bag.filter(x => x.id !== 'crop_radish');   // sold, eaten — gone
      r.check();
      expect(r.view).toMatchObject({ recover: 'r_radish_sow', pip: { bang: true } });
      expect(resendReady(c, r.s)).toBe(true);
      r.do({ type: 'talk', resident: 'res_pip', space: 'home' });
      expect(r.qty('seed_quick_radish')).toBe(2);
      expect(r.s.guide!.n.resend).toBe(nth);
      const plots = r.sowQuick();
      // the resent quick ones growing: their own countdown, not a Radish's (苏烈 on #506)
      expect(r.view).toMatchObject({ recover: 'r_quick_regrow', row: { line: 'Quick Radishes ready', countdown: 'crop_quick_radish', count: 2, format: 'mss' },
        pip: { line: 'They grow fast!' } });   // Pip says what the recover row says (q(260))
      expect(r.view.row.ready_in).toBeGreaterThan(0);
      r.now += 46 * S;
      r.check();
      expect(r.view).toMatchObject({ recover: 'r_quick_ripe', row: { line: 'Harvest 2 Quick Radishes' },
        pip: { line: "They're ready! Nadia at the market loves fresh radishes. Take her one." } });   // S6's own (q(260))
      expect(r.view.marks.at(-1)).toEqual({ button: 'harvest', pulse: true });   // as S5
      r.now -= 46 * S;
      r.harvest(plots);
      expect(r.view.recover).toBeNull();
    }
    r.s.bag = r.s.bag.filter(x => x.id !== 'crop_radish');
    r.do({ type: 'talk', resident: 'res_pip', space: 'home' });
    expect(r.qty('seed_quick_radish')).toBe(0);
    expect(r.view).toMatchObject({ recover: 'r_radish_sow', row: { line: 'Sow 1 Radish · 2 Energy' },
      pip: { bang: false, resend_left: 0, line: 'No quick ones left. Plant a regular radish. That one takes a few hours.' } });
    expect(r.view.marks).toEqual([{ plot: r.tilled(1)[0] }, { button: 'sow', pulse: true }]);   // one plot's halo (q(229)); the Sow key as S2 (341 9826e069)
    const plot = r.tilled(1)[0];
    r.do({ type: 'sow', plot, seed: 'seed_radish', space: 'home' }).do({ type: 'water', plot, space: 'home' });
    expect(r.view).toMatchObject({ recover: 'r_radish_wait', row: { line: 'Radish ready', countdown: 'crop_radish', count: 1, format: 'minutes' },
      pip: { line: "Off you go! I'll keep an eye on your plots." } });
    expect(r.view.row.ready_in).toBeGreaterThan(3 * 3_600_000);
  });
  it('q(254): the resent seeds in the Inbox — Claim Pip\'s seeds, Pip says so; in hand — Sow 2 / Sow 1 Quick Radish', () => {
    const r = new Run('director-resend-inbox').pick();
    r.harvest(r.sowQuick());
    r.s.bag = r.s.bag.filter(x => x.id !== 'crop_radish');
    // a full bag of things that are neither a Radish nor a Common crop (they would stop the resend)
    const kept = r.s.bag.map(x => ({ ...x }));
    for (const id of [...c.fish.map(f => f.id), ...Object.keys(c.goods)]) if (r.s.bag.length < r.s.bag_cap) r.s.bag.push({ id, qty: 1 });
    r.do({ type: 'talk', resident: 'res_pip', space: 'home' });
    const parcel = r.s.inbox.parcels.find(p => p.id === 'seed_quick_radish')!;
    expect(parcel.source).toBe("Pip's seeds");
    expect(r.view).toMatchObject({ step: 't_nadia_1', recover: 'r_seeds_inbox', row: { line: "Claim Pip's seeds · Inbox", icon: 'seed_quick_radish', go: 'inbox' },
      marks: [], pip: { bang: false, line: 'Your bag was full, so I left two quick ones in your Inbox.', resend_left: 1 } });
    r.s.bag = kept;   // room made (Parcels' Make room)
    r.do({ type: 'claim_parcel', key: parcel.key });
    expect(r.qty('seed_quick_radish')).toBe(2);
    const sow = { recover: 'r_quick_sow', row: { line: 'Sow 2 Quick Radishes', icon: 'seed_quick_radish', go: 'home' } };
    expect(r.view).toMatchObject({ ...sow, pip: { bang: false, line: 'These quick radishes are ready in no time. Plant them here!' } });   // q(260)
    expect(r.view.marks).toEqual([...r.tilled(2).map(plot => ({ plot })), { button: 'sow', pulse: true }]);   // as S2
    // a Radish sown meanwhile (4 h) does not hide the quick ones still in hand
    const slow = r.tilled(1)[0];
    r.do({ type: 'sow', plot: slow, seed: 'seed_radish', space: 'home' }).do({ type: 'water', plot: slow, space: 'home' });
    expect(r.view).toMatchObject(sow);
    // one of the two sown and harvested: the one left
    const one = r.tilled(1)[0];
    r.do({ type: 'sow', plot: one, seed: 'seed_quick_radish', space: 'home' }).do({ type: 'water', plot: one, space: 'home' });
    expect(r.view.recover).toBe('r_quick_regrow');
    r.harvest([one]);
    r.s.bag = r.s.bag.filter(x => x.id !== 'crop_radish');
    r.check();
    expect(r.view).toMatchObject({ recover: 'r_quick_sow_1', row: { line: 'Sow 1 Quick Radish' }, pip: { line: 'This quick radish is ready in no time. Plant it here!' } });
    expect(r.view.marks).toEqual([{ plot: r.tilled(1)[0] }, { button: 'sow', pulse: true }]);
    // none left, one resend left: back to Pip's ! (Radish ready: the slow one still growing)
    r.s.bag = r.s.bag.filter(x => x.id !== 'seed_quick_radish');
    r.check();
    expect(r.view).toMatchObject({ recover: 'r_radish_wait', pip: { bang: true } });
  });
  it('q(254) at S9: the soup still to make, the resent seeds in the Inbox, then in hand', () => {
    const r = new Run('director-soup-inbox').pick();
    r.harvest(r.sowQuick());
    r.nadia1().fish(2);
    r.s.energy.value = 100;
    r.cook(['fish_crucian'], true);
    expect(r.step).toBe('t_soup');
    r.s.bag = r.s.bag.filter(x => x.id !== 'crop_radish');
    const kept = r.s.bag.map(x => ({ ...x }));
    for (const id of [...c.fish.map(f => f.id), ...Object.keys(c.goods)]) if (r.s.bag.length < r.s.bag_cap) r.s.bag.push({ id, qty: 1 });
    expect(r.s.bag.length).toBe(r.s.bag_cap);
    r.do({ type: 'talk', resident: 'res_pip', space: 'home' });
    expect(r.view).toMatchObject({ step: 't_soup', recover: 'r_seeds_inbox', pip: { bang: false } });
    r.s.bag = kept;
    r.do({ type: 'claim_parcel', key: r.s.inbox.parcels.find(p => p.id === 'seed_quick_radish')!.key });
    expect(r.view).toMatchObject({ step: 't_soup', recover: 'r_quick_sow', row: { line: 'Sow 2 Quick Radishes' } });
  });
  it('the soup still to make, no crop held, the resent quick ones growing: their countdown at S9 too (苏烈 on #506)', () => {
    const r = new Run('director-soup-regrow').pick();
    r.harvest(r.sowQuick());
    r.nadia1().fish(2);
    r.s.energy.value = 100;
    r.cook(['fish_crucian'], true);
    expect(r.step).toBe('t_soup');
    r.s.bag = r.s.bag.filter(x => x.id !== 'crop_radish');
    r.check();
    expect(r.view.pip.bang).toBe(true);
    r.do({ type: 'talk', resident: 'res_pip', space: 'home' });
    r.sowQuick();
    expect(r.view).toMatchObject({ step: 't_soup', recover: 'r_quick_regrow', row: { countdown: 'crop_quick_radish', count: 2 }, pip: { line: 'They grow fast!' } });
    expect(r.view.row.ready_in).toBeGreaterThan(0);
    // ripe at S9: the soup's own line (q(260)), S6's harvest row and marks
    r.now += 46 * S;
    r.check();
    expect(r.view).toMatchObject({ step: 't_soup', recover: 'r_quick_ripe_soup', row: { line: 'Harvest 2 Quick Radishes' },
      pip: { line: "They're ready! Pick them for the soup." } });
    expect(r.view.marks.at(-1)).toEqual({ button: 'harvest', pulse: true });
  });
  it('a full bar at S8 skips the meal; the soup eaten before Nadia sends Today back to cooking, then to the pond', () => {
    const r = new Run('director-full-bar').pick();
    r.harvest(r.sowQuick());
    r.nadia1().fish(2);
    expect(r.step).toBe('t_meal');
    r.s.energy.value = maxEnergy(c, r.s);
    r.do({ type: 'talk', resident: 'res_pip', space: 'home' });
    expect(r.step).toBe('t_soup');
    r.cook(['fish_crucian', 'crop_radish']);
    expect(r.step).toBe('t_gift');
    r.s.energy.value = 100;
    const soup = r.s.bag.find(x => x.id.startsWith('dish_fish_soup'))!.id;
    r.do({ type: 'eat', item: soup, space: 'home' });
    expect(r.view.recover).toBe('r_cook_grill');   // one crucian left, no crop: grill it
    expect(r.view.row.line).toBe('Cook it: Grilled Crucian');
    r.s.bag = r.s.bag.filter(x => !x.id.startsWith('fish_'));
    r.check();
    expect(r.view).toMatchObject({ recover: 'r_fish_1', row: { line: 'Catch 1 fish · Fern Pond' } });
    expect(r.view.marks[1]).toEqual({ button: 'cast', pulse: true });   // as S7
    expect(r.view.marks[0].why).toBe('Catch 1 fish · 0/1');
    r.fish(1);
    expect(r.view.recover).toBe('r_cook_grill');
    r.cook(['fish_crucian']);
    expect(r.view.recover).toBeNull();
    r.gift('dish_grilled_crucian');   // any edible dish will do (S10)
    expect(r.step).toBe('t_nadia_2');
  });
  // SGODOT-368 (不知火舞's spec): a dish cooked and kept, not eaten, used to leave S8 on `Cook it`. The real flow: collect
  // (the dish goes to the cabinet or the bag; the card's Keep sends nothing), then Eat where it lies.
  const s8 = (player: string) => { const r = new Run(player).pick(); r.harvest(r.sowQuick()); r.nadia1().fish(2); r.s.energy.value = 100; r.check(); return r; };
  const EAT_PIP = "Eat it while it's warm. A meal brings your Energy back.";
  it('S8, kept to the bag: Eat it with the bag\'s cell and Eat pulsing; eaten from the bag, S8 passes', () => {
    const r = s8('director-s8-bag');
    expect(r.view.row.line).toBe('Cook it: Grilled Crucian');
    r.cook(['fish_crucian']);   // collect without eat: the card's Keep
    const kept = r.s.bag.find(x => x.id.startsWith('dish_grilled_crucian'));
    expect(kept).toBeDefined();
    expect(r.step).toBe('t_meal');
    expect(r.view).toMatchObject({ recover: 'r_eat_bag', row: { line: 'Eat it: Grilled Crucian', icon: 'dish_grilled_crucian', go: 'bag' },
      pip: { line: EAT_PIP } });
    expect(r.view.marks).toEqual([{ item: 'dish_grilled_crucian', pulse: true }, { button: 'eat', item: 'dish_grilled_crucian', pulse: true }]);
    r.do({ type: 'eat', item: kept!.id, space: 'pond', place: r.set.pond });   // the bag eats anywhere
    expect(r.step).toBe('t_soup');
  });
  it('S8, kept to the Warming Cabinet: home, the cabinet and its row pulse; eaten from the cabinet, S8 passes', () => {
    const r = s8('director-s8-cabinet');
    r.s.homestead.level = 3;   // the Warming Cabinet (Lv3): Keep fills it before the bag
    r.cook(['fish_crucian']);
    expect(r.s.cabinet.map(x => x.id.split('@')[0])).toContain('dish_grilled_crucian');
    expect(r.view).toMatchObject({ recover: 'r_eat_cabinet', row: { line: 'Eat it: Grilled Crucian', go: 'home' }, pip: { line: EAT_PIP } });
    expect(r.view.marks).toEqual([{ place: 'home', object: 'farmhouse', kind: 'request' }, { object: 'cabinet', pulse: true },
      { item: 'dish_grilled_crucian', pulse: true }, { button: 'eat', item: 'dish_grilled_crucian', pulse: true }]);
    const id = r.s.cabinet.find(x => x.id.startsWith('dish_grilled_crucian'))!.id;
    r.do({ type: 'eat', item: id, from: 'cabinet', space: 'home' });
    expect(r.step).toBe('t_soup');
  });
  it('S8, a done pot not yet taken: the stove and the card\'s Eat; taken and kept it moves to the bag\'s entry', () => {
    const r = s8('director-s8-pot');
    r.do({ type: 'cook', items: ['fish_crucian'], space: 'home' });
    expect(r.view.recover).toBeNull();   // still cooking: Cook it, the stove as before
    r.now += r.s.stove!.ms + S; r.check();
    expect(r.view).toMatchObject({ recover: 'r_eat_pot', row: { line: 'Eat it: Grilled Crucian', go: 'home' }, pip: { line: EAT_PIP } });
    expect(r.view.marks.slice(1)).toEqual([{ object: 'stove', pulse: true }, { button: 'eat', item: 'dish_grilled_crucian', pulse: true }]);
    r.do({ type: 'collect', space: 'home' });
    expect(r.view.recover).toBe('r_eat_bag');
    r.do({ type: 'eat', item: r.s.bag.find(x => x.id.startsWith('dish_grilled_crucian'))!.id, space: 'home' });
    expect(r.step).toBe('t_soup');
  });
  it('S8 eats a dish where it is quickest: the bag before a done pot before the Warming Cabinet', () => {
    const r = s8('director-s8-where');
    r.s.homestead.level = 3;
    r.s.bag.push({ id: 'dish_grilled_crucian', qty: 1 });
    r.s.cabinet.push({ id: 'dish_grilled_crucian', qty: 1 } as never); r.check();
    expect(r.view.recover).toBe('r_eat_bag');   // the bag and the cabinet: the bag (eaten anywhere)
    r.do({ type: 'cook', items: ['fish_crucian'], space: 'home' });
    r.now += r.s.stove!.ms + S; r.check();
    expect(r.view.recover).toBe('r_eat_bag');   // the bag and a done pot: the bag
    r.s.bag = r.s.bag.filter(x => !x.id.startsWith('dish_')); r.check();
    expect(r.view.recover).toBe('r_eat_pot');   // a done pot and the cabinet: the pot
  });
  it('S8 picks the dish: Grilled Crucian first, else another dish, the soup only with no fish left; a full bar still passes', () => {
    const r = s8('director-s8-pick');
    r.s.bag.push({ id: 'dish_veggie_plate', qty: 1 }); r.check();
    expect(r.view).toMatchObject({ recover: 'r_eat_bag', row: { line: 'Eat it: Veggie Plate', icon: 'dish_veggie_plate' } });
    r.s.cabinet.push({ id: 'dish_grilled_crucian', qty: 1 } as never); r.check();
    expect(r.view).toMatchObject({ recover: 'r_eat_cabinet', row: { line: 'Eat it: Grilled Crucian' } });   // preferred, though in the cabinet
    r.s.cabinet = []; r.s.bag = r.s.bag.filter(x => !x.id.startsWith('dish_'));
    r.s.bag.push({ id: 'dish_fish_soup', qty: 1 }); r.check();
    expect(r.view).toMatchObject({ recover: null, row: { line: 'Cook it: Grilled Crucian' } });   // a fish left: grill it, keep the soup
    r.s.bag = r.s.bag.filter(x => !x.id.startsWith('fish_')); r.check();
    expect(r.view).toMatchObject({ recover: 'r_eat_bag', row: { line: 'Eat it: Fresh Fish Soup' } });
    r.s.energy.value = maxEnergy(c, r.s);
    r.do({ type: 'talk', resident: 'res_pip', space: 'home' });
    expect(r.step).toBe('t_soup');
  });
  it('no fish at S8 before the soup: Catch 2 fish, counted 1/2, 2/2', () => {
    const r = new Run('director-two-fish').pick();
    r.harvest(r.sowQuick());
    r.nadia1().fish(2);
    r.s.energy.value = 100;
    r.s.bag = r.s.bag.filter(x => !x.id.startsWith('fish_'));
    r.check();
    expect(r.view).toMatchObject({ recover: 'r_fish_2', row: { line: 'Catch 2 fish · Fern Pond' }, progress: { have: 0, need: 2 } });
    expect(r.view.marks[1]).toEqual({ button: 'cast', pulse: true });
    r.fish(1);   // bite 3: a Pond Crucian (teaching pin 1)
    expect(r.view).toMatchObject({ recover: 'r_fish_2', progress: { have: 1, need: 2 } });
    expect(r.view.marks[0].why).toBe('Catch 2 fish · 1/2');
    r.s.bag.push({ id: 'fish_carp', qty: 1 });   // bite 4 would break free at Fishing Lv1 (pin 2): the second fish from the bag
    r.check();
    expect(r.view.recover).toBeNull();
    expect(r.step).toBe('t_meal');
  });
  it('a Mystery Dish given to Nadia does not count (S10)', () => {
    const r = new Run('director-mystery').pick();
    r.harvest(r.sowQuick());
    r.nadia1().fish(2);
    r.s.guide!.step = 't_gift';
    r.s.bag.push({ id: 'dish_mystery', qty: 1 });
    r.check();
    r.gift('dish_mystery');
    expect(r.step).toBe('t_gift');
  });
  it('another home city: the marks, names and places are Shanghai\'s, and the line runs the same', () => {
    const r = new Run('director-shanghai').pick(SHANGHAI);
    const set = r.set;
    expect(set.market).not.toBe('sh_market_1');
    r.harvest(r.sowQuick());
    expect(r.view.row.go).toBe(set.market);
    expect(r.view.row.line).not.toContain('Mission');
    r.nadia1();
    expect(r.view.row.go).toBe(set.pond);
    r.fish(2);
    expect(r.step).toBe('t_meal');
  });
  it('left alone: the guide ends at the second home-day rollover, the first stall slot filled, Pip gone', () => {
    const r = new Run('director-left-alone').pick();
    r.sowQuick();
    r.now = Date.UTC(2026, 9, 28, 11, 1);   // 10-28 04:01 PDT: the second rollover after 10-26
    r.do({ type: 'talk', resident: 'res_pip', space: 'home' }, 0);
    expect(r.s.guide).toMatchObject({ step: null, end: 'timeout' });
    expect(r.view.pip.here).toBe(false);
    expect(r.s.boards.stall[0].refill_at).toBeLessThanOrEqual(r.now);
  });
});
