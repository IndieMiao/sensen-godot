export type Cell = [number, number]; // [x(i), y(j)]

export interface Masks {
  visual: string[];
  walkable: string[];
  buildable: string[];
  cultivable: string[];
}

export interface Bed { id: string; cells: Cell[] }

export interface Anchors {
  spawn: Cell; house: Cell; storage: Cell; well: Cell; exit: Cell;
  beds: Bed[];
  reserved_bed: Bed;
}

export interface Report { far_bed_s: number; tour_s: number; errors: string[] }

export interface Blueprint {
  format: 1;
  layout_patch_id: string;
  revision: number;
  region_id: string;
  name: string;
  checksum: string;
  source: Record<string, unknown>;
  play_area_m: number;
  cell_m: number;
  grid: [number, number];
  masks: Masks;
  paths: { id: string; points: Cell[]; width_m: number }[];
  blocks: { id: string; polygon: [number, number][]; neighbors: string[] }[];
  anchors: Anchors;
  overlay_wgs84: { center: [number, number]; paths: [number, number][][]; blocks: [number, number][][] };
  report?: Report;
}
