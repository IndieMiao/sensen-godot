/**
 * 农场状态。**身份与索引字段只在数据库列上**（farms 表），这里只放可变玩法数据
 * （Codex 二审 Minor 2：两处都有会出现「以哪边为准」的歧义）。
 */
import { CROP_IDS, type CropId, type DecorationId, type DishId, type FieldCondition, type JourneyMaterial, type ResidentId } from './content.js';
import { initialQa, type QaClock } from './qa.js';

export const CELL_STATES = ['tilled', 'sown', 'growing'] as const;
export type CellState = (typeof CELL_STATES)[number];
/** 没有 `ripe`：成熟是 `ready_at <= now` 的**派生**结果，不是存下来的状态（Codex 二审 Critical 2）。 */

export type LifeChoice = 'gift' | 'keep' | 'sold';
export type GrowthChoice = 'tool' | 'field';
export type NurseryStage = 'derelict' | 'cleared' | 'built';

export interface DecorationPlacement {
  prop_id: DecorationId;
  /** 农场格坐标 `[i, j]`。过去是「相对 courtyard 锚点的四分之一米偏移」，
   *  自由格子种田后农场格本身就是 0.5m，锚点这一层没有存在必要了。 */
  cell: [number, number];
  rotation_q?: number;
}

export interface CellSlot {
  state: CellState;
  crop: CropId | null;
  /** 浇水完成时刻。客户端按 `watered_at → ready_at` 四等分画生长阶段。 */
  watered_at: number | null;
  /** 只在浇水成功那一刻写入；播下但未浇水为 null，作物停在起点不开始成长。 */
  ready_at: number | null;
}

export interface SeedLot { bought: number; bound: number }

export interface BagStack {
  id: string;
  item_id: string;
  quantity: number;
  quality: string;
  seed_lot?: 'bought' | 'bound';
  instance_id?: string;
  attributes?: Record<string, string | number | boolean>;
}

export interface BagState {
  version: 1 | 2;
  sequence: number;
  capacity: number;
  starter_rod_granted?: boolean;
  next_id: number;
  slots: BagStack[];
  /** Legacy holdings and automatic rewards retain ownership even when slots are full. */
  overflow: BagStack[];
  equipped: Partial<Record<'main_hand' | 'fishing_rod' | 'ring_1' | 'ring_2' | 'necklace' | 'gloves' | 'tool' | 'accessory' | 'weapon', BagStack | null>>;
}

export interface CharacterState {
  version: 1;
  hp?: number;
  starter_weapon_granted?: boolean;
  last_gather_at?: number;
  buffs: { id: string; source_item_id: string; remaining_uses: number }[];
}

export interface ResidentState {
  points: number;
  first_met_day: string | null;
  talked_day: string | null;
  gifts_given: number;
  request_done: boolean;
  shared_event_done: boolean;
  /** Choices explicitly discussed after resolution, separate from having talked earlier. */
  choice_memories?: Record<number, LifeChoice>;
}

export interface ChapterState {
  status: 'locked' | 'active' | 'done';
  activated_day: string | null;
  step_flags: Record<string, boolean>;
  grants_issued: boolean;
}

export interface XpState {
  total: number;
  first_harvest_crops: CropId[];
  first_recipes: DishId[];
  harvest_counted: { day: string | null; plants: number };
}

export interface HandbookEntry {
  kind: 'first_harvest' | 'first_recipe' | 'chapter_done' | 'week_summary';
  key: string;
  day: string;
  careful?: boolean;
  life_priority?: boolean;
}

export interface WeekSummary {
  id: 'first_week';
  completed_day: string;
  completed_at: number;
  life_priority: boolean;
  life_choice_count: number;
  choices: Record<number, LifeChoice>;
  photo_variant: 'personalized' | 'standard';
  journal_pages: string[];
  next_week_clue: 'resident_seed_exchange' | 'nursery_next_stage';
  wallet: number;
  xp: number;
  level: number;
  growth_choice: GrowthChoice | null;
  nursery: { stage: NurseryStage; appearance: 'a' | 'b' | null };
  relationships: Record<ResidentId, { points: number; stage: string }>;
}

