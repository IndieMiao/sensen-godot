/** 内存 VoiceStore：HTTP 层测试用。 */
import type { Role, RoomMemberRow, RoomRow, VoiceStore } from './voice.js';

export class MemoryVoiceStore implements VoiceStore {
  private rooms = new Map<string, RoomRow>();
  private membersByRoom = new Map<string, RoomMemberRow[]>();

  async createRoom(row: RoomRow) { this.rooms.set(row.id, { ...row }); this.membersByRoom.set(row.id, []); return { ...row }; }
  async room(roomId: string) { const r = this.rooms.get(roomId); return r ? { ...r } : null; }
  async openRooms(limit: number) {
    return [...this.rooms.values()].filter(r => r.closed_at === null)
      .sort((a, b) => b.created_at - a.created_at).slice(0, limit).map(r => ({ ...r }));
  }
  async closeRoom(roomId: string, now: number) {
    const r = this.rooms.get(roomId);
    if (r) r.closed_at = now;
    this.membersByRoom.set(roomId, []);
  }
  async join(roomId: string, userId: string, role: Role, now: number) {
    const list = this.membersByRoom.get(roomId) ?? [];
    const existing = list.find(m => m.user_id === userId);
    if (existing) return { ...existing };
    const row: RoomMemberRow = { room_id: roomId, user_id: userId, role, muted: false, joined_at: now };
    list.push(row);
    this.membersByRoom.set(roomId, list);
    return { ...row };
  }
  async leave(roomId: string, userId: string) {
    this.membersByRoom.set(roomId, (this.membersByRoom.get(roomId) ?? []).filter(m => m.user_id !== userId));
  }
  async members(roomId: string) { return (this.membersByRoom.get(roomId) ?? []).map(m => ({ ...m })); }
  async member(roomId: string, userId: string) {
    const m = (this.membersByRoom.get(roomId) ?? []).find(x => x.user_id === userId);
    return m ? { ...m } : null;
  }
  async setRole(roomId: string, userId: string, role: Role) {
    const m = (this.membersByRoom.get(roomId) ?? []).find(x => x.user_id === userId);
    if (!m) return null;
    m.role = role;
    return { ...m };
  }
  async setMuted(roomId: string, userId: string, muted: boolean) {
    const m = (this.membersByRoom.get(roomId) ?? []).find(x => x.user_id === userId);
    if (!m) return null;
    m.muted = muted;
    if (muted && m.role === 'speaker') m.role = 'listener'; // 被静音就先下麦
    return { ...m };
  }
  async roomsOf(userId: string) {
    const ids = new Set<string>();
    for (const [roomId, list] of this.membersByRoom) if (list.some(m => m.user_id === userId)) ids.add(roomId);
    for (const r of this.rooms.values()) if (r.host_id === userId) ids.add(r.id);
    return [...ids].map(id => this.rooms.get(id)!).filter(Boolean).map(r => ({ ...r }));
  }
  async deleteUser(userId: string) {
    for (const [roomId, list] of this.membersByRoom)
      this.membersByRoom.set(roomId, list.filter(m => m.user_id !== userId));
    for (const r of this.rooms.values()) if (r.host_id === userId && r.closed_at === null) r.closed_at = Date.now();
  }
}
