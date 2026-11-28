/**
 * Aquatic Park 码头钓鱼（C-232，0.4.7）。数值照 SEN-C-223 数值表第 6 节（所有者 SEN-Q-342 adopt），都在 dynamic_farm.json 的 fishing：
 * 7 种鱼（普通 / 优良 / 稀有 60 : 30 : 10）、投竿 5 体力、脱钩退 3、新手竿第一次到码头送、芦苇竿 / 碳素竿、蚯蚓 / 亮片。
 * 收线小游戏照 P0（modules/fishing/fishing_model.gd、scenes/p0/p0_fishing_panel.gd 的 reel_tier）：鱼在条里上下游，按住往上、
 * 松开往下，鱼在绿条里进度涨、在外面掉，涨满上钩，掉光或到时脱钩。
 *
 * 服务端定结果：投竿（cast_line）时按服务端时间和本块地编号定这一竿的随机种子、鱼的档次、咬钩时刻；收线（reel_line）时客户端只交
 * 提竿离咬钩多少毫秒和每 step_ms 一位的按键记录（1 按住、0 松开），服务端用同一个种子、同一套模拟重放，涨满才给鱼，
 * 鱼种按种子在这一档里挑。结算完这一竿就清掉：同一竿不能再领（NO_CAST），整批重发由 base_version 挡住。
 * 按键记录的时长不能长过服务端从咬钩到现在的时间（加 REPLAY_SLACK_MS），快进、编造提前交的记录被拒（REEL_INPUT）。
 * 客户端 modules/dynamic_farm/parcel_fishing.gd 照同一份规则一字不差地再算一遍（tests/dynamic_farm/fixtures/fishing_cases.json）。
 *
 * “人在码头沿边”和别的动作一样由客户端限定（服务端没有码头几何）。多人同屏这一版不做；存档里只有本人的一竿，不占码头的位置。
 *
 * 存档字段 fishing（v1 上追加的可选字段，没有时按没钓过读，版本号不变）：
 *   cast      正在水里的一竿；null 是没有
 *   casts     投过几竿（种子用）
 *   caught    钓到过的鱼 → 条数（委托板鱼单 C-237 会用）
 *   gifted_at 第一次到码头送新手竿的时间；null 是还没送
 *   bought    今天（玩家日）买了几个限量的鱼饵
 *   last      上一竿的结果，客户端拿来说话
 */
import { dayKey, maxEnergy, nextTickIn, settleEnergy } from './energy.js';
import { hash32 } from './requests.js';
import type { ParcelFarmState } from './farm.js';
import type { ParcelRules } from './rules.js';

export interface ReelTier { bar_size: number; fish_speed: number; turn_steps: number; gain: number; loss: number }
export interface ReelRules {
  step_ms: number; max_steps: number; bar_acceleration: number; bar_max_speed: number; initial_progress: number;
  /** 鱼竿加宽后的绿条最多占多宽（P0 reel_tier 的 0.45）；条外损耗最少多少（0.04 / 秒）。 */
  max_band: number; min_loss: number;
  /** 档次 "1" "2" "3" → 收线手感（P0 fishing.json 的 Common / Fine / Rare）。 */
  tiers: Record<string, ReelTier>;
}
/** 一根鱼竿：提竿窗口加多少毫秒、绿条加宽多少（0.03 = 3 个百分点）、条外损耗乘多少。rods 按好坏排，后面的好。 */
export interface RodRule { id: string; hook_bonus_ms: number; band_bonus: number; loss_mult: number }
/** 一种鱼饵：各档权重加减（[普通, 优良, 稀有]），咬钩等待乘多少（蚯蚓 0.5 = 快一倍）。 */
export interface BaitRule { shift: number[]; wait: number }
/** Jasmine 柜台限量的渔具（价格在 economy.buy_prices，不在那里的买不到）：最多拥有几个、每个玩家日最多买几个、要农场几级。 */
export interface GoodsRule { max_owned?: number; daily?: number; min_level?: number }
export interface FishingRules {
  cast_energy: number;
  /** 咬钩后脱钩、没钩上、收线收空退的体力；咬钩前收线全退 cast_energy。 */
  refund_fail: number;
  bite_min_ms: number; bite_spread_ms: number; hook_window_ms: number;
  /** 收线小游戏最长 max_steps × step_ms，再宽限这么久还没交结果，这一竿按脱钩算。 */
  settle_grace_ms: number;
  starter_rod: string;
  /** 档次权重 [普通, 优良, 稀有]。 */
  weights: number[];
  /** 鱼 → 档次（1 起）。售价在 economy.sell_prices。 */
  fish: Record<string, number>;
  rods: RodRule[];
  baits: Record<string, BaitRule>;
  goods: Record<string, GoodsRule>;
  reel: ReelRules;
}

