/**
 * The Barbary Card Room's blackjack (SGODOT-351, plan 2026-10-27 v4.3 §3 / §7; interface 351 b610f98a): one player
 * against the dealer, dealt and settled here, bets in coins (the table only draws them as chips). Four decks shuffled
 * afresh each hand; the dealer stands on all 17s; with an Ace or a ten up it peeks first; a blackjack pays 3 to 2,
 * half a coin rounded down; double on any first two cards; one split of a pair (10 / J / Q / K alike), split Aces take
 * one card each. After every stake the wallet keeps content.wallet_floor (40). Test phase: no bet or daily caps; the
 * day's net (day.bj_net) is kept for the observation log only, never in any economy.
 * A hand left a day (its start's day key, day_hold included) or 24 h untouched is settled as stood on the next command,
 * whatever it is (settleBlackjack, in applyP0's settle chain); a result no blackjack command carried back waits in
 * blackjack.last for bj_open.
 */
import { createHmac, randomBytes } from 'node:crypto';
import type { P0Content } from './content.js';
import type { Refusal } from './fishing.js';
import type { P0Event } from './progress.js';
import { dayKey } from './rules.js';
import type { P0State } from './state.js';

export const BJ_DECKS = 4;
export const BJ_CHIPS = [5, 10, 50, 100, 500, 1000];
export const BJ_MIN_BET = 5;
export const BJ_STEP = 5;
export const BJ_EXPIRE_MS = 24 * 3_600_000;
const RANKS = 'A23456789TJQK';
const SUITS = 'SHDC';

export type BjAction = 'hit' | 'stand' | 'double' | 'split';
export type BjResult = 'blackjack' | 'win' | 'dealer_bust' | 'push' | 'lose' | 'bust';
export type BjWhy = 'played' | 'peek' | 'blackjack' | 'expired';

/** One of the player's hands: cards are shoe indices (0–207), bet the coins staked on it (doubled included). */
export interface BjSeat { cards: number[]; bet: number; doubled?: boolean; split?: boolean; state: 'playing' | 'stood' | 'bust' | 'done' }
/** The hand in play, server only beyond what the view shows: the rest of the shoe, the salt, the day it began. */
export interface BjHand { n: number; deck: number[]; salt: string; day: string; at: number; last_at: number; seats: BjSeat[]; active: number; dealer: number[] }
export interface BjSettled {
  n: number; why: BjWhy; dealer: string[]; dealer_total: number;
  hands: { cards: string[]; result: BjResult; bet: number; payout: number; net: number }[]; net: number; coins_after: number;
}
export interface BjState { intro?: true; n: number; last_bet?: number; hand?: BjHand; last?: BjSettled }

/** The shuffle's key (P0_BJ_SECRET). The server sets it at start; dev and tests keep this fixed one. A release server
 * without one passes null: the card room alone is closed (bj_unavailable, the view's open false), the rest plays on. */
let secret: string | null = 'p0-bj-dev-secret';
export function setBlackjackSecret(key: string | null): void { secret = key; }
export const blackjackAvailable = () => secret !== null;
/** Each hand's salt (a restored save or a counter going back never replays a shoe); tests swap it for a fixed one. */
export const bjSalt = { next: (): string => randomBytes(8).toString('hex') };
/** The shoe for a hand, in dealing order; tests stack it. */
export const bjShoe = { make: (player: string, n: number, salt: string): number[] => shuffleShoe(player, n, salt) };

export const cardCode = (i: number): string => RANKS[(i % 52) % 13] + SUITS[Math.floor((i % 52) / 13)];
const rankOf = (i: number) => (i % 52) % 13;   // 0 = Ace … 12 = King
const valueOf = (i: number) => Math.min(rankOf(i) + 1, 10);   // Ace 1, face cards 10

/** The best total (an Ace as 11 when that does not bust) and whether an Ace is so counted. */
export function handTotal(cards: number[]): { total: number; soft: boolean } {
  let total = 0, aces = 0;
  for (const c of cards) { total += valueOf(c); if (rankOf(c) === 0) aces++; }
  return aces && total + 10 <= 21 ? { total: total + 10, soft: true } : { total, soft: false };
}
const natural = (cards: number[]) => cards.length === 2 && handTotal(cards).total === 21;

/** HMAC-SHA256(secret, player:n:salt) in counter blocks as the random stream; rejection sampling keeps every index
 * equally likely; Fisher–Yates over the 208 cards. */
