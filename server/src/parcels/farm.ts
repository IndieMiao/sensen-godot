/**
 * 玩家地块内的农场状态（C-31）与它的命令。服务端不持有地块几何（障碍位置、保护通道、核心区与外围来自
 * 地块数据集，由客户端 C-33/C-34 判断），这里只管服务端能核实的部分：首次进入发一次赠品（Q-39、Q-40），
 * 放房子要扣蓝图且不压开垦格和作物，开垦要有锄头且不在房子占地内，只能在开垦格上播种并扣种子，
 * 按服务端时间判成熟，收获入包。
 *
 * 地块经济（C-58，0.4.3）：金币余额（开局 0，与主农场 P0 的金币分开）、按配置单价出售背包里的东西、
 * 按外围物件编号采集并按服务端时间刷新、卖过东西后领一次鸡舍蓝图。数值都在 dynamic_farm.json 的 economy。
 * 这些字段是在 v1 上追加的可选字段：C-31 时期的旧存档没有它们，读写时按默认值补上（见 withEconomy），
 * 不改版本号，0.4.2 客户端照常读。
 *
 * 买入（C-149，0.4.5）：在 Jasmine 柜台按 economy.buy_prices 的单价花金币买（先只有胡萝卜种子 9）。
 * 单价只看服务端配置，请求里带的价格被丢掉；金币不够整批拒绝，存档不变。不改存档字段。
 */
import { gatherSourceOf, type ParcelRules } from './rules.js';

export const FARM_STATE_VERSION = 1;
/** 格坐标上限与每类格数上限；地块总格数不超过 8192（客户端 parcel_metadata）。 */
export const MAX_COORD = 1024;
export const MAX_CELLS = 8192;
export const MAX_BATCH = 50;
/** 金币上限；出售会让余额超过它就拒绝。 */
export const MAX_COINS = 1_000_000_000;
/** 一条出售命令最多卖的个数。 */
export const MAX_SELL_COUNT = 999;
/** 一条买入命令最多买的个数（C-149）。 */
export const MAX_BUY_COUNT = 999;
/** 采集记录最多条数（外围物件总数远低于此）；过了刷新时间的记录在下次采集时清掉。 */
export const MAX_GATHERED = 4096;

export interface HouseState { model: string; x: number; y: number; width: number; depth: number; rotation: number; built_at: number }
export interface CropState { crop: string; planted_at: number; ripe_at: number }
export interface ParcelFarmState {
  v: typeof FARM_STATE_VERSION;
  house: HouseState | null;
  /** 已清理障碍的格，"x,y"。 */
  cleared: string[];
  /** 已开垦格，"x,y"；收获后仍是开垦格。 */
  tilled: string[];
  crops: Record<string, CropState>;
  bag: Record<string, number>;
  /** 首次进入自家地块的赠品发放时间；null 表示还没进过。发过就不再发。 */
  welcomed_at: number | null;
  /** C-58：地块金币余额，开局 0；只由出售增加。 */
  coins: number;
  /** C-58：成功出售的次数（领蓝图的条件）。 */
  sales: number;
  /** C-58：外围物件编号 → 最近一次采集的服务端时间；刷新后的记录会被清掉。 */
  gathered: Record<string, number>;
  /** C-58：已领取的一次性蓝图编号 → 领取时间。 */
  blueprints_claimed: Record<string, number>;
}

export type FarmCommand =
  | { type: 'place_house'; x: number; y: number; rotation?: number }
  | { type: 'clear_obstacle'; cell: string }
  | { type: 'till'; cell: string }
  | { type: 'sow'; cell: string; crop: string }
  | { type: 'harvest'; cell: string }
  | { type: 'sell'; item: string; count: number }
  | { type: 'buy'; item: string; count: number }
  | { type: 'gather'; object: string }
  | { type: 'claim_blueprint'; blueprint: string };

