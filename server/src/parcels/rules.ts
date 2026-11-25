/**
 * 动态农场（C-31）的可调数值：社区与数据集、首次进入自家地块的赠品、各类建筑的占地与蓝图（C-150）、作物成熟时间；
 * 以及地块经济（C-58）：出售价格、外围采集与刷新时间、领蓝图条件；买入价格（C-149：Jasmine 卖种子，胡萝卜种子 9 照 P0，
 * 所有者 C-137#15 第 3 题“照搬p0”）。
 * 默认值按所有者拍板 Q-39（C-34#14）与 Q-40（C-33#14），经济按 C-30#29 第 3–5 题（C-30#30 写入的推荐）。
 * 来源是 assets/farm/data/dynamic_farm.json；它不在 content_version 的指纹里，改它不影响旧农场存档。
 */
import { readFileSync } from 'node:fs';
import path from 'node:path';

export interface CropRule { seed: string; grow_seconds: number; yield: number }
/**
 * 外围一类物件（树、花丛、石堆）：采一次得 amount 个 item；models 是美术配方里该类的模型名；
 * max_objects 是一块地上该类最多摆多少个（等于配方 outer_groves.targets.<类>.cap），刷新期内最多采这么多个不同物件。
 */
export interface GatherSource { item: string; amount: number; max_objects: number; models: string[] }
/**
 * 一种可摆放的建筑（C-150）：模型名、放下要扣的蓝图、未转向时的占地（宽沿格 x、深沿格 y）和一块地上最多几栋。
 * 转 90°/270° 时宽深互换。客户端按同一个类型编号取模型和碰撞（modules/dynamic_farm/farm_building.gd）。
 */
export interface BuildingRule { model: string; blueprint: string; width: number; depth: number; max: number }
/** 一次性领取的蓝图：卖成功过至少 min_sales 次后可领，只发一次。 */
export interface BlueprintRule { item: string; amount: number; min_sales: number }
export interface EconomyRules {
  /** 能卖的物品与单价（金币）；不在表里的不能卖。 */
  sell_prices: Record<string, number>;
  /** C-149：Jasmine 柜台能买的物品与单价（金币）；不在表里的不能买。没有这一项等于什么都不卖。 */
  buy_prices: Record<string, number>;
  gather: {
    /** 锁定的外围美术配方版本（499-art-recipe.json 的 outer_groves.version）；编号里的版本不同就拒收。 */
    recipe_version: string;
    /** 采过后按服务端时间多少秒重新可采。 */
    respawn_seconds: number;
    sources: Record<string, GatherSource>;
  };
  blueprints: Record<string, BlueprintRule>;
}
export interface ParcelRules {
  version: 1;
  /** 地块数据集归哪个社区：社区编号由服务端按数据集推出，客户端不能自报。datasets 按发布先后排列，新的在后（C-136）。 */
  communities: { id: string; datasets: string[] }[];
  /** 首次进入自己的地块发一次（锄头、种子、首栋住宅蓝图）；重开、重试不重发。 */
  welcome_gift: Record<string, number>;
  till_tool: string;
  /**
   * 可摆放的建筑，键是类型编号（C-150）。放一栋消耗一张对应 blueprint，放下即建成。
   * 必须有 cottage（首栋住宅，Q-40）：旧存档的 house 和旧客户端的 place_house 都按它算。
   */
  buildings: Record<string, BuildingRule>;
  crops: Record<string, CropRule>;
  economy: EconomyRules;
}

export const RULES_FILE = 'dynamic_farm.json';
/** 首栋住宅的建筑类型：C-150 之前存档里唯一的 house、旧客户端 place_house 放的都是它。 */
export const HOME_BUILDING = 'cottage';
/** 一块地上所有建筑合计最多几栋；单类的 max 也不超过它。 */
export const MAX_BUILDINGS = 64;
/** 建筑一边最多几格。 */
export const MAX_BUILDING_SIDE = 16;
const ID_RE = /^[a-z0-9_-]{1,64}$/;
const isId = (v: unknown): v is string => typeof v === 'string' && ID_RE.test(v);
const count = (v: unknown, min: number, max: number): v is number => Number.isInteger(v) && (v as number) >= min && (v as number) <= max;

