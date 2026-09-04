/**
 * 内容表加载与校验。`assets/farm/data/*.json` 是**唯一来源**：Godot 与服务端读同一份，
 * 服务端构建时打进镜像。代码里不出现游戏数值字面量（测试断言除外）——数值改动应该只改
 * 这些 JSON，然后由账本测试证明改对了。
 *
 * `_` 开头的键是 PRD 行号注释，随内容一起参与 content_version 哈希：注释变了也算内容变了，
 * 这样「某个数值为什么是这个值」的依据不会和数值本身脱节。
 */
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import path from 'node:path';

export class ContentError extends Error {
  constructor(message: string) {
    super(`ContentError: ${message}`);
    this.name = 'ContentError';
  }
}

export const CROP_IDS = ['R', 'L', 'C', 'H'] as const;
export type CropId = (typeof CROP_IDS)[number];
export const DISH_IDS = ['salad', 'tea'] as const;
export type DishId = (typeof DISH_IDS)[number];
export const RESIDENT_IDS = ['nursery_keeper', 'bistro_owner', 'restorer'] as const;
export type ResidentId = (typeof RESIDENT_IDS)[number];
export const FIELD_CONDITIONS = ['sunny', 'rain', 'wind'] as const;
export type FieldCondition = (typeof FIELD_CONDITIONS)[number];
export const CARE_KINDS = ['water', 'drain', 'shelter'] as const;
export type CareKind = (typeof CARE_KINDS)[number];
export const GROWTH_CHOICE_IDS = ['tool', 'field'] as const;
export type GrowthChoiceId = (typeof GROWTH_CHOICE_IDS)[number];

export type CropAmounts = Partial<Record<CropId, number>>;

export interface Content {
  crops: {
    crops: Record<CropId, { duration_ms: number; seed_price: number; yield: number; unit_price: number }>;
    d0_tutorial: { crop: CropId; count: number; duration_ms: number };
  };
  weather: {
    script: FieldCondition[];
    care_action: Record<FieldCondition, CareKind>;
    protected_slots: number[];
    day_rollover_hour: number;
  };
  xp: {
    sources: Record<string, { xp: number; daily_cap_plants?: number }>;
    level_thresholds: number[];
    target_cumulative: number[];
  };
  relationships: {
    residents: Record<ResidentId, { available_from_chapter: number; full: boolean }>;
    stages: { id: string; min: number; max: number; requires?: string }[];
    points: Record<string, { points: number; per: string; week_cap?: number; cap?: number }>;
    gift_clues: Record<ResidentId, CropId[]>;
    target_points_by_day: Record<ResidentId, number[]>;
  };
  chapters: {
    chapters: {
      index: number;
      min_facts: string[];
      grants: CropAmounts;
      tutorial_crop?: CropId;
      life_choice_crop?: CropId;
      unlocks: string[];
      nursery_stage?: string;
      subsidy?: string;
      shared_events?: { id: string; resident: ResidentId }[];
    }[];
    life_priority_threshold: number;
    max_new_chapters_per_player_day: number;
  };
  requests: {
    requests: Record<string, {
      chapter: number; resident: ResidentId; personal_story: boolean;
      items?: CropAmounts; dishes?: Partial<Record<DishId, number>>; coins: number;
    }>;
  };
  recipes: {
    recipes: Record<DishId, { inputs: CropAmounts; stall_price: number }>;
    buyback: { dish: DishId; coins: number; per_player_day: number; per_week: number; counts_against_stall_budget: boolean };
  };
  economy: {
    initial_wallet: number;
    stall_budget_per_day: number;
    growth_choice: {
      tool: { price: number };
      field: { price: number; seed_basket: CropAmounts; beds_unlocked_after: number };
    };
    subsidies: Record<string, { chapter: number; coins: number }>;
    engineering_quota: CropAmounts;
    seedling_pack: { contents: CropAmounts; bound: boolean; per_player_day: number; week_cap: number };
    target_wallet_by_day: Record<'tool' | 'field', number[]>;
    target_account_value_d6: number;
    sell_first_extra_coins: number;
    account_value_cap_multiplier: number;
  };
}

const FILES = [
  'crops', 'weather_script', 'xp', 'relationships', 'chapters', 'requests', 'recipes', 'economy',
] as const;

/** 只做本层能判定的检查；跨表一致性（例如 grants 里的作物必须在 crops 里）单列在下面。 */
function requireArray(v: unknown, len: number, what: string): void {
  if (!Array.isArray(v) || v.length !== len) throw new ContentError(`${what} 应有 ${len} 项`);
}