/** 命令执行时服务端核实过的上下文：本人地块编号（来自 token 查到的那一行，不来自请求体）。 */
export interface FarmContext { parcel_id: string }

export type FarmOutcome =
  | { ok: true; state: ParcelFarmState }
  | { ok: false; index: number; code: string; detail?: Record<string, unknown> };

/** 认领时的空农场：背包为空，赠品等首次进入时再发（认领和进入不是同一个动作）。 */
export function emptyFarm(): ParcelFarmState {
  return { v: FARM_STATE_VERSION, house: null, cleared: [], tilled: [], crops: {}, bag: {}, welcomed_at: null,
    coins: 0, sales: 0, gathered: {}, blueprints_claimed: {} };
}

/**
 * 旧存档兼容：C-31 时期写下的地块农场没有经济字段，按开局值补上（金币 0、没卖过、没采过、没领过）。
 * 只补缺的，不动已有字段；返回新对象，不改入参。
 */
export function withEconomy(state: ParcelFarmState): ParcelFarmState {
  const s = structuredClone(state) as Partial<ParcelFarmState> & ParcelFarmState;
  const count = (v: unknown) => Number.isInteger(v) && (v as number) >= 0 ? v as number : 0;
  const map = (v: unknown) => v && typeof v === 'object' && !Array.isArray(v) ? v as Record<string, number> : {};
  s.coins = count(s.coins);
  s.sales = count(s.sales);
  s.gathered = map(s.gathered);
  s.blueprints_claimed = map(s.blueprints_claimed);
  return s;
}

/** 首次进入自家地块：发一次 welcome_gift。已经发过返回 null（重开、重试都不重发）。 */
export function welcome(rules: ParcelRules, state: ParcelFarmState, now: number): ParcelFarmState | null {
  if (state.welcomed_at !== null) return null;
  const s = withEconomy(state);
  for (const [id, n] of Object.entries(rules.welcome_gift)) s.bag[id] = (s.bag[id] ?? 0) + n;
  s.welcomed_at = now;
  return s;
}

/**
 * 换到新数据集（C-136，Q-168 rebase）：新数据集里同一块地是另一套格子，按格子记的进度放不上去，清空；
 * 和格子无关的保留。清空的是房子、已清障碍、已开垦、作物和采集记录（采集冷却）；在地里的作物（不论熟没熟）
 * 每棵退一颗它的种子，房子退一张住宅蓝图，可以重新盖。背包其余物品、金币、卖出次数、已领蓝图和赠品记录不动。
 * 规则里已没有的作物不知道种子是什么，不退。返回新对象，不改入参。
 */
export function rebaseFarm(rules: ParcelRules, state: ParcelFarmState): ParcelFarmState {
  const s = withEconomy(state);
  for (const crop of Object.values(s.crops)) {
    const seed = rules.crops[crop.crop]?.seed;
    if (seed) s.bag[seed] = (s.bag[seed] ?? 0) + 1;
  }
  if (s.house) s.bag[rules.house.blueprint] = (s.bag[rules.house.blueprint] ?? 0) + 1;
  s.house = null;
  s.cleared = [];
  s.tilled = [];
  s.crops = {};
  s.gathered = {};
  return s;
}

const coord = (v: unknown): v is number => Number.isInteger(v) && (v as number) >= 0 && (v as number) < MAX_COORD;

/** "x,y" 的规范写法（无前导零、无空格）才收，避免同一格两种写法各占一行。 */
export function parseCell(v: unknown): [number, number] | null {
  if (typeof v !== 'string') return null;
  const m = /^(0|[1-9]\d{0,3}),(0|[1-9]\d{0,3})$/.exec(v);
  if (!m) return null;
  const x = Number(m[1]), y = Number(m[2]);
  return coord(x) && coord(y) ? [x, y] : null;
}