export interface CastState {
  at: number; bite_at: number;
  /** 咬钩后多久内提竿有效（hook_window_ms + 鱼竿加成）。 */
  hook_ms: number;
  rarity: number; seed: number; bait: string | null; rod: string;
}
export type CastResult = 'landed' | 'escaped' | 'cancelled';
export interface FishingState {
  cast: CastState | null;
  casts: number;
  caught: Record<string, number>;
  gifted_at: number | null;
  bought: { day: string | null; counts: Record<string, number> };
  last: { result: CastResult; at: number; fish: string | null; refund: number } | null;
}

/** 按键记录的时长最多比服务端算的“咬钩到现在”长这么多（时钟取整、请求排队的余量）。 */
export const REPLAY_SLACK_MS = 250;
const ID_RE = /^[a-z0-9_-]{1,64}$/;
const isId = (v: unknown): v is string => typeof v === 'string' && ID_RE.test(v);
const isMap = (v: unknown): v is Record<string, unknown> => Boolean(v) && typeof v === 'object' && !Array.isArray(v);
const count = (v: unknown, min: number, max: number): v is number => Number.isInteger(v) && (v as number) >= min && (v as number) <= max;
const real = (v: unknown, min: number, max: number): v is number => typeof v === 'number' && Number.isFinite(v) && v >= min && v <= max;

/** fishing 规则的边界；没有这一项等于不能钓鱼。 */
export function parseFishingRules(r: ParcelRules, fail: (what: string) => never): void {
  const f = r.fishing;
  if (f === undefined) return;
  if (!isMap(f) || !count(f.cast_energy, 0, 1000) || !count(f.refund_fail, 0, f.cast_energy) || !count(f.bite_min_ms, 0, 60_000)
    || !count(f.bite_spread_ms, 1, 60_000) || !count(f.hook_window_ms, 100, 60_000) || !count(f.settle_grace_ms, 0, 600_000)
    || !isId(f.starter_rod)) fail('fishing 不对');
  if (!Array.isArray(f.weights) || f.weights.length < 1 || f.weights.length > 9 || !f.weights.every(w => count(w, 0, 10_000))
    || !f.weights.some(w => w > 0)) fail('fishing.weights 不对');
  if (!isMap(f.fish) || !Object.keys(f.fish).length) fail('fishing.fish 不能为空');
  for (const [id, tier] of Object.entries(f.fish)) {
    if (!isId(id) || !count(tier, 1, f.weights.length)) fail(`fishing.fish.${id} 不对`);
    if (!Object.hasOwn(r.economy.sell_prices, id)) fail(`fishing.fish.${id} 没有售价`);
  }
  for (let t = 1; t <= f.weights.length; t++) if (f.weights[t - 1] > 0 && !Object.values(f.fish).includes(t)) fail(`fishing 第 ${t} 档没有鱼`);
  if (!Array.isArray(f.rods) || !f.rods.length) fail('fishing.rods 不能为空');
  const rods = new Set<string>();
  for (const rod of f.rods) {
    if (!isMap(rod) || !isId(rod.id) || rods.has(rod.id) || !count(rod.hook_bonus_ms, 0, 60_000) || !real(rod.band_bonus, 0, 1)
      || !real(rod.loss_mult, 0, 10)) fail(`fishing.rods.${rod?.id} 不对`);
    rods.add(rod.id);
  }
  if (!rods.has(f.starter_rod)) fail('fishing.starter_rod 不在 rods 里');
  if (!isMap(f.baits)) fail('fishing.baits 不对');
  for (const [id, b] of Object.entries(f.baits))
    if (!isId(id) || rods.has(id) || !isMap(b) || !Array.isArray(b.shift) || b.shift.length !== f.weights.length
      || !b.shift.every(n => count(n, -10_000, 10_000)) || !real(b.wait, 0.05, 10)) fail(`fishing.baits.${id} 不对`);
  if (!isMap(f.goods)) fail('fishing.goods 不对');
  for (const [id, g] of Object.entries(f.goods))
    if (!isId(id) || !isMap(g)
      || (g.max_owned !== undefined && !count(g.max_owned, 1, 999)) || (g.daily !== undefined && !count(g.daily, 1, 999))
      || (g.min_level !== undefined && !count(g.min_level, 1, 99))) fail(`fishing.goods.${id} 不对`);
  const q = f.reel;
  if (!isMap(q) || !count(q.step_ms, 10, 1000) || !count(q.max_steps, 1, 10_000) || !real(q.bar_acceleration, 0, 100)
    || !real(q.bar_max_speed, 0, 100) || !real(q.initial_progress, 0.01, 0.99) || !real(q.max_band, 0.01, 1) || !real(q.min_loss, 0, 100)
    || !isMap(q.tiers)) fail('fishing.reel 不对');
  for (let t = 1; t <= f.weights.length; t++) {
    const tier = q.tiers[String(t)];
    if (!isMap(tier) || !real(tier.bar_size, 0.01, 1) || !real(tier.fish_speed, 0, 100) || !count(tier.turn_steps, 1, 10_000)
      || !real(tier.gain, 0, 100) || !real(tier.loss, 0, 100)) fail(`fishing.reel.tiers.${t} 不对`);
  }
}