export function shuffleShoe(player: string, n: number, salt: string): number[] {
  const deck = Array.from({ length: 52 * BJ_DECKS }, (_, i) => i);
  let block = 0, buf = Buffer.alloc(0), at = 0;
  const u32 = () => {
    if (at + 4 > buf.length) { buf = createHmac('sha256', secret!).update(`${player}:${n}:${salt}:${block++}`).digest(); at = 0; }
    const v = buf.readUInt32BE(at); at += 4; return v;
  };
  for (let i = deck.length - 1; i > 0; i--) {
    const range = i + 1, limit = Math.floor(0x1_0000_0000 / range) * range;
    let r = u32();
    while (r >= limit) r = u32();
    const j = r % range;
    [deck[i], deck[j]] = [deck[j], deck[i]];
  }
  return deck;
}

/** §2 / q(110): Homestead Lv2, and a player in the new-player guide only once it is over. */
export const bjOpen = (s: P0State) => s.homestead.level >= 2 && (!s.guide || s.guide.step === null);
const atTable = (c: P0Content, space: unknown, place: unknown) =>
  space === 'outpost' && typeof place === 'string' && c.outposts?.some(o => o.id === place && o.role === 'casino') === true;
const expired = (c: P0Content, s: P0State, h: BjHand, now: number) => h.day !== dayKey(c, s, now) || now - h.last_at >= BJ_EXPIRE_MS;
const coinsShort = (c: P0Content, s: P0State, stake: number) => Math.max(0, stake + c.wallet_floor - s.coins);
const refuse = (code: string, detail?: Record<string, unknown>): Refusal => ({ code, detail });

/** The dealer draws to 17 (stands on soft 17); not when every hand of the player's has bust. Then each hand is paid:
 * a natural 3 to 2 rounded down, a win or a dealer bust 1 to 1, a push its stake back. */
function settle(c: P0Content, s: P0State, h: BjHand, why: BjWhy, now: number, events: P0Event[] | null): BjSettled {
  const live = h.seats.some(x => x.state !== 'bust');
  if (live && why !== 'peek' && why !== 'blackjack') {
    while (handTotal(h.dealer).total < 17) h.dealer.push(h.deck.pop()!);
  }
  const dealer = handTotal(h.dealer).total, dealerNatural = natural(h.dealer);
  const hands = h.seats.map(x => {
    const own = handTotal(x.cards).total, nat = !x.split && natural(x.cards);
    let result: BjResult, payout: number;
    if (x.state === 'bust') { result = 'bust'; payout = 0; }
    else if (dealerNatural) { result = nat ? 'push' : 'lose'; payout = nat ? x.bet : 0; }
    else if (nat) { result = 'blackjack'; payout = x.bet + Math.floor(x.bet * 1.5); }
    else if (dealer > 21) { result = 'dealer_bust'; payout = 2 * x.bet; }
    else if (own > dealer) { result = 'win'; payout = 2 * x.bet; }
    else if (own === dealer) { result = 'push'; payout = x.bet; }
    else { result = 'lose'; payout = 0; }
    return { cards: x.cards.map(cardCode), result, bet: x.bet, payout, net: payout - x.bet };
  });
  const paid = hands.reduce((a, x) => a + x.payout, 0), net = hands.reduce((a, x) => a + x.net, 0);
  s.coins += paid;
  if (h.day === dayKey(c, s, now)) s.day.bj_net = (s.day.bj_net ?? 0) + net;   // a hand of another day is in the log only
  const out: BjSettled = { n: h.n, why, dealer: h.dealer.map(cardCode), dealer_total: dealer, hands, net, coins_after: s.coins };
  if (events) {
    if (h.dealer.length >= 2) events.push({ kind: 'bj_card', to: 'dealer', hand_index: 0, card: cardCode(h.dealer[1]), hole: true });
    for (const card of h.dealer.slice(2)) events.push({ kind: 'bj_card', to: 'dealer', hand_index: 0, card: cardCode(card) });
    if (paid) events.push({ kind: 'coins', delta: paid });
    events.push({ kind: 'bj_result', ...out });
  }
  delete s.blackjack!.hand;
  return out;
}

/** The settle chain's step (applyP0, before requirePass, any command): a hand left past its day or 24 h is stood and
 * paid. A blackjack command carries the result back in its events; any other keeps it in blackjack.last for bj_open. */
