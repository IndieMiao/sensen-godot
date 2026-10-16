/**
 * Snapshot frame v1, byte-identical to the realtime Room's (OnlineSpace._frame decodes it):
 * u16 version 1 · u32 tick · u32 epoch · u16 count, then per member (26 bytes)
 * u16 id · f32 x · f32 z · f32 yaw · u16 hp · u16 max_hp · u8 action · u8 floor · u32 seq · u16 serial.
 * Outposts have no health or floors: hp, max_hp, floor and serial are 0.
 */
import { ACTIONS } from './actions.js';
import type { Occupant } from './rooms.js';

/** The realtime action list plus sitting; indices match OnlineCrowd's, sit is appended. */
export const P0_ACTIONS = [...ACTIONS, 'sit'] as const;
export const FRAME_HEADER = 12;
export const FRAME_MEMBER = 26;
/** Members per frame. Capacities are ≤ 64 (outposts table), so a frame stays under 1.7 KB. */
export const FRAME_MAX_MEMBERS = 64;

export function actionIndex(action: string): number {
  const i = P0_ACTIONS.indexOf(action as typeof P0_ACTIONS[number]);
  return i < 0 ? 0 : i;
}

export function snapshotFrame(tick: number, epoch: number, members: Occupant[]): Buffer {
  const list = members.slice(0, FRAME_MAX_MEMBERS);
  const buffer = Buffer.alloc(FRAME_HEADER + list.length * FRAME_MEMBER);
  buffer.writeUInt16LE(1, 0); buffer.writeUInt32LE(tick >>> 0, 2);
  buffer.writeUInt32LE(epoch >>> 0, 6); buffer.writeUInt16LE(list.length, 10);
  list.forEach((m, i) => {
    const at = FRAME_HEADER + i * FRAME_MEMBER;
    buffer.writeUInt16LE(m.id, at); buffer.writeFloatLE(m.x, at + 2); buffer.writeFloatLE(m.z, at + 6);
    buffer.writeFloatLE(m.yaw, at + 10); buffer.writeUInt8(actionIndex(m.action), at + 18);
    buffer.writeUInt32LE(Math.max(0, m.seq) >>> 0, at + 20);
  });
  return buffer;
}