export function emptyFishing(): FishingState {
  return { cast: null, casts: 0, caught: {}, gifted_at: null, bought: { day: null, counts: {} }, last: null };
}

const isCast = (v: unknown): v is CastState => {
  const c = v as CastState;
  return isMap(c) && Number.isFinite(c.at) && Number.isFinite(c.bite_at) && count(c.hook_ms, 0, 600_000) && count(c.rarity, 1, 9)
    && count(c.seed, 0, 0xFFFFFFFF) && (c.bait === null || isId(c.bait)) && isId(c.rod);
};

/** 存档里的 fishing：没有（C-232 以前的存档）按没钓过读，不成形的部分丢掉。返回新对象。 */
export function fishingOf(raw: unknown): FishingState {
  const out = emptyFishing();
  if (!isMap(raw)) return out;
  if (isCast(raw.cast)) out.cast = { ...raw.cast };
  if (count(raw.casts, 0, 2 ** 31 - 1)) out.casts = raw.casts;
  if (isMap(raw.caught)) for (const [id, n] of Object.entries(raw.caught)) if (isId(id) && count(n, 1, 2 ** 31 - 1)) out.caught[id] = n;
  if (Number.isFinite(raw.gifted_at)) out.gifted_at = raw.gifted_at as number;
  const b = raw.bought;
  if (isMap(b) && typeof b.day === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(b.day) && isMap(b.counts)) {
    out.bought.day = b.day;
    for (const [id, n] of Object.entries(b.counts)) if (isId(id) && count(n, 1, 100_000)) out.bought.counts[id] = n;
  }
  const l = raw.last as FishingState['last'];
  if (isMap(l) && ['landed', 'escaped', 'cancelled'].includes(l.result as string) && Number.isFinite(l.at)
    && (l.fish === null || isId(l.fish)) && count(l.refund, 0, 10_000)) out.last = { result: l.result, at: l.at, fish: l.fish, refund: l.refund };
  return out;
}

/** 背包里最好的一根鱼竿（rods 里排在后面的好）；一根都没有为 null。 */
export function bestRod(f: FishingRules, bag: Record<string, number>): RodRule | null {
  for (let i = f.rods.length - 1; i >= 0; i--) if ((bag[f.rods[i].id] ?? 0) > 0) return f.rods[i];
  return null;
}

/** 这一档鱼在这根鱼竿上的收线手感（P0 reel_tier）：绿条加宽到 max_band 为止，条外损耗乘鱼竿的倍数、不低于 min_loss。 */
export function reelTier(f: FishingRules, rarity: number, rod: RodRule): ReelTier {
  const t = f.reel.tiers[String(rarity)];
  return { ...t, bar_size: Math.min(f.reel.max_band, t.bar_size + rod.band_bonus), loss: Math.max(f.reel.min_loss, t.loss * rod.loss_mult) };
}

export interface ReelSim { step: number; bar: number; velocity: number; fish: number; target: number; rng: number; progress: number;
  outcome: 'playing' | 'caught' | 'escaped' }
