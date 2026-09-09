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
export const DECORATION_IDS = ['bench', 'planter', 'lantern', 'fountain', 'sign', 'crate'] as const;
export type DecorationId = (typeof DECORATION_IDS)[number];

export type CropAmounts = Partial<Record<CropId, number>>;
export type JourneyMaterial = 'wood' | 'stone' | 'fiber';
export const STREET_EFFECT_IDS = ['leaves', 'flowers', 'benches', 'baskets', 'picnic', 'tea'] as const;
export type StreetEffect = (typeof STREET_EFFECT_IDS)[number];
export interface JourneyProjectStage {
  name: string;
  materials: Partial<Record<JourneyMaterial, number>>;
  produce: CropAmounts;
  dishes: Partial<Record<DishId, number>>;
}

export interface JourneyContent {
  version: 1;
  contribution_steps: number;
  gatherings: { requires: string[]; themes: Record<string, { name: string; place: string;
    item: string; dish: DishId; coins: number; icon: string }> };
  crops: Record<CropId, { duration_ms: number; unit_price: number }>;
  dish_prices: Record<DishId, number>;
  discoveries: Record<string, { name: string; place: string; position: [number, number]; item: string;
    requires: string[]; hint: string; benefit: string; choices: Record<string, { name: string;
      materials: Partial<Record<JourneyMaterial, number>>; produce: CropAmounts; seeds: CropAmounts; requires?: string }> }>;
  costs: Record<'repair_workbench' | 'craft_planter' | 'clear_side_path', number>;
  workshop: { display_slots: number; recipes: Record<string, JourneyProjectStage & { requires: string[]; coins: number }> };
  stories: Record<ResidentId, (JourneyProjectStage & { id: string; requires: string[]; hint: string;
    points: number; shared: boolean; quote: string })[]>;
  routes: Record<string, { name: string; place: string; material: JourneyMaterial; bonus: number; requires?: string;
    surface?: 'street' }>;
  projects: Record<string, { name: string; place: string; position: [number, number]; requires: string;
    benefit: string; stages: JourneyProjectStage[] }>;
  milestones: { id: string; name: string; facts: string[]; unlocks: string[]; grants: CropAmounts }[];
  nodes: { id: string; place: string; position: [number, number]; wood: number; requires?: string;
    alternative?: { position: [number, number]; requires: string; materials: Partial<Record<JourneyMaterial, number>> } }[];
  opportunities: Record<string, { name: string; effect: StreetEffect; dishes: Partial<Record<DishId, number>>;
    wood: number; produce: CropAmounts; coins: number; requires?: string }[]>;
}

export interface Content {
  journey: JourneyContent;
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
  decorations: {
    anchor_id: 'courtyard';
    unit_m: number;
    bounds_q: { min_x: number; max_x: number; min_z: number; max_z: number };
    min_abs_x_q: number;
    blocked_outer: { min_abs_x_q: number; max_z_q: number };
    min_distance_q: number;
    props: Record<DecorationId, { name: string; default_offset_q: [number, number] }>;
  };
}

const FILES = [
  'crops', 'weather_script', 'xp', 'relationships', 'chapters', 'requests', 'recipes', 'economy', 'decorations', 'journey',
] as const;

/** 只做本层能判定的检查；跨表一致性（例如 grants 里的作物必须在 crops 里）单列在下面。 */
function requireArray(v: unknown, len: number, what: string): void {
  if (!Array.isArray(v) || v.length !== len) throw new ContentError(`${what} 应有 ${len} 项`);
}

