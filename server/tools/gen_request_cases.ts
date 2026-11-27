/**
 * C-191：生成 tests/dynamic_farm/fixtures/request_cases.json（驿站委托板的共用用例）。每个用例按服务端规则算出 expect，
 * server/test/parcels/requests.test.ts 和 tests/dynamic_farm/test_parcel_board.gd 各跑一遍，两边都要等于它。
 * 改了 requests.ts 或 dynamic_farm.json 的 requests 后重新生成，再逐条核对差异：
 *   pnpm --dir server exec tsx tools/gen_request_cases.ts
 */
import { writeFileSync } from 'node:fs';
import path from 'node:path';
import { DEFAULT_CONTENT_DIR } from '../src/domain/content.js';
import { applyFarmCommands, emptyFarm, welcome, withEconomy, type FarmCommand, type ParcelFarmState } from '../src/parcels/farm.js';
import { settleBoard } from '../src/parcels/requests.js';
import { loadParcelRules } from '../src/parcels/rules.js';

const rules = loadParcelRules(DEFAULT_CONTENT_DIR);
const T0 = 1795406400000;
const H = 3_600_000;
const OUT = path.join(DEFAULT_CONTENT_DIR, '..', '..', '..', 'tests', 'dynamic_farm', 'fixtures', 'request_cases.json');

const view = (s: ParcelFarmState, now: number): ParcelFarmState => {
  const v = withEconomy(s);
  settleBoard(rules, v, now);
  return v;
};
const run = (s: ParcelFarmState, commands: FarmCommand[], now: number): ParcelFarmState => {
  const out = applyFarmCommands(rules, s, commands, now);
  if (!out.ok) throw new Error(`${out.code} @${out.index}`);
  return out.state;
};
/** 存档里的样子（JSON 往返）。 */
const saved = (s: ParcelFarmState): ParcelFarmState => JSON.parse(JSON.stringify(s));
const welcomed = (extra: Partial<ParcelFarmState> = {}): ParcelFarmState => ({ ...welcome(rules, emptyFarm(), T0)!, ...extra });
const coop = { id: 2, type: 'coop', model: 'chicken_yard', x: 10, y: 10, width: 7, depth: 5, rotation: 0, built_at: T0,
  animals: ['hen_white', 'hen_brown', 'hen_white'] };
const req = (s: ParcelFarmState, slot: number) => s.board.slots[slot].req!;
const stock = (s: ParcelFarmState, slot: number, short = 0): ParcelFarmState => {
  const out = saved(s), r = req(out, slot);
  out.bag[r.item] = (out.bag[r.item] ?? 0) + r.qty - short;
  return out;
};

interface Case { name: string; farm: ParcelFarmState; commands?: FarmCommand[]; now: number }
const cases: Case[] = [];
const add = (name: string, farm: ParcelFarmState, now: number, commands?: FarmCommand[]) => cases.push({ name, farm: saved(farm), now, commands });

const fresh = welcomed();
add('the first read after entering fills both slots from the entry time', fresh, T0 + 5000);
const old = saved(welcomed()) as Partial<ParcelFarmState>;
delete old.board;
delete old.requests_done;
add('a save from before the board, entered 40 days ago: both slots drawn, swapped to the latest 72 h period', old as ParcelFarmState, T0 + 40 * 24 * H);
add('with a coop eggs may be drawn; at Lv4 each kind draws from its own Lv4 band', welcomed({ buildings: [coop], level: 4 }), T0 + 1000);
const shown = view(fresh, T0);
add('accepting the first request keeps it, now tracked', shown, T0 + H, [{ type: 'accept_request', request: 1 }]);
add('accepting it twice is refused', shown, T0 + H, [{ type: 'accept_request', request: 1 }, { type: 'accept_request', request: 1 }]);
add('an unknown request is refused', shown, T0 + H, [{ type: 'deliver_request', request: 9 }]);
add('delivering an open request pays Jasmine\'s price × count + 10 and refills the slot at once', stock(shown, 0), T0 + 2 * H,
  [{ type: 'deliver_request', request: 1 }]);
