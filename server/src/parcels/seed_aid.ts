/**
 * 种子兜底（C-197，所有者 SEN-Q-281 采纳数值评审 SEN-C-189 第 3 节第 6 条，照 P0 的 seedling_pack）：玩家同时没钱、没种子、
 * 没作物时，Jasmine 每个玩家日送一次种子（默认 3 颗胡萝卜种子）。数值在 dynamic_farm.json 的 seed_aid，没有这一项等于不送。
 * - 没钱：金币不够在 Jasmine 那里买 1 颗这种种子（economy.buy_prices，胡萝卜种子 9）。
 * - 没种子：背包里没有任何作物的种子（crops.<作物>.seed）。
 * - 没作物：背包里没有任何作物（crops 的键，收下来的胡萝卜），地里也没种着（播下没浇的、在长的、熟了没收的都算种着）。
 * 三条都满足、今天（玩家日，同体力 energy.day）还没送过，claim_seed_aid 才送；送了把今天记在存档 seed_aid_day。
 * “人在 Jasmine 跟前”由客户端限定（打开她的问候卡时发），服务端不知道人站在哪。不花体力。
 * seed_aid_day 是在 v1 上追加的字段：旧存档没有时按没送过读。
 */
import { dayKey, nextRollover } from './energy.js';
import type { ParcelFarmState } from './farm.js';
import type { ParcelRules } from './rules.js';

/** 送什么种子（必须是某种作物的种子，且 Jasmine 卖它，用它的价判断“没钱”）、送几颗。 */
export interface SeedAidRules { item: string; amount: number }

const ID_RE = /^[a-z0-9_-]{1,64}$/;

/** seed_aid 的边界：item 是某种作物的种子、在 buy_prices 里，amount 1–99。没有这一项等于不送。 */
export function parseSeedAidRules(r: ParcelRules, fail: (what: string) => never): void {
  const a = r.seed_aid;
  if (a === undefined) return;
  if (!a || typeof a !== 'object' || Array.isArray(a) || typeof a.item !== 'string' || !ID_RE.test(a.item)
    || !Number.isInteger(a.amount) || a.amount < 1 || a.amount > 99) fail('seed_aid 不对');
  if (!Object.values(r.crops).some(c => c.seed === a.item)) fail(`seed_aid.item ${a.item} 不是作物的种子`);
  if (!Object.hasOwn(r.economy.buy_prices, a.item)) fail(`seed_aid.item ${a.item} 不在 economy.buy_prices 里`);
}

/**
 * 现在能不能送：能送返回 null，不能返回拒绝码和细节（先看规则，再看今天送过没有，再按 没钱 → 没种子 → 没作物 的先后）。
 * 客户端 parcel_farm.gd seed_aid_refusal 照同一套判断。
 */
export function seedAidRefusal(rules: ParcelRules, s: ParcelFarmState, now: number): { code: string; detail?: Record<string, unknown> } | null {
  const a = rules.seed_aid;
  if (!a) return { code: 'NO_SEED_AID' };
  if (s.seed_aid_day === dayKey(rules, now)) return { code: 'SEED_AID_TODAY', detail: { resets_at: nextRollover(rules, now) } };
  const price = rules.economy.buy_prices[a.item];
  if (s.coins >= price) return { code: 'CONDITION_NOT_MET', detail: { reason: 'coins', coins: s.coins, price } };
  const seeds = new Set(Object.values(rules.crops).map(c => c.seed));
  const seed = Object.keys(s.bag).find(id => seeds.has(id) && s.bag[id] > 0);
  if (seed) return { code: 'CONDITION_NOT_MET', detail: { reason: 'seeds', item: seed } };
  const crop = Object.keys(s.bag).find(id => Object.hasOwn(rules.crops, id) && s.bag[id] > 0);
  if (crop) return { code: 'CONDITION_NOT_MET', detail: { reason: 'crops', item: crop } };
  const cell = Object.keys(s.crops)[0];
  if (cell !== undefined) return { code: 'CONDITION_NOT_MET', detail: { reason: 'crops', cell } };
  return null;
}

/** 送一次（就地改 s）：先核 seedAidRefusal，能送就把种子放进背包、记下今天。返回拒绝或 null（送了）。 */
export function claimSeedAid(rules: ParcelRules, s: ParcelFarmState, now: number): { code: string; detail?: Record<string, unknown> } | null {
  const refusal = seedAidRefusal(rules, s, now);
  if (refusal) return refusal;
  const a = rules.seed_aid!;
  s.bag[a.item] = (s.bag[a.item] ?? 0) + a.amount;
  s.seed_aid_day = dayKey(rules, now);
  return null;
}
