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
 * 多栋建筑（C-150，0.4.5）：buildings 存每栋建筑的类型、位置、朝向（0–3 个 90°）和放下时的占地，类型、占地、蓝图、
 * 每类上限按 dynamic_farm.json 的 buildings 配置。服务端拒绝与其它建筑重叠、压开垦格或作物的放置，转向后的占地同样检查。
 * 旧存档只有 house（唯一一栋小屋）：读写时转成 buildings 里的一栋 cottage，位置、朝向、占地原样（见 withBuildings）；
 * house 字段保留为 buildings 里那栋 cottage 的镜像，0.4.4 及更早的客户端照常读出小屋。版本号不变。
 *
 * 体力（C-148，照搬 P0，见 energy.ts）：清障碍、开垦、播种、外围采集花体力，收获、出售、领蓝图、放建筑免费；
 * 不够时整批拒绝（NO_ENERGY），存档不变。有小屋（buildings 里的 cottage）时每个玩家日可以休息一次（rest）。
 * 体力存在 energy 字段，同样是在 v1 上追加的可选字段：没有它的存档按满体力算。
 *
 * 养殖和掉落物（C-154，0.4.5 鸡场）：规则里带 livestock 的建筑类型（鸡场 coop）放下时记下它的动物。在里面喂一次（feed）扣 1 个
 * 饲料（胡萝卜）和 energy.costs.feed 的体力，喂过 produce_seconds 后这只动物把产物（蛋）下在地上：drops 里一条掉落物，
 * 喂的那一刻就写好它在哪个落点、哪只动物下的、什么时候下（ready_at），到点前不能捡、客户端不画。人走近时客户端发 pick_up，
 * 服务端只核实这条掉落物在、已经下了，捡一次就从 drops 删掉，同一个编号不会再出现（编号取 drop_seq 递增，不复用）。
 * 不喂不产；每只动物同时只等一个；这栋建筑地上的（含没下的）到 max_ground 就不能再喂。drops、drop_seq 也是 v1 上追加的可选字段。
 *
 * 浇水（C-151，所有者 SEN-C-137#6、#15）：播下的作物是干土、不计时（watered_at 为 null，ripe_at 为 NEVER）；
 * 在井（watering.well 类建筑）旁打水（draw_water，花体力），水桶装满 pail_uses 次，每浇一格（water）用一次，浇过才从那一刻起长。
 * 服务端不知道人站在哪，“人在井边”由客户端限定；这里核实井已盖好、有水桶、桶里的次数、格子播下了还没浇。
 * 桶里的次数存在 pail_water，补发记录存在 grants，都是在 v1 上追加的字段：旧存档没有时按 0 次、没补发过算。
 * C-151 以前种下的作物没有 watered_at，按已浇过算，照原来的 ripe_at 成熟。
 *
 * 农场等级（C-152，照 P0 家园等级）：在 Scott 处升级（upgrade_farm），花 farm_levels 里下一级的金币和材料，不花体力；
 * 材料或金币不够整批拒绝，存档不变。每级体力上限 +energy.per_level；某一级写了 buildings 的，从这一级起那类建筑能多盖
 * （井：3 级 2 口、5 级 3 口），送的 gift（井的蓝图）升级时进背包。不限制开垦格数（所有者 SEN-C-137#10）。
 * 等级存在 level，也是在 v1 上追加的字段：旧存档没有时按 1 级。换数据集不动等级。
 *
 * 牛棚（C-181，0.4.6）：照鸡场，是又一类养殖建筑（barn），盖的时候除蓝图外扣 materials（木材、石头）；喂一次扣 livestock.feed_amount
 * 个饲料（2 根胡萝卜），一次仍只产一份（牛奶）。牛棚蓝图在 Scott 处花金币买：economy.blueprints 里带 coins 的蓝图，claim_blueprint
 * 时扣这么多金币，不够整批拒绝（NOT_ENOUGH_COINS），只能买一次（同 blueprints_claimed）。不加存档字段，版本号不变。
 *
 * 驿站委托板（C-191，照搬 P0 系统委托板，见 requests.ts）：board 存两格单子和今天交了几单、发了多少完成奖，requests_done
 * 是累计交了几单（羊圈解锁要用）。接单、交单、放弃（accept_request / deliver_request / drop_request）不花体力，“人在驿站”由客户端限定。
 * 每批命令前后各补一次委托板（settleBoard），读档在副本上补。board、requests_done 也是 v1 上追加的字段：旧存档按空板、0 单读。
 * 换数据集不动委托板。
 */
