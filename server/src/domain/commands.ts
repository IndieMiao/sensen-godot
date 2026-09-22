/**
 * 命令的载荷定义与封套。领域层按 `type` 分发；payload 校验在各 handler 手写。
 *
 * 数组字段统一约束：非空、至多 MAX_CELLS_PER_COMMAND 项、不得重复。
 * 「整批原子」——一条命令里的任意一格不合法，整条失败，状态不变（Codex 二审 Important 5）。
 */
import type { CropId, DishId, GrowthChoiceId, ResidentId } from './content.js';
import type { DecorationPlacement, GrowthChoice, LifeChoice } from './state.js';

export const MAX_CELLS_PER_COMMAND = 64;

export type Command =
  | { type: 'cast_fishing'; sequence: number; site_id: string; target?: [number, number] }
  | { type: 'hook_fishing'; sequence: number }
  | { type: 'finish_fishing'; sequence: number; inputs: string }
  | { type: 'cancel_fishing'; sequence: number }
  | { type: 'sell_fish'; sequence: number; stack_id: string; quantity: number }
  | { type: 'split_bag_stack'; sequence: number; stack_id: string; quantity: number }
  | { type: 'merge_bag_stacks'; sequence: number; source_id: string; target_id: string }
  | { type: 'sort_bag'; sequence: number; mode: 'category' | 'name' }
  | { type: 'discard_bag_stack'; sequence: number; stack_id: string; quantity: number }
  | { type: 'equip_bag_item'; sequence: number; stack_id: string; slot?: import('./content.js').EquipmentSlot }
  | { type: 'unequip_bag_item'; sequence: number; slot?: import('./content.js').EquipmentSlot }
  | { type: 'claim_bag_overflow'; sequence: number; stack_id: string }
  | { type: 'use_bag_item'; sequence: number; stack_id: string }
  | { type: 'craft_equipment'; sequence: number; item_id: string }
  | { type: 'mine_combat'; run: number; floor: number; sequence: number; targets: string[]; hurt_by?: string }
  | { type: 'rest_character' }
  | { type: 'enter_mine'; run: number }
  | { type: 'leave_mine'; run: number; floor: number }
  | { type: 'mine_rock'; run: number; floor: number; node_id: string }
  | { type: 'descend_mine'; run: number; floor: number }
  | { type: 'ascend_mine'; run: number; floor: number }
  | { type: 'use_mine_elevator'; run: number; floor: number }
  | { type: 'restart_mine'; run: number }
  | { type: 'start_journey' }
  | { type: 'collect_resource'; node_id: string; round: number; choice?: 'primary' | 'alternate' }
  | { type: 'next_exploration'; round: number; route?: string }
  | { type: 'build_journey_project'; project: string; stage: number }
  | { type: 'use_journey_facility'; project: string; choice: string; sequence: number }
  | { type: 'plan_journey_gathering'; theme: string; sequence: number }
  | { type: 'host_journey_gathering'; theme: string; sequence: number }
  | { type: 'pack_journey_gathering'; sequence: number }
  | { type: 'craft_journey_item'; item: string; sequence: number }
  | { type: 'deliver_journey_item'; item: string; sequence: number }
  | { type: 'display_journey_item'; project: string; slot: number; item: string; sequence: number }
  | { type: 'plan_journey_display'; project: string; slot: number; item: string; sequence: number }
  | { type: 'complete_journey_story'; resident_id: ResidentId; story: string }
  | { type: 'track_journey_discovery'; discovery: string }
  | { type: 'track_journey_project'; project: string }
  | { type: 'track_journey_opportunity'; slot: string; sequence: number; tracking: boolean }
  | { type: 'accept_opportunity'; slot: string; sequence: number }
  | { type: 'abandon_opportunity'; slot: string; sequence: number }
  | { type: 'install_journey_discovery'; discovery: string; sequence: number }
  | { type: 'harvest_journey_discovery'; discovery: string; choice: string; round: number }
  | { type: 'journey_action'; action: 'repair_workbench' | 'craft_planter' | 'clear_side_path' | 'share_meal' | 'plant_planter' }
  | { type: 'fulfill_opportunity'; slot: string; sequence: number }
  | { type: 'decline_opportunity'; slot: string; sequence: number; timber_only?: boolean }
  // —— 建场与设置 ——
  | { type: 'create_farm'; region_id: string; layout_patch_id: string; blueprint_revision: number }
  | { type: 'set_location_visible'; visible: boolean }
  | { type: 'set_visit_access'; access: 'only_me' | 'anyone' }
  // —— 农事：开垦 → 播种 → 浇水 → 收割，外加铲平与买种 ——
  | { type: 'till_cells'; cell_ids: string[] }
  | { type: 'sow_cells'; cell_ids: string[]; crop: CropId; lot: 'bought' | 'bound' }
  | { type: 'water_cells'; cell_ids: string[] }
  | { type: 'harvest_cells'; cell_ids: string[] }
  | { type: 'clear_plot'; cell_ids: string[] }
  | { type: 'buy_seeds'; crop: CropId; qty: number }
  // —— 经济 ——
  | { type: 'sell_at_stall'; items: { kind: 'produce' | 'dish'; id: string; qty: number }[] }
  | { type: 'sell_to_buyback_box'; qty: number }
  | { type: 'cook_dish'; recipe: DishId }
  // —— 居民与选择 ——
  | { type: 'talk_to_resident'; resident_id: ResidentId }
  | { type: 'give_gift'; resident_id: ResidentId; crop: CropId }
  | { type: 'resolve_life_choice'; chapter: number; choice: LifeChoice }
  | { type: 'submit_request'; request_id: string }
  | { type: 'attend_shared_event'; event_id: string }
  // —— 工程篮与成长选择 ——
  | { type: 'reserve_engineering'; items: Partial<Record<CropId, number>> }
  | { type: 'withdraw_engineering'; items: Partial<Record<CropId, number>> }
  | { type: 'submit_engineering'; items: Partial<Record<CropId, number>> }
  | { type: 'set_growth_intent'; choice: GrowthChoice }
  | { type: 'purchase_growth_choice'; choice: GrowthChoice; transaction_id: string }
  | { type: 'choose_nursery_appearance'; appearance: 'a' | 'b' }
  | { type: 'save_decorations'; props: DecorationPlacement[] }
  // —— 领取 ——
  | { type: 'claim_subsidy'; subsidy_id: string }
  | { type: 'claim_seedling_pack' }
  // —— 访问（G2 由服务端内部调用）——
  | { type: 'record_visit_return'; visited_farm_id: string }
  // —— QA 导演（仅 qa=true 农场）——
  | { type: 'qa_set_clock'; scale: number }
  | { type: 'qa_skip_days'; days: number }
  | { type: 'qa_set_weather'; overrides: Record<string, string> };