export interface FarmState {
  fishing?: import('./fishing.js').FishingState;
  /** Equipment attributes are derived; only remaining successful meal uses are persisted. */
  character?: CharacterState;
  /** Missing legacy bags are imported without loss; once present this is the inventory authority. */
  bag?: BagState;
  /** Missing on previous saves; created by the first owner mine entry. */
  mine?: MineState;
  /** Absent on G3 saves; upgrading is an explicit, idempotent owner command. */
  journey?: JourneyState;
  clock: {
    player_day_id: string;
    /** 章节日索引，到 6 冻结（决策⑨）。 */
    chapter_index: number;
    /** 天气日索引，每个玩家日 +1 **永不冻结**——章节冻结后天气仍要循环（Codex 三审 N-I2）。 */
    weather_day_index: number;
    field_condition: FieldCondition;
    /** 单调守卫：正式农场取 max(采样, 本字段)，QA 农场回拨直接拒绝。 */
    last_effective_now: number;
  };
  wallet: number;
  inventory: {
    seeds: Record<CropId, SeedLot>;
    produce: Record<CropId, number>;
    dishes: Record<'salad' | 'tea', number> & Partial<Record<DishId, number>>;
  };
  /** 稀疏：有 key = 已开垦。没有 key = 荒地，不占存储。 */
  cells: Record<string, CellSlot | undefined>;
  /** 导演模式时钟；正式农场是恒等变换。老农场缺这个字段时按未加速补齐。 */
  qa?: QaClock;
  beds_unlocked: 3 | 4;
  tools: { row_tool: boolean };
  growth_choice: {
    intent: GrowthChoice | null;
    purchase: GrowthChoice | null;
    locked_at: number | null;
    transaction_id: string | null;
  };
  stall: { day: string; settled: number };
  buyback: { day: string; sold: number; week_total: number };
  seedling_packs: { days: string[] };
  engineering: { reserved: Partial<Record<CropId, number>>; submitted: Partial<Record<CropId, number>> };
  nursery: { stage: NurseryStage; appearance: 'a' | 'b' | null };
  /** Missing on earlier domain-2 farms; read as an empty courtyard without a read-time write. */
  decorations?: DecorationPlacement[];
  residents: Record<ResidentId, ResidentState>;
  chapters: ChapterState[];
  requests_done: string[];
  /** 六个唯一槽（D1-D6），只由 resolve_life_choice 写（Codex 三审 N-I11）。 */
  life_choices: Record<number, LifeChoice>;
  /** sell_at_stall 按章节累加实际成交项；resolve_life_choice(sold) 的唯一校验依据。 */
  sales_facts: Record<number, Partial<Record<CropId, number>>>;
  subsidies_claimed: string[];
  xp: XpState;
  handbook: HandbookEntry[];
  /** First completed-week snapshot; later farming cannot rewrite its branch or balances. */
  week_summary?: WeekSummary;
}

export const cellId = (i: number, j: number): string => `${i},${j}`;

export interface MineState {
  version: 1;
  run: number;
  /** Zero is the farm; active mine floors are one through five. */
  floor: number;
  deepest_floor: number;
  cleared_floors: number[];
  broken: Record<string, string[]>;
  elevator_unlocked: boolean;
  combat?: { version: 1 | 2; sequence: number; monsters: Record<string, number[]>;
    last_attack_at?: number; last_hurt_at?: number; defeats: number;
    last_result?: { damage: number; hurt: number; defeated: string[]; rescued: boolean;
      materials: Partial<Record<JourneyMaterial, number>>; loot?: Record<string, number> } };
  last_drop?: { floor: number; node_id: string; materials: Partial<Record<JourneyMaterial, number>> };
}

