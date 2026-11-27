/**
 * 驿站委托板（C-191，0.4.6）：照搬 P0 的系统委托板（server/src/p0/boards.ts，方案 §9.6、§9.13.2），去掉跨城和地区、探索类，
 * 挂在华盛顿广场驿站。数值都在 dynamic_farm.json 的 requests；报酬和每单件数按所有者 SEN-Q-281（推翻 Q-278，
 * 采纳数值评审 SEN-C-189 第 4.1 节）改过（C-197）：
 * - slots 个单子格；交完 done_refill_seconds 后补（默认立即），放弃 drop_refill_seconds 后补（8 小时），
 *   开着没人接 expire_seconds 后换一张（72 小时）；接了（accept_request）不过期，但占着格。
 * - 交单（deliver_request）不要求先接：背包里够数就扣物品、加金币。报酬 = 地板价 × 件数 + 完成奖；
 *   地板价是 Jasmine 的售价 × floor_percent%（向下取整；C-197 起 100，即售价），件数和完成奖按抽单时的农场等级取一档：
 *   模板自己写了 tiers 用它的，否则用这种物品在 item_tiers 里的（C-197：胡萝卜、木材、石头完成奖 10，蛋、奶、羊毛 20），
 *   都没有用公共的 tiers。
 * - 每个玩家日（同体力，energy.day）最多交 daily_max 单，完成奖合计不超过 daily_bonus_max；到上限后照常能接、
 *   能放弃，交单被拒（DAILY_LIMIT）。
 * - 单子只按玩家已有的出：模板写了 building 的（鸡蛋要鸡场），这块地上有这类建筑才抽得到；两格尽量不重样。
 * - 累计完成的单数存在 requests_done（羊圈解锁要用，SEN-C-176）。
 *
 * 抽单不用随机数：每次抽单由（首次进入时间、格子、抽单时刻、单号）的 32 位哈希决定，抽单时刻是这一格的补位时刻
 * 或换单时刻，不是读档的时刻，所以读档（在副本上补位）看到的单子和下一条命令补位抽到的是同一张、同一个编号。
 * 客户端 modules/dynamic_farm/parcel_farm.gd 照同一套规则和哈希再算一遍，两边按 tests/dynamic_farm/fixtures/request_cases.json 对账。
 *
 * 存档 farm.board = { slots: [{ req, refill_at }], seq, day, done_today, bonus_today }：req 为 null 是空格，refill_at 之后补；
 * seq 是上一张单子的编号（新单取 +1，不复用）；day 是 done_today / bonus_today 记的那个玩家日。都是在 v1 上追加的字段，
 * 旧存档没有时按空板、0 单读，首次进入过的农场下次读档时两格从 welcomed_at 起补上。
 */
import { dayKey, nextRollover } from './energy.js';
import type { BuildingState, ParcelFarmState } from './farm.js';
import type { ParcelRules } from './rules.js';

/**
 * 一种单子：要的物品（必须是 Jasmine 收的，sell_prices 里有）；building：这块地上有这类建筑才出（鸡蛋要鸡场）；
 * tiers：这种单子自己的件数和完成奖分档（可选，没有就看 requests.item_tiers 里这种物品的，再没有用 requests.tiers）。
 */
export interface RequestTemplate { item: string; building?: string; tiers?: RequestTier[] }
/** 农场 level 级起的一档：每单 qty[0]–qty[1] 件，完成奖 bonus。 */
export interface RequestTier { level: number; qty: [number, number]; bonus: number }
export interface RequestRules {
  slots: number;
  done_refill_seconds: number;
  drop_refill_seconds: number;
  expire_seconds: number;
  daily_max: number;
  daily_bonus_max: number;
  floor_percent: number;
  tiers: RequestTier[];
  /**
   * C-197：按物品分档（物品编号 → 分档），可选。按物品而不是按模板写，以后加的模板（牛奶、羊毛）要的物品在这里有就照它，
   * 不用再改；物品不必已经在 sell_prices 里（还没上线的产物先写着）。
   */
  item_tiers?: Record<string, RequestTier[]>;
  templates: Record<string, RequestTemplate>;
}