/** 请求体里的命令只做形状检查；语义检查在 applyFarmCommands 里。 */
export function parseFarmCommands(raw: unknown): FarmCommand[] | null {
  if (!Array.isArray(raw) || raw.length < 1 || raw.length > MAX_BATCH) return null;
  const out: FarmCommand[] = [];
  for (const c of raw as Record<string, unknown>[]) {
    if (!c || typeof c !== 'object') return null;
    switch (c.type) {
      case 'place_house':
        if (!coord(c.x) || !coord(c.y) || (c.rotation !== undefined && ![0, 1, 2, 3].includes(c.rotation as number))) return null;
        out.push({ type: 'place_house', x: c.x, y: c.y, rotation: (c.rotation as number | undefined) ?? 0 });
        break;
      case 'clear_obstacle': case 'till': case 'harvest':
        if (!parseCell(c.cell)) return null;
        out.push({ type: c.type, cell: c.cell as string });
        break;
      case 'sow':
        if (!parseCell(c.cell) || typeof c.crop !== 'string' || c.crop.length > 64) return null;
        out.push({ type: 'sow', cell: c.cell as string, crop: c.crop });
        break;
      case 'sell':
        if (typeof c.item !== 'string' || c.item.length > 64 || !Number.isInteger(c.count) || (c.count as number) < 1 || (c.count as number) > MAX_SELL_COUNT) return null;
        out.push({ type: 'sell', item: c.item, count: c.count as number });
        break;
      case 'buy':
        // 只取物品和个数；请求里的 price 等其它字段不进命令（单价只看服务端配置）。
        if (typeof c.item !== 'string' || c.item.length > 64 || !Number.isInteger(c.count) || (c.count as number) < 1 || (c.count as number) > MAX_BUY_COUNT) return null;
        out.push({ type: 'buy', item: c.item, count: c.count as number });
        break;
      case 'gather':
        if (typeof c.object !== 'string' || c.object.length > 256) return null;
        out.push({ type: 'gather', object: c.object });
        break;
      case 'claim_blueprint':
        if (typeof c.blueprint !== 'string' || c.blueprint.length > 64) return null;
        out.push({ type: 'claim_blueprint', blueprint: c.blueprint });
        break;
      default:
        return null;
    }
  }
  return out;
}

/**
 * 外围物件编号（与客户端 C-60 共用）：`<地块编号>:<外围配方版本>:<模型名>:<x>,<y>:<序号>`，例如
 * `p-3512001:outer-groves-v2:wild_pz_tree_20:41,7:0`。x,y 是物件原点所在的地块本地网格格子（与开垦格同一网格），
 * 序号是同一格同一模型的物件按配方摆放顺序的 0 起编号（通常为 0）。
 */
export interface OuterObjectId { parcel_id: string; recipe_version: string; model: string; cell: string; ordinal: number }
const OBJECT_RE = /^(p-[A-Za-z0-9_*-]{1,98}):([a-z0-9_-]{1,64}):([a-z0-9_-]{1,64}):((?:0|[1-9]\d{0,3}),(?:0|[1-9]\d{0,3})):(0|[1-9]\d?)$/;
export function parseObjectId(v: unknown): OuterObjectId | null {
  if (typeof v !== 'string') return null;
  const m = OBJECT_RE.exec(v);
  if (!m || !parseCell(m[4])) return null;
  return { parcel_id: m[1], recipe_version: m[2], model: m[3], cell: m[4], ordinal: Number(m[5]) };
}
export const objectId = (o: OuterObjectId): string => `${o.parcel_id}:${o.recipe_version}:${o.model}:${o.cell}:${o.ordinal}`;

/** 转 90°/270° 时宽深互换。 */
function footprint(h: { x: number; y: number; width: number; depth: number; rotation: number }): { x0: number; y0: number; x1: number; y1: number } {
  const [w, d] = h.rotation % 2 ? [h.depth, h.width] : [h.width, h.depth];
  return { x0: h.x, y0: h.y, x1: h.x + w - 1, y1: h.y + d - 1 };
}

