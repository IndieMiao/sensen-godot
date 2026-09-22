/**
 * 四条账本脚本的**唯一来源**。每条脚本是一串公开命令，从 `create_farm` 之后的初始状态起
 * 逐条 apply，跑出 PRD §7.5 的目标数字。
 *
 * 为什么用生成函数而不是手写 JSON：四条路径的 D0-D4 完全相同，只在 D5/D6 分叉
 * （工具 vs 扩地 × 生活优先 vs 出售优先）。写成四份 JSON 会有三份是复制粘贴，改一处要改四处。
 *
 * **数字对不上时改内容表或 reducer，不许改这里的命令序列去凑。**
 */
import type { Command } from '../../src/domain/commands.js';
import { BEDS, EXTRA_SOIL } from '../domain/helpers.js';

export type Step = { day: number; cmd: Command; /** 执行前先在当天内推进这么多分钟，默认 5。 */ waitMinutes?: number };
export type Path = 'tool' | 'field';
export type Style = 'life' | 'sell';

const nine = BEDS;
const s = (day: number, cmd: Command, waitMinutes?: number): Step => ({ day, cmd, waitMinutes });

/** 一轮：收获 9 格 → （用途）→ 买种 → 播种 → 照料。 */
function sowRound(day: number, buy: [string, number][], plan: [string, number, 'bought' | 'bound'][]): Step[] {
  const out: Step[] = [];
  for (const [crop, qty] of buy)
    out.push(s(day, { type: 'buy_seeds', crop: crop as 'R', qty }));
  let cursor = 0;
  for (const [crop, n, lot] of plan) {
    out.push(s(day, { type: 'sow_cells', cell_ids: nine.slice(cursor, cursor + n), crop: crop as 'R', lot }));
    cursor += n;
  }
  out.push(s(day, { type: 'water_cells', cell_ids: nine.slice(0, cursor) }));
  return out;
}