export interface BoardRequest {
  id: number; template: string; item: string; qty: number;
  /** 抽单时定下的完成奖（那时农场等级的一档）；实发还看当天剩下的额度。 */
  bonus: number;
  /** 抽单时刻：这一格的补位或换单时刻。开着没人接的单子 drawn_at + expire_seconds 后换掉。 */
  drawn_at: number;
  status: 'open' | 'accepted';
}
export interface BoardSlot { req: BoardRequest | null; refill_at: number }
export interface BoardState { slots: BoardSlot[]; seq: number; day: string | null; done_today: number; bonus_today: number }

export const MAX_SLOTS = 8;
const MAX_ID = 2 ** 31 - 1;
const ID_RE = /^[a-z0-9_-]{1,64}$/;
const isId = (v: unknown): v is string => typeof v === 'string' && ID_RE.test(v);
const count = (v: unknown, min: number, max: number): v is number => Number.isInteger(v) && (v as number) >= min && (v as number) <= max;
const isMap = (v: unknown): v is Record<string, unknown> => Boolean(v) && typeof v === 'object' && !Array.isArray(v);

export const emptyBoard = (): BoardState => ({ slots: [], seq: 0, day: null, done_today: 0, bonus_today: 0 });

/**
 * requests 的边界：1–8 格，补位 0 秒–30 天，换单 1 小时–30 天，每天 1–100 单、完成奖 0–100000，地板价 1–100%；
 * 档从 1 级起、等级递增，件数 1–999 且下限不大于上限（公共、按物品、按模板的都一样）；模板至少一个，物品是 Jasmine 收的，
 * building 是已有的建筑类型。
 * 没有 requests 等于没有委托板。
 */
export function parseRequestRules(r: ParcelRules, fail: (what: string) => never): void {
  const q = r.requests;
  if (q === undefined) return;
  if (!isMap(q) || !count(q.slots, 1, MAX_SLOTS) || !count(q.done_refill_seconds, 0, 30 * 86400) || !count(q.drop_refill_seconds, 0, 30 * 86400)
    || !count(q.expire_seconds, 3600, 30 * 86400) || !count(q.daily_max, 1, 100) || !count(q.daily_bonus_max, 0, 100_000)
    || !count(q.floor_percent, 1, 100)) fail('requests 不对');
  parseTiers(q.tiers, fail, 'requests.tiers');
  if (q.item_tiers !== undefined) {
    if (!isMap(q.item_tiers)) fail('requests.item_tiers 不对');
    for (const [item, tiers] of Object.entries(q.item_tiers)) {
      if (!isId(item)) fail(`requests.item_tiers.${item} 不对`);
      parseTiers(tiers, fail, `requests.item_tiers.${item}`);
    }
  }
  if (!isMap(q.templates) || !Object.keys(q.templates).length) fail('requests.templates 不能为空');
  for (const [id, t] of Object.entries(q.templates)) {
    if (!isId(id) || !isMap(t) || !isId(t.item) || !Object.hasOwn(r.economy.sell_prices, t.item)) fail(`requests.templates.${id} 不对`);
    if (t.building !== undefined && !(isId(t.building) && Object.hasOwn(r.buildings, t.building))) fail(`requests.templates.${id}.building 不对`);
    if (t.tiers !== undefined) parseTiers(t.tiers, fail, `requests.templates.${id}.tiers`);
  }
}

/** 分档：从 1 级起、等级递增，件数 1–999 且下限不大于上限，完成奖 0–10000。 */
function parseTiers(tiers: RequestTier[], fail: (what: string) => never, at: string): void {
  if (!Array.isArray(tiers) || !tiers.length || tiers[0]?.level !== 1) fail(`${at} 要从 1 级起`);
  tiers.forEach((t, i) => {
    if (!isMap(t) || !count(t.level, 1, 999) || (i > 0 && t.level <= tiers[i - 1].level) || !Array.isArray(t.qty) || t.qty.length !== 2
      || !count(t.qty[0], 1, 999) || !count(t.qty[1], t.qty[0], 999) || !count(t.bonus, 0, 10_000)) fail(`${at}[${i}] 不对`);
  });
}

/** 存档里的委托板；没有或不成形时为空板。不成形的格子、单子丢掉，编号至少是现有最大编号。返回新对象。 */
export function boardOf(raw: unknown): BoardState {
  if (!isMap(raw)) return emptyBoard();
  const slots = Array.isArray(raw.slots) ? raw.slots.filter(isSlot).map(sl => structuredClone(sl)) : [];
  const seq = Math.max(count(raw.seq, 0, MAX_ID) ? raw.seq : 0, ...slots.map(sl => sl.req?.id ?? 0));
  const day = typeof raw.day === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(raw.day) ? raw.day : null;
  return { slots, seq, day, done_today: day && count(raw.done_today, 0, 10_000) ? raw.done_today : 0,
    bonus_today: day && count(raw.bonus_today, 0, 1_000_000) ? raw.bonus_today : 0 };
}