const underHouse = (s: ParcelFarmState, cell: string): boolean => {
  if (!s.house) return false;
  const [x, y] = parseCell(cell)!, f = footprint(s.house);
  return x >= f.x0 && x <= f.x1 && y >= f.y0 && y <= f.y1;
};

/**
 * 一批命令全部成功才生效；任一失败整批不变，返回失败的序号。
 * ctx 是服务端从 token 查到的本人地块；没有 ctx 时采集一律按不是自家物件拒绝。
 */
export function applyFarmCommands(rules: ParcelRules, state: ParcelFarmState, commands: FarmCommand[], now: number, ctx?: FarmContext): FarmOutcome {
  const s = withEconomy(state);
  const eco = rules.economy;
  for (const [index, c] of commands.entries()) {
    const fail = (code: string, detail?: Record<string, unknown>): FarmOutcome => ({ ok: false, index, code, ...(detail ? { detail } : {}) });
    switch (c.type) {
      case 'place_house': {
        if (s.house) return fail('HOUSE_PLACED');
        if (!(s.bag[rules.house.blueprint] > 0)) return fail('NO_BLUEPRINT', { item: rules.house.blueprint });
        const house = { model: rules.house.model, x: c.x, y: c.y, width: rules.house.width, depth: rules.house.depth, rotation: c.rotation ?? 0, built_at: now };
        const f = footprint(house);
        if (f.x1 >= MAX_COORD || f.y1 >= MAX_COORD) return fail('OUT_OF_BOUNDS');
        const covered = [...s.tilled, ...Object.keys(s.crops)].filter(cell => {
          const [x, y] = parseCell(cell)!;
          return x >= f.x0 && x <= f.x1 && y >= f.y0 && y <= f.y1;
        });
        if (covered.length) return fail('CELL_OCCUPIED', { cells: [...new Set(covered)].sort() });
        take(s.bag, rules.house.blueprint, 1);
        s.house = house;
        break;
      }
      case 'clear_obstacle':
        if (s.cleared.includes(c.cell)) return fail('ALREADY_CLEARED');
        if (s.cleared.length >= MAX_CELLS) return fail('TOO_MANY_CELLS');
        s.cleared.push(c.cell);
        break;
      case 'till':
        if (!(s.bag[rules.till_tool] > 0)) return fail('NO_TOOL', { item: rules.till_tool });
        if (underHouse(s, c.cell)) return fail('CELL_OCCUPIED', { cells: [c.cell] });
        if (s.tilled.includes(c.cell)) return fail('ALREADY_TILLED');
        if (s.tilled.length >= MAX_CELLS) return fail('TOO_MANY_CELLS');
        s.tilled.push(c.cell);
        break;
      case 'sow': {
        const rule = rules.crops[c.crop];
        if (!rule) return fail('UNKNOWN_CROP');
        if (!s.tilled.includes(c.cell)) return fail('NOT_TILLED');
        if (s.crops[c.cell]) return fail('CELL_OCCUPIED', { cells: [c.cell] });
        if (!(s.bag[rule.seed] > 0)) return fail('NO_SEED', { item: rule.seed });
        take(s.bag, rule.seed, 1);
        s.crops[c.cell] = { crop: c.crop, planted_at: now, ripe_at: now + rule.grow_seconds * 1000 };
        break;
      }
      case 'harvest': {
        const crop = s.crops[c.cell];
        if (!crop) return fail('NO_CROP');
        if (now < crop.ripe_at) return fail('NOT_RIPE', { ripe_at: crop.ripe_at });
        delete s.crops[c.cell];
        const amount = rules.crops[crop.crop]?.yield ?? 1;
        s.bag[crop.crop] = (s.bag[crop.crop] ?? 0) + amount;
        break;
      }
      case 'sell': {
        // 单价只看服务端配置；请求里没有价格字段。
        const price = Object.hasOwn(eco.sell_prices, c.item) ? eco.sell_prices[c.item] : undefined;
        if (price === undefined) return fail('NOT_SELLABLE', { item: c.item });
        const have = s.bag[c.item] ?? 0;
        if (have < c.count) return fail('NOT_ENOUGH', { item: c.item, have, need: c.count });
        const earned = price * c.count;
        if (s.coins + earned > MAX_COINS) return fail('COINS_CAP', { coins: s.coins, max: MAX_COINS });
        take(s.bag, c.item, c.count);
        s.coins += earned;
        s.sales += 1;
        break;
      }
      case 'buy': {
        // 单价只看服务端配置；请求里的价格在 parseFarmCommands 已丢掉。
        const price = Object.hasOwn(eco.buy_prices, c.item) ? eco.buy_prices[c.item] : undefined;
        if (price === undefined) return fail('NOT_FOR_SALE', { item: c.item });
        const cost = price * c.count;
        if (s.coins < cost) return fail('NOT_ENOUGH_COINS', { coins: s.coins, need: cost });
        s.coins -= cost;
        s.bag[c.item] = (s.bag[c.item] ?? 0) + c.count;
        break;
      }
      case 'gather': {
        const o = parseObjectId(c.object);
        if (!o) return fail('UNKNOWN_OBJECT');
        if (!ctx || o.parcel_id !== ctx.parcel_id) return fail('NOT_YOUR_PARCEL');
        if (o.recipe_version !== eco.gather.recipe_version) return fail('STALE_RECIPE', { recipe_version: eco.gather.recipe_version });
        const src = gatherSourceOf(rules, o.model);
        if (!src) return fail('UNKNOWN_OBJECT');
        // 服务端没有地块几何（C-37）；能核实的是：住宅占地、开垦格、作物格、清过障碍的格都在核心区，不是外围。
        if (underHouse(s, o.cell) || s.tilled.includes(o.cell) || s.crops[o.cell] || s.cleared.includes(o.cell)) return fail('NOT_OUTER');
        const id = objectId(o);
        const respawnMs = eco.gather.respawn_seconds * 1000;
        const last = s.gathered[id];
        if (last !== undefined && now < last + respawnMs) return fail('NOT_RESPAWNED', { ready_at: last + respawnMs });
        for (const [k, at] of Object.entries(s.gathered)) if (now >= at + respawnMs) delete s.gathered[k];
        if (Object.keys(s.gathered).length >= MAX_GATHERED) return fail('TOO_MANY_OBJECTS', { max: MAX_GATHERED });
        // 服务端不知道外围真有哪些物件：同一类刷新期内最多采配方里该类最多摆放的个数，编造编号也拿不到更多。
        const live = Object.keys(s.gathered).filter(k => src.models.includes(parseObjectId(k)?.model ?? '')).length;
        if (live >= src.max_objects) return fail('TOO_MANY_OBJECTS', { max: src.max_objects });
        s.gathered[id] = now;
        s.bag[src.item] = (s.bag[src.item] ?? 0) + src.amount;
        break;
      }
      case 'claim_blueprint': {
        const rule = Object.hasOwn(eco.blueprints, c.blueprint) ? eco.blueprints[c.blueprint] : undefined;
        if (!rule) return fail('UNKNOWN_BLUEPRINT');
        if (Object.hasOwn(s.blueprints_claimed, c.blueprint)) return fail('BLUEPRINT_CLAIMED');
        if (s.sales < rule.min_sales) return fail('CONDITION_NOT_MET', { sales: s.sales, min_sales: rule.min_sales });
        s.blueprints_claimed[c.blueprint] = now;
        s.bag[rule.item] = (s.bag[rule.item] ?? 0) + rule.amount;
        break;
      }
    }
  }
  return { ok: true, state: s };
}

function take(bag: Record<string, number>, id: string, n: number): void {
  bag[id] -= n;
  if (bag[id] <= 0) delete bag[id];
}
