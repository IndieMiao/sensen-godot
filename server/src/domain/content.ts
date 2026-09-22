/**
 * 内容表加载与校验。`assets/farm/data/*.json` 是**唯一来源**：Godot 与服务端读同一份，
 * 服务端构建时打进镜像。代码里不出现游戏数值字面量（测试断言除外）——数值改动应该只改
 * 这些 JSON，然后由账本测试证明改对了。
 *
 * `_` 开头的键是 PRD 行号注释，随内容一起参与 content_version 哈希：注释变了也算内容变了，
 * 这样「某个数值为什么是这个值」的依据不会和数值本身脱节。
 */
import type { FishingContent } from './fishing.js';
import { PLOT_KINDS, type PlotContent, type PlotKind } from './plot.js';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import path from 'node:path';

export class ContentError extends Error {
  constructor(message: string) {
    super(`ContentError: ${message}`);
    this.name = 'ContentError';
  }
}

/** T 是木本作物（果树）：占住格子并阻挡通行，与一年生蔬菜相对。 */
export const CROP_IDS = ['R', 'L', 'C', 'H', 'T'] as const;
export type CropId = (typeof CROP_IDS)[number];
export const DISH_IDS = ['salad', 'tea', 'vegetable_soup'] as const;
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
export const JOURNEY_MATERIAL_IDS = ['wood', 'stone', 'fiber', 'copper_ore', 'rock_salt'] as const;
export type JourneyMaterial = (typeof JOURNEY_MATERIAL_IDS)[number];
export const ITEM_CATEGORIES = ['seeds', 'crops', 'mineral', 'material', 'dish', 'equipment', 'prop', 'fish'] as const;
export interface ItemDefinition {
  name: string;
  description: string;
  icon: string;
  category: (typeof ITEM_CATEGORIES)[number];
  max_stack: number;
  discardable: boolean;
  uses: string[];
  properties: Record<string, string | number | boolean>;
  source: { kind: 'seed' | 'produce' | 'material' | 'dish' | 'prop' | 'tool' | 'equipment' | 'fish'; id: string };
}
export interface ItemsContent { version: 1; capacity: number; items: Record<string, ItemDefinition> }
export const CHARACTER_STATS = ['tool_scope', 'gather_bonus', 'mining_bonus', 'craft_savings', 'max_hp', 'move_speed', 'defense'] as const;
export type CharacterStat = (typeof CHARACTER_STATS)[number];
export type CharacterBonusStat = Exclude<CharacterStat, 'tool_scope'>;
export const EQUIPMENT_SLOTS = ['main_hand', 'fishing_rod', 'ring_1', 'ring_2', 'necklace', 'gloves'] as const;
export type EquipmentSlot = (typeof EQUIPMENT_SLOTS)[number];
export const HAND_STATS = ['damage', 'speed', 'range', 'knockback', 'crop_power', 'ore_power', 'wood_power'] as const;
export type HandStats = Record<(typeof HAND_STATS)[number], number>;
export interface CharacterContent {
  version: 1;
  main_hand_base: HandStats;
  auto_grant_starter_rod: boolean;
  starter_rod: string;
  base: Record<CharacterStat, number>;
  equipment: Record<string, { slot: EquipmentSlot; modifiers: Partial<Record<CharacterBonusStat, number>>;
    materials: Partial<Record<JourneyMaterial, number>>; starter?: boolean }>;
  consumables: Record<string, { buff_id: string; stat: CharacterBonusStat; amount: number; uses: number; heal?: number }>;
}