import { dayKey, energyCost, maxEnergy, nextRollover, nextTickIn, settleEnergy, spendEnergy, type EnergyState } from './energy.js';
import { boardOf, emptyBoard, requestCommand, settleBoard, type BoardState } from './requests.js';
import { buildingMax, gatherSourceOf, HOME_BUILDING, MAX_BUILDINGS, nextFarmLevel, type ParcelRules } from './rules.js';

export const FARM_STATE_VERSION = 1;
/** 格坐标上限与每类格数上限；地块总格数不超过 8192（客户端 parcel_metadata）。 */
export const MAX_COORD = 1024;
export const MAX_CELLS = 8192;
export const MAX_BATCH = 50;
/** 金币上限；出售会让余额超过它就拒绝。 */
export const MAX_COINS = 1_000_000_000;
/** 一条出售命令最多卖的个数。 */
export const MAX_SELL_COUNT = 999;
/** 命令里建筑、掉落物编号的上限。 */
export const MAX_ID = 2 ** 31 - 1;
/** 一条买入命令最多买的个数（C-149）。 */
export const MAX_BUY_COUNT = 999;
/** 采集记录最多条数（外围物件总数远低于此）；过了刷新时间的记录在下次采集时清掉。 */
export const MAX_GATHERED = 4096;

export interface HouseState { model: string; x: number; y: number; width: number; depth: number; rotation: number; built_at: number }
/**
 * 一栋建筑（C-150）。x,y 是占地 x、y 最小的格；width/depth 是放下时配置里的未转向占地，之后改配置不影响已建的；
 * rotation 是转了几个 90°（0–3），转 1、3 时宽深互换。id 在本块地现有建筑里唯一（放下时取现有最大 id + 1），
 * 以后按栋操作（喂鸡、移动）用它。
 */
export interface BuildingState extends HouseState {
  id: number; type: string;
  /** C-154：养殖建筑放下时的动物（规则 livestock.animals 的副本，以后改配置不影响已建的）；普通建筑没有。 */
  animals?: string[];
}
/**
 * 地上的一个掉落物（C-154）：id 在本块地永不复用；item × amount 是捡到什么；building / animal / spot 是哪栋建筑里哪只动物
 * 下在第几个落点（建筑规则 livestock.spots）；ready_at 之后才在地上、才能捡。
 */
export interface DropState { id: number; item: string; amount: number; building: number; animal: number; spot: number; ready_at: number }
/**
 * 地里的一棵作物。watered_at（C-151）：浇水的服务端时间，从这一刻起长；null 是播下还没浇（干土），这时 ripe_at 为 NEVER；
 * 没有这个字段的是 C-151 以前种下的，按已浇过算。
 */
export interface CropState { crop: string; planted_at: number; ripe_at: number; watered_at?: number | null }
/**
 * 还没浇水的作物的 ripe_at（C-151）：JS 时间能表示的最晚时刻，永远不熟。存一个数而不是 null，
 * 0.4.4 及更早的客户端照常读出存档，只是把它当成一直在长；收获照样被服务端拒绝。
 */
export const NEVER = 8_640_000_000_000_000;
/** 播下了还没浇水（C-151）。 */
export const isDry = (crop: CropState): boolean => crop.watered_at === null;
export interface ParcelFarmState {
  v: typeof FARM_STATE_VERSION;
  /** C-150：地上的建筑，按放下先后排列。 */
  buildings: BuildingState[];
  /** buildings 里那栋 cottage 的镜像（没有为 null），给 0.4.4 及更早的客户端读；以 buildings 为准，不单独写。 */
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
  /** C-148：体力与上次结算时间、最近一次休息的玩家日；没有时按满体力（energy.ts energyOf）。 */
  energy?: EnergyState;
  /** C-154：地上的掉落物（含已喂、还没下的），按产生先后。 */
  drops: DropState[];
  /** C-154：上一个掉落物的编号；新掉落物取它 + 1。 */
  drop_seq: number;
  /** C-151：水桶里还能浇几格（0 到 watering.pail_uses）。 */
  pail_water: number;
  /** C-151：已发过的一次性补发编号 → 发放时间（rules.grants）。 */
  grants: Record<string, number>;
  /** C-152：农场等级，从 1 起。 */
  level: number;
  /** C-191：驿站委托板的格子、单号和今天的单数、完成奖（requests.ts）。 */
  board: BoardState;
  /** C-191：累计交了几单委托（羊圈解锁要用）。 */
  requests_done: number;
}

