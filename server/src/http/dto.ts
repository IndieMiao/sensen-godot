/**
 * 三个显式 DTO（Codex 二审 Critical 4）。原设计只有一个 `publicView(state)` 且计划被 G2
 * 访客接口复用，那会把 owner_id、钱包、库存、关系、剧情全发给访客。
 *
 * 测试用**精确允许字段集**校验，而不是扫描禁用键名——后者只能挡住已知的坏字段。
 */
import type { FarmState } from '../domain/state.js';
import { derive, type Derived } from '../domain/derive.js';
import { STREET_EFFECT_IDS, type Content } from '../domain/content.js';
import type { Ctx } from '../domain/reducer.js';
import { projectFarmState } from '../domain/progress.js';
import type { FarmLocation } from './farm_location.js';

export interface FarmRow {
  id: string;
  owner_id: string;
  region_id: string;
  layout_patch_id: string;
  blueprint_revision: number;
  location?: FarmLocation;
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
    ...(f.location ? { location: f.location } : {}),
    version: f.version,
    location_visible: f.location_visible,
    visit_access: f.visit_access,
    state: f.state,
    derived: {
      player_day_id: d.player_day_id,
      field_condition: d.field_condition,
      chapter_index: d.chapter_index,
      next_chapter_opens_at: d.next_chapter_opens_at,
      ripe_cells: d.ripe_cells,
    },
    server_time: serverTime,
  };
}

/** Reads and command replies project the same chapter and grants without a database write. */
export function currentOwnerFarmView(
  f: FarmRow, serverTime: number, timezone: string, content: Content, blueprint: Ctx['blueprint'],
) {
  const state = projectFarmState(f.state, serverTime, timezone, content, blueprint);
  return ownerFarmView({ ...f, state }, derive(state, serverTime, timezone, content), serverTime);
}

export interface VisitorProp {
  anchor_id: string;
  prop_id: string;
  offset_q: [number, number];
}

/**
 * 访客快照（G2 用，本 Task 只定形状）。**不含** owner_id / wallet / inventory /
 * residents / chapters / xp / growth_choice。公开位置只来自玩家主动选址。
 *
 * `location_visible` 为假时连 region_id 一起省掉；`layout_patch_id` 仍要发——访客要渲染
 * 对方农场就必须知道用的哪张蓝图，这是 MVP 明确接受的折衷（SGODOT-29）。
 */
export function visitorSnapshot(
  f: FarmRow, d: Derived, snapshotRevision: number, takenAt: number, props: VisitorProp[] = f.state.decorations ?? [],
  avatarRef = 'seed:unknown',
) {
  const cells = Object.entries(f.state.cells).map(([cell_id, c]) => ({
    cell_id, state: c.state, crop: c.crop, ripe: d.ripe_cells.includes(cell_id),
  }));
  return {
    farm_id: f.id,
    avatar_ref: avatarRef,
    layout_patch_id: f.layout_patch_id,
    blueprint_revision: f.blueprint_revision,
    snapshot_revision: snapshotRevision,
    snapshot_taken_at: takenAt,
    beds_unlocked: f.state.beds_unlocked,
    ...(f.state.field_progress ? { unlocked_cell_ids: [
      ...f.state.field_progress.order.slice(0, f.state.field_progress.plots),
      ...(f.state.beds_unlocked === 4 ? Object.keys(f.state.cells).filter(id => !f.state.field_progress!.order.includes(id)) : []),
    ] } : {}),
    cells,
    nursery: { stage: f.state.nursery.stage, appearance: f.state.nursery.appearance },
    props: props.map(prop => ({ anchor_id: prop.anchor_id, prop_id: prop.prop_id,
      offset_q: [prop.offset_q[0], prop.offset_q[1]] as [number, number] })),
    weather_snapshot: d.field_condition,
    ...(f.state.journey ? { street_snapshot: {
      side_path: f.state.journey.facts.includes('side_path'),
      contributions: Object.fromEntries(STREET_EFFECT_IDS.map(id => [id, f.state.journey!.contributions?.[id] ?? 0])),
      gathering: f.state.journey.gathering?.current ?? '',
    } } : {}),
    ...(f.location_visible ? { region_id: f.region_id, ...(f.location ? { location: f.location } : {}) } : {}),
  };
}

export function nearbyEntry(f: FarmRow, avatarRef: string) {
  return {
    farm_id: f.id,
    avatar_ref: avatarRef,
    nursery_stage: f.state.nursery.stage,
    ...(f.location_visible ? { region_id: f.region_id, ...(f.location ? { location: f.location } : {}) } : {}),
  };
}

/**
 * 快照按**固定 15 分钟槽**生成，与主人是否操作无关（Codex 三审 V3-I3）。按操作触发的
 * 快照会让 `snapshot_taken_at` 的变化泄露主人的上线与操作时刻；固定槽下访客反复轮询
 * 只能看到槽在走。
 */
export const SNAPSHOT_SLOT_MS = 15 * 60_000;
export const snapshotSlot = (now: number): number => Math.floor(now / SNAPSHOT_SLOT_MS) * SNAPSHOT_SLOT_MS;
