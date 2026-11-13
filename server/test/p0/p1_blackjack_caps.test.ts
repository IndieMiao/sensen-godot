/** The card room's caps (q(320), the user's numbers pending; the user 11-13 「牌室 C」 kept the room in the store
 *  builds). Tested at 奕星's review's recommended 20 / 50 / 50: a deal's stake at most, and no new hand once the day's
 *  net has reached its loss or its win (`line`); the hand in play plays on, the rollover starts the net over; `mid`
 *  keeps the deal itself inside the day's loss. */
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { bjCaps, bjShoe, shuffleShoe } from '../../src/p0/blackjack.js';
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
beforeEach(() => Object.assign(bjCaps, { maxBet: 20, dayLoss: 50, dayWin: 50, mode: 'line' }));
afterEach(() => { Object.assign(bjCaps, shipped); bjShoe.make = (p, n, salt) => shuffleShoe(p, n, salt); });

/** A player at the table with `coins`, today's card-room net already `net`. */
function player(net = 0, coins = 1000): P0State {
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

describe('the card room caps (q(320), line)', () => {
  it('a deal at most 20 (25 and 30 refused); the chips up to it are 5 and 10; the view says so', () => {
    stack('TS', '7H', '9S', '9D');
    expect(ok(player(), { type: 'bj_deal', bet: 20 }).blackjack?.hand?.seats[0].bet).toBe(20);
    for (const bet of [25, 30]) expect(run(player(), { type: 'bj_deal', bet })).toMatchObject({ ok: false, code: 'bj_max_bet', detail: { max: 20 } });
    expect(viewOf(c, player(), T0).blackjack).toMatchObject({ chips: [5, 10], max_bet: 20, max_deal: 20 });
  });

  it("a test phase's last bet over the cap comes back at the cap, so the first Deal after the update is taken", () => {
    const s = player();
    s.blackjack = { n: 9, last_bet: 500 };
    expect(viewOf(c, s, T0).blackjack.last_bet).toBe(20);
    s.blackjack.last_bet = 10;
    expect(viewOf(c, s, T0).blackjack.last_bet).toBe(10);
  });

  it("no new hand at −50 (closed before the coins are looked at), with when it opens again; at −45 one more", () => {
    const at = player(-50, 41);   // 1 coin over the floor: the closed table is what it says
    const resets = rolloverAfter(c, at, dayKey(c, at, T0));
    expect(run(at, { type: 'bj_deal', bet: 30 })).toMatchObject({ ok: false, code: 'bj_day_cap',
      detail: { cap: 'loss', net: -50, loss: 50, win: 50, resets_at: resets } });
    expect(viewOf(c, at, T0).blackjack.day).toEqual({ net: -50, loss: 50, win: 50, capped: 'loss', resets_at: resets });
    stack('TS', '7H', '9S', '9D');
    expect(run(player(-45), { type: 'bj_deal', bet: 20 }).ok).toBe(true);
  });

  it('a split of 20 lost twice at −45 is −85, both hands in the net at once; the next deal is refused', () => {
    stack('8S', 'TH', '8D', '9C');   // 8 8 against T 9: split, the hands take 2 and 3 (10 and 11), both stand, both lose
    let s = ok(player(-45), { type: 'bj_deal', bet: 20 });
    s = ok(s, { type: 'bj_act', action: 'split' });
    s = ok(s, { type: 'bj_act', action: 'stand' });
    s = ok(s, { type: 'bj_act', action: 'stand' });
    expect(s.day.bj_net).toBe(-85);
    expect(run(s, { type: 'bj_deal', bet: 5 })).toMatchObject({ ok: false, code: 'bj_day_cap', detail: { cap: 'loss', net: -85 } });
  });

  it('the same for the win; the hand in play plays on though the cap is reached', () => {
    expect(run(player(50), { type: 'bj_deal', bet: 5 })).toMatchObject({ ok: false, code: 'bj_day_cap', detail: { cap: 'win', net: 50 } });
    expect(viewOf(c, player(45), T0).blackjack.day.capped).toBeNull();
    stack('TS', '9H', '6S', '9D');
    const playing = ok(player(-45), { type: 'bj_deal', bet: 5 });
    playing.day.bj_net = -50;   // reached while this hand is out: the cap guards new hands only
    expect(run(playing, { type: 'bj_act', action: 'stand' }).ok).toBe(true);
  });

  it("an account already at ±50 on the update's day finds the table closed that day; the rollover opens it", () => {
    const s = player(-60);
    expect(run(s, { type: 'bj_deal', bet: 5 })).toMatchObject({ ok: false, code: 'bj_day_cap' });
    const tomorrow = rolloverAfter(c, s, dayKey(c, s, T0)) + 60_000;
    expect(viewOf(c, s, tomorrow).blackjack.day).toMatchObject({ net: 0, capped: null });
    stack('TS', '7H', '9S', '9D');
    expect(run(s, { type: 'bj_deal', bet: 5 }, tomorrow).ok).toBe(true);
  });
});

describe('the card room caps (q(320) v3 丙, mode mid: the deal inside the day)', () => {
  beforeEach(() => { bjCaps.mode = 'mid'; });

  it("the deal may stake only what the day's loss has left, in fives; Double and Split stay unchecked", () => {
    expect(viewOf(c, player(-38), T0).blackjack).toMatchObject({ max_deal: 10, last_bet: 0 });
    expect(run(player(-38), { type: 'bj_deal', bet: 15 })).toMatchObject({ ok: false, code: 'bj_day_cap', detail: { cap: 'loss', net: -38, left: 10 } });
    expect(run(player(-38), { type: 'bj_deal', bet: 25 })).toMatchObject({ ok: false, code: 'bj_max_bet', detail: { max: 20 } });
    stack('8S', 'TH', '8D', '9C');
    const s = ok(player(-38), { type: 'bj_deal', bet: 10 });
    expect(run(s, { type: 'bj_act', action: 'split' }).ok).toBe(true);
  });

  it('under the table minimum left to lose, the table closes', () => {
    expect(run(player(-46), { type: 'bj_deal', bet: 5 })).toMatchObject({ ok: false, code: 'bj_day_cap', detail: { cap: 'loss' } });
    expect(viewOf(c, player(-46), T0).blackjack.day.capped).toBe('loss');
    expect(viewOf(c, player(-45), T0).blackjack.day.capped).toBeNull();
  });
});
