/**
 * 玩家地块内的农场状态（C-31）与它的命令。服务端不持有地块几何（障碍位置、保护通道、核心区与外围来自
 * 地块数据集，由客户端 C-33/C-34 判断），这里只管服务端能核实的部分：首次进入发一次赠品（Q-39、Q-40），
 * 放房子要扣蓝图且不压开垦格和作物，开垦要有锄头且不在房子占地内，只能在开垦格上播种并扣种子，
 * 按服务端时间判成熟，收获入包。
 */
import type { ParcelRules } from './rules.js';

export const FARM_STATE_VERSION = 1;
/** 格坐标上限与每类格数上限；地块总格数不超过 8192（客户端 parcel_metadata）。 */
export const MAX_COORD = 1024;
export const MAX_CELLS = 8192;
export const MAX_BATCH = 50;

export interface HouseState { model: string; x: number; y: number; width: number; depth: number; rotation: number; built_at: number }
export interface CropState { crop: string; planted_at: number; ripe_at: number }
export interface ParcelFarmState {
  v: typeof FARM_STATE_VERSION;
  house: HouseState | null;
  /** 已清理障碍的格，"x,y"。 */
  cleared: string[];
  /** 已开垦格，"x,y"；收获后仍是开垦格。 */
  tilled: string[];
  crops: Record<string, CropState>;
  bag: Record<string, number>;
  /** 首次进入自家地块的赠品发放时间；null 表示还没进过。发过就不再发。 */
  welcomed_at: number | null;
}

export type FarmCommand =
  | { type: 'place_house'; x: number; y: number; rotation?: number }
  | { type: 'clear_obstacle'; cell: string }
  | { type: 'till'; cell: string }
  | { type: 'sow'; cell: string; crop: string }
  | { type: 'harvest'; cell: string };

export type FarmOutcome =
  | { ok: true; state: ParcelFarmState }
  | { ok: false; index: number; code: string; detail?: Record<string, unknown> };

/** 认领时的空农场：背包为空，赠品等首次进入时再发（认领和进入不是同一个动作）。 */
export function emptyFarm(): ParcelFarmState {
  return { v: FARM_STATE_VERSION, house: null, cleared: [], tilled: [], crops: {}, bag: {}, welcomed_at: null };
}

/** 首次进入自家地块：发一次 welcome_gift。已经发过返回 null（重开、重试都不重发）。 */
export function welcome(rules: ParcelRules, state: ParcelFarmState, now: number): ParcelFarmState | null {
  if (state.welcomed_at !== null) return null;
  const s = structuredClone(state);
  for (const [id, n] of Object.entries(rules.welcome_gift)) s.bag[id] = (s.bag[id] ?? 0) + n;
  s.welcomed_at = now;
  return s;
}

const coord = (v: unknown): v is number => Number.isInteger(v) && (v as number) >= 0 && (v as number) < MAX_COORD;

/** "x,y" 的规范写法（无前导零、无空格）才收，避免同一格两种写法各占一行。 */
export function parseCell(v: unknown): [number, number] | null {
  if (typeof v !== 'string') return null;
  const m = /^(0|[1-9]\d{0,3}),(0|[1-9]\d{0,3})$/.exec(v);
  if (!m) return null;
  const x = Number(m[1]), y = Number(m[2]);
  return coord(x) && coord(y) ? [x, y] : null;
}

/** 请求体里的命令只做形状检查；语义检查在 applyFarmCommands 里。 */
export function parseFarmCommands(raw: unknown): FarmCommand[] | null {
  if (!Array.isArray(raw) || raw.length < 1 || raw.length > MAX_BATCH) return null;
  const out: FarmCommand[] = [];
  for (const c of raw as Record<string, unknown>[]) {
    if (!c || typeof c !== 'object') return null;
    switch (c.type) {
      case 'place_house':
        if (!coord(c.x) || !coord(c.y) || (c.rotation !== undefined && ![0, 1, 2, 3].includes(c.rotation as number))) return null;
        out.push({ type: 'place_house', x: c.x, y: c.y, rotation: (c.rotation as number | undefined) ?? 0 });
        break;
      case 'clear_obstacle': case 'till': case 'harvest':
        if (!parseCell(c.cell)) return null;
        out.push({ type: c.type, cell: c.cell as string });
        break;
      case 'sow':
        if (!parseCell(c.cell) || typeof c.crop !== 'string' || c.crop.length > 64) return null;
        out.push({ type: 'sow', cell: c.cell as string, crop: c.crop });
        break;
      default:
        return null;
    }
  }
  return out;
}