export function initialReel(f: FishingRules, seed: number): ReelSim {
  return { step: 0, bar: 0.5, velocity: 0, fish: 0.5, target: 0.5, rng: seed >>> 0, progress: f.reel.initial_progress, outcome: 'playing' };
}
const clamp = (v: number, low: number, high: number): number => v < low ? low : v > high ? high : v;
/** Godot 的 move_toward，逐位相同。 */
const moveToward = (from: number, to: number, delta: number): number => Math.abs(to - from) <= delta ? to : from + Math.sign(to - from) * delta;
/**
 * 收线小游戏走一步（step_ms）。和客户端 parcel_fishing.gd step 的每一步运算、先后都一样，结果逐位相同：
 * 鱼每 turn_steps 步换一个目标（线性同余随机数），朝它游；按住条往上加速、松开往下，碰到头停住；鱼在条里进度涨，不在掉。
 */
export function stepReel(f: FishingRules, s: ReelSim, held: boolean, tier: ReelTier): void {
  if (s.outcome !== 'playing') return;
  const q = f.reel, dt = q.step_ms / 1000;
  if (s.step % tier.turn_steps === 0) {
    s.rng = (Math.imul(s.rng, 1664525) + 1013904223) >>> 0;
    s.target = 0.1 + s.rng / 4294967296 * 0.8;
  }
  s.fish = moveToward(s.fish, s.target, tier.fish_speed * dt);
  s.velocity = clamp(s.velocity + (held ? 1 : -1) * q.bar_acceleration * dt, -q.bar_max_speed, q.bar_max_speed);
  const half = tier.bar_size * 0.5;
  s.bar = clamp(s.bar + s.velocity * dt, half, 1 - half);
  if (s.bar === half || s.bar === 1 - half) s.velocity = 0;
  const inside = Math.abs(s.fish - s.bar) <= half;
  s.progress = clamp(s.progress + (inside ? tier.gain : -tier.loss) * dt, 0, 1);
  s.step += 1;
  if (s.progress >= 1) s.outcome = 'caught';
  else if (s.progress <= 0 || s.step >= q.max_steps) s.outcome = 'escaped';
}

/** 按 inputs 从头重放：每一位走一步。记录走完时还在玩、或走完前已经分出结果（多交了位）都算不成形，返回 null。 */
export function replayReel(f: FishingRules, seed: number, tier: ReelTier, inputs: string): ReelSim | null {
  const s = initialReel(f, seed);
  for (const bit of inputs) {
    if (s.outcome !== 'playing') return null;
    stepReel(f, s, bit === '1', tier);
  }
  return s.outcome === 'playing' ? null : s;
}

/** 这一竿的随机种子：本块地、服务端时间、第几竿（客户端本地替身用同一个算法）。 */
export const castSeed = (parcel: string, now: number, casts: number): number => hash32(`${parcel}:${now}:${casts}`);

/** 按种子抽档次：权重加上鱼饵的加减（不低于 0），没有鱼的档不抽。 */
export function rollRarity(f: FishingRules, seed: number, bait: string | null): number {
  const shift = bait ? f.baits[bait]?.shift ?? [] : [];
  const weights = f.weights.map((w, i) => (Object.values(f.fish).includes(i + 1) ? Math.max(0, w + (shift[i] ?? 0)) : 0));
  const total = weights.reduce((a, b) => a + b, 0);
  let roll = hash32(`${seed}:r`) % total;
  for (let i = 0; i < weights.length; i++) {
    if (roll < weights[i]) return i + 1;
    roll -= weights[i];
  }
  return weights.findIndex(w => w > 0) + 1;
}

/** 上钩时这一档里给哪条鱼：按种子在 fish 里这一档的鱼中均匀挑（按配置先后）。 */
export function pickFish(f: FishingRules, seed: number, rarity: number): string {
  const pool = Object.keys(f.fish).filter(id => f.fish[id] === rarity);
  return pool[hash32(`${seed}:f`) % pool.length];
}

/** 这一竿最晚什么时候还能交结果：咬钩 + 提竿窗口 + 整局收线 + 宽限。过了按脱钩结算。 */
export const castDeadline = (f: FishingRules, c: CastState): number =>
  c.bite_at + c.hook_ms + f.reel.max_steps * f.reel.step_ms + f.settle_grace_ms;

