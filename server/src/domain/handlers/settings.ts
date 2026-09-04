/** 农场设置命令。位置可见与访问权限是**两个独立开关**（2026-09-04 决策②）。 */
import type { Command } from '../commands.js';
import { ok, type Result } from '../errors.js';
import type { Ctx } from '../reducer.js';
import type { FarmState } from '../state.js';

/**
 * `location_visible` / `visit_access` 存在数据库列上而不是 state jsonb 里（身份与索引
 * 字段只在列上），所以这两条命令在领域层是空操作，真正的写入由 DB 层完成。这里只负责
 * 让它们成为合法命令、走同一套幂等与版本协议。
 */
export function applySettings(s: FarmState, cmd: Command, _ctx: Ctx): Result<FarmState> | null {
  switch (cmd.type) {
    case 'set_location_visible':
      return ok(s, [{ type: 'location_visible', visible: cmd.visible }]);
    case 'set_visit_access':
      return ok(s, [{ type: 'visit_access', access: cmd.access }]);
    default:
      return null;
  }
}