const eggs = view(welcomed({ buildings: [coop] }), T0);
eggs.board.slots[1].req = { id: 2, template: 'egg_basket', item: 'egg', qty: 2, bonus: 20, drawn_at: T0, status: 'accepted' };
add('delivering a tracked egg request: 2 eggs pay 2 × 20 + 20', stock(eggs, 1), T0 + 3 * H, [{ type: 'deliver_request', request: 2 }]);
add('one item short: refused, nothing changes', stock(shown, 1, 1), T0 + 2 * H,
  [{ type: 'accept_request', request: 2 }, { type: 'deliver_request', request: 2 }]);
const dropped = run(shown, [{ type: 'drop_request', request: 2 }], T0 + H);
add('dropping empties the slot for 8 h', shown, T0 + H, [{ type: 'drop_request', request: 2 }]);
add('a dropped slot is still empty just before 8 h', dropped, T0 + 9 * H - 1);
add('a dropped slot is drawn again at 8 h, read later', dropped, T0 + 11 * H);
const tracked = run(shown, [{ type: 'accept_request', request: 2 }], T0 + H);
add('an open request is swapped 72 h after it was drawn; the tracked one stays', tracked, T0 + 72 * H + 1);
let six = shown;
for (let n = 0; n < 6; n++) six = run(stock(six, 0), [{ type: 'deliver_request', request: req(six, 0).id }], T0 + (n + 1) * 60_000);
add('the seventh delivery of a player day is refused', stock(six, 0), T0 + 10 * 60_000, [{ type: 'deliver_request', request: req(six, 0).id }]);
add('the next player day it goes and the day counts restart', stock(six, 0), T0 + 24 * H, [{ type: 'deliver_request', request: req(six, 0).id }]);
const lv4 = view(welcomed({ buildings: [coop], level: 4 }), T0);
lv4.board = { ...lv4.board, day: '2026-11-22', done_today: 4, bonus_today: 90 };
lv4.board.slots[0].req = { id: 1, template: 'egg_basket', item: 'egg', qty: 4, bonus: 20, drawn_at: T0, status: 'open' };
add('with 10 of the day\'s 100 left a +20 egg request pays 10 of it (Lv4)', stock(lv4, 0), T0 + H, [{ type: 'deliver_request', request: 1 }]);
add('a delivery that would pass the coin cap is refused', { ...stock(shown, 0), coins: 1_000_000_000 - 5 }, T0 + H,
  [{ type: 'deliver_request', request: 1 }]);
add('delivering both in one batch refills both slots', stock(stock(shown, 0), 1), T0 + H,
  [{ type: 'deliver_request', request: 1 }, { type: 'deliver_request', request: 2 }]);

const expect = (c: Case) => {
  if (!c.commands) {
    const v = view(structuredClone(c.farm), c.now);
    return { ok: true, board: v.board, bag: v.bag, coins: v.coins, requests_done: v.requests_done };
  }
  const r = applyFarmCommands(rules, structuredClone(c.farm), c.commands, c.now);
  return r.ok ? { ok: true, board: r.state.board, bag: r.state.bag, coins: r.state.coins, requests_done: r.state.requests_done }
    : { ok: false, index: r.index, code: r.code, detail: r.detail ?? {} };
};
writeFileSync(OUT, `${JSON.stringify({
  _note: 'C-191 request board: each case runs through server/src/parcels/farm.ts (server/test/parcels/requests.test.ts) and '
    + 'modules/dynamic_farm/parcel_farm.gd (tests/dynamic_farm/test_parcel_board.gd); both must give `expect`. A case without '
    + '`commands` is a read (the board settled on a copy at `now`). Generated by server/tools/gen_request_cases.ts from the server '
    + 'rules: Jasmine\'s price × count + bonus, count and bonus by item and farm level (owner SEN-Q-281, C-197).',
  cases: cases.map(c => ({ ...c, expect: expect(c) })),
}, null, 1)}\n`);
console.log(`${cases.length} cases → ${OUT}`);