/** 不合法就抛错：启动时发现，而不是在第一次认领时。 */
export function parseParcelRules(raw: unknown): ParcelRules {
  const r = raw as ParcelRules;
  const fail = (what: string): never => { throw new Error(`${RULES_FILE}: ${what}`); };
  if (!r || r.version !== 1) fail('version 必须为 1');
  if (!Array.isArray(r.communities) || !r.communities.length) fail('communities 不能为空');
  const datasets = new Set<string>();
  for (const c of r.communities) {
    if (!isId(c?.id) || !Array.isArray(c.datasets) || !c.datasets.length) fail('社区格式不对');
    for (const d of c.datasets) {
      if (!isId(d) || datasets.has(d)) fail(`数据集 ${d} 格式不对或重复`);
      datasets.add(d);
    }
  }
  if (!r.welcome_gift || typeof r.welcome_gift !== 'object') fail('welcome_gift 缺失');
  for (const [id, n] of Object.entries(r.welcome_gift)) if (!isId(id) || !count(n, 1, 999)) fail(`welcome_gift.${id} 不对`);
  if (!isId(r.till_tool)) fail('till_tool 缺失');
  if (!r.buildings || typeof r.buildings !== 'object' || Array.isArray(r.buildings)) fail('buildings 缺失');
  for (const [id, b] of Object.entries(r.buildings))
    if (!isId(id) || !b || !isId(b.model) || !isId(b.blueprint) || !count(b.width, 1, MAX_BUILDING_SIDE) || !count(b.depth, 1, MAX_BUILDING_SIDE)
      || !count(b.max, 1, MAX_BUILDINGS)) fail(`buildings.${id} 不对`);
  if (!Object.hasOwn(r.buildings, HOME_BUILDING)) fail(`buildings 缺少 ${HOME_BUILDING}`);
  if (!r.crops || !Object.keys(r.crops).length) fail('crops 不能为空');
  for (const [id, c] of Object.entries(r.crops))
    if (!isId(id) || !isId(c?.seed) || !count(c.grow_seconds, 1, 30 * 24 * 3600) || !count(c.yield, 1, 99)) fail(`crops.${id} 不对`);
  parseEconomy(r.economy, fail);
  return r;
}

/** 价格、采集、蓝图条件的边界：卖出和买入单价 1–100000，刷新 1 秒–30 天，每次 1–99 个，模型名不跨类重复。 */
function parseEconomy(e: EconomyRules | undefined, fail: (what: string) => never): void {
  if (!e || typeof e !== 'object') fail('economy 缺失');
  const isMap = (v: unknown): v is Record<string, unknown> => Boolean(v) && typeof v === 'object' && !Array.isArray(v);
  if (!isMap(e!.sell_prices) || !Object.keys(e!.sell_prices).length) fail('economy.sell_prices 不能为空');
  for (const [id, price] of Object.entries(e!.sell_prices)) if (!isId(id) || !count(price, 1, 100_000)) fail(`economy.sell_prices.${id} 不对`);
  if (e!.buy_prices === undefined) e!.buy_prices = {};
  if (!isMap(e!.buy_prices)) fail('economy.buy_prices 不对');
  for (const [id, price] of Object.entries(e!.buy_prices)) if (!isId(id) || !count(price, 1, 100_000)) fail(`economy.buy_prices.${id} 不对`);
  const g = e!.gather;
  if (!isMap(g) || !isId(g.recipe_version) || !count(g.respawn_seconds, 1, 30 * 24 * 3600) || !isMap(g.sources) || !Object.keys(g.sources).length)
    fail('economy.gather 不对');
  const models = new Set<string>();
  for (const [kind, src] of Object.entries(g.sources)) {
    if (!isId(kind) || !isMap(src) || !isId(src.item) || !count(src.amount, 1, 99) || !count(src.max_objects, 1, 1000)
      || !Array.isArray(src.models) || !src.models.length)
      fail(`economy.gather.sources.${kind} 不对`);
    for (const m of src.models) {
      if (!isId(m) || models.has(m)) fail(`economy.gather 模型 ${m} 格式不对或重复`);
      models.add(m);
    }
  }
  if (!isMap(e!.blueprints)) fail('economy.blueprints 缺失');
  for (const [id, b] of Object.entries(e!.blueprints))
    if (!isId(id) || !isMap(b) || !isId(b.item) || !count(b.amount, 1, 99) || !count(b.min_sales, 0, 1000)) fail(`economy.blueprints.${id} 不对`);
}

/** 模型名对应的外围物件类别（tree / flower / rock）；不可采的模型返回 null。 */
export function gatherSourceOf(rules: ParcelRules, model: string): GatherSource | null {
  for (const src of Object.values(rules.economy.gather.sources)) if (src.models.includes(model)) return src;
  return null;
}

export function loadParcelRules(contentDir: string): ParcelRules {
  return parseParcelRules(JSON.parse(readFileSync(path.join(contentDir, RULES_FILE), 'utf8')));
}

/** 数据集所属社区；未登记的数据集返回 null。 */
export function communityOf(rules: ParcelRules, dataset: string): string | null {
  return rules.communities.find(c => c.datasets.includes(dataset))?.id ?? null;
}

/**
 * 认领能否从数据集 from 换到 to（C-136，Q-168 rebase）：两个都已登记、同属一个社区，且 to 比 from 新。
 * 新旧按社区 datasets 里的先后：后登记的是新版本（发新数据集时追加在末尾）。只能往新换，不能换回旧的。
 */
export function isNewerDataset(rules: ParcelRules, from: string, to: string): boolean {
  const c = rules.communities.find(x => x.datasets.includes(from));
  return Boolean(c) && c!.datasets.indexOf(to) > c!.datasets.indexOf(from);
}
