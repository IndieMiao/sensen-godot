import { afterEach, describe, expect, it } from 'vitest';
import { bjSalt, bjShoe, bjTableFromEnv, cardCode, refundHand, setBlackjackSecret, setBlackjackTable, shuffleShoe } from '../../src/p0/blackjack.js';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { freshState, upgradeState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

// SGODOT-351 (plan v4.3 §3 / §7, q(238)–(240); interface 351 b610f98a): the Barbary Card Room's blackjack, dealt and
// settled on the server, bets in coins, the wallet kept at 40 after every stake.
const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 28, 2, 0, 0);
const H = 3_600_000;
const AT = { space: 'outpost', place: 'sf_card_room_1' } as const;

/** A card in the shoe: rank 'A23456789TJQK', suit 'SHDC' (the first deck). */
const card = (code: string) => 'SHDC'.indexOf(code[1]) * 13 + 'A23456789TJQK'.indexOf(code[0]);
/** The shoe in dealing order (player, dealer up, player, dealer hole, then the rest), padded with low cards. */
function stack(...codes: string[]) {
  const top = codes.map(card);
  bjShoe.make = () => [...top, ...Array.from({ length: 60 }, (_, i) => card(['2S', '3H', '2D', '3C'][i % 4]) + 52)];
}
afterEach(() => { bjShoe.make = (p, n, salt) => shuffleShoe(p, n, salt); });