/** D0-D4 四条路径共用（PRD §7.5 L565「共用 D0-D4 账本」）。 */
function commonDays(style: Style): Step[] {
  const six = nine.slice(0, 6);
  const out: Step[] = [
    // —— D0 晴：教学 6R（3 分钟）→ 收 → 3R 教学回购 30、3R 出售 24 → 买 6R → 播 6R+3L ——
    s(0, { type: 'till_cells', cell_ids: nine }),
    s(0, { type: 'sow_cells', cell_ids: six, crop: 'R', lot: 'bound' }),
    s(0, { type: 'water_cells', cell_ids: six }),
    s(0, { type: 'harvest_cells', cell_ids: six }, 4 * 60),
    s(0, { type: 'submit_request', request_id: 'd0_tutorial_buyback' }),
    s(0, { type: 'sell_at_stall', items: [{ kind: 'produce', id: 'R', qty: 3 }] }),
    s(0, { type: 'talk_to_resident', resident_id: 'nursery_keeper' }),
    ...sowRound(0, [['R', 6]], [['R', 6, 'bought'], ['L', 3, 'bound']]),
  ];

  // —— D1 雨：3L 请求 45、1R 赠礼/出售、5R 出售 40、天气故事 20 → 买 4R+2L → 播 4R+2L+3L ——
  out.push(
    s(1, { type: 'harvest_cells', cell_ids: nine }),
    s(1, { type: 'talk_to_resident', resident_id: 'bistro_owner' }),
    s(1, { type: 'submit_request', request_id: 'd1_bistro_lettuce' }),
    s(1, { type: 'talk_to_resident', resident_id: 'nursery_keeper' }),
    s(1, { type: 'claim_subsidy', subsidy_id: 'weather_story' }),
  );
  out.push(...lifeChoice(1, 'R', style, 'nursery_keeper'));
  out.push(s(1, { type: 'sell_at_stall', items: [{ kind: 'produce', id: 'R', qty: 5 }] }));
  out.push(...sowRound(1, [['R', 4], ['L', 2]],
    [['R', 4, 'bought'], ['L', 2, 'bought'], ['L', 3, 'bound']]));

  // —— D2 晴：1L 赠礼/出售、4R+4L 出售 80 → 买 2R+3L+2C → 播 2R+3L+2C+2C ——
  out.push(
    s(2, { type: 'harvest_cells', cell_ids: nine }),
    s(2, { type: 'talk_to_resident', resident_id: 'bistro_owner' }),
    s(2, { type: 'talk_to_resident', resident_id: 'nursery_keeper' }),
  );
  out.push(...lifeChoice(2, 'L', style, 'bistro_owner'));
  // The resident remembers the resolved choice in this second conversation, without extra daily points.
  out.push(s(2, { type: 'talk_to_resident', resident_id: 'bistro_owner' }));
  out.push(s(2, { type: 'sell_at_stall', items: [
    { kind: 'produce', id: 'R', qty: 4 }, { kind: 'produce', id: 'L', qty: 4 }] }));
  out.push(...sowRound(2, [['R', 2], ['L', 3], ['C', 2]],
    [['R', 2, 'bought'], ['L', 3, 'bought'], ['C', 2, 'bought'], ['C', 2, 'bound']]));

  // —— D3 晴：沙拉 1C1L、2C1L 请求 55、1R 赠礼/出售、1C1L1R 出售 36 → 买 4C+2L+1H ——
  out.push(
    s(3, { type: 'harvest_cells', cell_ids: nine }),
    s(3, { type: 'talk_to_resident', resident_id: 'nursery_keeper' }),
    s(3, { type: 'talk_to_resident', resident_id: 'bistro_owner' }),
    s(3, { type: 'cook_dish', recipe: 'salad' }),
    s(3, { type: 'attend_shared_event', event_id: 'cooking_together' }),
    s(3, { type: 'submit_request', request_id: 'd3_nursery_basket' }),
  );
  out.push(...lifeChoice(3, 'R', style, 'bistro_owner'));
  out.push(s(3, { type: 'sell_at_stall', items: [
    { kind: 'produce', id: 'C', qty: 1 }, { kind: 'produce', id: 'L', qty: 1 },
    ...(style === 'life' ? [] : [{ kind: 'produce' as const, id: 'R', qty: 1 }])] }));
  if (style === 'life')
    out.push(s(3, { type: 'sell_at_stall', items: [{ kind: 'produce', id: 'R', qty: 1 }] }));
  out.push(...sowRound(3, [['C', 4], ['L', 2], ['H', 1]],
    [['C', 4, 'bought'], ['L', 2, 'bought'], ['H', 1, 'bought'], ['H', 2, 'bound']]));

  // —— D4 晴：工程 1C1H、茶 1H 回购 24、1L 留作下周/出售、3C1H1L 出售 79 → 买 3C+3L+1H ——
  out.push(
    s(4, { type: 'harvest_cells', cell_ids: nine }),
    s(4, { type: 'reserve_engineering', items: { C: 1, H: 1 } }),
    s(4, { type: 'submit_engineering', items: { C: 1, H: 1 } }),
    s(4, { type: 'cook_dish', recipe: 'tea' }),
    s(4, { type: 'sell_to_buyback_box', qty: 1 }),
    s(4, { type: 'record_visit_return', visited_farm_id: 'preset_a' }),
  );
  // D4 的 1L 只保留、不计关系（PRD L635 明确「D4 的 1L 只保留，不计关系」）。
  out.push(...lifeChoice(4, 'L', style, null));
  out.push(s(4, { type: 'sell_at_stall', items: [
    { kind: 'produce', id: 'C', qty: 3 }, { kind: 'produce', id: 'H', qty: 1 },
    { kind: 'produce', id: 'L', qty: 1 }] }));
  // D4 是雨天（脚本第 5 项）——照料动作必须匹配播种当时的田况，不是匹配今天的。
  out.push(...sowRound(4, [['C', 3], ['L', 3], ['H', 1]],
    [['C', 3, 'bought'], ['L', 3, 'bought'], ['H', 1, 'bought'], ['H', 2, 'bound']]));
  return out;
}

/**
 * 一次用途选择：生活优先走赠礼/保留，出售优先一律卖掉（PRD L578）。
 * D4 那次没有归属居民，只保留。
 */
function lifeChoice(day: number, crop: string, style: Style, resident: string | null): Step[] {
  if (style === 'sell')
    return [
      s(day, { type: 'sell_at_stall', items: [{ kind: 'produce', id: crop, qty: 1 }] }),
      s(day, { type: 'resolve_life_choice', chapter: day, choice: 'sold' }),
    ];
  if (resident === null)
    return [s(day, { type: 'resolve_life_choice', chapter: day, choice: 'keep' })];
  return [
    s(day, { type: 'give_gift', resident_id: resident as 'nursery_keeper', crop: crop as 'R' }),
    s(day, { type: 'resolve_life_choice', chapter: day, choice: 'gift' }),
  ];
}