export interface JourneyState {
  version: 1;
  facts: string[];
  completed: string[];
  unlocks: string[];
  wood: number;
  materials?: { stone: number; fiber: number } & Partial<Record<Exclude<JourneyMaterial, 'wood'>, number>>;
  facility_uses?: Record<string, number>;
  exploration: { round: number; collected: string[]; route?: string; routes_by_place?: Record<string, string>;
    branching_places?: string[]; choices?: Record<string, 'primary' | 'alternate'> };
  gift_rounds?: Partial<Record<ResidentId, number>>;
  workshop?: { sequence: number; stock: Record<string, number>; displays: Record<string, string[]>;
    planned?: { project: string; slot: number; item: string } };
  tracked_discovery?: string;
  tracked_project?: string;
  tracked_opportunity?: { slot: string; sequence: number };
  discovery_choices?: Record<string, string>;
  contributions?: Record<string, number>;
  gathering?: { sequence: number; planned?: string; current?: string; memories: string[] };
  opportunities: Record<string, {
    sequence: number;
    variant: number;
    accepted?: boolean;
    last_completed?: { offer_id: string; resident_id: ResidentId; sequence: number;
      consumed: Record<string, number>; coins: number; effect: string; contribution: number };
  }>;
}
export const parseCellId = (id: string): [number, number] => {
  const [i, j] = id.split(',').map(Number);
  return [i, j];
};

/**
 * 每种作物给一份**独立**的值。写成 `{ R: v, L: v, ... }` 会让四种作物共用同一个对象引用，
 * 发 Grant 时 6R 与 3L 会写进同一个仓（测试 sow_cells 抓到过）。
 */
const perCrop = <T>(make: () => T): Record<CropId, T> =>
  Object.fromEntries(CROP_IDS.map(id => [id, make()])) as Record<CropId, T>;

export interface InitialArgs {
  player_day_id: string;
  field_condition: FieldCondition;
  now: number;
  wallet: number;
}

export function createInitialState(a: InitialArgs): FarmState {
  // 开局一格未开垦：cells 为空字典，玩家自己决定在哪下锄。
  const cells: Record<string, CellSlot | undefined> = {};
  return {
    clock: {
      player_day_id: a.player_day_id,
      chapter_index: 0,
      weather_day_index: 0,
      field_condition: a.field_condition,
      last_effective_now: a.now,
    },
    qa: initialQa(a.now),
    wallet: a.wallet,
    inventory: {
      seeds: perCrop(() => ({ bought: 0, bound: 0 })),
      produce: perCrop(() => 0),
      dishes: { salad: 0, tea: 0 },
    },
    cells,
    beds_unlocked: 3,
    tools: { row_tool: false },
    growth_choice: { intent: null, purchase: null, locked_at: null, transaction_id: null },
    stall: { day: a.player_day_id, settled: 0 },
    buyback: { day: a.player_day_id, sold: 0, week_total: 0 },
    seedling_packs: { days: [] },
    engineering: { reserved: {}, submitted: {} },
    nursery: { stage: 'derelict', appearance: null },
    decorations: [],
    residents: {
      nursery_keeper: emptyResident(),
      bistro_owner: emptyResident(),
      restorer: emptyResident(),
    },
    chapters: Array.from({ length: 7 }, (_, i): ChapterState => ({
      status: i === 0 ? 'active' : 'locked',
      activated_day: i === 0 ? a.player_day_id : null,
      step_flags: i === 0 ? { farm_created: true } : {},
      grants_issued: false,
    })),
    requests_done: [],
    life_choices: {},
    sales_facts: {},
    subsidies_claimed: [],
    xp: {
      total: 0, first_harvest_crops: [], first_recipes: [],
      harvest_counted: { day: a.player_day_id, plants: 0 },
    },
    handbook: [],
  };
}

function emptyResident(): ResidentState {
  return {
    points: 0, first_met_day: null, talked_day: null,
    gifts_given: 0, request_done: false, shared_event_done: false,
  };
}

/** 等级由 XP 派生，不存状态（PRD §7.2）。 */
export function levelOf(totalXp: number, thresholds: number[]): number {
  let level = 1;
  for (let i = 0; i < thresholds.length; i++) if (totalXp >= thresholds[i]) level = i + 1;
  return level;
}

/** PRD §7.5 L431：账户价值 = 钱包 + 已购成长资产原价，不折旧。 */
export function accountValue(s: FarmState, toolPrice: number, fieldPrice: number): number {
  return s.wallet + (s.tools.row_tool ? toolPrice : 0) + (s.beds_unlocked === 4 ? fieldPrice : 0);
}