const isSlot = (v: unknown): v is BoardSlot => {
  const sl = v as BoardSlot;
  return isMap(sl) && Number.isFinite(sl.refill_at) && (sl.req === null || isRequest(sl.req));
};
const isRequest = (v: unknown): v is BoardRequest => {
  const r = v as BoardRequest;
  return isMap(r) && count(r.id, 1, MAX_ID) && isId(r.template) && isId(r.item) && count(r.qty, 1, 999) && count(r.bonus, 0, 10_000)
    && Number.isFinite(r.drawn_at) && (r.status === 'open' || r.status === 'accepted');
};

/** 32 位哈希（FNV-1a 加 murmur3 的收尾），客户端 parcel_farm.gd hash32 一字不差地照算。 */
export function hash32(key: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < key.length; i++) h = Math.imul(h ^ key.charCodeAt(i), 0x01000193);
  h ^= h >>> 16;
  h = Math.imul(h, 0x85ebca6b);
  h ^= h >>> 13;
  h = Math.imul(h, 0xc2b2ae35);
  h ^= h >>> 16;
  return h >>> 0;
}

/**
 * 农场 level 级时这种单子（template，不给就看公共分档）的那一档：level 不低于它的最后一档。
 * 分档先看模板自己的，再看它要的物品在 item_tiers 里的（C-197），都没有用公共的。
 */
export function tierFor(q: RequestRules, level: number, template?: string): RequestTier {
  const t = template !== undefined && Object.hasOwn(q.templates, template) ? q.templates[template] : undefined;
  const tiers = t?.tiers ?? (t && q.item_tiers && Object.hasOwn(q.item_tiers, t.item) ? q.item_tiers[t.item] : undefined) ?? q.tiers;
  let tier = tiers[0];
  for (const t of tiers) if (level >= t.level) tier = t;
  return tier;
}

/** 一件 item 的地板价：Jasmine 的售价 × floor_percent%，向下取整。 */
export function floorPrice(rules: ParcelRules, item: string): number {
  return Math.floor(((rules.economy.sell_prices[item] ?? 0) * rules.requests!.floor_percent) / 100);
}

/** 现在能抽的模板，按配置先后：没写 building 的，或这块地上有这类建筑的。 */
export function eligibleTemplates(rules: ParcelRules, buildings: BuildingState[]): string[] {
  const q = rules.requests!;
  return Object.keys(q.templates).filter(id => {
    const b = q.templates[id].building;
    return b === undefined || buildings.some(x => x.type === b);
  });
}

/**
 * 第 slot 格在 at 时刻抽一张：可抽的模板里先去掉别的格（含这一格刚过期的那张）正挂着的，都去掉了就不去；
 * 件数和完成奖按现在的农场等级。没有可抽的模板返回 null（这一格空着，等有了再抽）。编号取 board.seq + 1。
 */
function draw(rules: ParcelRules, s: ParcelFarmState, slot: number, at: number): BoardRequest | null {
  const q = rules.requests!, b = s.board;
  const open = eligibleTemplates(rules, s.buildings);
  if (!open.length) return null;
  const taken = new Set(b.slots.map(sl => sl.req?.template));
  const fresh = open.filter(id => !taken.has(id));
  const pool = fresh.length ? fresh : open;
  const seed = `${s.welcomed_at}:${slot}:${at}:${b.seq + 1}`;
  const template = pool[hash32(`${seed}:t`) % pool.length];
  const tier = tierFor(q, s.level, template);
  const qty = tier.qty[0] + (hash32(`${seed}:q`) % (tier.qty[1] - tier.qty[0] + 1));
  b.seq += 1;
  return { id: b.seq, template, item: q.templates[template].item, qty, bonus: tier.bonus, drawn_at: at, status: 'open' };
}