function checkContent(c: Content): void {
  for (const id of CROP_IDS) {
    const crop = c.crops.crops[id];
    if (!crop) throw new ContentError(`crops.${id} 缺失`);
    // `_` 开头是 PRD 行号注释，不参与数值校验（但参与 content_version 哈希）。
    for (const [k, v] of Object.entries(crop))
      if (!k.startsWith('_') && (typeof v !== 'number' || v <= 0))
        throw new ContentError(`crops.${id}.${k} 必须是正数`);
  }
  requireArray(c.weather.script, 7, 'weather.script');
  for (const cond of c.weather.script)
    if (!FIELD_CONDITIONS.includes(cond)) throw new ContentError(`未知田况 ${cond}`);
  for (const cond of FIELD_CONDITIONS)
    if (!CARE_KINDS.includes(c.weather.care_action[cond])) throw new ContentError(`care_action.${cond} 非法`);
  requireArray(c.xp.level_thresholds, 7, 'xp.level_thresholds');
  requireArray(c.xp.target_cumulative, 7, 'xp.target_cumulative');
  requireArray(c.chapters.chapters, 7, 'chapters.chapters');
  c.chapters.chapters.forEach((ch, i) => {
    if (ch.index !== i) throw new ContentError(`chapters[${i}].index 应为 ${i}`);
    if (ch.min_facts.length === 0) throw new ContentError(`chapters[${i}].min_facts 不能为空`);
    for (const id of Object.keys(ch.grants))
      if (!id.startsWith('_') && !CROP_IDS.includes(id as CropId))
        throw new ContentError(`chapters[${i}].grants 含未知作物 ${id}`);
  });
  for (const [id, r] of Object.entries(c.requests.requests)) {
    if (!RESIDENT_IDS.includes(r.resident)) throw new ContentError(`requests.${id}.resident 未知`);
    if (r.chapter < 0 || r.chapter > 6) throw new ContentError(`requests.${id}.chapter 越界`);
    if (!r.items && !r.dishes) throw new ContentError(`requests.${id} 既无 items 也无 dishes`);
  }
  for (const id of DISH_IDS)
    if (!c.recipes.recipes[id]) throw new ContentError(`recipes.${id} 缺失`);
  // 扩地固定篮必须恰好 12 枚：账本里的 84 金币是按这个篮子算出来的（Codex 二审 Critical 1）。
  const basket = c.economy.growth_choice.field.seed_basket;
  const seeds = Object.values(basket).reduce<number>((n, v) => n + (v ?? 0), 0);
  if (seeds !== 12) throw new ContentError(`扩地种子篮应恰好 12 枚，收到 ${seeds}`);
  requireArray(c.economy.target_wallet_by_day.tool, 7, 'economy.target_wallet_by_day.tool');
  requireArray(c.economy.target_wallet_by_day.field, 7, 'economy.target_wallet_by_day.field');
  for (const rid of RESIDENT_IDS) {
    if (!c.relationships.residents[rid]) throw new ContentError(`relationships.residents.${rid} 缺失`);
    requireArray(c.relationships.target_points_by_day[rid], 7, `target_points_by_day.${rid}`);
    for (const crop of c.relationships.gift_clues[rid] ?? [])
      if (!CROP_IDS.includes(crop)) throw new ContentError(`gift_clues.${rid} 含未知作物 ${crop}`);
  }
}

export function loadContent(dir: string): Content {
  const raw: Record<string, unknown> = {};
  for (const name of FILES) {
    const file = path.join(dir, `${name}.json`);
    try {
      raw[name] = JSON.parse(readFileSync(file, 'utf8'));
    } catch (err) {
      throw new ContentError(`读取 ${file} 失败: ${err instanceof Error ? err.message : String(err)}`);
    }
  }
  const c: Content = {
    crops: raw.crops as Content['crops'],
    weather: raw.weather_script as Content['weather'],
    xp: raw.xp as Content['xp'],
    relationships: raw.relationships as Content['relationships'],
    chapters: raw.chapters as Content['chapters'],
    requests: raw.requests as Content['requests'],
    recipes: raw.recipes as Content['recipes'],
    economy: raw.economy as Content['economy'],
  };
  checkContent(c);
  return c;
}

/**
 * 内容版本：文件名进入哈希输入，避免「按文件名排序后直接拼接」的歧义
 * （两组不同的文件可以拼出同一个字符串，Codex 三审 O-I6）。
 */
export function contentVersion(dir: string): string {
  const parts = FILES.map(name => ({
    name,
    content: readFileSync(path.join(dir, `${name}.json`), 'utf8'),
  }));
  return createHash('sha256').update(JSON.stringify(parts), 'utf8').digest('hex').slice(0, 16);
}

export const DEFAULT_CONTENT_DIR = path.resolve(
  path.dirname(new URL(import.meta.url).pathname), '..', '..', '..', 'assets', 'farm', 'data',
);
