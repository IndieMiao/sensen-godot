/**
 * 地块体力（C-148，所有者 C-137#15 第 3 题“照搬p0”）：照 P0 的 server/src/p0/rules.ts 结算。
 * 上限 max_base（农场每级 +per_level，等级在 C-152 做，这里按 1 级）；每 regen_ms 回 1 点，按服务端时间算，下线也回，
 * 满了不再回、计时停在结算时刻，所以满条后花掉 1 点，下一个 +1 从花的时刻起算（§3.1.1）；新手期（首次进入自家地块后
 * blessing.days 天）恢复快 regen_mult 倍。休息：有小屋、每个玩家日一次，回 rest_amount（不超过上限）。
 * 玩家日按 day.utc_offset_hours 的当地时间、day.rollover_hour 点换日（P0 §3.1.1 的 04:00）。
 * 数值都在 dynamic_farm.json 的 energy；客户端 modules/dynamic_farm/parcel_farm.gd 照同一份规则再算一遍。
 *
 * 存档字段 farm.energy = { value, at, rested_on }：value 当前体力，at 上次结算的服务端时间（满条时就是结算时刻），
 * rested_on 最近一次休息的玩家日（YYYY-MM-DD），没休息过为 null。C-148 以前的存档没有这个字段，按满体力补上（energyOf）。
 */
import type { FarmCommand, ParcelFarmState } from './farm.js';
import type { ParcelRules } from './rules.js';

export interface EnergyState { value: number; at: number; rested_on: string | null }
export interface EnergyRules {
  max_base: number;
  /** 农场每升一级加的上限（C-152 接等级；本卡按 1 级）。 */
  per_level: number;
  regen_ms: number;
  rest_amount: number;
  blessing: { days: number; regen_mult: number };
  day: { utc_offset_hours: number; rollover_hour: number };
  /** 不按作物计价的动作的体力价；播种按 crops.<作物>.energy。不在表里的动作不花体力（收获、出售、领蓝图、放房子、休息）。 */
  costs: Record<string, number>;
}

/** 有体力价的命令类型；播种的价在作物上。 */
export const PRICED_COMMANDS = ['clear_obstacle', 'till', 'gather'] as const;
const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;

/** 农场等级（C-152 之前一律 1 级）。 */
export const farmLevel = (_s: ParcelFarmState): number => 1;

export function maxEnergy(rules: ParcelRules, s: ParcelFarmState): number {
  return rules.energy.max_base + rules.energy.per_level * (farmLevel(s) - 1);
}

/** 新手期：首次进入自家地块（welcomed_at）后的 blessing.days × 24 小时。 */
export function blessed(rules: ParcelRules, s: ParcelFarmState, now: number): boolean {
  return s.welcomed_at !== null && now - s.welcomed_at < rules.energy.blessing.days * 86_400_000;
}

/** 回 1 点要多少毫秒：4:00，新手期 2:40（×1.5）。 */
export function regenMs(rules: ParcelRules, s: ParcelFarmState, now: number): number {
  const e = rules.energy;
  return blessed(rules, s, now) ? Math.round(e.regen_ms / e.blessing.regen_mult) : e.regen_ms;
}

/** 新手期还剩多少毫秒；不在新手期为 0。 */
export function blessingLeft(rules: ParcelRules, s: ParcelFarmState, now: number): number {
  return blessed(rules, s, now) ? s.welcomed_at! + rules.energy.blessing.days * 86_400_000 - now : 0;
}

/** 存档里的体力；没有（C-148 以前的存档、刚认领的空农场）或不成形时按满体力、没休息过补上。返回新对象。 */
export function energyOf(rules: ParcelRules, s: ParcelFarmState, now: number): EnergyState {
  const e = s.energy as Partial<EnergyState> | undefined;
  if (e && typeof e === 'object' && Number.isInteger(e.value) && e.value! >= 0 && Number.isFinite(e.at)
    && (e.rested_on === null || (typeof e.rested_on === 'string' && DAY_RE.test(e.rested_on))))
    return { value: e.value!, at: e.at!, rested_on: e.rested_on };
  return { value: maxEnergy(rules, s), at: now, rested_on: null };
}

