import type { Command } from '../commands.js';
import type { Content } from '../content.js';
import { err, ok, type Result } from '../errors.js';
import type { Ctx } from '../reducer.js';
import type { DecorationPlacement, FarmState } from '../state.js';
import { isPlaceable, type PlotLayout } from '../plot.js';
import { canUse, hasFact } from '../journey.js';

/** 一个道具占的全部格。左上角为锚点，向东南铺开。 */
export function footprintCells(cell: [number, number], size: [number, number]): string[] {
  const out: string[] = [];
  for (let dj = 0; dj < size[1]; dj++)
    for (let di = 0; di < size[0]; di++) out.push(`${cell[0] + di},${cell[1] + dj}`);
  return out;
}

/**
 * 能不能把道具放在这里。三条判据缺一不可：
 *   ① 地面「可放置」属性（路、草坪、土都行；水面、建筑、岩壁不行）
 *   ② 那一格没有开垦过的地（不能压在作物上）
 *   ③ 不与已放的道具重叠
 */
export function propPlacementAllowed(
  plot: PlotLayout, s: FarmState, cell: [number, number], size: [number, number], taken: Set<string>,
): boolean {
  for (const id of footprintCells(cell, size)) {
    if (!isPlaceable(plot, id)) return false;
    if (s.cells[id]) return false;
    if (taken.has(id)) return false;
  }
  return true;
}

export function applyDecorations(s: FarmState, cmd: Command, ctx: Ctx): Result<FarmState> | null {
  if (cmd.type !== 'save_decorations') return null;
  if (!hasFact(s, 'planter_crafted') && s.growth_choice.purchase !== 'tool' && s.growth_choice.purchase !== 'field')
    return err('DECORATION_LOCKED', '购买成长路线后可布置庭院');
  const content = ctx.content.decorations;
  if (!Array.isArray(cmd.props) || cmd.props.length > content.max_props)
    return err('INVALID_DECORATION', '摆件列表非法');
  const ids = new Set<string>();
  const taken = new Set<string>();
  const placements: DecorationPlacement[] = [];
  for (const raw of cmd.props) {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)
      || Object.keys(raw).some(key => !['prop_id', 'cell', 'rotation_q'].includes(key))
      || typeof raw.prop_id !== 'string' || !Object.hasOwn(content.props, raw.prop_id)
      || ids.has(raw.prop_id) || !Array.isArray(raw.cell) || raw.cell.length !== 2
      || !raw.cell.every((n: unknown) => Number.isSafeInteger(n)))
      return err('INVALID_DECORATION', '摆件或位置非法');
    if (raw.rotation_q !== undefined && (!Number.isSafeInteger(raw.rotation_q) || raw.rotation_q < 0 || raw.rotation_q > 3))
      return err('INVALID_DECORATION', 'Invalid rotation');
    const cell = raw.cell as [number, number];
    if (s.journey && !canUse(s, 'decorations', 99) && raw.prop_id !== 'planter')
      return err('DECORATION_LOCKED', 'Place your first crafted planter');
    const size = content.props[raw.prop_id].footprint;
    if (!propPlacementAllowed(ctx.plot, s, cell, size, taken))
      return err('INVALID_DECORATION', '这里不能放东西');
    for (const id of footprintCells(cell, size)) taken.add(id);
    ids.add(raw.prop_id);
    placements.push({ prop_id: raw.prop_id, cell,
      ...(raw.rotation_q ? { rotation_q: raw.rotation_q } : {}) });
  }
  const next = structuredClone(s);
  if (next.journey) {
    const workshop = next.journey.workshop ??= { sequence: 0, stock: {}, displays: {} };
    const previous = new Set((s.decorations ?? []).map(prop => prop.prop_id));
    const added = placements.filter(prop => !previous.has(prop.prop_id));
    const removed = (s.decorations ?? []).filter(prop => !ids.has(prop.prop_id));
    for (const prop of added) {
      if ((workshop.stock[prop.prop_id] ?? 0) < 1) return err('INSUFFICIENT_ITEMS', prop.prop_id);
      workshop.stock[prop.prop_id] -= 1;
    }
    for (const prop of removed) workshop.stock[prop.prop_id] = (workshop.stock[prop.prop_id] ?? 0) + 1;
    if (added.length || removed.length) workshop.sequence += 1;
  }
  next.decorations = placements;
  return ok(next, [{ type: 'decorations_saved', count: placements.length }]);
}
