import type { Command } from '../commands.js';
import type { Content } from '../content.js';
import { err, ok, type Result } from '../errors.js';
import type { Ctx } from '../reducer.js';
import type { DecorationPlacement, FarmState } from '../state.js';

export function decorationPositionAllowed(x: number, z: number, content: Content['decorations']): boolean {
  const bounds = content.bounds_q;
  return Number.isSafeInteger(x) && Number.isSafeInteger(z)
    && x >= bounds.min_x && x <= bounds.max_x && z >= bounds.min_z && z <= bounds.max_z
    && Math.abs(x) >= content.min_abs_x_q
    && !(Math.abs(x) >= content.blocked_outer.min_abs_x_q && z <= content.blocked_outer.max_z_q);
}

export function applyDecorations(s: FarmState, cmd: Command, ctx: Ctx): Result<FarmState> | null {
  if (cmd.type !== 'save_decorations') return null;
  if (s.growth_choice.purchase !== 'tool' && s.growth_choice.purchase !== 'field')
    return err('DECORATION_LOCKED', '购买成长路线后可布置庭院');
  const content = ctx.content.decorations;
  if (!Array.isArray(cmd.props) || cmd.props.length > Object.keys(content.props).length)
    return err('INVALID_DECORATION', '摆件列表非法');
  const ids = new Set<string>();
  const placements: DecorationPlacement[] = [];
  for (const raw of cmd.props) {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)
      || Object.keys(raw).length !== 3 || raw.anchor_id !== content.anchor_id
      || typeof raw.prop_id !== 'string' || !Object.hasOwn(content.props, raw.prop_id)
      || ids.has(raw.prop_id) || !Array.isArray(raw.offset_q) || raw.offset_q.length !== 2)
      return err('INVALID_DECORATION', '摆件或锚点非法');
    const [x, z] = raw.offset_q;
    if (!decorationPositionAllowed(x, z, content))
      return err('INVALID_DECORATION', '摆件超出布置区域或阻挡通道');
    if (placements.some(prop => (prop.offset_q[0] - x) ** 2 + (prop.offset_q[1] - z) ** 2
      < content.min_distance_q ** 2)) return err('DECORATION_OVERLAP', '摆件需要留出间距');
    ids.add(raw.prop_id);
    placements.push({ anchor_id: content.anchor_id, prop_id: raw.prop_id, offset_q: [x, z] });
  }
  const next = structuredClone(s);
  next.decorations = placements;
  return ok(next, [{ type: 'decorations_saved', count: placements.length }]);
}
