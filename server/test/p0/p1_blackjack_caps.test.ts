/** The card room's caps (q(320), the user's numbers pending — the placeholders of blackjack.ts until then; the user
 *  11-13 「牌室 C」 kept the room in the store builds): a deal's stake at most, and no new hand once the day's net has
 *  reached its loss or its win; the hand in play plays on, and the rollover starts the day's net over. */
import { afterEach, describe, expect, it } from 'vitest';
import { BJ_DAY_LOSS, BJ_DAY_WIN, BJ_MAX_BET, bjShoe, shuffleShoe } from '../../src/p0/blackjack.js';
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
/** The shoe in dealing order (player, dealer up, player, dealer hole, then low cards). */
function stack(...codes: string[]) {
  const top = codes.map(card);
  bjShoe.make = () => [...top, ...Array.from({ length: 60 }, (_, i) => card(['2S', '3H', '2D', '3C'][i % 4]) + 52)];
}
afterEach(() => { bjShoe.make = (p, n, salt) => shuffleShoe(p, n, salt); });

/** A player at the table with `coins`, today's card-room net already `net`. */
function player(coins = 10_000, net = 0): P0State {
  const s = upgradeState(c, { ...freshState(c, 'player-bj-caps-1', T0, 7), created_at: T0 - 8 * 24 * H }, T0);
  s.homestead.level = 2;
  delete s.guide;
  s.coins = coins;
  s.day.key = dayKey(c, s, T0);
  s.day.bj_net = net;
  return s;
}
const run = (s: P0State, cmd: Record<string, unknown>, now = T0) => applyP0(c, s, { ...AT, ...cmd } as unknown as P0Command, now);
const dealt = (s: P0State, bet: number, now = T0) => { const r = run(s, { type: 'bj_deal', bet }, now); if (!r.ok) throw new Error(r.code); return r.state; };

describe('the card room caps (q(320))', () => {
  it('a deal at most BJ_MAX_BET; the view says so', () => {
    stack('TS', '7H', '9S', '9D');
    expect(dealt(player(), BJ_MAX_BET).blackjack?.hand?.seats[0].bet).toBe(BJ_MAX_BET);
    const over = run(player(), { type: 'bj_deal', bet: BJ_MAX_BET + 5 });
    expect(over).toMatchObject({ ok: false, code: 'bj_max_bet', detail: { max: BJ_MAX_BET } });
    expect(viewOf(c, player(), T0).blackjack).toMatchObject({ max_bet: BJ_MAX_BET });
  });

  it("no new hand once the day's loss is reached, with when it starts over; just short of it, one more", () => {
    const at = player(10_000, -BJ_DAY_LOSS);
    const r = run(at, { type: 'bj_deal', bet: 5 });
    const resets = rolloverAfter(c, at, dayKey(c, at, T0));
    expect(r).toMatchObject({ ok: false, code: 'bj_day_cap', detail: { cap: 'loss', net: -BJ_DAY_LOSS, loss: BJ_DAY_LOSS, win: BJ_DAY_WIN, resets_at: resets } });
    expect(viewOf(c, at, T0).blackjack.day).toEqual({ net: -BJ_DAY_LOSS, loss: BJ_DAY_LOSS, win: BJ_DAY_WIN, capped: 'loss', resets_at: resets });
    stack('TS', '7H', '9S', '9D');
    expect(run(player(10_000, -BJ_DAY_LOSS + 5), { type: 'bj_deal', bet: 5 }).ok).toBe(true);
  });

  it("the same for the day's win", () => {
    const at = player(10_000, BJ_DAY_WIN);
    expect(run(at, { type: 'bj_deal', bet: 5 })).toMatchObject({ ok: false, code: 'bj_day_cap', detail: { cap: 'win', net: BJ_DAY_WIN } });
    expect(viewOf(c, at, T0).blackjack.day.capped).toBe('win');
    expect(viewOf(c, player(10_000, BJ_DAY_WIN - 5), T0).blackjack.day.capped).toBeNull();
  });

  it('a hand lost to the cap is paid; the next deal is refused; the hand in play plays on though the cap is reached', () => {
    stack('TS', '9H', '6S', '9D');   // the player 16 stands, the dealer 18: lost
    let s = dealt(player(10_000, -BJ_DAY_LOSS + 100), 100);
    const stood = run(s, { type: 'bj_act', action: 'stand' });
    expect(stood.ok).toBe(true);
    s = stood.ok ? stood.state : s;
    expect(s.day.bj_net).toBe(-BJ_DAY_LOSS);
    expect(run(s, { type: 'bj_deal', bet: 5 })).toMatchObject({ ok: false, code: 'bj_day_cap' });
    stack('TS', '9H', '6S', '9D');
    const playing = dealt(player(10_000, -BJ_DAY_LOSS + 5), 5);
    playing.day.bj_net = -BJ_DAY_LOSS;   // reached while this hand is out (the cap guards new hands only)
    expect(run(playing, { type: 'bj_act', action: 'stand' }).ok).toBe(true);
  });

  it("the rollover starts the day's net over: yesterday's loss caps nothing", () => {
    const s = player(10_000, -BJ_DAY_LOSS);
    const tomorrow = rolloverAfter(c, s, dayKey(c, s, T0)) + 60_000;
    expect(viewOf(c, s, tomorrow).blackjack.day).toMatchObject({ net: 0, capped: null });
    stack('TS', '7H', '9S', '9D');
    expect(run(s, { type: 'bj_deal', bet: 5 }, tomorrow).ok).toBe(true);
  });
});
