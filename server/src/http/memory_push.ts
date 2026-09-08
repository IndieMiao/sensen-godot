/** 内存 DeviceStore：HTTP 层测试用。 */
import type { DeviceRow, DeviceStore, Platform } from './push.js';

export class MemoryDeviceStore implements DeviceStore {
  private byToken = new Map<string, DeviceRow>();

  async upsert(userId: string, token: string, platform: Platform, now: number) {
    const row: DeviceRow = { user_id: userId, token, platform, updated_at: now };
    this.byToken.set(token, row);
    return { ...row };
  }
  async remove(token: string) { this.byToken.delete(token); }
  async tokensFor(userIds: string[]) {
    const want = new Set(userIds);
    return [...this.byToken.values()].filter(d => want.has(d.user_id)).map(d => ({ ...d }));
  }
  async deleteUser(userId: string) {
    for (const [token, row] of [...this.byToken]) if (row.user_id === userId) this.byToken.delete(token);
  }
}
