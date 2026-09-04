/**
 * 蓝图的共享类型。管线（tools/geo_blueprint）、服务端（server）与 Godot 测试三方共用同一份
 * canonical/validate/fairness 实现，本文件是它们的契约。
 */

export type Cell = [number, number]; // [x(i 向东), y(j 向北)]

export interface Masks {
  visual: string[];
  walkable: string[];
  buildable: string[];
  cultivable: string[];
}

export interface Bed {
  id: string;
  cells: Cell[];
}

export interface Anchors {
  spawn: Cell;
  house: Cell;
  storage: Cell;
  well: Cell;
  exit: Cell;
  beds: Bed[];
  reserved_bed: Bed;
}

/**
 * 公平指标（spec §6）。全部是绝对秒数，没有相对差值——相对差值在 6 秒量级的基数上
 * 会因为一个常数项的取值在 6.8% 与 29% 之间跳动，衡量不了任何东西（2026-09-04 决策③）。
 */
export interface Report {
  far_bed_9_s: number;
  far_bed_12_s: number;
  walk_tour_9_s: number;
  walk_tour_12_s: number;
  tour_s: number;
  errors: string[];
}

export interface Blueprint {
  format: number;
  layout_patch_id: string;
  revision: number;
  region_id: string;
  name: string;
  checksum: string;
  source: Record<string, unknown>;
  /**
   * 权威尺寸字段是整数毫米。r1 只有浮点 play_area_m / cell_m，canonical 因此依赖
   * "1.0" 与 1 在两种语言里的字面量写法一致，而 JSON 解析器不保留数值词法
   * （JS `String(1.0)` 得 "1"，GDScript `str(1.0)` 得 "1.0"）。r2 起以毫米整数为准，
   * 浮点字段降级为展示用派生值且不进 canonical（Codex 三审 V3-I5）。
   */
  cell_mm: number;
  play_area_mm: number;
  /** 派生展示值 = *_mm / 1000，不参与 checksum。r1 蓝图只有这两个字段。 */
  cell_m: number;
  play_area_m: number;
  grid: [number, number];
  masks: Masks;
  paths: { id: string; points: Cell[]; width_m: number }[];
  blocks: { id: string; polygon: [number, number][]; neighbors: string[] }[];
  anchors: Anchors;
  overlay_wgs84: { center: [number, number]; paths: [number, number][][]; blocks: [number, number][][] };
  report?: Report;
}
