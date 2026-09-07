/** 内存 LocationStore：HTTP 层测试用。 */
import type { LocationRow, LocationStore } from './location.js';

export class MemoryLocationStore implements LocationStore {
  private rows = new Map<string, LocationRow>();

  async upsert(userId: string, lat: number, lng: number, accuracyM: number | null, now: number) {
    const row: LocationRow = { user_id: userId, lat, lng, accuracy_m: accuracyM, updated_at: now };
    this.rows.set(userId, row);
    return { ...row };
  }
  async remove(userId: string) { this.rows.delete(userId); }
  async get(userId: string) { const r = this.rows.get(userId); return r ? { ...r } : null; }
  async many(userIds: string[]) {
    const out = new Map<string, LocationRow>();
    for (const id of userIds) { const r = this.rows.get(id); if (r) out.set(id, { ...r }); }
    return out;
  }
}