export function equipmentSlot(content: Content, itemId: string): EquipmentSlot | undefined {
  const item = content.items.items[itemId];
  if (item?.source.kind === 'tool') return 'main_hand';
  return item?.source.kind === 'equipment' ? content.character.equipment[itemId]?.slot : undefined;
}
export function equipmentSlots(content: Content, itemId: string): EquipmentSlot[] {
  const slot = equipmentSlot(content, itemId);
  return slot === 'ring_1' || slot === 'ring_2' ? ['ring_1', 'ring_2'] : slot ? [slot] : [];
}
export interface MiningContent {
  version: 1;
  name: string;
  floors: number;
  rockless_floors: number[];
  combat: { version: 2; starter_weapon: string; invulnerability_ms: number; entry_grace_seconds: number;
    attack_arc_degrees: number; hit_stun_seconds: number; floors: Record<string, string[]>;
    monsters: Record<string, { name: string; hp: number; damage: number; defense: number;
      move_speed: number; aggro_range: number; attack_range: number; radius: number;
      windup_seconds: number; dash_speed: number; dash_seconds: number; recovery_seconds: number;
      stun_resistant: boolean; knockback_resistance: number;
      loot: { item_id: string; quantity: number; weight: number }[] }> };
  rocks: { id: string; position: [number, number] }[];
  stone_per_rock: number;
  bonus_drops: { material: 'copper_ore' | 'rock_salt' | ''; quantity: number; weight: number }[];
}
export function mineRocks(mine: MiningContent, floor: number): MiningContent['rocks'] {
  return mine.rockless_floors.includes(floor) ? [] : mine.rocks;
}
export const STREET_EFFECT_IDS = ['leaves', 'flowers', 'benches', 'baskets', 'picnic', 'tea'] as const;
export type StreetEffect = (typeof STREET_EFFECT_IDS)[number];
export const OPPORTUNITY_RESIDENTS = { nursery: 'nursery_keeper', bistro: 'bistro_owner', restorer: 'restorer' } as const;
export interface JourneyOpportunity {
  id: string;
  resident_id: ResidentId;
  name: string;
  description: string;
  reply: string;
  effect: StreetEffect;
  dishes: Partial<Record<DishId, number>>;
  wood: number;
  produce: CropAmounts;
  materials?: Partial<Record<JourneyMaterial, number>>;
  props?: Partial<Record<DecorationId, number>>;
  coins: number;
  requires?: string;
}
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
  /** Growth durations live in crops.json; the journey only overrides sale prices. */
  crops: Record<CropId, { unit_price: number }>;
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
  opportunities: Record<string, JourneyOpportunity[]>;
}