function checkContent(c: Content): void {
  if (c.journey.version !== 1) throw new ContentError('journey.version unsupported');
  const positive = (n: unknown): boolean => Number.isSafeInteger(n) && Number(n) > 0;
  for (const id of CROP_IDS)
    if (!positive(c.journey.crops[id]?.duration_ms) || !positive(c.journey.crops[id]?.unit_price))
      throw new ContentError(`journey.crops.${id} invalid`);
  for (const id of DISH_IDS)
    if (!positive(c.journey.dish_prices[id])) throw new ContentError(`journey.dish_prices.${id} invalid`);
  for (const action of ['repair_workbench', 'craft_planter', 'clear_side_path'] as const)
    if (!positive(c.journey.costs[action])) throw new ContentError('journey.costs invalid');
  const facts = new Set(['first_harvest', 'met_nursery', 'met_bistro', 'workbench', 'planter_crafted',
    'shared_meal', 'planter_placed', 'side_path', 'planter_planted']);
  if (!c.journey.milestones.length || new Set(c.journey.milestones.map(m => m.id)).size !== c.journey.milestones.length)
    throw new ContentError('journey milestones must be nonempty and unique');
  for (const milestone of c.journey.milestones) {
    if (!milestone.id || !milestone.name || !milestone.facts.length || !milestone.facts.every(f => facts.has(f))
      || !milestone.unlocks.every(u => typeof u === 'string' && u.length > 0))
      throw new ContentError('journey milestone invalid');
    for (const [id, n] of Object.entries(milestone.grants))
      if (!CROP_IDS.includes(id as CropId) || !positive(n)) throw new ContentError('journey grant invalid');
  }
  const capabilities = new Set(c.journey.milestones.flatMap(m => m.unlocks));
  const materials = ['wood', 'stone', 'fiber'];
  const places = ['nursery', 'bistro', 'courtyard'];
  const workshop = c.journey.workshop;
  if (!workshop || !positive(workshop.display_slots) || workshop.display_slots > 3 || !Object.keys(workshop.recipes).length)
    throw new ContentError('journey workshop invalid');
  const activityFacts = new Set([...facts, ...Object.keys(workshop.recipes).map(id => `crafted_${id}`),
    ...Object.entries(c.journey.projects).flatMap(([id, p]) => p.stages.map((_, i) => `project_${id}_${i}`))]);
  const storyIds = new Set<string>();
  for (const id of RESIDENT_IDS) {
    if (!Array.isArray(c.journey.stories?.[id])) throw new ContentError('journey stories missing');
    for (const story of c.journey.stories[id]) {
      if (!story.id || storyIds.has(story.id)) throw new ContentError('journey story id invalid');
      storyIds.add(story.id);
      activityFacts.add(`story_${story.id}`);
    }
  }
  const validateActivity = (activity: JourneyProjectStage & { requires: string[] }) => {
    if (!activity.name || !Array.isArray(activity.requires) || !activity.requires.every(f => activityFacts.has(f)))
      throw new ContentError('journey activity requirements invalid');
    if (![activity.materials, activity.produce, activity.dishes].some(cost => Object.keys(cost).length))
      throw new ContentError('journey activity cost empty');
    for (const [cost, ids] of [[activity.materials, materials], [activity.produce, CROP_IDS], [activity.dishes, DISH_IDS]] as const)
      for (const [id, qty] of Object.entries(cost))
        if (!(ids as readonly string[]).includes(id) || !positive(qty)) throw new ContentError('journey activity cost invalid');
  };
  for (const [id, recipe] of Object.entries(workshop.recipes)) {
    if (!DECORATION_IDS.includes(id as DecorationId) || !positive(recipe.coins)) throw new ContentError('journey recipe invalid');
    validateActivity(recipe);
  }
  if (!c.journey.discoveries || !Object.keys(c.journey.discoveries).length)
    throw new ContentError('journey discoveries missing');
  for (const [id, discovery] of Object.entries(c.journey.discoveries)) {
    if (!/^[a-z_]+$/.test(id) || !discovery.name || !discovery.hint || !discovery.benefit
      || !places.includes(discovery.place) || !Object.hasOwn(workshop.recipes, discovery.item)
      || !Array.isArray(discovery.requires) || !discovery.requires.every(f => activityFacts.has(f))
      || discovery.position.length !== 2 || !discovery.position.every(Number.isFinite)
      || Object.keys(discovery.choices).length < 2)
      throw new ContentError('journey discovery invalid');
    for (const choice of Object.values(discovery.choices)) {
      if (!choice.name || (choice.requires && !capabilities.has(choice.requires))
        || ![choice.materials, choice.produce, choice.seeds].some(reward => Object.keys(reward).length))
        throw new ContentError('journey discovery choice invalid');
      for (const [reward, ids] of [[choice.materials, materials], [choice.produce, CROP_IDS], [choice.seeds, CROP_IDS]] as const)
        for (const [key, qty] of Object.entries(reward))
          if (!(ids as readonly string[]).includes(key) || !positive(qty)) throw new ContentError('journey discovery reward invalid');
    }
  }
  for (const stories of Object.values(c.journey.stories))
    for (const story of stories) {
      validateActivity(story);
      if (!positive(story.points) || typeof story.shared !== 'boolean' || !story.quote || !story.hint)
        throw new ContentError('journey story invalid');
    }
  const gatherings = c.journey.gatherings;
  if (!gatherings || !Array.isArray(gatherings.requires) || !gatherings.requires.length
    || !gatherings.requires.every(f => activityFacts.has(f)) || !gatherings.themes
    || Object.keys(gatherings.themes).length !== 2)
    throw new ContentError('journey gatherings invalid');
  for (const [id, theme] of Object.entries(gatherings.themes))
    if (!['garden', 'lantern'].includes(id) || !theme || typeof theme.name !== 'string' || !theme.name || !places.includes(theme.place)
      || !Object.hasOwn(workshop.recipes, theme.item) || !DISH_IDS.includes(theme.dish)
      || !positive(theme.coins) || typeof theme.icon !== 'string' || !theme.icon)
      throw new ContentError('journey gathering theme invalid');
  if (!c.journey.routes.neighbourhood || !Object.keys(c.journey.projects).length)
    throw new ContentError('journey routes/projects missing');
  for (const route of Object.values(c.journey.routes))
    if (!route.name || !places.includes(route.place) || !materials.includes(route.material)
      || !Number.isSafeInteger(route.bonus) || route.bonus < 0 || (route.requires && !capabilities.has(route.requires))
      || (route.surface !== undefined && (route.surface !== 'street' || route.place !== 'bistro')))
      throw new ContentError('journey route invalid');
  for (const project of Object.values(c.journey.projects)) {
    if (!project.name || !places.includes(project.place) || !facts.has(project.requires)
      || project.position.length !== 2 || !project.position.every(Number.isFinite) || !project.stages.length)
      throw new ContentError('journey project invalid');
    for (const stage of project.stages) {
      if (!stage.name || ![stage.materials, stage.produce, stage.dishes].some(cost => Object.keys(cost).length))
        throw new ContentError('journey project stage empty');
      for (const [cost, ids] of [[stage.materials, materials], [stage.produce, CROP_IDS], [stage.dishes, DISH_IDS]] as const)
        for (const [id, qty] of Object.entries(cost))
          if (!(ids as readonly string[]).includes(id) || !positive(qty)) throw new ContentError('journey project cost invalid');
    }
  }
  if (!c.journey.nodes.length || new Set(c.journey.nodes.map(n => n.id)).size !== c.journey.nodes.length)
    throw new ContentError('journey.nodes must be nonempty and unique');
  for (const node of c.journey.nodes) {
    if (!['nursery', 'bistro', 'courtyard'].includes(node.place) || !positive(node.wood)
      || !node.id || (node.requires && !facts.has(node.requires))
      || node.position.length !== 2 || !node.position.every(Number.isFinite))
      throw new ContentError('journey.node invalid');
    const alternative = node.alternative;
    if (alternative && (!facts.has(alternative.requires) || alternative.position.length !== 2
      || !alternative.position.every(Number.isFinite) || !Object.keys(alternative.materials).length
      || Object.entries(alternative.materials).some(([id, qty]) => !materials.includes(id as JourneyMaterial) || !positive(qty))))
      throw new ContentError('journey.node alternative invalid');
  }
  if (!positive(c.journey.contribution_steps)) throw new ContentError('journey contribution steps invalid');
  const effects = new Set<string>();
  for (const variants of Object.values(c.journey.opportunities)) {
    if (!variants.length) throw new ContentError('journey opportunity is empty');
    for (const v of variants) {
      if (!STREET_EFFECT_IDS.includes(v.effect) || effects.has(v.effect)) throw new ContentError('journey opportunity effect invalid');
      effects.add(v.effect);
      if (!positive(v.coins) || !Number.isSafeInteger(v.wood) || v.wood < 0 || (v.requires && !capabilities.has(v.requires)))
        throw new ContentError('journey opportunity reward/cost invalid');
      for (const [id, n] of Object.entries(v.produce))
        if (!CROP_IDS.includes(id as CropId) || !positive(n)) throw new ContentError('journey produce invalid');
      for (const [id, n] of Object.entries(v.dishes))
        if (!DISH_IDS.includes(id as DishId) || !positive(n)) throw new ContentError('journey dish invalid');
      if (v.wood === 0 && !Object.keys(v.produce).length && !Object.keys(v.dishes).length)
        throw new ContentError('journey opportunity must consume resources');
    }
  }
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
  const decoration = c.decorations;
  if (decoration.anchor_id !== 'courtyard' || !Number.isFinite(decoration.unit_m)
    || decoration.unit_m <= 0 || decoration.min_distance_q <= 0)
    throw new ContentError('decorations anchor/unit/distance 非法');
  const bounds = decoration.bounds_q;
  for (const value of [...Object.values(bounds), decoration.min_abs_x_q,
    ...Object.values(decoration.blocked_outer), decoration.min_distance_q])
    if (!Number.isSafeInteger(value)) throw new ContentError('decorations 必须使用整数格坐标');
  if (bounds.min_x > bounds.max_x || bounds.min_z > bounds.max_z)
    throw new ContentError('decorations bounds 非法');
  if (Object.keys(decoration.props).length !== DECORATION_IDS.length)
    throw new ContentError('decorations 必须恰好六件');
  for (const id of DECORATION_IDS) {
    if (!decoration.props[id]) throw new ContentError(`decorations.${id} 缺失`);
    const offset = decoration.props[id].default_offset_q;
    requireArray(offset, 2, `decorations.${id}.default_offset_q`);
    if (!offset.every(Number.isSafeInteger)) throw new ContentError(`decorations.${id} 坐标非法`);
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
    journey: raw.journey as JourneyContent,
    crops: raw.crops as Content['crops'],
    weather: raw.weather_script as Content['weather'],
    xp: raw.xp as Content['xp'],
    relationships: raw.relationships as Content['relationships'],
    chapters: raw.chapters as Content['chapters'],
    requests: raw.requests as Content['requests'],
    recipes: raw.recipes as Content['recipes'],
    economy: raw.economy as Content['economy'],
    decorations: raw.decorations as Content['decorations'],
  };
  checkContent(c);
  return c;
}

/**
 * 内容版本：文件名进入哈希输入，避免「按文件名排序后直接拼接」的歧义
 * （两组不同的文件可以拼出同一个字符串，Codex 三审 O-I6）。
 */
export function contentVersion(dir: string, legacy = false): string {
  const parts = FILES.filter(name => !legacy || name !== 'journey').map(name => ({
    name,
    content: readFileSync(path.join(dir, `${name}.json`), 'utf8'),
  }));
  return createHash('sha256').update(JSON.stringify(parts), 'utf8').digest('hex').slice(0, 16);
}

export const DEFAULT_CONTENT_DIR = path.resolve(
  path.dirname(new URL(import.meta.url).pathname), '..', '..', '..', 'assets', 'farm', 'data',
);
