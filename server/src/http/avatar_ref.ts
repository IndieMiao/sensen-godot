/**
 * `avatar_ref`：farms 表没有装扮列，MVP 用农场 id 派生一个稳定种子，客户端用它生成确定性
 * 外观——同一座农场每次看都是同一个人。预置农场用显式名字，客户端给它们固定造型。
 *
 * 不发 owner_id：那是身份列，访客不该拿到。
 */
import { presetByFarmId } from '../domain/presets.js';
import type { FarmRow } from './dto.js';

export function avatarRef(f: FarmRow): string {
  const preset = presetByFarmId(f.id);
  if (preset) return preset.avatar_ref;
  return `seed:${f.id.replace(/-/g, '').slice(0, 8)}`;
}