export type FarmCommand =
  /** 旧客户端（0.4.4 及更早）放首栋小屋，等于 place_building cottage，只是第二栋时仍报 HOUSE_PLACED。 */
  | { type: 'place_house'; x: number; y: number; rotation?: number }
  | { type: 'place_building'; building: string; x: number; y: number; rotation: number }
  | { type: 'clear_obstacle'; cell: string }
  | { type: 'till'; cell: string }
  | { type: 'sow'; cell: string; crop: string }
  | { type: 'harvest'; cell: string }
  | { type: 'sell'; item: string; count: number }
  | { type: 'buy'; item: string; count: number }
  | { type: 'gather'; object: string }
  | { type: 'claim_blueprint'; blueprint: string }
  | { type: 'rest' }
  /** C-154：在养殖建筑 building（建筑 id）里喂一次。 */
  | { type: 'feed'; building: number }
  /** C-154：捡起地上的掉落物 drop（掉落物 id）。 */
  | { type: 'pick_up'; drop: number }
  /** C-151：在编号为 building 的井旁把水桶打满。 */
  | { type: 'draw_water'; building: number }
  /** C-151：浇一格播下还没浇的作物。 */
  | { type: 'water'; cell: string }
  /** C-152：在 Scott 处把农场升到下一级。 */
  | { type: 'upgrade_farm' }
  /** C-191：在驿站委托板上接单、交单、放弃，request 是单号。 */
  | { type: 'accept_request' | 'deliver_request' | 'drop_request'; request: number };

/** 命令执行时服务端核实过的上下文：本人地块编号（来自 token 查到的那一行，不来自请求体）。 */
export interface FarmContext { parcel_id: string }

export type FarmOutcome =
  | { ok: true; state: ParcelFarmState }
  | { ok: false; index: number; code: string; detail?: Record<string, unknown> };

/** 认领时的空农场：背包为空，赠品等首次进入时再发（认领和进入不是同一个动作）。 */
export function emptyFarm(): ParcelFarmState {
  return { v: FARM_STATE_VERSION, buildings: [], house: null, cleared: [], tilled: [], crops: {}, bag: {}, welcomed_at: null,
    coins: 0, sales: 0, gathered: {}, blueprints_claimed: {}, drops: [], drop_seq: 0, pail_water: 0, grants: {}, level: 1,
    board: emptyBoard(), requests_done: 0 };
}

/**
 * 旧存档兼容：C-31 时期写下的地块农场没有经济字段，按开局值补上（金币 0、没卖过、没采过、没领过）；
 * C-150 之前的存档没有 buildings，按 house 补上（见 withBuildings）；C-151 之前的没有水桶次数和补发记录，按 0 次、没发过补上；
 * C-152 之前的没有等级，按 1 级补上；C-191 之前的没有委托板，按空板、0 单补上。
 * 只补缺的，不动已有字段；返回新对象，不改入参。
 */
export function withEconomy(state: ParcelFarmState): ParcelFarmState {
  const s = structuredClone(state) as Partial<ParcelFarmState> & ParcelFarmState;
  withBuildings(s);
  const count = (v: unknown) => Number.isInteger(v) && (v as number) >= 0 ? v as number : 0;
  const map = (v: unknown) => v && typeof v === 'object' && !Array.isArray(v) ? v as Record<string, number> : {};
  s.coins = count(s.coins);
  s.sales = count(s.sales);
  s.gathered = map(s.gathered);
  s.blueprints_claimed = map(s.blueprints_claimed);
  // C-154 之前的存档没有掉落物：空列表、编号从 0 起；不成形的条目丢掉，编号至少是现有最大编号。
  s.drops = Array.isArray(s.drops) ? s.drops.filter(isDrop) : [];
  s.drop_seq = Math.max(count(s.drop_seq), ...s.drops.map(d => d.id));
  s.pail_water = count(s.pail_water);
  s.grants = map(s.grants);
  s.level = Number.isInteger(s.level) && s.level >= 1 ? s.level : 1;
  s.board = boardOf(s.board);
  s.requests_done = count(s.requests_done);
  return s;
}