/**
 * 把委托板补到 now（就地改 s.board）：格数补到 slots（新格从 welcomed_at 起补）；开着没人接、过了 expire_seconds 的单子
 * 换一张，换单时刻是它到期的那一刻（隔了好几期就取最近的一期）；空格到了补位时刻就抽。还没首次进入的农场不补。
 * 读档在副本上补（routes farmView），每批命令前后各补一次；抽单只看格子自己的时刻，所以几次补的结果一样。
 */
export function settleBoard(rules: ParcelRules, s: ParcelFarmState, now: number): void {
  const q = rules.requests;
  if (!q || s.welcomed_at === null) return;
  const b = s.board;
  while (b.slots.length < q.slots) b.slots.push({ req: null, refill_at: s.welcomed_at });
  const expire = q.expire_seconds * 1000;
  for (let i = 0; i < q.slots; i++) {
    const sl = b.slots[i];
    if (!sl.req && now >= sl.refill_at) sl.req = draw(rules, s, i, sl.refill_at);
    // 补上的这张也可能早已过期（补位时刻在很久以前）：同一次补位里就换到最近一期。
    if (sl.req?.status === 'open' && now >= sl.req.drawn_at + expire) {
      const at = sl.req.drawn_at + Math.floor((now - sl.req.drawn_at) / expire) * expire;
      sl.req = draw(rules, s, i, at);
      sl.refill_at = at;
    }
  }
  // 配置减了格数：多出来的空格去掉，挂着单子的留到交掉或放弃。
  b.slots = b.slots.filter((sl, i) => i < q.slots || sl.req);
}

/** 今天（当前玩家日）已交几单、已发多少完成奖。 */
export function today(rules: ParcelRules, b: BoardState, now: number): { done: number; bonus: number } {
  return b.day === dayKey(rules, now) ? { done: b.done_today, bonus: b.bonus_today } : { done: 0, bonus: 0 };
}

export type RequestCommand =
  | { type: 'accept_request'; request: number }
  | { type: 'deliver_request'; request: number }
  | { type: 'drop_request'; request: number };

type Fail = (code: string, detail?: Record<string, unknown>) => { ok: false; index: number; code: string; detail?: Record<string, unknown> };

/**
 * 接单、交单、放弃（就地改 s，失败时返回拒绝、s 不变）。交单：NO_REQUEST、DAILY_LIMIT {max, resets_at}、NOT_ENOUGH {item, have, need}、
 * COINS_CAP；成功扣物品、加地板价 × 件数和完成奖（不超过当天剩下的额度），今天的单数、额度和累计单数 +1，这一格按交完补位。
 * 放弃：这一格空出来，drop_refill_seconds 后补；物品留在背包里。
 */
export function requestCommand(rules: ParcelRules, s: ParcelFarmState, c: RequestCommand, now: number, fail: Fail, maxCoins: number):
  ReturnType<Fail> | null {
  const q = rules.requests;
  const slot = q ? s.board.slots.find(sl => sl.req?.id === c.request) : undefined;
  if (!q || !slot) return fail('NO_REQUEST', { request: c.request });
  const r = slot.req!;
  if (c.type === 'accept_request') {
    if (r.status === 'accepted') return fail('ALREADY_ACCEPTED', { request: r.id });
    r.status = 'accepted';
    return null;
  }
  if (c.type === 'drop_request') {
    slot.req = null;
    slot.refill_at = now + q.drop_refill_seconds * 1000;
    return null;
  }
  const done = today(rules, s.board, now);
  if (done.done >= q.daily_max) return fail('DAILY_LIMIT', { max: q.daily_max, resets_at: nextRollover(rules, now) });
  const have = s.bag[r.item] ?? 0;
  if (have < r.qty) return fail('NOT_ENOUGH', { item: r.item, have, need: r.qty });
  const bonus = Math.max(0, Math.min(r.bonus, q.daily_bonus_max - done.bonus));
  const coins = floorPrice(rules, r.item) * r.qty + bonus;
  if (s.coins + coins > maxCoins) return fail('COINS_CAP', { coins: s.coins, max: maxCoins });
  s.bag[r.item] = have - r.qty;
  if (s.bag[r.item] <= 0) delete s.bag[r.item];
  s.coins += coins;
  s.board.day = dayKey(rules, now);
  s.board.done_today = done.done + 1;
  s.board.bonus_today = done.bonus + bonus;
  s.requests_done += 1;
  slot.req = null;
  slot.refill_at = now + q.done_refill_seconds * 1000;
  return null;
}