export function settleBlackjack(c: P0Content, s: P0State, now: number, events: P0Event[], cmdType: string): boolean {
  const h = s.blackjack?.hand;
  if (!h || !expired(c, s, h, now)) return false;
  for (const x of h.seats) if (x.state === 'playing') x.state = 'stood';
  const carried = cmdType.startsWith('bj_');
  const out = settle(c, s, h, 'expired', now, carried ? events : null);
  if (carried) delete s.blackjack!.last;
  else s.blackjack!.last = out;
  return true;
}

/** The next hand to play after the active one stood or bust; none left, the dealer's turn and the pay-out. */
function advance(c: P0Content, s: P0State, h: BjHand, now: number, events: P0Event[]): void {
  const next = h.seats.findIndex((x, i) => i > h.active && x.state === 'playing');
  if (next >= 0) { h.active = next; return; }
  if (h.seats[h.active]?.state === 'playing') return;
  settle(c, s, h, 'played', now, events);
}

function draw(h: BjHand, seat: number, events: P0Event[]): void {
  const card = h.deck.pop()!;
  h.seats[seat].cards.push(card);
  events.push({ kind: 'bj_card', to: 'player', hand_index: seat, card: cardCode(card) });
}

/** A seat's state after a card: bust over 21, stood at 21 (nothing better to draw for). */
function afterCard(x: BjSeat): void {
  const t = handTotal(x.cards).total;
  if (t > 21) x.state = 'bust';
  else if (t === 21) x.state = 'stood';
}

/** Why Double / Split is grey on the active hand (null: it may), coins aside. */
function rulesBlock(h: BjHand, action: 'double' | 'split'): string | null {
  const x = h.seats[h.active];
  if (action === 'double') return x.split ? 'after_split' : x.cards.length !== 2 ? 'first_two' : null;   // MVP: no double after a split
  if (h.seats.length > 1) return x.split && rankOf(x.cards[0]) === 0 ? 'split_aces' : 'one_split';
  if (x.cards.length !== 2) return 'first_two';
  return valueOf(x.cards[0]) === valueOf(x.cards[1]) ? null : 'pairs_only';
}

export type BjCommand =
  | { type: 'bj_open' } | { type: 'bj_intro' } | { type: 'bj_deal'; bet: number } | { type: 'bj_act'; action: BjAction };

/** The four blackjack commands; `settled`: the settle chain stood an expired hand on this very command. */
export function blackjackCommand(c: P0Content, s: P0State, cmd: BjCommand & { space?: unknown; place?: unknown }, now: number,
  events: P0Event[], settled: boolean): Refusal | null {
  if (secret === null) return refuse('bj_unavailable');   // no shuffle key on this server: the card room is closed
  if (!atTable(c, cmd.space, cmd.place)) return refuse('bj_not_here');
  if (!bjOpen(s)) return refuse('bj_locked');
  const bj = (s.blackjack ??= { n: 0 });
  switch (cmd.type) {
    case 'bj_open': {
      if (bj.last) { events.push({ kind: 'bj_result', ...bj.last }); delete bj.last; }
      return null;
    }
    case 'bj_intro': { bj.intro = true; return null; }
    case 'bj_deal': {
      const bet = cmd.bet;
      if (!Number.isInteger(bet) || bet < BJ_MIN_BET || bet % BJ_STEP !== 0) return refuse('bj_bad_bet', { min: BJ_MIN_BET, step: BJ_STEP });
      if (bj.hand) return refuse('bj_in_hand', { n: bj.hand.n });
      const need = coinsShort(c, s, bet);
      if (need) return refuse('bj_no_coins', { need, have: s.coins, floor: c.wallet_floor });
      const n = bj.n + 1, salt = bjSalt.next();
      const h: BjHand = { n, deck: bjShoe.make(s.player, n, salt).reverse(), salt, day: dayKey(c, s, now), at: now, last_at: now,
        seats: [{ cards: [], bet, state: 'playing' }], active: 0, dealer: [] };
      // the deck is reversed so pop() deals from its front: player, dealer up, player, dealer hole
      h.seats[0].cards.push(h.deck.pop()!); h.dealer.push(h.deck.pop()!); h.seats[0].cards.push(h.deck.pop()!); h.dealer.push(h.deck.pop()!);
      bj.n = n; bj.last_bet = bet; bj.hand = h;
      s.coins -= bet;
      events.push({ kind: 'coins', delta: -bet });
      events.push({ kind: 'bj_dealt', n, bet, hand: handView(c, s, h, now) });
      // an Ace or a ten up: the dealer peeks; a natural settles at once. A player's natural is paid at once too.
      if (valueOf(h.dealer[0]) >= 10 || rankOf(h.dealer[0]) === 0) {
        if (natural(h.dealer)) { settle(c, s, h, 'peek', now, events); return null; }
      }
      if (natural(h.seats[0].cards)) settle(c, s, h, 'blackjack', now, events);
      return null;
    }
    case 'bj_act': {
      const h = bj.hand;
      // a hand that had run out: the settle chain has stood and paid it, its result is in the events — not played
      if (!h) return settled ? null : refuse('bj_no_hand');
      const x = h.seats[h.active];
      const action = cmd.action;
      if (action === 'hit') { draw(h, h.active, events); afterCard(x); }
      else if (action === 'stand') x.state = 'stood';
      else if (action === 'double' || action === 'split') {
        const why = rulesBlock(h, action);
        if (why) return refuse('bj_bad_action', { why });
        const need = coinsShort(c, s, x.bet);
        if (need) return refuse('bj_no_coins', { need, have: s.coins, floor: c.wallet_floor });
        const stake = x.bet;
        s.coins -= stake;
        events.push({ kind: 'coins', delta: -stake });
        if (action === 'double') {
          x.bet += stake; x.doubled = true;
          draw(h, h.active, events);
          x.state = handTotal(x.cards).total > 21 ? 'bust' : 'stood';
        } else {
          const aces = rankOf(x.cards[0]) === 0;
          const second: BjSeat = { cards: [x.cards.pop()!], bet: stake, split: true, state: 'playing' };
          x.split = true;
          h.seats.push(second);
          draw(h, 0, events); draw(h, 1, events);
          for (const y of h.seats) { if (aces) y.state = 'stood'; else afterCard(y); }
          h.active = h.seats[0].state === 'playing' ? 0 : 1;
        }
      } else return refuse('bj_bad_action', { why: 'unknown' });
      h.last_at = now;
      if (x.state !== 'playing' || h.seats[h.active].state !== 'playing') advance(c, s, h, now, events);
      return null;
    }
  }
}