export interface Content {
  fishing: FishingContent;
  /** 农场地面属性：哪些格可开垦、可放置、可通行。见 domain/plot.ts。 */
  farm_plot: PlotContent;
  character: CharacterContent;
  items: ItemsContent;
  mining: MiningContent;
  journey: JourneyContent;
  crops: {
    crops: Record<CropId, { duration_ms: number; seed_price: number; yield: number; unit_price: number;
      /** 木本作物占格且挡路；一年生作物可以踩过去（星露谷的藤架/果树规则）。 */
      woody?: boolean }>;
  };
  /** Weather is atmosphere and narrative only; care no longer branches on field condition. */
  weather: {
    script: FieldCondition[];
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
    recipes: Record<DishId, { inputs: CropAmounts; materials?: Partial<Record<JourneyMaterial, number>>; stall_price: number }>;
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
  /** 道具放置：位置是农场格坐标，合法性查 farm_plot 的「可放置」属性。 */
  decorations: {
    unit_m: number;
    max_props: number;
    props: Record<DecorationId, { name: string; footprint: [number, number]; default_cell: [number, number] }>;
  };
}

const FILES = [
  'crops', 'weather_script', 'xp', 'relationships', 'chapters', 'requests', 'recipes', 'economy', 'decorations', 'journey', 'mining', 'items', 'character', 'farm_plot', 'fishing',
] as const;

/** 只做本层能判定的检查；跨表一致性（例如 grants 里的作物必须在 crops 里）单列在下面。 */
function requireArray(v: unknown, len: number, what: string): void {
  if (!Array.isArray(v) || v.length !== len) throw new ContentError(`${what} 应有 ${len} 项`);
}

function checkContent(c: Content): void {
  if (c.journey.version !== 1) throw new ContentError('journey.version unsupported');
  const positive = (n: unknown): boolean => Number.isSafeInteger(n) && Number(n) > 0;
  const f = c.fishing;
  if (!f || f.version !== 1 || f.step_ms !== 50 || !positive(f.max_steps) || f.max_steps > 1200
    || ![f.bite_min_ms, f.bite_spread_ms, f.hook_window_ms, f.settle_grace_ms].every(positive)
    || ![f.shore_range, f.max_cast, f.anchor_tolerance, f.stand_radius, f.bar_acceleration, f.bar_max_speed, f.initial_progress].every(n => Number.isFinite(n) && n > 0)
    || f.initial_progress >= 1 || !f.tiers || !f.fish || !f.sites) throw new ContentError('fishing config invalid');
  const levels = Object.keys(f.tiers);
  if (levels.length < 2 || levels.some((n, i) => Number(n) !== i + 1)) throw new ContentError('fishing tiers invalid');
  for (const tier of Object.values(f.tiers)) {
    if (!tier.name || !(tier.bar_size > 0 && tier.bar_size < 1) || !positive(tier.turn_steps)
      || ![tier.fish_speed, tier.gain, tier.loss].every(n => Number.isFinite(n) && n > 0)) throw new ContentError('fishing difficulty invalid');
  }
  let previousPrice = 0;
  for (const level of levels) {
    const fish = Object.entries(f.fish).filter(([, fish]) => fish.tier === Number(level));
    if (!fish.length || fish.some(([id, fish]) => !fish.name || !positive(fish.price) || fish.price <= previousPrice
      || c.items.items[id]?.source.kind !== 'fish' || c.items.items[id]?.source.id !== id || c.items.items[id]?.category !== 'fish'))
      throw new ContentError('fishing fish catalog invalid');
    previousPrice = Math.max(...fish.map(([, fish]) => fish.price));
  }
  if (Object.values(f.fish).some(fish => !Object.hasOwn(f.tiers, String(fish.tier)))) throw new ContentError('fishing unknown tier');
  for (const site of Object.values(f.sites)) {
    const point = (v: unknown): boolean => Array.isArray(v) && v.length === 2 && v.every(Number.isFinite);
    if (!site.name || !['farm', 'street'].includes(site.space) || !point(site.stand)
      || !(point(site.center) && point(site.radii) && site.radii!.every(n => n > 0)
        || Array.isArray(site.path) && site.path.length >= 2 && site.path.every(point) && Number.isFinite(site.width) && site.width! > 0)
      || site.fish_weights.length !== levels.length || site.fish_weights.some(n => !Number.isSafeInteger(n) || n < 0)
      || !site.fish_weights.some(n => n > 0)) throw new ContentError('fishing site invalid');
  }
  const catalog = c.items;
  if (!catalog || catalog.version !== 1 || !positive(catalog.capacity) || catalog.capacity > 256 || !catalog.items)
    throw new ContentError('items catalog unsupported');
  const sources = new Set<string>();
  for (const [id, item] of Object.entries(catalog.items)) {
    if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(id) || !item || !item.name || !item.description
      || typeof item.icon !== 'string' || !item.icon.startsWith('res://assets/')
      || !ITEM_CATEGORIES.includes(item.category) || !positive(item.max_stack) || item.max_stack > 999
      || typeof item.discardable !== 'boolean' || !Array.isArray(item.uses) || !item.uses.length
      || item.uses.some(use => typeof use !== 'string' || !use)
      || !item.properties || typeof item.properties !== 'object' || Array.isArray(item.properties)
      || Object.values(item.properties).some(value => !['string', 'number', 'boolean'].includes(typeof value)
        || typeof value === 'number' && !Number.isFinite(value))
      || !item.source || !['seed', 'produce', 'material', 'dish', 'prop', 'tool', 'equipment', 'fish'].includes(item.source.kind))
      throw new ContentError(`items.${id} invalid`);
    const source = `${item.source.kind}:${item.source.id}`;
    if (sources.has(source)) throw new ContentError(`items duplicate source ${source}`);
    sources.add(source);
    const allowed = item.source.kind === 'fish' ? Object.keys(c.fishing?.fish ?? {}) : item.source.kind === 'seed' || item.source.kind === 'produce' ? CROP_IDS
      : item.source.kind === 'material' ? JOURNEY_MATERIAL_IDS
        : item.source.kind === 'dish' ? DISH_IDS
          : item.source.kind === 'prop' ? DECORATION_IDS
            : item.source.kind === 'equipment' ? Object.keys(c.character?.equipment ?? {}) : ['hand_tools', 'row_tool'];
    if (!(allowed as readonly string[]).includes(item.source.id)) throw new ContentError(`items.${id} unknown source`);
    if (item.source.kind === 'tool' && (item.max_stack !== 1 || item.discardable
      || item.category !== 'equipment' || item.properties.tool_scope !== (item.source.id === 'row_tool' ? 3 : 1)))
      throw new ContentError(`items.${id} invalid tool`);
    if (item.source.kind === 'equipment' && (item.source.id !== id || item.max_stack !== 1 || item.discardable
      || item.category !== 'equipment')) throw new ContentError(`items.${id} invalid equipment`);
  }
  const requiredSources = [
    ...Object.keys(c.fishing?.fish ?? {}).map(id => `fish:${id}`),
    ...CROP_IDS.flatMap(id => [`seed:${id}`, `produce:${id}`]),
    ...JOURNEY_MATERIAL_IDS.map(id => `material:${id}`), ...DISH_IDS.map(id => `dish:${id}`),
    ...DECORATION_IDS.map(id => `prop:${id}`), 'tool:hand_tools', 'tool:row_tool',
    ...Object.keys(c.character?.equipment ?? {}).map(id => `equipment:${id}`),
  ];
  if (sources.size !== requiredSources.length || requiredSources.some(source => !sources.has(source)))
    throw new ContentError('items must cover every inventory source');
  const character = c.character;
  if (!character || character.version !== 1 || !character.base
    || CHARACTER_STATS.some(stat => !Number.isFinite(character.base[stat]) || character.base[stat] < 0
      || (stat !== 'move_speed' && !Number.isSafeInteger(character.base[stat])))
    || character.base.tool_scope < 1 || !character.equipment || !character.consumables)
    throw new ContentError('character config unsupported');
  for (const [id, equipment] of Object.entries(character.equipment)) {
    if (!equipment || !EQUIPMENT_SLOTS.includes(equipment.slot) || !equipment.modifiers
      || (!Object.keys(equipment.modifiers).length && !['main_hand', 'fishing_rod'].includes(equipment.slot))
      || Object.entries(equipment.modifiers).some(([stat, value]) => !CHARACTER_STATS.includes(stat as CharacterStat)
        || stat === 'tool_scope' || !Number.isFinite(value) || value! <= 0
        || (stat !== 'move_speed' && !Number.isSafeInteger(value)))
      || !equipment.materials || (!Object.keys(equipment.materials).length && !equipment.starter)
      || Object.entries(equipment.materials).some(([material, amount]) => !JOURNEY_MATERIAL_IDS.includes(material as JourneyMaterial)
        || !positive(amount)) || catalog.items[id]?.source.kind !== 'equipment')
      throw new ContentError(`character.equipment.${id} invalid`);
    if (equipment.slot === 'main_hand' && HAND_STATS.some(key =>
      typeof catalog.items[id].properties[key] !== 'number' || !Number.isFinite(catalog.items[id].properties[key])
      || Number(catalog.items[id].properties[key]) <= 0
      || (key === 'damage' && !Number.isSafeInteger(catalog.items[id].properties[key])))) throw new ContentError(`weapon.${id} invalid`);
  }
  if (typeof character.auto_grant_starter_rod !== 'boolean'
    || character.equipment[character.starter_rod]?.slot !== 'fishing_rod'
    || HAND_STATS.some(key => !Number.isFinite(character.main_hand_base?.[key]) || character.main_hand_base[key] <= 0))
    throw new ContentError('character main-hand defaults or starter rod invalid');
  for (const id of ['hand_tools', 'row_tool']) if (HAND_STATS.some(key => typeof catalog.items[id].properties[key] !== 'number' || Number(catalog.items[id].properties[key]) <= 0))
    throw new ContentError('tool main-hand properties invalid');
  const buffIds = new Set<string>();
  for (const [id, consumable] of Object.entries(character.consumables)) {
    if (!consumable || !/^[a-z][a-z0-9_]*$/.test(consumable.buff_id) || buffIds.has(consumable.buff_id)
      || !['gather_bonus', 'mining_bonus', 'craft_savings'].includes(consumable.stat)
      || !positive(consumable.amount) || !positive(consumable.uses) || catalog.items[id]?.source.kind !== 'dish'
      || (consumable.heal !== undefined && !positive(consumable.heal)))
      throw new ContentError(`character.consumables.${id} invalid`);
    buffIds.add(consumable.buff_id);
  }
  const mine = c.mining;
  if (!mine || mine.version !== 1 || !mine.name || mine.floors !== 5 || !positive(mine.stone_per_rock)
    || !Array.isArray(mine.rockless_floors) || mine.rockless_floors.length !== 1 || mine.rockless_floors[0] !== mine.floors
    || !Array.isArray(mine.rocks) || mine.rocks.length !== 6
    || new Set(mine.rocks.map(rock => rock?.id)).size !== mine.rocks.length
    || mine.rocks.some(rock => !rock || !/^rock_[a-z0-9_]+$/.test(rock.id)
      || !Array.isArray(rock.position) || rock.position.length !== 2 || !rock.position.every(Number.isFinite))
    || !Array.isArray(mine.bonus_drops) || mine.bonus_drops.length !== 3
    || new Set(mine.bonus_drops.map(drop => drop?.material)).size !== 3
    || mine.bonus_drops.some(drop => !drop || !['copper_ore', 'rock_salt', ''].includes(drop.material)
      || !positive(drop.weight) || (drop.material ? !positive(drop.quantity) : drop.quantity !== 0))
    || !Number.isSafeInteger(mine.bonus_drops.reduce((sum, drop) => sum + drop.weight, 0)))
    throw new ContentError('mining invalid');
  const combat = mine.combat;
  if (!combat || combat.version !== 2 || character.equipment[combat.starter_weapon]?.slot !== 'main_hand'
    || !character.equipment[combat.starter_weapon]?.starter || !positive(combat.invulnerability_ms)
    || !Number.isFinite(combat.entry_grace_seconds) || combat.entry_grace_seconds <= 0
    || !Number.isFinite(combat.hit_stun_seconds) || combat.hit_stun_seconds <= 0
    || !Number.isFinite(combat.attack_arc_degrees) || combat.attack_arc_degrees <= 0 || combat.attack_arc_degrees > 180
    || !combat.floors || !combat.monsters || character.base.max_hp <= 0 || character.base.move_speed <= 0)
    throw new ContentError('mining.combat invalid');
  for (const monster of Object.values(combat.monsters)) {
    if (!monster.name || !positive(monster.hp) || !positive(monster.damage) || !Number.isSafeInteger(monster.defense)
      || monster.defense < 0 || ['move_speed', 'aggro_range', 'attack_range', 'radius', 'windup_seconds',
        'dash_speed', 'dash_seconds', 'recovery_seconds'].some(key => {
        const value = monster[key as keyof typeof monster]; return typeof value !== 'number' || !Number.isFinite(value) || value <= 0;
      }) || typeof monster.stun_resistant !== 'boolean' || !Number.isFinite(monster.knockback_resistance)
      || monster.knockback_resistance < 0 || monster.knockback_resistance > 1
      || !Array.isArray(monster.loot) || !monster.loot.length
      || new Set(monster.loot.map(drop => drop?.item_id)).size !== monster.loot.length
      || monster.loot.some(drop => !drop || !Object.hasOwn(catalog.items, drop.item_id)
        || !['seed', 'material'].includes(catalog.items[drop.item_id].source.kind)
        || !positive(drop.quantity) || !positive(drop.weight))
      || !Number.isSafeInteger(monster.loot.reduce((sum, drop) => sum + drop.weight, 0)))
      throw new ContentError('mining.combat.monster invalid');
  }
  for (let floor = 1; floor <= mine.floors; floor++) {
    const kinds = combat.floors[String(floor)];
    if (!Array.isArray(kinds) || kinds.length !== [0, 0, 1, 3, 1][floor - 1]
      || kinds.some(kind => !Object.hasOwn(combat.monsters, kind))) throw new ContentError('mining.combat.floor invalid');
  }
  for (const id of CROP_IDS)
    if (!positive(c.journey.crops[id]?.unit_price))
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
  const materials: readonly string[] = JOURNEY_MATERIAL_IDS;
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
  const offerIds = new Set<string>();
  if (Object.keys(c.journey.opportunities).length !== Object.keys(OPPORTUNITY_RESIDENTS).length)
    throw new ContentError('journey opportunity slots invalid');
  for (const [slot, variants] of Object.entries(c.journey.opportunities)) {
    if (!Object.hasOwn(OPPORTUNITY_RESIDENTS, slot)) throw new ContentError('journey opportunity slot invalid');
    if (!variants.length) throw new ContentError('journey opportunity is empty');
    for (const v of variants) {
      if (!v || !/^[a-z][a-z0-9_]*$/.test(v.id) || offerIds.has(v.id)
        || v.resident_id !== OPPORTUNITY_RESIDENTS[slot as keyof typeof OPPORTUNITY_RESIDENTS]
        || [v.name, v.description, v.reply].some(text => typeof text !== 'string' || !text.trim())
        || !v.produce || typeof v.produce !== 'object' || Array.isArray(v.produce)
        || !v.dishes || typeof v.dishes !== 'object' || Array.isArray(v.dishes)
        || [v.materials, v.props].some(cost => cost !== undefined && (!cost || typeof cost !== 'object' || Array.isArray(cost))))
        throw new ContentError('journey opportunity identity invalid');
      offerIds.add(v.id);
      if (!STREET_EFFECT_IDS.includes(v.effect)) throw new ContentError('journey opportunity effect invalid');
      if (!positive(v.coins) || !Number.isSafeInteger(v.wood) || v.wood < 0 || (v.requires && !capabilities.has(v.requires)))
        throw new ContentError('journey opportunity reward/cost invalid');
      for (const [id, n] of Object.entries(v.produce))
        if (!CROP_IDS.includes(id as CropId) || !positive(n)) throw new ContentError('journey produce invalid');
      for (const [id, n] of Object.entries(v.dishes))
        if (!DISH_IDS.includes(id as DishId) || !positive(n)) throw new ContentError('journey dish invalid');
      for (const [id, n] of Object.entries(v.materials ?? {}))
        if (!JOURNEY_MATERIAL_IDS.includes(id as JourneyMaterial) || !positive(n)) throw new ContentError('journey request material invalid');
      for (const [id, n] of Object.entries(v.props ?? {}))
        if (!Object.hasOwn(c.journey.workshop.recipes, id) || catalog.items[id]?.source.kind !== 'prop'
          || !positive(n)) throw new ContentError('journey request prop invalid');
      if (v.wood === 0 && !Object.keys(v.produce).length && !Object.keys(v.dishes).length
        && !Object.keys(v.materials ?? {}).length && !Object.keys(v.props ?? {}).length)
        throw new ContentError('journey opportunity must consume resources');
    }
  }
  for (const id of CROP_IDS) {
    const crop = c.crops.crops[id];
    if (!crop) throw new ContentError(`crops.${id} 缺失`);
    // `_` 开头是 PRD 行号注释，不参与数值校验（但参与 content_version 哈希）。
    // woody 是布尔标志（木本作物占格挡路），不是数值。
    for (const [k, v] of Object.entries(crop)) {
      if (k.startsWith('_')) continue;
      if (k === 'woody') {
        if (typeof v !== 'boolean') throw new ContentError(`crops.${id}.woody 必须是布尔值`);
        continue;
      }
      if (typeof v !== 'number' || v <= 0) throw new ContentError(`crops.${id}.${k} 必须是正数`);
    }
  }
  requireArray(c.weather.script, 7, 'weather.script');
  for (const cond of c.weather.script)
    if (!FIELD_CONDITIONS.includes(cond)) throw new ContentError(`未知田况 ${cond}`);
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
  for (const id of DISH_IDS) {
    const recipe = c.recipes.recipes[id];
    if (!recipe || !positive(recipe.stall_price) || !recipe.inputs
      || Object.entries(recipe.inputs).some(([crop, qty]) => !CROP_IDS.includes(crop as CropId) || !positive(qty))
      || Object.entries(recipe.materials ?? {}).some(([material, qty]) => !materials.includes(material) || !positive(qty))
      || !Object.keys(recipe.inputs).length)
      throw new ContentError(`recipes.${id} invalid`);
  }
  requireArray(c.economy.target_wallet_by_day.tool, 7, 'economy.target_wallet_by_day.tool');
  requireArray(c.economy.target_wallet_by_day.field, 7, 'economy.target_wallet_by_day.field');
  for (const rid of RESIDENT_IDS) {
    if (!c.relationships.residents[rid]) throw new ContentError(`relationships.residents.${rid} 缺失`);
    requireArray(c.relationships.target_points_by_day[rid], 7, `target_points_by_day.${rid}`);
    for (const crop of c.relationships.gift_clues[rid] ?? [])
      if (!CROP_IDS.includes(crop)) throw new ContentError(`gift_clues.${rid} 含未知作物 ${crop}`);
  }
  const decoration = c.decorations;
  if (!Number.isFinite(decoration.unit_m) || decoration.unit_m <= 0
    || !Number.isSafeInteger(decoration.max_props) || decoration.max_props <= 0)
    throw new ContentError('decorations unit/max_props 非法');
  if (Object.keys(decoration.props).length !== DECORATION_IDS.length)
    throw new ContentError('decorations 必须恰好六件');
  for (const id of DECORATION_IDS) {
    const prop = decoration.props[id];
    if (!prop) throw new ContentError(`decorations.${id} 缺失`);
    requireArray(prop.footprint, 2, `decorations.${id}.footprint`);
    requireArray(prop.default_cell, 2, `decorations.${id}.default_cell`);
    if (!prop.footprint.every(n => Number.isSafeInteger(n) && n > 0))
      throw new ContentError(`decorations.${id}.footprint 必须是正整数格`);
    if (!prop.default_cell.every(Number.isSafeInteger))
      throw new ContentError(`decorations.${id}.default_cell 坐标非法`);
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
    fishing: raw.fishing as FishingContent,
    farm_plot: raw.farm_plot as PlotContent,
    character: raw.character as CharacterContent,
    items: raw.items as ItemsContent,
    mining: raw.mining as MiningContent,
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
  const parts = FILES.filter(name => !legacy || !['journey', 'mining', 'items', 'character', 'fishing'].includes(name)).map(name => ({
    name,
    content: readFileSync(path.join(dir, `${name}.json`), 'utf8'),
  }));
  return createHash('sha256').update(JSON.stringify(parts), 'utf8').digest('hex').slice(0, 16);
}

export const DEFAULT_CONTENT_DIR = path.resolve(
  path.dirname(new URL(import.meta.url).pathname), '..', '..', '..', 'assets', 'farm', 'data',
);