/** 转 90°/270° 时宽深互换。 */
function footprint(h: { x: number; y: number; width: number; depth: number; rotation: number }): { x0: number; y0: number; x1: number; y1: number } {
  const [w, d] = h.rotation % 2 ? [h.depth, h.width] : [h.width, h.depth];
  return { x0: h.x, y0: h.y, x1: h.x + w - 1, y1: h.y + d - 1 };
}

const underHouse = (s: ParcelFarmState, cell: string): boolean => {
  if (!s.house) return false;
  const [x, y] = parseCell(cell)!, f = footprint(s.house);
  return x >= f.x0 && x <= f.x1 && y >= f.y0 && y <= f.y1;
};

/** 一批命令全部成功才生效；任一失败整批不变，返回失败的序号。 */
export function applyFarmCommands(rules: ParcelRules, state: ParcelFarmState, commands: FarmCommand[], now: number): FarmOutcome {
  const s = structuredClone(state);
  for (const [index, c] of commands.entries()) {
    const fail = (code: string, detail?: Record<string, unknown>): FarmOutcome => ({ ok: false, index, code, ...(detail ? { detail } : {}) });
    switch (c.type) {
      case 'place_house': {
        if (s.house) return fail('HOUSE_PLACED');
        if (!(s.bag[rules.house.blueprint] > 0)) return fail('NO_BLUEPRINT', { item: rules.house.blueprint });
        const house = { model: rules.house.model, x: c.x, y: c.y, width: rules.house.width, depth: rules.house.depth, rotation: c.rotation ?? 0, built_at: now };
        const f = footprint(house);
        if (f.x1 >= MAX_COORD || f.y1 >= MAX_COORD) return fail('OUT_OF_BOUNDS');
        const covered = [...s.tilled, ...Object.keys(s.crops)].filter(cell => {
          const [x, y] = parseCell(cell)!;
          return x >= f.x0 && x <= f.x1 && y >= f.y0 && y <= f.y1;
        });
        if (covered.length) return fail('CELL_OCCUPIED', { cells: [...new Set(covered)].sort() });
        take(s.bag, rules.house.blueprint, 1);
        s.house = house;
        break;
      }
      case 'clear_obstacle':
        if (s.cleared.includes(c.cell)) return fail('ALREADY_CLEARED');
        if (s.cleared.length >= MAX_CELLS) return fail('TOO_MANY_CELLS');
        s.cleared.push(c.cell);
        break;
      case 'till':
        if (!(s.bag[rules.till_tool] > 0)) return fail('NO_TOOL', { item: rules.till_tool });
        if (underHouse(s, c.cell)) return fail('CELL_OCCUPIED', { cells: [c.cell] });
        if (s.tilled.includes(c.cell)) return fail('ALREADY_TILLED');
        if (s.tilled.length >= MAX_CELLS) return fail('TOO_MANY_CELLS');
        s.tilled.push(c.cell);
        break;
      case 'sow': {
        const rule = rules.crops[c.crop];
        if (!rule) return fail('UNKNOWN_CROP');
        if (!s.tilled.includes(c.cell)) return fail('NOT_TILLED');
        if (s.crops[c.cell]) return fail('CELL_OCCUPIED', { cells: [c.cell] });
        if (!(s.bag[rule.seed] > 0)) return fail('NO_SEED', { item: rule.seed });
        take(s.bag, rule.seed, 1);
        s.crops[c.cell] = { crop: c.crop, planted_at: now, ripe_at: now + rule.grow_seconds * 1000 };
        break;
      }
      case 'harvest': {
        const crop = s.crops[c.cell];
        if (!crop) return fail('NO_CROP');
        if (now < crop.ripe_at) return fail('NOT_RIPE', { ripe_at: crop.ripe_at });
        delete s.crops[c.cell];
        const amount = rules.crops[crop.crop]?.yield ?? 1;
        s.bag[crop.crop] = (s.bag[crop.crop] ?? 0) + amount;
        break;
      }
    }
  }
  return { ok: true, state: s };
}

function take(bag: Record<string, number>, id: string, n: number): void {
  bag[id] -= n;
  if (bag[id] <= 0) delete bag[id];
}
