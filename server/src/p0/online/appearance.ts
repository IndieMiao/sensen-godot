/**
 * A player's look on the wire (P0 online rooms): slot → part id, checked against the avatar parts a player may wear.
 * The Journey realtime rooms read the same catalog (realtime/appearance.ts) until the Journey server is retired
 * (SGODOT-304); P0 owns it so that retirement leaves P0 whole.
 */
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';

export const DEFAULT_SLOTS = {
  body: 'body00', eyes: 'eyes00', hairHat: 'hairhat0', cloth: 'cloth0', shoes: 'shoes0',
  shoulderBag: '', messengerBag: '', pocketBag: '', backpack: '', headset: '',
  handleft: '', handright: '', mask: '', glass: '',
} as const;
export type Appearance = { version: 1; slots: Record<keyof typeof DEFAULT_SLOTS, string> };
export const defaultAppearance = (): Appearance => ({ version: 1, slots: { ...DEFAULT_SLOTS } });

/** Cosmetic IDs only: no paths, transforms, ownership grants or combat attributes. `root`: assets/avatar (its parts
 * manifest, the demo denylist and the NPC-only list). */
export class AppearanceCatalog {
  private parts = new Map<string, string>();
  constructor(root: string) {
    const manifest = JSON.parse(readFileSync(path.join(root, 'parts_manifest.json'), 'utf8'));
    const denied = new Set(JSON.parse(readFileSync(path.join(root, 'demo_denylist.json'), 'utf8')).hidden);
    // NPC-only parts (SGODOT-229) dress the outpost NPCs on the client; no player may send them.
    const npcFile = path.join(root, 'npc_only.json');
    const npcOnly = new Set<string>(existsSync(npcFile) ? JSON.parse(readFileSync(npcFile, 'utf8')).npc_only ?? [] : []);
    for (const part of manifest.parts) if (!denied.has(part.id) && !npcOnly.has(part.id)) this.parts.set(part.id, part.slot);
  }
  parse(raw: unknown): Appearance {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new Error('APPEARANCE_INVALID');
    const value = raw as Record<string, unknown>;
    if (value.version !== 1 || Object.keys(value).some(k => k !== 'version' && k !== 'slots') ||
      !value.slots || typeof value.slots !== 'object' || Array.isArray(value.slots)) throw new Error('APPEARANCE_INVALID');
    const slots = value.slots as Record<string, unknown>, result = defaultAppearance();
    if (Object.keys(slots).some(k => !Object.hasOwn(DEFAULT_SLOTS, k))) throw new Error('APPEARANCE_INVALID');
    for (const slot of Object.keys(DEFAULT_SLOTS) as (keyof typeof DEFAULT_SLOTS)[]) {
      const id = slots[slot] ?? DEFAULT_SLOTS[slot];
      if (typeof id !== 'string' || id.length > 64 || (id === '' ? DEFAULT_SLOTS[slot] !== '' : this.parts.get(id) !== slot))
        throw new Error('APPEARANCE_INVALID');
      result.slots[slot] = id;
    }
    return result;
  }
}
