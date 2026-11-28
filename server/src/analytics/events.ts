/**
 * 上报的事件名和由地块命令推出的事件（C-203）。清单和属性说明见 docs/plans/C-203.md。
 * 地块位置只报到社区一级（community_id），不报地块编号和中心点。
 */
import type { FarmCommand } from '../parcels/farm.js';
import type { ParcelRules } from '../parcels/rules.js';

export const EVENTS = {
  accountCreated: 'account_created',
  login: 'login',
  parcelClaimed: 'parcel_claimed',
  parcelEnter: 'parcel_enter',
  farmCommand: 'farm_command',
  marketSell: 'market_sell',
  blueprintClaimed: 'blueprint_claimed',
} as const;

/** 同一事件在用户这边只该有一次的，用固定去重键：补发脚本和实时上报的 account_created 只算一次。 */
export const accountCreatedInsertId = (userId: string): string => `${EVENTS.accountCreated}:${userId}`;

export type FarmCommandResult =
  | { kind: 'applied' }
  | { kind: 'rejected'; index: number; code: string }
  | { kind: 'version_conflict' };

export interface TrackedEvent { event: string; props: Record<string, unknown> }

/**
 * 一次地块命令请求对应的事件：
 * - 整批成功：每种命令一条 farm_command（command、count、outcome=applied），每条卖出一条 market_sell，每条领蓝图一条 blueprint_claimed；
 * - 被拒：只报拒绝的那条命令（outcome=rejected、reject_code），整批没生效，其余命令不计；
 * - 版本不符：每种命令一条（outcome=version_conflict），整批没生效。
 */
export function farmCommandEvents(rules: ParcelRules, commands: FarmCommand[], result: FarmCommandResult, communityId: string): TrackedEvent[] {
  const base = { community_id: communityId };
  if (result.kind === 'rejected') {
    const failed = commands[result.index];
    return [{ event: EVENTS.farmCommand, props: { ...base, command: failed?.type ?? null, count: 1, outcome: 'rejected', reject_code: result.code } }];
  }
  const counts = new Map<string, number>();
  for (const c of commands) counts.set(c.type, (counts.get(c.type) ?? 0) + 1);
  const out: TrackedEvent[] = [...counts].map(([command, count]) =>
    ({ event: EVENTS.farmCommand, props: { ...base, command, count, outcome: result.kind } }));
  if (result.kind !== 'applied') return out;
  for (const c of commands) {
    if (c.type === 'sell')
      out.push({ event: EVENTS.marketSell, props: { ...base, item: c.item, count: c.count, coins: (rules.economy.sell_prices[c.item] ?? 0) * c.count } });
    else if (c.type === 'claim_blueprint')
      out.push({ event: EVENTS.blueprintClaimed, props: { ...base, blueprint: c.blueprint, item: rules.economy.blueprints[c.blueprint]?.item ?? null } });
  }
  return out;
}
