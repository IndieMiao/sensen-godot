/**
 * 三个显式 DTO（Codex 二审 Critical 4）。原设计只有一个 `publicView(state)` 且计划被 G2
 * 访客接口复用，那会把 owner_id、钱包、库存、关系、剧情全发给访客。
 *
 * 测试用**精确允许字段集**校验，而不是扫描禁用键名——后者只能挡住已知的坏字段。
 */
import type { FarmState } from '../domain/state.js';
import type { Derived } from '../domain/derive.js';

export interface FarmRow {
  id: string;
  owner_id: string;
  region_id: string;
  layout_patch_id: string;
  blueprint_revision: number;
  version: number;
  location_visible: boolean;
  visit_access: 'only_me' | 'anyone';
  state: FarmState;
}

/** 主人视图：状态全给自己。 */
export function ownerFarmView(f: FarmRow, d: Derived, serverTime: number) {
  return {
    farm_id: f.id,
    region_id: f.region_id,
    layout_patch_id: f.layout_patch_id,
    blueprint_revision: f.blueprint_revision,
    version: f.version,
    location_visible: f.location_visible,
    visit_access: f.visit_access,
    state: f.state,
    derived: {
      player_day_id: d.player_day_id,
      field_condition: d.field_condition,
      chapter_index: d.chapter_index,
      ripe_cells: d.ripe_cells,
    },
    server_time: serverTime,
  };
}

export interface VisitorProp {
  anchor_id: string;
  prop_id: string;
  offset_q: [number, number];
}

/**
 * 访客快照（G2 用，本 Task 只定形状）。**不含** owner_id / wallet / inventory /
 * residents / chapters / xp / growth_choice / 任何经纬度。
 *
 * `location_visible` 为假时连 region_id 一起省掉；`layout_patch_id` 仍要发——访客要渲染
 * 对方农场就必须知道用的哪张蓝图，这是 MVP 明确接受的折衷（SGODOT-29）。
 */
export function visitorSnapshot(
  f: FarmRow, d: Derived, snapshotRevision: number, takenAt: number, props: VisitorProp[] = [],
) {
  const cells = Object.entries(f.state.cells).map(([cell_id, c]) => ({
    cell_id, state: c.state, crop: c.crop, ripe: d.ripe_cells.includes(cell_id),
  }));
  return {
    farm_id: f.id,
    layout_patch_id: f.layout_patch_id,
    blueprint_revision: f.blueprint_revision,
    snapshot_revision: snapshotRevision,
    snapshot_taken_at: takenAt,
    cells,
    nursery: { stage: f.state.nursery.stage, appearance: f.state.nursery.appearance },
    props,
    weather_snapshot: d.field_condition,
    ...(f.location_visible ? { region_id: f.region_id } : {}),
  };
}

export function nearbyEntry(f: FarmRow, avatarRef: string) {
  return {
    farm_id: f.id,
    avatar_ref: avatarRef,
    nursery_stage: f.state.nursery.stage,
    ...(f.location_visible ? { region_id: f.region_id } : {}),
  };
}

/**
 * 快照按**固定 15 分钟槽**生成，与主人是否操作无关（Codex 三审 V3-I3）。按操作触发的
 * 快照会让 `snapshot_taken_at` 的变化泄露主人的上线与操作时刻；固定槽下访客反复轮询
 * 只能看到槽在走。
 */
export const SNAPSHOT_SLOT_MS = 15 * 60_000;
export const snapshotSlot = (now: number): number => Math.floor(now / SNAPSHOT_SLOT_MS) * SNAPSHOT_SLOT_MS;