const isDrop = (d: unknown): d is DropState => {
  const x = d as DropState;
  const n = (v: unknown) => Number.isInteger(v) && (v as number) >= 0;
  return Boolean(x) && typeof x === 'object' && n(x.id) && x.id > 0 && typeof x.item === 'string' && n(x.amount) && x.amount > 0
    && n(x.building) && n(x.animal) && n(x.spot) && Number.isFinite(x.ready_at);
};

/**
 * C-150 之前的存档只有 house：转成 buildings 里 id 为 1 的一栋 cottage，位置、朝向、占地、模型和建成时间原样。
 * 有 buildings 就以它为准，house 按它重算成那栋 cottage 的镜像。就地修改 s。
 */
function withBuildings(s: Partial<ParcelFarmState> & ParcelFarmState): void {
  if (!Array.isArray(s.buildings)) s.buildings = s.house ? [{ id: 1, type: HOME_BUILDING, ...s.house }] : [];
  s.house = homeOf(s.buildings);
}

/** buildings 里第一栋 cottage 去掉 id 和类型，即旧存档的 house；没有为 null。 */
function homeOf(buildings: BuildingState[]): HouseState | null {
  const home = buildings.find(b => b.type === HOME_BUILDING);
  if (!home) return null;
  const { id: _id, type: _type, ...house } = home;
  return house;
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
 * 一次性补发（C-151）：rules.grants 里存档还没记下的，各发一次并记下发放时间；新玩家在首次进入时和赠品一起拿到，
 * 老玩家下次进入时拿到。都发过返回 null。gift 是这次发的物品合计。返回新对象，不改入参。
 */
export function grant(rules: ParcelRules, state: ParcelFarmState, now: number): { state: ParcelFarmState; gift: Record<string, number> } | null {
  const s = withEconomy(state);
  const gift: Record<string, number> = {};
  for (const [id, items] of Object.entries(rules.grants)) {
    if (Object.hasOwn(s.grants, id)) continue;
    for (const [item, n] of Object.entries(items)) {
      s.bag[item] = (s.bag[item] ?? 0) + n;
      gift[item] = (gift[item] ?? 0) + n;
    }
    s.grants[id] = now;
  }
  return Object.keys(gift).length ? { state: s, gift } : null;
}

/**
 * 换到新数据集（C-136，Q-168 rebase）：新数据集里同一块地是另一套格子，按格子记的进度放不上去，清空；
 * 和格子无关的保留。清空的是建筑、已清障碍、已开垦、作物和采集记录（采集冷却）；在地里的作物（不论熟没熟）
 * 每棵退一颗它的种子，每栋建筑退一张它那类的蓝图（C-150），可以重新盖。地上的掉落物（C-154）随建筑清空：已经下了的进背包，
 * 还没下的退回喂它的饲料。背包其余物品、金币、卖出次数、已领蓝图、赠品记录和农场等级（C-152）不动。
 * 规则里已没有的作物、建筑类型不知道该退什么，不退。返回新对象，不改入参。
 */
export function rebaseFarm(rules: ParcelRules, state: ParcelFarmState, now: number): ParcelFarmState {
  const s = withEconomy(state);
  for (const crop of Object.values(s.crops)) {
    const seed = rules.crops[crop.crop]?.seed;
    if (seed) s.bag[seed] = (s.bag[seed] ?? 0) + 1;
  }
  for (const b of s.buildings) {
    const blueprint = Object.hasOwn(rules.buildings, b.type) ? rules.buildings[b.type].blueprint : undefined;
    if (blueprint) s.bag[blueprint] = (s.bag[blueprint] ?? 0) + 1;
  }
  for (const d of s.drops) {
    const b = s.buildings.find(x => x.id === d.building);
    const rule = b && Object.hasOwn(rules.buildings, b.type) ? rules.buildings[b.type].livestock : undefined;
    // 已经下了的照样归玩家；没下的退喂它的饲料（C-181：喂一次几个就退几个；规则里已没有这类建筑就不知道退什么，不退）。
    if (d.ready_at <= now || rule === undefined) s.bag[d.item] = (s.bag[d.item] ?? 0) + d.amount;
    else s.bag[rule.feed] = (s.bag[rule.feed] ?? 0) + (rule.feed_amount ?? 1);
  }
  s.drops = [];
  s.buildings = [];
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
      case 'draw_water':
        if (!Number.isInteger(c.building) || (c.building as number) < 1 || (c.building as number) > 2 ** 30) return null;
        out.push({ type: 'draw_water', building: c.building as number });
        break;
      case 'place_house':
        if (!coord(c.x) || !coord(c.y) || (c.rotation !== undefined && ![0, 1, 2, 3].includes(c.rotation as number))) return null;
        out.push({ type: 'place_house', x: c.x, y: c.y, rotation: (c.rotation as number | undefined) ?? 0 });
        break;
      case 'place_building':
        if (typeof c.building !== 'string' || c.building.length > 64 || !coord(c.x) || !coord(c.y)
          || (c.rotation !== undefined && ![0, 1, 2, 3].includes(c.rotation as number))) return null;
        out.push({ type: 'place_building', building: c.building, x: c.x, y: c.y, rotation: (c.rotation as number | undefined) ?? 0 });
        break;
      case 'clear_obstacle': case 'till': case 'harvest': case 'water':
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
      case 'rest':
        out.push({ type: 'rest' });
        break;
      case 'feed':
        if (!Number.isInteger(c.building) || (c.building as number) < 1 || (c.building as number) > MAX_ID) return null;
        out.push({ type: 'feed', building: c.building as number });
        break;
      case 'pick_up':
        if (!Number.isInteger(c.drop) || (c.drop as number) < 1 || (c.drop as number) > MAX_ID) return null;
        out.push({ type: 'pick_up', drop: c.drop as number });
        break;
      case 'upgrade_farm':
        out.push({ type: 'upgrade_farm' });
        break;
      case 'accept_request': case 'deliver_request': case 'drop_request':
        if (!Number.isInteger(c.request) || (c.request as number) < 1 || (c.request as number) > MAX_ID) return null;
        out.push({ type: c.type, request: c.request as number });
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

interface Rect { x0: number; y0: number; x1: number; y1: number }
/** 建筑占的格子范围（含两端）；转 90°/270° 时宽深互换。 */
function footprint(h: { x: number; y: number; width: number; depth: number; rotation: number }): Rect {
  const [w, d] = h.rotation % 2 ? [h.depth, h.width] : [h.width, h.depth];
  return { x0: h.x, y0: h.y, x1: h.x + w - 1, y1: h.y + d - 1 };
}

const inRect = (f: Rect, x: number, y: number): boolean => x >= f.x0 && x <= f.x1 && y >= f.y0 && y <= f.y1;

/** 格子在哪栋建筑下面。 */
const underBuilding = (s: ParcelFarmState, cell: string): boolean => {
  const [x, y] = parseCell(cell)!;
  return s.buildings.some(b => inRect(footprint(b), x, y));
};

/** 占地 f 里已被其它建筑占的格，"x,y" 按字符串排序。 */
function overlapped(s: ParcelFarmState, f: Rect): string[] {
  const out: string[] = [];
  for (const b of s.buildings) {
    const o = footprint(b);
    for (let y = Math.max(f.y0, o.y0); y <= Math.min(f.y1, o.y1); y++)
      for (let x = Math.max(f.x0, o.x0); x <= Math.min(f.x1, o.x1); x++) out.push(`${x},${y}`);
  }
  return [...new Set(out)].sort();
}

/**
 * 一批命令全部成功才生效；任一失败整批不变，返回失败的序号。
 * ctx 是服务端从 token 查到的本人地块；没有 ctx 时采集一律按不是自家物件拒绝。
 * 体力先结算到 now；每条命令先做它自己的检查，再看体力够不够（NO_ENERGY 带 need / have / next_in），够了才改存档。
 * 委托板（C-191）在第一条命令前补到 now，整批成功后再补一次（交完的格子立即补上）。
 */
export function applyFarmCommands(rules: ParcelRules, state: ParcelFarmState, commands: FarmCommand[], now: number, ctx?: FarmContext): FarmOutcome {
  const s = withEconomy(state);
  const eco = rules.economy;
  settleEnergy(rules, s, now);
  settleBoard(rules, s, now);
  for (const [index, c] of commands.entries()) {
    const fail = (code: string, detail?: Record<string, unknown>): FarmOutcome => ({ ok: false, index, code, ...(detail ? { detail } : {}) });
    const cost = energyCost(rules, c);
    /** 体力够这条命令就扣掉并返回 null，不够返回拒绝。 */
    const pay = (): FarmOutcome | null => {
      if (cost <= 0) return null;
      const have = s.energy!.value;
      if (have < cost) return fail('NO_ENERGY', { need: cost, have, next_in: nextTickIn(rules, s, now) });
      spendEnergy(rules, s, now, cost);
      return null;
    };
    let refused: FarmOutcome | null = null;
    switch (c.type) {
      case 'place_house': case 'place_building': {
        // 服务端没有地块几何：只在核心区、不挡入口到出生点通道由客户端判断（farm_building.gd）；这里管格子之间的冲突。
        const type = c.type === 'place_house' ? HOME_BUILDING : c.building;
        const rule = Object.hasOwn(rules.buildings, type) ? rules.buildings[type] : undefined;
        if (!rule) return fail('UNKNOWN_BUILDING', { building: type });
        // C-152：每类的上限随农场等级（井 3 级 2 口、5 级 3 口）。
        const most = buildingMax(rules, type, s.level);
        if (s.buildings.filter(b => b.type === type).length >= most)
          return c.type === 'place_house' ? fail('HOUSE_PLACED') : fail('BUILDING_LIMIT', { building: type, max: most });
        if (s.buildings.length >= MAX_BUILDINGS) return fail('BUILDING_LIMIT', { max: MAX_BUILDINGS });
        if (!(s.bag[rule.blueprint] > 0)) return fail('NO_BLUEPRINT', { item: rule.blueprint });
        // C-154：除蓝图外的材料（默认没有）；不够就拒绝，什么都不扣。
        for (const [item, need] of Object.entries(rule.materials ?? {}))
          if ((s.bag[item] ?? 0) < need) return fail('NOT_ENOUGH', { item, have: s.bag[item] ?? 0, need });
        const id = s.buildings.reduce((m, b) => Math.max(m, b.id), 0) + 1;
        const building: BuildingState = { id, type, model: rule.model, x: c.x, y: c.y, width: rule.width, depth: rule.depth,
          rotation: c.rotation ?? 0, built_at: now };
        if (rule.livestock) building.animals = [...rule.livestock.animals];
        const f = footprint(building);
        if (f.x1 >= MAX_COORD || f.y1 >= MAX_COORD) return fail('OUT_OF_BOUNDS');
        const overlap = overlapped(s, f);
        if (overlap.length) return fail('BUILDING_OVERLAP', { cells: overlap });
        const covered = [...s.tilled, ...Object.keys(s.crops)].filter(cell => {
          const [x, y] = parseCell(cell)!;
          return inRect(f, x, y);
        });
        if (covered.length) return fail('CELL_OCCUPIED', { cells: [...new Set(covered)].sort() });
        take(s.bag, rule.blueprint, 1);
        for (const [item, need] of Object.entries(rule.materials ?? {})) take(s.bag, item, need);
        s.buildings.push(building);
        s.house = homeOf(s.buildings);
        break;
      }
      case 'clear_obstacle':
        if (s.cleared.includes(c.cell)) return fail('ALREADY_CLEARED');
        if (s.cleared.length >= MAX_CELLS) return fail('TOO_MANY_CELLS');
        if ((refused = pay())) return refused;
        s.cleared.push(c.cell);
        break;
      case 'till':
        if (!(s.bag[rules.till_tool] > 0)) return fail('NO_TOOL', { item: rules.till_tool });
        if (underBuilding(s, c.cell)) return fail('CELL_OCCUPIED', { cells: [c.cell] });
        if (s.tilled.includes(c.cell)) return fail('ALREADY_TILLED');
        if (s.tilled.length >= MAX_CELLS) return fail('TOO_MANY_CELLS');
        if ((refused = pay())) return refused;
        s.tilled.push(c.cell);
        break;
      case 'sow': {
        const rule = rules.crops[c.crop];
        if (!rule) return fail('UNKNOWN_CROP');
        if (!s.tilled.includes(c.cell)) return fail('NOT_TILLED');
        if (s.crops[c.cell]) return fail('CELL_OCCUPIED', { cells: [c.cell] });
        if (!(s.bag[rule.seed] > 0)) return fail('NO_SEED', { item: rule.seed });
        if ((refused = pay())) return refused;
        take(s.bag, rule.seed, 1);
        // C-151：播下是干土，不计时，浇过水才开始长。
        s.crops[c.cell] = { crop: c.crop, planted_at: now, ripe_at: NEVER, watered_at: null };
        break;
      }
      case 'draw_water': {
        // 服务端不知道人站在哪：“在井边”由客户端限定，这里核实这口井盖好了。
        const well = s.buildings.find(b => b.id === c.building);
        if (!well || well.type !== rules.watering.well) return fail('NO_WELL', { building: c.building });
        if (!(s.bag[rules.watering.pail] > 0)) return fail('NO_PAIL', { item: rules.watering.pail });
        if (s.pail_water >= rules.watering.pail_uses) return fail('PAIL_FULL', { water: s.pail_water });
        if ((refused = pay())) return refused;
        s.pail_water = rules.watering.pail_uses;
        break;
      }
      case 'water': {
        if (!(s.bag[rules.watering.pail] > 0)) return fail('NO_PAIL', { item: rules.watering.pail });
        const crop = s.crops[c.cell];
        if (!crop) return fail('NO_CROP');
        if (!isDry(crop)) return fail('ALREADY_WATERED');
        if (s.pail_water <= 0) return fail('PAIL_EMPTY');
        const grow = rules.crops[crop.crop]?.grow_seconds;
        if (grow === undefined) return fail('UNKNOWN_CROP');
        s.pail_water -= 1;
        crop.watered_at = now;
        crop.ripe_at = now + grow * 1000;
        break;
      }
      case 'harvest': {
        const crop = s.crops[c.cell];
        if (!crop) return fail('NO_CROP');
        if (isDry(crop)) return fail('NOT_WATERED');
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
        const total = price * c.count;
        if (s.coins < total) return fail('NOT_ENOUGH_COINS', { coins: s.coins, need: total });
        s.coins -= total;
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
        // 服务端没有地块几何（C-37）；能核实的是：建筑占地、开垦格、作物格、清过障碍的格都在核心区，不是外围。
        if (underBuilding(s, o.cell) || s.tilled.includes(o.cell) || s.crops[o.cell] || s.cleared.includes(o.cell)) return fail('NOT_OUTER');
        const id = objectId(o);
        const respawnMs = eco.gather.respawn_seconds * 1000;
        const last = s.gathered[id];
        if (last !== undefined && now < last + respawnMs) return fail('NOT_RESPAWNED', { ready_at: last + respawnMs });
        for (const [k, at] of Object.entries(s.gathered)) if (now >= at + respawnMs) delete s.gathered[k];
        if (Object.keys(s.gathered).length >= MAX_GATHERED) return fail('TOO_MANY_OBJECTS', { max: MAX_GATHERED });
        // 服务端不知道外围真有哪些物件：同一类刷新期内最多采配方里该类最多摆放的个数，编造编号也拿不到更多。
        const live = Object.keys(s.gathered).filter(k => src.models.includes(parseObjectId(k)?.model ?? '')).length;
        if (live >= src.max_objects) return fail('TOO_MANY_OBJECTS', { max: src.max_objects });
        if ((refused = pay())) return refused;
        s.gathered[id] = now;
        s.bag[src.item] = (s.bag[src.item] ?? 0) + src.amount;
        break;
      }
      case 'claim_blueprint': {
        const rule = Object.hasOwn(eco.blueprints, c.blueprint) ? eco.blueprints[c.blueprint] : undefined;
        if (!rule) return fail('UNKNOWN_BLUEPRINT');
        if (Object.hasOwn(s.blueprints_claimed, c.blueprint)) return fail('BLUEPRINT_CLAIMED');
        if (s.sales < rule.min_sales) return fail('CONDITION_NOT_MET', { sales: s.sales, min_sales: rule.min_sales });
        // C-181：带售价的蓝图（牛棚）要花金币买；单价只看服务端配置。
        const price = rule.coins ?? 0;
        if (s.coins < price) return fail('NOT_ENOUGH_COINS', { coins: s.coins, need: price });
        s.coins -= price;
        s.blueprints_claimed[c.blueprint] = now;
        s.bag[rule.item] = (s.bag[rule.item] ?? 0) + rule.amount;
        break;
      }
      case 'rest': {
        // 在自家小屋门口休息（C-137#16）：服务端不知道人站在哪，能核实的是建筑里已经有一栋小屋（cottage）；每个玩家日一次，不超过上限。
        if (!s.buildings.some(b => b.type === HOME_BUILDING)) return fail('NO_HOUSE');
        const e = s.energy!, today = dayKey(rules, now);
        if (e.rested_on === today) return fail('RESTED_TODAY', { resets_at: nextRollover(rules, now) });
        const max = maxEnergy(rules, s);
        if (e.value >= max) return fail('ENERGY_FULL');
        e.value += Math.min(rules.energy.rest_amount, max - e.value);
        e.rested_on = today;
        if (e.value >= max) e.at = now;
        break;
      }
      case 'feed': {
        // 服务端不知道人站在哪：在食盆前喂由客户端限定；这里核实建筑在、是养殖建筑、有饲料、有动物空着、地上没满。
        const b = s.buildings.find(x => x.id === c.building);
        if (!b) return fail('NO_BUILDING', { building: c.building });
        const rule = Object.hasOwn(rules.buildings, b.type) ? rules.buildings[b.type].livestock : undefined;
        if (!rule || !b.animals?.length) return fail('NOT_LIVESTOCK', { building: c.building });
        // C-181：喂一次 feed_amount 个（牛 2 根胡萝卜，鸡 1 根）。
        const portion = rule.feed_amount ?? 1;
        if ((s.bag[rule.feed] ?? 0) < portion) return fail('NO_FEED', { item: rule.feed });
        const mine = s.drops.filter(d => d.building === b.id);
        if (mine.length >= rule.max_ground) return fail('GROUND_FULL', { max: rule.max_ground });
        const waiting = new Set(mine.filter(d => d.ready_at > now).map(d => d.animal));
        const animal = b.animals.findIndex((_, i) => !waiting.has(i));
        if (animal < 0) return fail('ANIMALS_FED', { next_at: Math.min(...mine.filter(d => d.ready_at > now).map(d => d.ready_at)) });
        if ((refused = pay())) return refused;
        take(s.bag, rule.feed, portion);
        const id = ++s.drop_seq;
        s.drops.push({ id, item: rule.product, amount: rule.amount, building: b.id, animal, spot: freeSpot(rule.spots.length, mine, id),
          ready_at: now + rule.produce_seconds * 1000 });
        break;
      }
      case 'pick_up': {
        // “人走近”只有客户端知道；服务端核实掉落物在、已经下了。捡过就删，同一个编号不会再有。
        const at = s.drops.findIndex(d => d.id === c.drop);
        if (at < 0) return fail('NO_DROP', { drop: c.drop });
        const d = s.drops[at];
        if (now < d.ready_at) return fail('NOT_READY', { ready_at: d.ready_at });
        s.drops.splice(at, 1);
        s.bag[d.item] = (s.bag[d.item] ?? 0) + d.amount;
        break;
      }
      case 'upgrade_farm': {
        // 在 Scott 处升级（C-152）：服务端不知道人站在哪，“在 Scott 那里”由客户端限定。先核材料（按配置先后）再核金币，不花体力。
        const next = nextFarmLevel(rules, s.level);
        if (!next) return fail('MAX_LEVEL', { level: s.level });
        for (const [item, need] of Object.entries(next.items)) {
          const have = s.bag[item] ?? 0;
          if (have < need) return fail('NOT_ENOUGH', { item, have, need });
        }
        if (s.coins < next.coins) return fail('NOT_ENOUGH_COINS', { coins: s.coins, need: next.coins });
        for (const [item, n] of Object.entries(next.items)) take(s.bag, item, n);
        s.coins -= next.coins;
        for (const [item, n] of Object.entries(next.gift ?? {})) s.bag[item] = (s.bag[item] ?? 0) + n;
        // 体力上限跟着加；体力已在本批开头结算到 now，满条时计时从 now 起，所以新加的上限从现在开始回。
        s.level = next.level;
        break;
      }
      case 'accept_request': case 'deliver_request': case 'drop_request': {
        // 在驿站委托板前（C-191）：服务端不知道人站在哪，“在驿站”由客户端限定。
        const refusal = requestCommand(rules, s, c, now, fail as Parameters<typeof requestCommand>[4], MAX_COINS);
        if (refusal) return refusal;
        break;
      }
    }
  }
  settleBoard(rules, s, now);
  return { ok: true, state: s };
}

/**
 * 新掉落物的落点：这栋建筑地上没被占的落点里挑一个（落点数不少于地上上限，总有空的）。按掉落物编号错开，
 * 同一份存档总是挑同一个，不靠随机数。
 */
function freeSpot(spots: number, taken: DropState[], id: number): number {
  const used = new Set(taken.map(d => d.spot));
  const free = Array.from({ length: spots }, (_, i) => i).filter(i => !used.has(i));
  return free[(id * 7) % free.length];
}

function take(bag: Record<string, number>, id: string, n: number): void {
  bag[id] -= n;
  if (bag[id] <= 0) delete bag[id];
}