export type FishingCommand =
  /** 第一次到码头：送一根新手竿（只送一次）。 */
  | { type: 'visit_pier' }
  /** 投竿；bait 是要挂的鱼饵（背包里要有），不挂为 null。用背包里最好的一根鱼竿。 */
  | { type: 'cast_line'; bait: string | null }
  /** 收线：hook_ms 是提竿时离咬钩多少毫秒，inputs 是从提竿起每 step_ms 一位的按键记录。 */
  | { type: 'reel_line'; hook_ms: number; inputs: string }
  /** 不钓了：咬钩前收线全退体力、鱼饵不用；咬钩后收线（没提竿、半途放弃）按脱钩算。 */
  | { type: 'cancel_line' };
export const FISHING_COMMANDS = ['visit_pier', 'cast_line', 'reel_line', 'cancel_line'] as const;

/** 请求体里钓鱼命令的形状检查；不是钓鱼命令返回 undefined，形状不对返回 null。 */
export function parseFishingCommand(c: Record<string, unknown>, maxSteps = 10_000): FishingCommand | null | undefined {
  switch (c.type) {
    case 'visit_pier': case 'cancel_line':
      return { type: c.type };
    case 'cast_line':
      if (c.bait !== undefined && c.bait !== null && (typeof c.bait !== 'string' || c.bait.length > 64)) return null;
      return { type: 'cast_line', bait: typeof c.bait === 'string' ? c.bait : null };
    case 'reel_line':
      if (!count(c.hook_ms, 0, 600_000) || typeof c.inputs !== 'string' || c.inputs.length < 1 || c.inputs.length > maxSteps
        || !/^[01]+$/.test(c.inputs)) return null;
      return { type: 'reel_line', hook_ms: c.hook_ms, inputs: c.inputs };
    default:
      return undefined;
  }
}

type Fail<R> = (code: string, detail?: Record<string, unknown>) => R;

/** 退体力（脱钩 3、咬钩前收线 5）：先结算到 now，加到上限为止；到上限时计时停在 now。 */
function refund(rules: ParcelRules, s: ParcelFarmState, now: number, n: number): number {
  const e = settleEnergy(rules, s, now), max = maxEnergy(rules, s);
  const back = Math.max(0, Math.min(n, max - e.value));
  e.value += back;
  if (e.value >= max) e.at = now;
  return back;
}

/** 收掉水里这一竿：上钩给 fish，脱钩退 refund_fail，咬钩前收线全退；咬钩后结算的用掉鱼饵。 */
function settle(rules: ParcelRules, s: ParcelFarmState, fs: FishingState, now: number, result: CastResult, fish: string | null): void {
  const f = rules.fishing!, c = fs.cast!;
  fs.cast = null;
  let back = 0;
  if (result === 'landed' && fish) {
    s.bag[fish] = (s.bag[fish] ?? 0) + 1;
    fs.caught[fish] = (fs.caught[fish] ?? 0) + 1;
  } else back = refund(rules, s, now, result === 'cancelled' ? f.cast_energy : f.refund_fail);
  if (result !== 'cancelled' && c.bait && (s.bag[c.bait] ?? 0) > 0) {
    s.bag[c.bait] -= 1;
    if (s.bag[c.bait] <= 0) delete s.bag[c.bait];
  }
  fs.last = { result, at: now, fish: result === 'landed' ? fish : null, refund: back };
}

/**
 * 一条钓鱼命令（farm.ts applyFarmCommands 里调用，体力已结算到 now）。成功返回 null 并改 s.fishing，拒绝返回原因、不改存档。
 */
