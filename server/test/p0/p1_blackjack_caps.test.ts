/** The card room's day loss (q(320), approved and set as written: the user 11-13 「上限不做限制, 输到50 按照丙」): a deal
 *  may not take the day's net below −50 by its own stake (bj_day_cap); under the table minimum left the table closes till
 *  the rollover; Double and Split are not held to it; no cap on a stake or the day's win; every build. */
import { afterEach, describe, expect, it } from 'vitest';
import { BJ_CHIPS, BJ_DAY_LOSS, bjShoe, shuffleShoe } from '../../src/p0/blackjack.js';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { dayKey, rolloverAfter } from '../../src/p0/rules.js';
import { freshState, upgradeState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 28, 2, 0, 0);
const H = 3_600_000;
const AT = { space: 'outpost', place: 'sf_card_room_1' } as const;

const card = (code: string) => 'SHDC'.indexOf(code[1]) * 13 + 'A23456789TJQK'.indexOf(code[0]);
/** The shoe in dealing order (player, dealer up, player, dealer hole), then 2S 3H 2D 3C … of the second deck. */
function stack(...codes: string[]) {
  const top = codes.map(card);
  bjShoe.make = () => [...top, ...Array.from({ length: 60 }, (_, i) => card(['2S', '3H', '2D', '3C'][i % 4]) + 52)];
}
afterEach(() => { bjShoe.make = (p, n, salt) => shuffleShoe(p, n, salt); });

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
const opens = (s: P0State) => rolloverAfter(c, s, dayKey(c, s, T0));

describe("the card room's day loss (q(320))", () => {
  it('the view: the six chips, today\'s net, the limit, what is left, closed or not, when it opens', () => {
    expect(BJ_DAY_LOSS).toBe(50);
    const s = player();
    expect(viewOf(c, s, T0).blackjack).toMatchObject({ chips: BJ_CHIPS, day: { net: 0, limit: 50, left: 50, closed: false, opens_at: opens(s) } });
    expect(viewOf(c, player(-20), T0).blackjack.day).toMatchObject({ net: -20, left: 30 });
    expect(viewOf(c, player(-38), T0).blackjack.day.left).toBe(10);   // 12 left, in fives
  });

  it("a deal may stake what is left — 50 at the day's start, 10 at −38; over it bj_day_cap {cap, net, resets_at}", () => {
    stack('TS', '7H', '9S', '9D');
    expect(ok(player(), { type: 'bj_deal', bet: 50 }).blackjack?.hand?.seats[0].bet).toBe(50);
    const s = player();
    expect(run(s, { type: 'bj_deal', bet: 55 })).toMatchObject({ ok: false, code: 'bj_day_cap', detail: { cap: 'loss', net: 0, resets_at: opens(s) } });
    expect(run(player(-38), { type: 'bj_deal', bet: 15 })).toMatchObject({ ok: false, code: 'bj_day_cap', detail: { cap: 'loss', net: -38 } });
    stack('TS', '7H', '9S', '9D');
    expect(run(player(-38), { type: 'bj_deal', bet: 10 }).ok).toBe(true);
  });

  it('no cap on a stake or the win: ahead +500, 550 may go down; however far ahead, the table stays open', () => {
    expect(viewOf(c, player(500), T0).blackjack.day.left).toBe(550);
    stack('TS', '7H', '9S', '9D');
    expect(run(player(500), { type: 'bj_deal', bet: 550 }).ok).toBe(true);
    expect(viewOf(c, player(100_000), T0).blackjack.day.closed).toBe(false);
  });

  it('Double and Split are not held to it: 50 split and lost twice is −100, both hands counted at once; then closed', () => {
    stack('8S', 'TH', '8D', '9C');   // 8 8 against T 9: split, the hands take 2 and 3 (10 and 11), both stand, both lose
    let s = ok(player(), { type: 'bj_deal', bet: 50 });
    s = ok(s, { type: 'bj_act', action: 'split' });
    s = ok(s, { type: 'bj_act', action: 'stand' });
    s = ok(s, { type: 'bj_act', action: 'stand' });
    expect(s.day.bj_net).toBe(-100);
    expect(run(s, { type: 'bj_deal', bet: 5 })).toMatchObject({ ok: false, code: 'bj_day_cap', detail: { net: -100 } });
    stack('TS', '7H', '5S', '9D');   // 15 against 7: a double at −45 on a 5 stake goes, past what is left
    const d = ok(player(-45), { type: 'bj_deal', bet: 5 });
    expect(run(d, { type: 'bj_act', action: 'double' }).ok).toBe(true);
  });

  it('down 46 (under 5 left) the table closes — the day\'s limit before the coins short; down 45 it does not', () => {
    const at = player(-46, 41);   // 1 over the floor too: the day's limit is what is said
    expect(run(at, { type: 'bj_deal', bet: 5 })).toMatchObject({ ok: false, code: 'bj_day_cap', detail: { cap: 'loss', net: -46 } });
    expect(viewOf(c, at, T0).blackjack.day).toMatchObject({ left: 0, closed: true, opens_at: opens(at) });
    expect(viewOf(c, player(-45), T0).blackjack.day).toMatchObject({ left: 5, closed: false });
    expect(viewOf(c, player(-60), T0).blackjack.day.closed).toBe(true);   // an account already past it on the update's day
  });

  it("the last bet comes back at what is left; the hand in play plays on; a hand of yesterday's counts nowhere; the rollover opens", () => {
    const s = player(-30);
    s.blackjack = { n: 9, last_bet: 500 };
    expect(viewOf(c, s, T0).blackjack.last_bet).toBe(20);
    stack('TS', '9H', '6S', '9D');
    const playing = ok(player(-45), { type: 'bj_deal', bet: 5 });
    playing.day.bj_net = -50;   // reached while this hand is out: the limit guards new hands only
    expect(run(playing, { type: 'bj_act', action: 'stand' }).ok).toBe(true);
    stack('TS', '9H', '6S', '9D');
    const late = ok(player(0), { type: 'bj_deal', bet: 50 });   // begun today, played out after the rollover: lost
    const tomorrow = opens(late) + 60_000;
    const after = ok(late, { type: 'bj_act', action: 'stand' }, tomorrow);
    expect(after.day.bj_net ?? 0).toBe(0);
    expect(viewOf(c, player(-60), tomorrow).blackjack.day).toMatchObject({ net: 0, left: 50, closed: false });
  });
});