/** The hand as the client sees it: the player's cards, the dealer's up card ("" for the hole), what the active hand may
 * do and why the rest are grey; the shoe, the salt and the hole card never leave the server before the pay-out. */
export function handView(c: P0Content, s: P0State, h: BjHand, now: number) {
  const out = expired(c, s, h, now);
  const x = h.seats[h.active];
  const actions: BjAction[] = [], blocked: Record<string, string> = {}, need: Record<string, number> = {};
  if (!out && x?.state === 'playing') {
    actions.push('hit', 'stand');
    for (const a of ['double', 'split'] as const) {
      const why = rulesBlock(h, a) ?? (coinsShort(c, s, x.bet) ? 'coins' : null);
      if (!why) actions.push(a);
      else { blocked[a] = why; if (why === 'coins') need[a] = coinsShort(c, s, x.bet); }
    }
  }
  return {
    n: h.n, expired: out, active: h.active,
    hands: h.seats.map(y => ({ cards: y.cards.map(cardCode), ...handTotal(y.cards), bet: y.bet, doubled: !!y.doubled, state: y.state })),
    dealer: [cardCode(h.dealer[0]), ''], dealer_total: handTotal(h.dealer.slice(0, 1)).total,
    actions, blocked, ...(Object.keys(need).length ? { need } : {}),
  };
}

/** view.blackjack: the gate, the table's numbers, the hand in play and a result not yet seen. */
export function blackjackView(c: P0Content, s: P0State, now: number) {
  const bj = s.blackjack;
  return {
    open: bjOpen(s) && secret !== null, ...(secret === null ? { unavailable: true } : {}), intro: !!bj?.intro, floor: c.wallet_floor, min_bet: BJ_MIN_BET, step: BJ_STEP, chips: BJ_CHIPS,
    last_bet: bj?.last_bet ?? 0,
    hand: bj?.hand ? handView(c, s, bj.hand, now) : null,
    last: bj?.last ?? null,
  };
}

/** A rollback to a server that knows no blackjack (plan §7, q(238)): a hand still open goes back as it was staked —
 * every hand's stake (doubles and splits too) to the wallet, the hand cleared, nothing in bj_net. One more seq, so a
 * client holding the old one reads again. tools/bj_rollback_settle.ts runs it over a stopped server's state file. */
export function refundHand(s: P0State): { player: string; n: number; refunded: number } | null {
  const h = s.blackjack?.hand;
  if (!h) return null;
  const refunded = h.seats.reduce((a, x) => a + x.bet, 0);
  s.coins += refunded;
  delete s.blackjack!.hand;
  s.seq += 1;
  return { player: s.player, n: h.n, refunded };
}