export function ledgerScript(path: Path, style: Style): Step[] {
  const out = commonDays(style);

  // —— D5 风：两份沙拉 → 修缮师请求 70、工程 1H、1H 赠礼/出售、1C1H1L 出售 47 ——
  out.push(
    s(5, { type: 'harvest_cells', cell_ids: nine }),
    s(5, { type: 'talk_to_resident', resident_id: 'restorer' }),
    // PRD L629-633 夹具：D5 苗圃 31=29+2、小馆 60=58+2；D6 苗圃 58=31+2+25、小馆 62=60+2。
    // 也就是这两天与两名完整居民各有一次当日首次对话。
    s(5, { type: 'talk_to_resident', resident_id: 'nursery_keeper' }),
    s(5, { type: 'talk_to_resident', resident_id: 'bistro_owner' }),
    s(5, { type: 'cook_dish', recipe: 'salad' }),
    s(5, { type: 'cook_dish', recipe: 'salad' }),
    s(5, { type: 'submit_request', request_id: 'd5_restorer_salads' }),
    s(5, { type: 'reserve_engineering', items: { H: 1 } }),
    s(5, { type: 'submit_engineering', items: { H: 1 } }),
    s(5, { type: 'choose_nursery_appearance', appearance: 'a' }),
  );
  out.push(...lifeChoice(5, 'H', style, 'restorer'));
  out.push(s(5, { type: 'sell_at_stall', items: [
    { kind: 'produce', id: 'C', qty: 1 }, { kind: 'produce', id: 'H', qty: 1 },
    { kind: 'produce', id: 'L', qty: 1 }] }));
  out.push(s(5, { type: 'set_growth_intent', choice: path }));
  out.push(s(5, { type: 'purchase_growth_choice', choice: path, transaction_id: `tx_${path}` }));

  if (path === 'tool') {
    out.push(...sowRound(5, [['C', 3], ['H', 3], ['L', 3]],
      [['C', 3, 'bought'], ['H', 3, 'bought'], ['L', 3, 'bought']]));
  } else {
    // 扩地：400 + 固定篮 3R3L3C3H = 84 已在 purchase 里一次付清并入库，第四畦到手即已翻土。
    // 本轮在原 9 格外多播 3R（PRD L567「在原 9 格配方外多买并播种 3R，种子共 84」）。
    out.push(...sowRound(5, [], [['C', 3, 'bought'], ['H', 3, 'bought'], ['L', 3, 'bought']]));
    out.push(s(5, { type: 'till_cells', cell_ids: EXTRA_SOIL }));
    out.push(s(5, { type: 'sow_cells', cell_ids: EXTRA_SOIL, crop: 'R', lot: 'bought' }));
    out.push(s(5, { type: 'water_cells', cell_ids: EXTRA_SOIL }));
  }

  // —— D6 晴：工程 1C2H 交齐配额、1L 赠礼/出售、2C1H2L 出售 75、竣工补贴 60 ——
  const all = path === 'field' ? [...nine, ...EXTRA_SOIL] : nine;
  out.push(
    s(6, { type: 'harvest_cells', cell_ids: nine }),
    ...(path === 'field' ? [s(6, { type: 'harvest_cells', cell_ids: EXTRA_SOIL } as Command)] : []),
    s(6, { type: 'reserve_engineering', items: { C: 1, H: 2 } }),
    s(6, { type: 'submit_engineering', items: { C: 1, H: 2 } }),
    s(6, { type: 'attend_shared_event', event_id: 'nursery_activity' }),
    s(6, { type: 'talk_to_resident', resident_id: 'nursery_keeper' }),
    s(6, { type: 'talk_to_resident', resident_id: 'restorer' }),
    s(6, { type: 'talk_to_resident', resident_id: 'bistro_owner' }),
    s(6, { type: 'claim_subsidy', subsidy_id: 'nursery_built' }),
  );
  out.push(...lifeChoice(6, 'L', style, 'restorer'));
  out.push(s(6, { type: 'sell_at_stall', items: [
    { kind: 'produce', id: 'C', qty: 2 }, { kind: 'produce', id: 'H', qty: 1 },
    { kind: 'produce', id: 'L', qty: 2 }] }));
  if (path === 'field')
    out.push(s(6, { type: 'sell_at_stall', items: [{ kind: 'produce', id: 'R', qty: 3 }] }));
  const buy: [string, number][] = path === 'field'
    ? [['C', 2], ['H', 2], ['L', 2], ['R', 3]]
    : [['C', 2], ['H', 2], ['L', 2]];
  out.push(...sowRound(6, buy, [['C', 2, 'bought'], ['H', 2, 'bought'], ['L', 2, 'bought'],
    ['C', 1, 'bound'], ['H', 1, 'bound'], ['L', 1, 'bound']]));
  if (path === 'field') {
    out.push(s(6, { type: 'sow_cells', cell_ids: EXTRA_SOIL, crop: 'R', lot: 'bought' }));
    out.push(s(6, { type: 'water_cells', cell_ids: EXTRA_SOIL }));
  }
  return out;
}
