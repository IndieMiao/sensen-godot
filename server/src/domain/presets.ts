/**
 * 预置访客农场（PRD §8.4：至少两座风格明显不同的系统农场，复用已发布蓝图）。
 *
 * **id 是确定性的**：farm_id / owner_id 都由 sha1("preset:<layout>") 拼成 UUID。这样随包
 * 兜底快照（assets/farm/presets/*.json）与线上库里的那座是**同一座**农场——客户端离线时
 * 用随包、在线时用服务端，`record_visit_return.visited_farm_id` 两条路对得上。
 *
 * 状态用**真实归约器**跑出来而不是手写 JSON：手写的很容易出现服务端永远不会产生的组合
 * （比如 growing 却没有 ready_at），访客渲染就会撞上没测过的分支。
 */
import { createHash } from 'node:crypto';
import type { Content } from './content.js';
import type { Command } from './commands.js';
import { applyAt, type Ctx } from './reducer.js';
import type { FarmState } from './state.js';
import { initialFarmState } from './farm_factory.js';
import type { FarmLocation } from '../http/farm_location.js';

export type PresetStyle = 'lush' | 'early';

export interface PresetSpec {
  id?: string;
  location?: FarmLocation;
  layout: string;
  revision: number;
  region: string;
  style: PresetStyle;
  avatar_ref: string;
}

/** 每城两座：一座繁茂（作物满地、部分已熟），一座初垦（只清了几格）。 */
export const PRESET_SPECS: PresetSpec[] = [
  { layout: 'sh_b', revision: 2, region: 'shanghai', style: 'lush', avatar_ref: 'preset_a' },
  { layout: 'sh_c', revision: 2, region: 'shanghai', style: 'early', avatar_ref: 'preset_b' },
  { layout: 'la_b', revision: 2, region: 'los_angeles', style: 'lush', avatar_ref: 'preset_a' },
  { layout: 'la_c', revision: 2, region: 'los_angeles', style: 'early', avatar_ref: 'preset_b' },
  { id: 'demo_sh_01', layout: 'sh_b', revision: 2, region: 'shanghai', style: 'lush', avatar_ref: 'demo_sh_01', location: { lat: 31.2315, lng: 121.4722 } },
  { id: 'demo_sh_02', layout: 'sh_a', revision: 2, region: 'shanghai', style: 'lush', avatar_ref: 'demo_sh_02', location: { lat: 31.2315, lng: 121.4752 } },
  { id: 'demo_sh_03', layout: 'sh_c', revision: 2, region: 'shanghai', style: 'early', avatar_ref: 'demo_sh_03', location: { lat: 31.2293, lng: 121.4722 } },
  { id: 'demo_sh_04', layout: 'sh_b', revision: 2, region: 'shanghai', style: 'lush', avatar_ref: 'demo_sh_04', location: { lat: 31.2293, lng: 121.4752 } },
  { id: 'demo_la_01', layout: 'la_a', revision: 2, region: 'los_angeles', style: 'lush', avatar_ref: 'demo_la_01', location: { lat: 34.0533, lng: -118.2452 } },
  { id: 'demo_la_02', layout: 'la_b', revision: 2, region: 'los_angeles', style: 'lush', avatar_ref: 'demo_la_02', location: { lat: 34.0533, lng: -118.2422 } },
  { id: 'demo_la_03', layout: 'la_c', revision: 2, region: 'los_angeles', style: 'early', avatar_ref: 'demo_la_03', location: { lat: 34.0511, lng: -118.2452 } },
  { id: 'demo_la_04', layout: 'la_a', revision: 2, region: 'los_angeles', style: 'lush', avatar_ref: 'demo_la_04', location: { lat: 34.0511, lng: -118.2422 } },
];