/**
 * 结算到 now：每 regen_ms 线性 +1，到上限停；满条时计时停在 now。s.energy 被改写（缺的先补满）。
 * 同 P0 settleEnergy。
 */
export function settleEnergy(rules: ParcelRules, s: ParcelFarmState, now: number): EnergyState {
  const e = energyOf(rules, s, now);
  s.energy = e;
  const max = maxEnergy(rules, s), period = regenMs(rules, s, now);
  if (e.value >= max) { e.at = now; return e; }
  const steps = Math.floor((now - e.at) / period);
  if (steps <= 0) return e;
  e.value = Math.min(max, e.value + steps);
  e.at = e.value >= max ? now : e.at + steps * period;
  return e;
}

/** 下一个 +1 还要多少毫秒；满了为 null。先 settleEnergy。 */
export function nextTickIn(rules: ParcelRules, s: ParcelFarmState, now: number): number | null {
  const e = energyOf(rules, s, now);
  if (e.value >= maxEnergy(rules, s)) return null;
  return Math.max(0, e.at + regenMs(rules, s, now) - now);
}

/** 花体力（调用方已核过够不够）：满条时花，计时从现在起算。 */
export function spendEnergy(rules: ParcelRules, s: ParcelFarmState, now: number, amount: number): void {
  const e = settleEnergy(rules, s, now);
  if (e.value >= maxEnergy(rules, s)) e.at = now;
  e.value -= amount;
}

/** 一条命令的体力价：播种看作物，清障碍、开垦、外围采集看 costs，其余 0。 */
export function energyCost(rules: ParcelRules, c: FarmCommand): number {
  if (c.type === 'sow') return rules.crops[c.crop]?.energy ?? 0;
  return Object.hasOwn(rules.energy.costs, c.type) ? rules.energy.costs[c.type] : 0;
}

/** 玩家日：当地时间（utc_offset_hours）退回 rollover_hour 小时后的日期，YYYY-MM-DD。 */
export function dayKey(rules: ParcelRules, now: number): string {
  const d = rules.energy.day;
  return new Date(now + (d.utc_offset_hours - d.rollover_hour) * 3_600_000).toISOString().slice(0, 10);
}

/** 当前玩家日结束（下一次换日）的服务端时间。 */
export function nextRollover(rules: ParcelRules, now: number): number {
  const d = rules.energy.day;
  const shift = (d.utc_offset_hours - d.rollover_hour) * 3_600_000;
  return Date.parse(`${dayKey(rules, now)}T00:00:00Z`) + 86_400_000 - shift;
}

/** 今天（当前玩家日）休息过没有。 */
export function restedToday(rules: ParcelRules, s: ParcelFarmState, now: number): boolean {
  return energyOf(rules, s, now).rested_on === dayKey(rules, now);
}

/** energy 规则的边界；不合法时调用 fail。 */
export function parseEnergyRules(e: EnergyRules | undefined, fail: (what: string) => never): void {
  const count = (v: unknown, min: number, max: number): boolean => Number.isInteger(v) && (v as number) >= min && (v as number) <= max;
  if (!e || typeof e !== 'object') fail('energy 缺失');
  if (!count(e!.max_base, 1, 10_000) || !count(e!.per_level, 0, 1000) || !count(e!.regen_ms, 1000, 86_400_000)
    || !count(e!.rest_amount, 1, 10_000)) fail('energy 数值不对');
  const b = e!.blessing, d = e!.day;
  if (!b || !count(b.days, 0, 365) || typeof b.regen_mult !== 'number' || !(b.regen_mult >= 1 && b.regen_mult <= 10)) fail('energy.blessing 不对');
  if (!d || !count(d.utc_offset_hours, -12, 14) || !count(d.rollover_hour, 0, 23)) fail('energy.day 不对');
  if (!e!.costs || typeof e!.costs !== 'object' || Array.isArray(e!.costs)) fail('energy.costs 缺失');
  for (const [type, n] of Object.entries(e!.costs))
    if (!(PRICED_COMMANDS as readonly string[]).includes(type) || !count(n, 0, 1000)) fail(`energy.costs.${type} 不对`);
}
