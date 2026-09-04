/**
 * 26 条命令的载荷定义与封套。HTTP 层用同一份定义生成 TypeBox schema
 * （`additionalProperties: false`），领域层按 `type` 分发。
 *
 * 数组字段统一约束：非空、至多 12 项（一个农场最多 12 格）、不得重复。
 * 「整批原子」——一条命令里的任意一格不合法，整条失败，状态不变（Codex 二审 Important 5）。
 */
import type { CropId, DishId, GrowthChoiceId, ResidentId } from './content.js';
import type { GrowthChoice, LifeChoice } from './state.js';

export const MAX_CELLS_PER_COMMAND = 12;

export type CareKindPayload = 'water' | 'drain' | 'shelter';

export type Command =
  // —— 建场与设置 ——
  | { type: 'create_farm'; region_id: string; layout_patch_id: string; blueprint_revision: number }
  | { type: 'set_location_visible'; visible: boolean }
  | { type: 'set_visit_access'; access: 'only_me' | 'anyone' }
  // —— 农事（G1 客户端用的 9 条）——
  | { type: 'clear_cells'; cell_ids: string[] }
  | { type: 'till_cells'; cell_ids: string[] }
  | { type: 'sow_cells'; cell_ids: string[]; crop: CropId; lot: 'bought' | 'bound' }
  | { type: 'apply_care'; cell_ids: string[]; kind: CareKindPayload }
  | { type: 'apply_optional_care'; cell_ids: string[] }
  | { type: 'harvest_cells'; cell_ids: string[] }
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
