/** The card room's cap (q(320): the user 11-13, via 奕星 — v3 丙, the day's loss alone; the user 11-13 「牌室 C」 kept the
 *  room in the store builds): no deal that could take the day's net past −50 by its own stake, Double and Split
 *  unchecked; under the table minimum left the table closes till the rollover; no cap on a stake or the day's win. */
import { afterEach, describe, expect, it } from 'vitest';
import { BJ_CHIPS, bjCaps, bjShoe, shuffleShoe } from '../../src/p0/blackjack.js';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { dayKey, rolloverAfter } from '../../src/p0/rules.js';
import { freshState, upgradeState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 28, 2, 0, 0);
const H = 3_600_000;
const AT = { space: 'outpost', place: 'sf_card_room_1' } as const;
const shipped = { ...bjCaps };

const card = (code: string) => 'SHDC'.indexOf(code[1]) * 13 + 'A23456789TJQK'.indexOf(code[0]);
/** The shoe in dealing order (player, dealer up, player, dealer hole), then 2S 3H 2D 3C … of the second deck. */
function stack(...codes: string[]) {
  const top = codes.map(card);
  bjShoe.make = () => [...top, ...Array.from({ length: 60 }, (_, i) => card(['2S', '3H', '2D', '3C'][i % 4]) + 52)];
}
afterEach(() => { Object.assign(bjCaps, shipped); bjShoe.make = (p, n, salt) => shuffleShoe(p, n, salt); });

/** A player at the table with `coins`, today's card-room net already `net`. */
function player(net = 0, coins = 2000): P0State {
  const s = upgradeState(c, { ...freshState(c, 'player-bj-caps-1', T0, 7), created_at: T0 - 8 * 24 * H }, T0);
  s.homestead.level = 2;
  delete s.guide;
  s.coins = coins;
  s.day.key = dayKey(c, s, T0);
  s.day.bj_net = net;
  return s;
}
const run = (s: P0State, cmd: Record<string, unknown>, now = T0) => applyP0(c, s, { ...AT, ...cmd } as unknown as P0Command, now);
function ok(s: P0State, cmd: Record<string, unknown>, now = T0): P0State {
  const r = run(s, cmd, now);
  if (!r.ok) throw new Error(`${String(cmd.type)}: ${r.code}`);
  return r.state;
}

describe('the card room cap (q(320) v3 丙, the day\'s loss of 50)', () => {
  it('ships as the user set it: no stake cap, 50 a day lost, no win cap, the deal kept inside the day', () => {
    expect(shipped).toEqual({ maxBet: null, dayLoss: 50, dayWin: null, mode: 'mid' });
    expect(viewOf(c, player(), T0).blackjack).toMatchObject({ chips: BJ_CHIPS, max_bet: null, max_deal: 50,
      day: { net: 0, loss: 50, win: null, capped: null } });
  });

  it("a deal may stake what the day's loss has left, in fives: 50 at the day's start, 10 at −38; over it bj_day_cap with what is left", () => {
    stack('TS', '7H', '9S', '9D');
    expect(ok(player(), { type: 'bj_deal', bet: 50 }).blackjack?.hand?.seats[0].bet).toBe(50);
    expect(run(player(), { type: 'bj_deal', bet: 55 })).toMatchObject({ ok: false, code: 'bj_day_cap', detail: { cap: 'loss', net: 0, left: 50 } });
    expect(viewOf(c, player(-38), T0).blackjack.max_deal).toBe(10);
    expect(run(player(-38), { type: 'bj_deal', bet: 15 })).toMatchObject({ ok: false, code: 'bj_day_cap', detail: { cap: 'loss', net: -38, left: 10 } });
    stack('TS', '7H', '9S', '9D');
    expect(run(player(-38), { type: 'bj_deal', bet: 10 }).ok).toBe(true);
  });

  it('ahead on the day, more may be staked: +200 leaves 250; no win closes the table', () => {
    expect(viewOf(c, player(200), T0).blackjack.max_deal).toBe(250);
    stack('TS', '7H', '9S', '9D');
    expect(run(player(200), { type: 'bj_deal', bet: 250 }).ok).toBe(true);
    expect(viewOf(c, player(10_000), T0).blackjack.day.capped).toBeNull();
  });

  it('Double and Split stay unchecked: 50 split and lost twice at the day\'s start is −100; then the table is closed', () => {
    stack('8S', 'TH', '8D', '9C');   // 8 8 against T 9: split, the hands take 2 and 3 (10 and 11), both stand, both lose
    let s = ok(player(), { type: 'bj_deal', bet: 50 });
    s = ok(s, { type: 'bj_act', action: 'split' });
    s = ok(s, { type: 'bj_act', action: 'stand' });
    s = ok(s, { type: 'bj_act', action: 'stand' });
    expect(s.day.bj_net).toBe(-100);
    expect(run(s, { type: 'bj_deal', bet: 5 })).toMatchObject({ ok: false, code: 'bj_day_cap', detail: { cap: 'loss', net: -100 } });
  });

  it('under the table minimum left the table closes, before the coins are looked at, with when it opens again', () => {
    const at = player(-46, 41);
    const resets = rolloverAfter(c, at, dayKey(c, at, T0));
    expect(run(at, { type: 'bj_deal', bet: 5 })).toMatchObject({ ok: false, code: 'bj_day_cap', detail: { cap: 'loss', net: -46, resets_at: resets } });
    expect(viewOf(c, at, T0).blackjack.day).toMatchObject({ capped: 'loss', resets_at: resets });
    expect(viewOf(c, at, T0).blackjack.max_deal).toBe(0);
    expect(viewOf(c, player(-45), T0).blackjack.day.capped).toBeNull();
  });

  it("the last bet comes back at what is left; the hand in play plays on; the rollover starts the day over", () => {
    const s = player(-30);
    s.blackjack = { n: 9, last_bet: 500 };
    expect(viewOf(c, s, T0).blackjack.last_bet).toBe(20);
    stack('TS', '9H', '6S', '9D');
    const playing = ok(player(-45), { type: 'bj_deal', bet: 5 });
    playing.day.bj_net = -50;   // reached while this hand is out: the cap guards new hands only
    expect(run(playing, { type: 'bj_act', action: 'stand' }).ok).toBe(true);
    const lost = player(-60);
    const tomorrow = rolloverAfter(c, lost, dayKey(c, lost, T0)) + 60_000;
    expect(viewOf(c, lost, tomorrow).blackjack).toMatchObject({ max_deal: 50, day: { net: 0, capped: null } });
  });

  it('the switches still hold: a stake cap drops the chips over it; `line` looks at the net only; a win cap closes the table', () => {
    Object.assign(bjCaps, { maxBet: 20, dayLoss: 50, dayWin: 50, mode: 'line' });
    expect(viewOf(c, player(), T0).blackjack).toMatchObject({ chips: [5, 10], max_bet: 20, max_deal: 20 });
    expect(run(player(), { type: 'bj_deal', bet: 25 })).toMatchObject({ ok: false, code: 'bj_max_bet', detail: { max: 20 } });
    stack('TS', '7H', '9S', '9D');
    expect(run(player(-45), { type: 'bj_deal', bet: 20 }).ok).toBe(true);   // line: −45 may stake 20
    expect(run(player(50), { type: 'bj_deal', bet: 5 })).toMatchObject({ ok: false, code: 'bj_day_cap', detail: { cap: 'win' } });
  });
});