// Four neighbours around each selectable neighbourhood, visible at its initial zoom.
const DEMO_NEIGHBOURHOODS = [
  { layout: 'sh_a', region: 'shanghai', center: [31.204, 121.447] },
  { layout: 'sh_b', region: 'shanghai', center: [31.2265, 121.4915] },
  { layout: 'sh_c', region: 'shanghai', center: [31.22, 121.438] },
  { layout: 'la_a', region: 'los_angeles', center: [34.0455, -118.2495] },
  { layout: 'la_b', region: 'los_angeles', center: [33.9822, -118.4665] },
  { layout: 'la_c', region: 'los_angeles', center: [34.087, -118.2745] },
] as const;
for (const [index, neighbourhood] of DEMO_NEIGHBOURHOODS.entries()) {
  for (const [slot, offset] of [[0.00125, -0.0014], [-0.00015, -0.00165], [-0.0014, 0.0014], [0.00105, 0.00165]].entries()) {
    const prefix = neighbourhood.region === 'shanghai' ? 'sh' : 'la';
    const id = `demo_${prefix}_${String(5 + (index % 3) * 4 + slot).padStart(2, '0')}`;
    PRESET_SPECS.push({ id, layout: neighbourhood.layout, revision: 2, region: neighbourhood.region,
      style: slot === 1 ? 'early' : 'lush', avatar_ref: id,
      location: { lat: neighbourhood.center[0] + offset[0]!, lng: neighbourhood.center[1] + offset[1]! } });
  }
}

/** sha1 → 合法 UUID（版本位 5，变体位 10xx），pg 的 uuid 列才收。 */
export function deterministicUuid(name: string): string {
  const h = createHash('sha1').update(name).digest('hex').slice(0, 32).split('');
  h[12] = '5';
  h[16] = ((parseInt(h[16]!, 16) & 0x3) | 0x8).toString(16);
  const s = h.join('');
  return `${s.slice(0, 8)}-${s.slice(8, 12)}-${s.slice(12, 16)}-${s.slice(16, 20)}-${s.slice(20)}`;
}

export const presetFarmId = (layout: string): string => deterministicUuid(`preset:${layout}`);
export const presetOwnerId = (layout: string): string => deterministicUuid(`preset-owner:${layout}`);
/** 系统玩家没有安装密钥；这个值只用来占住 players.install_key_hmac 的唯一列。 */
export const presetHmac = (layout: string): string => `preset:${layout}`;

const PRESET_BY_FARM_ID = new Map(PRESET_SPECS.map(s => [presetFarmId(s.id ?? s.layout), s]));
export const presetByFarmId = (farmId: string): PresetSpec | undefined => PRESET_BY_FARM_ID.get(farmId);

export interface PresetFarmRow {
  location?: FarmLocation;
  id: string;
  owner_id: string;
  region_id: string;
  layout_patch_id: string;
  blueprint_revision: number;
  version: number;
  location_visible: boolean;
  visit_access: 'anyone';
  state: FarmState;
}

const chunk3 = (xs: string[]): string[][] => [xs.slice(0, 3), xs.slice(3, 6), xs.slice(6, 9)];

export function buildPresetFarm(
  spec: PresetSpec, sets: Ctx['blueprint'], content: Content, timezone: string, now: number,
): PresetFarmRow {
  let state = initialFarmState(content, sets, timezone, now);
  const beds = chunk3([...sets.cultivable].filter(x => !sets.reserved.has(x)));
  const all9 = beds.flat();
  const care = content.weather.care_action[content.weather.script[0]];
  const script: Command[] = spec.style === 'lush'
    ? [
      { type: 'clear_cells', cell_ids: all9 },
      { type: 'till_cells', cell_ids: all9 },
      { type: 'sow_cells', cell_ids: beds[0]!, crop: 'R', lot: 'bound' },
      { type: 'sow_cells', cell_ids: beds[1]!, crop: 'L', lot: 'bound' },
      { type: 'sow_cells', cell_ids: beds[2]!, crop: 'R', lot: 'bound' },
      { type: 'apply_care', cell_ids: all9, kind: care },
    ]
    : [
      { type: 'clear_cells', cell_ids: [...beds[0]!, ...beds[1]!] },
      { type: 'till_cells', cell_ids: beds[0]! },
    ];
  for (const cmd of script) {
    const r = applyAt(state, cmd, now, timezone, content, sets);
    if (!r.ok) throw new Error(`预置农场 ${spec.layout} 脚本失败于 ${cmd.type}: ${r.code} ${r.detail ?? ''}`);
    state = r.state;
  }
  if (spec.style === 'lush') state.nursery.stage = 'cleared';
  return {
    id: presetFarmId(spec.id ?? spec.layout), owner_id: presetOwnerId(spec.id ?? spec.layout),
    ...(spec.location ? { location: { ...spec.location } } : {}),
    region_id: spec.region, layout_patch_id: spec.layout, blueprint_revision: spec.revision,
    version: 0, location_visible: true, visit_access: 'anyone', state,
  };
}