function player(coins = 500): P0State {
  const s = upgradeState(c, { ...freshState(c, 'player-blackjack-1', T0, 7), created_at: T0 - 8 * 24 * H }, T0);
  s.homestead.level = 2;
  delete s.guide;
  s.coins = coins;
  return s;
}
function step(s: P0State, cmd: P0Command, now = T0) {
  const r = applyP0(c, s, { ...AT, ...cmd } as P0Command, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return r;
}
function refused(s: P0State, cmd: P0Command, now = T0) {
  const r = applyP0(c, s, { ...AT, ...cmd } as P0Command, now);
  if (r.ok) throw new Error(`${cmd.type} was accepted`);
  return r;
}
const result = (events: { kind: string }[]) => events.find(e => e.kind === 'bj_result') as unknown as {
  why: string; net: number; dealer: string[]; hands: { result: string; payout: number; net: number; cards: string[] }[]; coins_after: number };

describe('the card room table (gate, place, bets)', () => {
  it('opens at Homestead Lv2 and, in the guide, only once it is over; at the card room only', () => {
    const low = player(); low.homestead.level = 1;
    expect(refused(low, { type: 'bj_open' }).code).toBe('bj_locked');
    const guided = player(); guided.guide = { ...(freshState(c, 'g', T0, 7, { guide: true }).guide!), step: 'farm_till' };
    expect(refused(guided, { type: 'bj_deal', bet: 10 }).code).toBe('bj_locked');
    expect(refused(player(), { type: 'bj_deal', bet: 10, space: 'outpost', place: 'sh_tea_1' }).code).toBe('bj_not_here');
    expect(viewOf(c, low, T0).blackjack.open).toBe(false);
    expect(viewOf(c, player(), T0).blackjack).toMatchObject({ open: true, intro: false, floor: 40, min_bet: 5, step: 5, chips: [5, 10, 50, 100, 500, 1000], last_bet: 0, hand: null, last: null });
  });

  it('takes 5 or more in fives; a stake that would leave under 40 is refused with the coins short', () => {
    for (const bet of [0, 3, 7, 12.5]) expect(refused(player(), { type: 'bj_deal', bet }).code).toBe('bj_bad_bet');
    expect(refused(player(44), { type: 'bj_deal', bet: 5 })).toMatchObject({ code: 'bj_no_coins', detail: { need: 1, have: 44, floor: 40 } });
    stack('TS', '7H', '9S', '9D');
    expect(step(player(45), { type: 'bj_deal', bet: 5 }).state.coins).toBe(40);
  });

  it('records the intro card once; a second deal while a hand is open is refused', () => {
    const s = step(player(), { type: 'bj_intro' }).state;
    expect(viewOf(c, s, T0).blackjack.intro).toBe(true);
    stack('TS', '7H', '9S', '9D');
    const dealt = step(s, { type: 'bj_deal', bet: 10 }).state;
    expect(refused(dealt, { type: 'bj_deal', bet: 10 }).code).toBe('bj_in_hand');
    expect(refused(player(), { type: 'bj_act', action: 'hit' }).code).toBe('bj_no_hand');
  });
});

describe('the rules (plan §3)', () => {
  it('deals player, dealer up, player, hole; the view shows the up card only, never the shoe', () => {
    stack('TS', '7H', '9S', '9D');
    const r = step(player(), { type: 'bj_deal', bet: 20 });
    expect(r.state.coins).toBe(480);
    const hand = viewOf(c, r.state, T0).blackjack.hand!;
    expect(hand).toMatchObject({ n: 1, expired: false, active: 0, dealer: ['7H', ''], dealer_total: 7, actions: ['hit', 'stand', 'double'], blocked: { split: 'pairs_only' } });
    expect(hand.hands).toEqual([{ cards: ['TS', '9S'], total: 19, soft: false, bet: 20, doubled: false, state: 'playing' }]);
    expect(JSON.stringify(viewOf(c, r.state, T0))).not.toContain('"deck"');
    expect(JSON.stringify(viewOf(c, r.state, T0))).not.toContain('"salt"');
  });

  it('the dealer draws on 16 and stands on 17; a win pays 1 to 1 and counts in today\'s net', () => {
    stack('TS', '7H', '9S', '9D', '2C');   // dealer 16 draws 2: 18 against 19
    const s = step(player(), { type: 'bj_deal', bet: 20 }).state;
    const r = step(s, { type: 'bj_act', action: 'stand' });
    expect(result(r.events)).toMatchObject({ why: 'played', dealer: ['7H', '9D', '2C'], net: 20, hands: [{ result: 'win', payout: 40, net: 20 }], coins_after: 520 });
    expect(r.state.coins).toBe(520);
    expect(r.state.day.bj_net).toBe(20);
    expect(r.state.blackjack!.hand).toBeUndefined();
    expect(r.events.filter(e => e.kind === 'bj_card').map(e => (e as { card: string }).card)).toEqual(['9D', '2C']);
  });

  it('stands on a soft 17 (S17)', () => {
    stack('TS', 'AH', '8S', '6D');   // dealer A + 6: soft 17, stands; 18 wins
    const s = step(player(), { type: 'bj_deal', bet: 10 }).state;
    expect(result(step(s, { type: 'bj_act', action: 'stand' }).events)).toMatchObject({ dealer: ['AH', '6D'], hands: [{ result: 'win' }] });
  });

  it('peeks with an Ace or a ten up: a dealer blackjack settles at once, a player blackjack against it is a push', () => {
    stack('TS', 'AH', '9S', 'KD');
    let r = step(player(), { type: 'bj_deal', bet: 20 });
    expect(result(r.events)).toMatchObject({ why: 'peek', hands: [{ result: 'lose', payout: 0, net: -20 }] });
    expect(r.state.coins).toBe(480);
    stack('AS', 'KH', 'KS', 'AD');
    r = step(player(), { type: 'bj_deal', bet: 20 });
    expect(result(r.events)).toMatchObject({ why: 'peek', hands: [{ result: 'push', payout: 20, net: 0 }] });
    expect(r.state.coins).toBe(500);
  });

  it('pays a player blackjack 3 to 2 at once, half a coin rounded down (5 → 7, 15 → 22, 25 → 37)', () => {
    for (const [bet, win] of [[5, 7], [15, 22], [25, 37], [10, 15]]) {
      stack('AS', '7H', 'KS', '9D');
      const r = step(player(), { type: 'bj_deal', bet });
      expect(result(r.events)).toMatchObject({ why: 'blackjack', hands: [{ result: 'blackjack', payout: bet + win, net: win }] });
      expect(r.state.coins).toBe(500 + win);
    }
    stack('AS', 'TH', 'KS', '9D');   // a ten up, no dealer blackjack: paid at once too
    expect(result(step(player(), { type: 'bj_deal', bet: 10 }).events)).toMatchObject({ why: 'blackjack', net: 15 });
  });

  it('busts over 21 and, with every hand bust, the dealer draws nothing', () => {
    stack('TS', '6H', '6S', 'TD', 'KC');
    const s = step(player(), { type: 'bj_deal', bet: 10 }).state;
    const r = step(s, { type: 'bj_act', action: 'hit' });
    expect(result(r.events)).toMatchObject({ dealer: ['6H', 'TD'], hands: [{ result: 'bust', payout: 0, net: -10 }] });
  });

  it('doubles on any first two: one more stake, one card, stood; grey when it would leave under 40', () => {
    stack('5S', '6H', '6S', 'TD', '9C', '2D');   // 11 doubles to 20; dealer 16 draws 2: 18
    const s = step(player(), { type: 'bj_deal', bet: 50 }).state;
    const r = step(s, { type: 'bj_act', action: 'double' });
    expect(result(r.events)).toMatchObject({ hands: [{ result: 'win', payout: 200, net: 100, cards: ['5S', '6S', '9C'] }] });
    expect(r.state.coins).toBe(600);
    stack('5S', '6H', '6S', 'TD');
    const poor = step(player(130), { type: 'bj_deal', bet: 50 }).state;   // 80 left: a second 50 would leave 30
    expect(viewOf(c, poor, T0).blackjack.hand).toMatchObject({ actions: ['hit', 'stand'], blocked: { double: 'coins', split: 'pairs_only' }, need: { double: 10 } });
    expect(refused(poor, { type: 'bj_act', action: 'double' })).toMatchObject({ code: 'bj_no_coins', detail: { need: 10 } });
    const hit = step(poor, { type: 'bj_act', action: 'hit' }).state;
    expect(refused(hit, { type: 'bj_act', action: 'double' })).toMatchObject({ code: 'bj_bad_action', detail: { why: 'first_two' } });
  });

  it('splits a pair once (10 / J / Q / K alike), plays left to right; a split 21 pays 1 to 1; no double after it', () => {
    stack('KS', '6H', 'QS', 'TD', 'AC', '9D', '5C');   // K | Q, each takes one: K+A (21), Q+9; dealer 16 draws 5: 21
    const s = step(player(), { type: 'bj_deal', bet: 20 }).state;
    let r = step(s, { type: 'bj_act', action: 'split' });
    expect(r.state.coins).toBe(460);
    const v = viewOf(c, r.state, T0).blackjack.hand!;
    expect(v.hands.map(h => [h.cards, h.state])).toEqual([[['KS', 'AC'], 'stood'], [['QS', '9D'], 'playing']]);
    expect(v.active).toBe(1);
    expect(v.blocked).toMatchObject({ double: 'after_split', split: 'one_split' });
    r = step(r.state, { type: 'bj_act', action: 'stand' });
    expect(result(r.events)).toMatchObject({ dealer_total: 21, hands: [{ result: 'push', net: 0 }, { result: 'lose', net: -20 }] });
    stack('8S', '6H', '8D', 'TD', 'AC', 'AD', '2C');   // 8 | 8 take A, A: 19 and 19; dealer 16 draws 2: 18
    const t = step(step(player(), { type: 'bj_deal', bet: 10 }).state, { type: 'bj_act', action: 'split' }).state;
    expect(viewOf(c, t, T0).blackjack.hand!.active).toBe(0);
    const u = step(t, { type: 'bj_act', action: 'stand' });
    const w = step(u.state, { type: 'bj_act', action: 'stand' });
    expect(result(w.events)).toMatchObject({ hands: [{ result: 'win', payout: 20 }, { result: 'win', payout: 20 }], net: 20 });
  });

  it('split Aces take one card each and stand; the 21 there is no blackjack', () => {
    stack('AS', '7H', 'AD', 'TD', 'KC', '5C');   // A+K = 21 (1 to 1), A+5 = 16; dealer 17
    const s = step(player(), { type: 'bj_deal', bet: 10 }).state;
    const r = step(s, { type: 'bj_act', action: 'split' });
    expect(result(r.events)).toMatchObject({ why: 'played', hands: [{ result: 'win', payout: 20, net: 10 }, { result: 'lose', net: -10 }] });
    stack('7S', '7H', '7D', 'TD');
    const poor = step(player(55), { type: 'bj_deal', bet: 10 }).state;   // 45 left: a second 10 would leave 35
    expect(refused(poor, { type: 'bj_act', action: 'split' })).toMatchObject({ code: 'bj_no_coins', detail: { need: 5 } });
  });
});

describe('the table switch (P0_BJ_TABLE; 用户 via 奕星 on 351)', () => {
  afterEach(() => setBlackjackTable(true));
  it('is on unless the variable is literally "0" (unset and empty are on)', () => {
    expect([undefined, '', '1', 'true', 'off', '00', ' 0', '0'].map(bjTableFromEnv)).toEqual([true, true, true, true, true, true, true, false]);
  });
  it('off, the table is closed to everyone past the gate; a hand already in play still settles as it runs out', () => {
    stack('TS', '7H', '9S', '9D', '2C');
    const s = step(player(), { type: 'bj_deal', bet: 20 }).state;
    setBlackjackTable(false);
    expect(viewOf(c, player(), T0).blackjack.open).toBe(false);
    for (const cmd of [{ type: 'bj_open' }, { type: 'bj_intro' }, { type: 'bj_deal', bet: 10 }, { type: 'bj_act', action: 'stand' }] as P0Command[])
      expect(refused(s, cmd).code).toBe('bj_locked');
    const later = applyP0(c, s, { type: 'read_inbox', keys: [] }, T0 + 24 * H);
    if (!later.ok) throw new Error(later.code);
    expect(later.state.blackjack!.hand).toBeUndefined();
    expect(later.state.coins).toBe(520);
    expect(later.state.blackjack!.last).toMatchObject({ why: 'expired', net: 20 });
    setBlackjackTable(true);
    expect(viewOf(c, player(), T0).blackjack.open).toBe(true);
  });
});

describe('a hand left behind (expiry, the unseen result, the day)', () => {
  const dealt = () => { stack('TS', '7H', '9S', '9D', '2C'); return step(player(), { type: 'bj_deal', bet: 20 }).state; };

  it('the next day any command stands and pays it; the result waits in last for bj_open; not in that day\'s net', () => {
    const s = dealt();
    expect(viewOf(c, s, T0 + 24 * H).blackjack.hand).toMatchObject({ expired: true, actions: [] });
    const other = applyP0(c, s, { type: 'read_inbox', keys: [] }, T0 + 24 * H);
    if (!other.ok) throw new Error(other.code);
    expect(other.state.blackjack!.hand).toBeUndefined();
    expect(other.state.coins).toBe(520);
    expect(other.state.day.bj_net).toBeUndefined();   // begun the day before: the log only
    expect(other.state.blackjack!.last).toMatchObject({ why: 'expired', net: 20 });
    const open = step(other.state, { type: 'bj_open' }, T0 + 24 * H);
    expect(result(open.events)).toMatchObject({ why: 'expired', net: 20 });
    expect(open.state.blackjack!.last).toBeUndefined();
    expect(step(open.state, { type: 'bj_open' }, T0 + 24 * H).events.filter(e => e.kind === 'bj_result')).toEqual([]);
    stack('TS', '7H', '9S', '9D');
    expect(step(other.state, { type: 'bj_deal', bet: 10 }, T0 + 24 * H).state.blackjack!.last).toBeUndefined();   // a new hand clears it
  });

  it('an action on a hand that has run out is not played: ok, with its result (not a refusal, which saves nothing)', () => {
    const r = step(dealt(), { type: 'bj_act', action: 'hit' }, T0 + 24 * H);
    expect(result(r.events)).toMatchObject({ why: 'expired', hands: [{ cards: ['TS', '9S'], result: 'win' }] });
    expect(r.state.blackjack!.last).toBeUndefined();
  });

  it('a carried day (day_hold) keeps the hand open past midnight; 24 h untouched ends it all the same', () => {
    const s = dealt();
    const key = s.day.key;
    s.travel.day_hold = { key, start: T0, until: T0 + 30 * H } as typeof s.travel.day_hold;
    expect(viewOf(c, s, T0 + 23 * H).blackjack.hand!.expired).toBe(false);
    const r = step(s, { type: 'bj_act', action: 'stand' }, T0 + 23 * H);
    expect(r.state.day.bj_net).toBe(20);   // still the hand's day
    const t = dealt();
    t.travel.day_hold = { key: t.day.key, start: T0, until: T0 + 30 * H } as typeof t.travel.day_hold;
    expect(viewOf(c, t, T0 + 24 * H).blackjack.hand!.expired).toBe(true);
  });
});

describe('the shoe (plan §7)', () => {
  it('is all 208 cards; another salt deals another shoe, the same salt the same one', () => {
    const a = shuffleShoe('p', 3, 'salt-a');
    expect([...a].sort((x, y) => x - y)).toEqual(Array.from({ length: 208 }, (_, i) => i));
    expect(shuffleShoe('p', 3, 'salt-a')).toEqual(a);
    expect(shuffleShoe('p', 3, 'salt-b')).not.toEqual(a);
    expect(shuffleShoe('q', 3, 'salt-a')).not.toEqual(a);
    expect(cardCode(card('TH'))).toBe('TH');
  });

  it('salts each hand afresh, so a save restored to an earlier hand number deals another shoe', () => {
    const salts = ['one', 'two'], keep = bjSalt.next;
    bjSalt.next = () => salts.shift()!;
    try {
      stack('TS', '7H', '9S', '9D');
      const s = player();
      const first = step(s, { type: 'bj_deal', bet: 10 });
      const again = step(s, { type: 'bj_deal', bet: 10 });   // the same save, the same n
      expect(first.state.blackjack!.hand?.salt).toBe('one');
      expect(again.state.blackjack!.hand?.salt).toBe('two');
    } finally { bjSalt.next = keep; }
  });
});

describe('a rollback (plan §7, q(238))', () => {
  it('gives an open hand its stakes back, splits and doubles too, clears it, one more seq, nothing in bj_net', () => {
    stack('8S', '6H', '8D', 'TD', '3C', '3D');
    const s = step(step(player(), { type: 'bj_deal', bet: 50 }).state, { type: 'bj_act', action: 'split' }).state;
    expect(s.coins).toBe(400);
    const seq = s.seq;
    expect(refundHand(s)).toEqual({ player: 'player-blackjack-1', n: 1, refunded: 100 });
    expect(s.coins).toBe(500);
    expect(s.blackjack!.hand).toBeUndefined();
    expect(s.seq).toBe(seq + 1);
    expect(s.day.bj_net).toBeUndefined();
    expect(refundHand(s)).toBeNull();
  });
});

describe('the shuffle key (亚瑟 / 奕星 on #523)', () => {
  it('another key deals another shoe; a hand in play keeps its stored shoe when the key changes', () => {
    const a = shuffleShoe('p', 1, 'salt');
    setBlackjackSecret('another-key');
    try {
      expect(shuffleShoe('p', 1, 'salt')).not.toEqual(a);
    } finally { setBlackjackSecret('p0-bj-dev-secret'); }
    stack('TS', '7H', '9S', '9D', '2C');
    const dealt = step(player(), { type: 'bj_deal', bet: 20 }).state;
    setBlackjackSecret('restarted-key');
    try {
      expect(result(step(dealt, { type: 'bj_act', action: 'stand' }).events)).toMatchObject({ dealer: ['7H', '9D', '2C'], net: 20 });
    } finally { setBlackjackSecret('p0-bj-dev-secret'); }
  });
});