export type CommandType = Command['type'];

/** 命令封套；`base_version` 与 `idempotency_key` 由 HTTP/DB 层消费，不进 reducer。 */
export interface CommandEnvelope {
  idempotency_key: string;
  base_version: number;
  /** Frozen coordinate-space identity of a queued spatial edit; not refreshed during version rebasing. */
  terrain_checksum?: string;
  type: CommandType;
  payload: Record<string, unknown>;
}

export const QA_COMMANDS: CommandType[] = ['qa_set_clock', 'qa_skip_days', 'qa_set_weather'];
export const isQaCommand = (t: CommandType): boolean => QA_COMMANDS.includes(t);

/** QA 参数域（Codex 三审 N-I6：负 scale / 巨大 scale / 负 days 都要挡住）。 */
export const QA_SCALE_RANGE: [number, number] = [0.1, 100];
export const QA_SKIP_DAYS_RANGE: [number, number] = [1, 30];

/** 命令数组字段的通用校验；返回错误说明或 null。 */
export function checkCellIds(ids: unknown): string | null {
  if (!Array.isArray(ids) || ids.length === 0) return 'cell_ids 不能为空';
  if (ids.length > MAX_CELLS_PER_COMMAND) return `cell_ids 最多 ${MAX_CELLS_PER_COMMAND} 项`;
  if (new Set(ids).size !== ids.length) return 'cell_ids 不得重复';
  for (const id of ids)
    if (typeof id !== 'string' || !/^\d+,\d+$/.test(id)) return `非法 cell_id ${String(id)}`;
  return null;
}