export function fishingCommand<R>(rules: ParcelRules, s: ParcelFarmState, c: FishingCommand, now: number, parcel: string, fail: Fail<R>): R | null {
  const f = rules.fishing;
  if (!f) return fail('NO_FISHING');
  const fs = fishingOf(s.fishing);
  const active = fs.cast;
  switch (c.type) {
    case 'visit_pier': {
      if (fs.gifted_at !== null) return fail('PIER_GIFTED');
      fs.gifted_at = now;
      s.bag[f.starter_rod] = (s.bag[f.starter_rod] ?? 0) + 1;
      break;
    }
    case 'cast_line': {
      if (active && now <= castDeadline(f, active)) return fail('ALREADY_CASTING', { bite_at: active.bite_at });
      const rod = bestRod(f, s.bag);
      if (!rod) return fail('NO_ROD', { item: f.starter_rod });
      if (c.bait !== null && (!Object.hasOwn(f.baits, c.bait) || !((s.bag[c.bait] ?? 0) > 0))) return fail('NO_BAIT', { item: c.bait });
      // 上一竿放过了最晚交结果的时刻：先按脱钩收掉（退 refund_fail、用掉它的饵），再看体力够不够这一竿。
      if (active) settle(rules, s, fs, now, 'escaped', null);
      if (c.bait !== null && !((s.bag[c.bait] ?? 0) > 0)) return fail('NO_BAIT', { item: c.bait });
      const e = s.energy!;
      if (e.value < f.cast_energy) return fail('NO_ENERGY', { need: f.cast_energy, have: e.value, next_in: nextTickIn(rules, s, now) });
      if (e.value >= maxEnergy(rules, s)) e.at = now;
      e.value -= f.cast_energy;
      const seed = castSeed(parcel, now, fs.casts);
      fs.casts += 1;
      const wait = c.bait ? f.baits[c.bait].wait : 1;
      const bite = Math.round((f.bite_min_ms + (hash32(`${seed}:b`) % f.bite_spread_ms)) * wait);
      fs.cast = { at: now, bite_at: now + bite, hook_ms: f.hook_window_ms + rod.hook_bonus_ms, rarity: rollRarity(f, seed, c.bait), seed,
        bait: c.bait, rod: rod.id };
      break;
    }
    case 'reel_line': {
      if (!active) return fail('NO_CAST');
      if (now < active.bite_at) return fail('TOO_EARLY', { bite_at: active.bite_at });
      // 过了最晚交结果的时刻，或提竿晚过窗口：没钩上，按脱钩算。
      if (now > castDeadline(f, active) || c.hook_ms > active.hook_ms) {
        settle(rules, s, fs, now, 'escaped', null);
        break;
      }
      // 记录的时长不能长过服务端从咬钩到现在的时间：客户端的咬钩时刻只会比服务端晚（收到回复才开始数）。
      if (active.bite_at + c.hook_ms + c.inputs.length * f.reel.step_ms > now + REPLAY_SLACK_MS)
        return fail('REEL_INPUT', { reason: 'too_fast' });
      const rod = f.rods.find(r => r.id === active.rod) ?? f.rods[0];
      const sim = replayReel(f, active.seed, reelTier(f, active.rarity, rod), c.inputs);
      if (!sim) return fail('REEL_INPUT', { reason: 'unfinished' });
      settle(rules, s, fs, now, sim.outcome === 'caught' ? 'landed' : 'escaped', sim.outcome === 'caught' ? pickFish(f, active.seed, active.rarity) : null);
      break;
    }
    case 'cancel_line': {
      if (!active) return fail('NO_CAST');
      settle(rules, s, fs, now, now < active.bite_at ? 'cancelled' : 'escaped', null);
      break;
    }
  }
  s.fishing = fs;
  return null;
}

/**
 * 在 Jasmine 柜台买限量的渔具（farm.ts buy 里调用，单价已核过）：鱼竿每种最多一根，鱼饵每个玩家日限量，碳素竿和亮片要 4 级。
 * 不限量的物品返回 null；够条件时把今天买的数记上（买成了才记，farm.ts 扣金币前调用、失败整批不写）。
 */
export function goodsRefusal<R>(rules: ParcelRules, s: ParcelFarmState, item: string, n: number, now: number, fail: Fail<R>): R | null {
  const g = rules.fishing && Object.hasOwn(rules.fishing.goods, item) ? rules.fishing.goods[item] : undefined;
  if (!g) return null;
  const level = Number.isInteger(s.level) && s.level >= 1 ? s.level : 1;
  if (g.min_level !== undefined && level < g.min_level) return fail('CONDITION_NOT_MET', { level, min_level: g.min_level });
  if (g.max_owned !== undefined && (s.bag[item] ?? 0) + n > g.max_owned) return fail('ALREADY_OWNED', { item, max: g.max_owned });
  if (g.daily !== undefined) {
    const fs = fishingOf(s.fishing), day = dayKey(rules, now);
    if (fs.bought.day !== day) fs.bought = { day, counts: {} };
    const had = fs.bought.counts[item] ?? 0;
    if (had + n > g.daily) return fail('DAILY_LIMIT', { item, limit: g.daily, bought: had });
    fs.bought.counts[item] = had + n;
    s.fishing = fs;
  }
  return null;
}
